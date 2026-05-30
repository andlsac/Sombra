#include "sombra_llama.h"
#include "llama.h"

#include <stdlib.h>
#include <string.h>

struct sombra_ctx {
    struct llama_model   * model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    struct llama_sampler * sampler;

    // Tokens do prompt atualmente representados no KV-cache (posições 0..cached_n-1).
    // Permite reaproveitar o prefixo em comum entre chamadas sucessivas.
    llama_token * cached_tokens;
    int cached_n;
    int cached_cap;
};

static bool g_backend_ready = false;

sombra_ctx * sombra_load(const char * model_path, int n_ctx, int n_gpu_layers) {
    if (!g_backend_ready) {
        llama_backend_init();
        g_backend_ready = true;
    }

    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = n_gpu_layers; // <0 => todas (Metal)

    struct llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (!model) return NULL;

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx   = (uint32_t)(n_ctx > 0 ? n_ctx : 2048);
    cparams.n_batch = cparams.n_ctx;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx) { llama_model_free(model); return NULL; }

    // Sampler guloso: continuação mais provável => rápido e determinístico,
    // ideal para autocomplete.
    struct llama_sampler_chain_params sp = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sp);
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

    sombra_ctx * c = (sombra_ctx *)calloc(1, sizeof(sombra_ctx));
    c->model   = model;
    c->ctx     = ctx;
    c->vocab   = llama_model_get_vocab(model);
    c->sampler = smpl;
    return c;
}

void sombra_free(sombra_ctx * c) {
    if (!c) return;
    if (c->cached_tokens) free(c->cached_tokens);
    if (c->sampler) llama_sampler_free(c->sampler);
    if (c->ctx)     llama_free(c->ctx);
    if (c->model)   llama_model_free(c->model);
    free(c);
}

int sombra_complete(sombra_ctx * c,
                    const char * prompt,
                    char * out, int out_cap,
                    int max_tokens,
                    int max_words,
                    bool stop_on_newline) {
    if (!c || !out || out_cap <= 1) return -1;
    out[0] = '\0';
    if (max_words < 1) max_words = 1;

    // 1) Tokeniza o prompt.
    const int prompt_len = (int)strlen(prompt);
    int cap = prompt_len + 8;
    llama_token * tokens = (llama_token *)malloc(sizeof(llama_token) * cap);
    int n = llama_tokenize(c->vocab, prompt, prompt_len, tokens, cap,
                           /*add_special=*/true, /*parse_special=*/true);
    if (n < 0) { // buffer pequeno: realoca
        cap = -n;
        tokens = (llama_token *)realloc(tokens, sizeof(llama_token) * cap);
        n = llama_tokenize(c->vocab, prompt, prompt_len, tokens, cap, true, true);
    }
    if (n <= 0) { free(tokens); return -1; }

    // 2) Reaproveita o KV-cache: encontra o prefixo em comum com a chamada
    //    anterior e decodifica apenas os tokens novos.
    llama_memory_t mem = llama_get_memory(c->ctx);

    int common = 0;
    while (common < n && common < c->cached_n &&
           tokens[common] == c->cached_tokens[common]) {
        common++;
    }
    // Decodifica sempre ao menos o último token (para obter os logits).
    int reuse = (common < n) ? common : (n - 1);
    if (reuse < 0) reuse = 0;

    // Remove do cache tudo após `reuse`: tokens divergentes do prompt + quaisquer
    // tokens gerados na chamada anterior (que ficam em posições >= cached_n).
    if (!llama_memory_seq_rm(mem, 0, reuse, -1)) {
        // Alguns backends não suportam remoção parcial: limpa e reprocessa.
        llama_memory_clear(mem, true);
        reuse = 0;
    }

    // Decodifica só os tokens novos [reuse, n).
    struct llama_batch batch = llama_batch_get_one(tokens + reuse, n - reuse);
    if (llama_decode(c->ctx, batch) != 0) { free(tokens); return -1; }

    // Atualiza o cache de prompt = tokens[0..n-1].
    if (c->cached_cap < n) {
        c->cached_tokens = (llama_token *)realloc(c->cached_tokens, sizeof(llama_token) * n);
        c->cached_cap = n;
    }
    memcpy(c->cached_tokens, tokens, sizeof(llama_token) * n);
    c->cached_n = n;
    free(tokens);

    // 3) Loop de geração gulosa, caractere a caractere.
    //
    // Espaçamento: o modelo já emite o espaço de fronteira de palavra quando
    // necessário (ex.: prefixo "ou" -> sugere " seja"). Preservamos esse espaço.
    // Só pulamos um espaço inicial se o PRÓPRIO prompt já terminar em espaço
    // (para não duplicar), além de pular quebras de linha/tabs iniciais.
    const bool prompt_ends_space = (prompt_len > 0 && prompt[prompt_len - 1] == ' ');

    int written = 0;
    int words_done = 0;     // palavras completas (contadas pelos espaços)
    bool skipping_leading = true;
    char piece[256];
    bool stop = false;

    for (int t = 0; t < max_tokens && !stop; t++) {
        llama_token id = llama_sampler_sample(c->sampler, c->ctx, -1);
        if (llama_vocab_is_eog(c->vocab, id)) break;

        int np = llama_token_to_piece(c->vocab, id, piece, (int)sizeof(piece),
                                      /*lstrip=*/0, /*special=*/false);
        if (np < 0) np = 0;

        for (int i = 0; i < np; i++) {
            char ch = piece[i];

            if (skipping_leading) {
                if (ch == '\n' || ch == '\r' || ch == '\t') continue;
                if (ch == ' ' && prompt_ends_space) continue;
                skipping_leading = false; // primeiro caractere de conteúdo real
            }

            // Quebra de linha encerra (autocomplete de uma linha).
            if (ch == '\n' || ch == '\r') { stop = true; break; }

            // Espaço após conteúdo marca o fim de uma palavra.
            if (ch == ' ' && written > 0 && out[written - 1] != ' ') {
                words_done++;
                if (words_done >= max_words) { stop = true; break; }
            }

            if (written < out_cap - 1) {
                out[written++] = ch;
                out[written] = '\0';
            } else { stop = true; break; }
        }

        if (stop) break;

        // Realimenta o token gerado.
        llama_token next[1] = { id };
        struct llama_batch nb = llama_batch_get_one(next, 1);
        if (llama_decode(c->ctx, nb) != 0) break;
    }

    // Remove espaço(s) finais para uma sombra limpa.
    while (written > 0 && out[written - 1] == ' ') out[--written] = '\0';
    return written;
}
