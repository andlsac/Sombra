#include "sombra_llama.h"
#include "llama.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

struct sombra_ctx {
    struct llama_model   * model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    struct llama_sampler * sampler;

    // Estado do sampler (persistido para reconstruí-lo ao mudar temp OU bias sem
    // perder o outro): temperatura e o viés (logit bias) do perfil do usuário.
    float temp;
    llama_logit_bias * biases;
    int n_biases;

    // Tokens do prompt atualmente representados no KV-cache (posições 0..cached_n-1).
    // Permite reaproveitar o prefixo em comum entre chamadas sucessivas.
    llama_token * cached_tokens;
    int cached_n;
    int cached_cap;

    // RASCUNHO (speculative decoding): modelo pequeno que PROPÕE tokens; o modelo
    // grande (target, acima) só VERIFICA em lote. Mesmo vocabulário do target.
    // NULL = speculative desligado (usa o caminho guloso normal).
    struct llama_model   * draft_model;
    struct llama_context * draft_ctx;
    const struct llama_vocab * draft_vocab;
    llama_token * draft_cached;
    int draft_cached_n;
    int draft_cached_cap;
};

static bool g_backend_ready = false;

// Monta a cadeia de sampling usada na geração. Em todos os casos:
//   penalties (anti-repetição) -> [logit bias opcional] -> greedy.
// O greedy fica por último: continuação mais provável (determinística, ideal
// para autocomplete). As penalidades evitam loops degenerados e lixo repetido
// (ex.: '''/***/---), que modelos pequenos costumam emitir.
static struct llama_sampler * build_sampler(const struct llama_vocab * vocab,
                                            const llama_logit_bias * biases, int nb,
                                            float temp) {
    struct llama_sampler_chain_params sp = llama_sampler_chain_default_params();
    struct llama_sampler * chain = llama_sampler_chain_init(sp);
    // Anti-repetição: só repeat penalty (a frequency penalty deixava a geração
    // "burra" — penalizava palavras comuns). last_n cobre o contexto recente para
    // reduzir o eco do texto já escrito.
    llama_sampler_chain_add(chain,
        llama_sampler_init_penalties(/*last_n*/128, /*repeat*/1.2f,
                                     /*freq*/0.0f, /*present*/0.0f));
    if (biases && nb > 0) {
        llama_sampler_chain_add(chain,
            llama_sampler_init_logit_bias(llama_vocab_n_tokens(vocab), nb, biases));
    }
    // temp <= 0 => greedy (determinístico). temp > 0 => amostragem leve
    // (top_k -> top_p -> temp -> dist com seed FIXA): o greedy em modelo base
    // pequeno cai em continuações genéricas/estranhas (ex.: começar com número);
    // um pouco de temperatura melhora a naturalidade. A seed fixa + o reset por
    // chamada mantêm a sugestão ESTÁVEL para o mesmo texto.
    if (temp <= 0.0f) {
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.95f, 1));
        llama_sampler_chain_add(chain, llama_sampler_init_temp(temp));
        llama_sampler_chain_add(chain, llama_sampler_init_dist(1234));
    }
    return chain;
}

// (Re)constrói o sampler a partir do estado atual do ctx (temp + bias), sem
// perder nenhum dos dois ao mudar só um.
static void rebuild_sampler(sombra_ctx * c) {
    if (c->sampler) { llama_sampler_free(c->sampler); c->sampler = NULL; }
    c->sampler = build_sampler(c->vocab, c->biases, c->n_biases, c->temp);
}

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
    // Flash Attention acelera a atenção no Metal (sobretudo em modelos maiores).
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx) { llama_model_free(model); return NULL; }

    sombra_ctx * c = (sombra_ctx *)calloc(1, sizeof(sombra_ctx));
    c->model   = model;
    c->ctx     = ctx;
    c->vocab   = llama_model_get_vocab(model);
    // Temperatura inicial: env (teste) ou 0.6 (padrão). O app sobrescreve via
    // sombra_set_temp conforme o slider de Ajustes.
    const char * tenv = getenv("SOMBRA_TEMP");
    c->temp = tenv ? (float)atof(tenv) : 0.6f;
    c->biases = NULL;
    c->n_biases = 0;
    c->sampler = build_sampler(c->vocab, NULL, 0, c->temp);
    return c;
}

// Ajusta a temperatura de amostragem (0 = greedy) e reconstrói o sampler,
// preservando o viés do perfil.
void sombra_set_temp(sombra_ctx * c, float temp) {
    if (!c) return;
    c->temp = temp;
    rebuild_sampler(c);
}

// true se o modelo traz um template de chat embutido (instruct/it/chat).
// Usado pelo Swift para decidir entre continuação crua (base) e
// continuação via template (instruct), evitando o modo "assistente".
bool sombra_has_chat_template(sombra_ctx * c) {
    if (!c || !c->model) return false;
    return llama_model_chat_template(c->model, NULL) != NULL;
}

// Aplica o template de chat do modelo a uma única mensagem `user` =
// `instruction`, com o turno do assistente ABERTO (add_ass=true). O Swift
// concatena o texto do usuário logo após, fazendo o modelo CONTINUAR esse
// turno (prefill) em vez de "responder". Retorna o nº de bytes (>=0) ou -1.
int sombra_build_chat_prefix(sombra_ctx * c, const char * instruction,
                             char * out, int out_cap) {
    if (!c || !c->model || !out || out_cap <= 1) return -1;
    const char * tmpl = llama_model_chat_template(c->model, NULL);
    if (!tmpl) { out[0] = '\0'; return 0; }
    struct llama_chat_message msg[1];
    msg[0].role = "user";
    msg[0].content = instruction ? instruction : "";
    int32_t n = llama_chat_apply_template(tmpl, msg, 1, /*add_ass=*/true, out, out_cap);
    if (n < 0) { out[0] = '\0'; return -1; }
    if (n >= out_cap) n = out_cap - 1; // truncado (improvável p/ instrução curta)
    out[n] = '\0';
    return n;
}

void sombra_set_bias(sombra_ctx * c, const char * words_nl, float strength) {
    if (!c) return;

    llama_logit_bias biases[256];
    int nb = 0;

    if (words_nl && strength > 0.0f) {
        const int n_vocab = llama_vocab_n_tokens(c->vocab);
        const char * p = words_nl;
        char word[256];
        while (*p && nb < 256) {
            int wl = 0;
            while (*p && *p != '\n' && wl < 200) { word[wl++] = *p; p++; }
            while (*p && *p != '\n') p++;       // descarta excesso
            if (*p == '\n') p++;
            if (wl < 2) continue;

            // Tokeniza " palavra" para pegar o token de início de palavra.
            char buf[260];
            buf[0] = ' ';
            memcpy(buf + 1, word, (size_t)wl);
            llama_token toks[8];
            int nt = llama_tokenize(c->vocab, buf, wl + 1, toks, 8,
                                    /*add_special=*/false, /*parse_special=*/false);
            if (nt <= 0) continue;
            llama_token t = toks[0];
            if (t < 0 || t >= n_vocab) continue;

            int dup = 0;
            for (int j = 0; j < nb; j++) if (biases[j].token == t) { dup = 1; break; }
            if (dup) continue;
            biases[nb].token = t;
            biases[nb].bias = strength;
            nb++;
        }
    }

    // Guarda o viés no ctx (para sobreviver a reconstruções por mudança de temp).
    free(c->biases);
    c->biases = NULL;
    c->n_biases = 0;
    if (nb > 0) {
        c->biases = (llama_logit_bias *)malloc(sizeof(llama_logit_bias) * nb);
        memcpy(c->biases, biases, sizeof(llama_logit_bias) * nb);
        c->n_biases = nb;
    }
    rebuild_sampler(c);
}

void sombra_free(sombra_ctx * c) {
    if (!c) return;
    if (c->cached_tokens) free(c->cached_tokens);
    if (c->draft_cached)  free(c->draft_cached);
    if (c->biases) free(c->biases);
    if (c->sampler) llama_sampler_free(c->sampler);
    if (c->draft_ctx)   llama_free(c->draft_ctx);
    if (c->draft_model) llama_model_free(c->draft_model);
    if (c->ctx)     llama_free(c->ctx);
    if (c->model)   llama_model_free(c->model);
    free(c);
}

bool sombra_set_draft(sombra_ctx * c, const char * draft_path, int n_ctx) {
    if (!c) return false;
    // Libera um rascunho anterior.
    if (c->draft_ctx)   { llama_free(c->draft_ctx); c->draft_ctx = NULL; }
    if (c->draft_model) { llama_model_free(c->draft_model); c->draft_model = NULL; }
    free(c->draft_cached); c->draft_cached = NULL; c->draft_cached_n = 0; c->draft_cached_cap = 0;
    c->draft_vocab = NULL;
    if (!draft_path || !draft_path[0]) return true;   // "" = desliga speculative

    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = -1;
    struct llama_model * dm = llama_model_load_from_file(draft_path, mp);
    if (!dm) return false;
    const struct llama_vocab * dv = llama_model_get_vocab(dm);
    // O rascunho PRECISA do mesmo vocabulário do target (verificação por token id).
    if (llama_vocab_n_tokens(dv) != llama_vocab_n_tokens(c->vocab)) {
        llama_model_free(dm);
        return false;
    }
    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx   = (uint32_t)(n_ctx > 0 ? n_ctx : 2048);
    cp.n_batch = cp.n_ctx;
    cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
    struct llama_context * dc = llama_init_from_model(dm, cp);
    if (!dc) { llama_model_free(dm); return false; }
    c->draft_model = dm;
    c->draft_ctx   = dc;
    c->draft_vocab = dv;
    return true;
}

static llama_token argmax_token(const float * logits, int n_vocab);   // (definido adiante)

// Anexa o piece de um token a `out`, com a lógica de fronteira de palavra/linha
// do autocomplete (igual ao laço guloso). Atualiza *written/*words_done/*skipping.
// Devolve 1 se a geração deve PARAR.
static int spec_emit(const struct llama_vocab * vocab, llama_token id,
                     char * out, int * written, int out_cap,
                     int * words_done, int max_words, int * skipping,
                     int prompt_ends_space) {
    char piece[256];
    int np = llama_token_to_piece(vocab, id, piece, (int)sizeof(piece), 0, false);
    if (np < 0) np = 0;
    for (int i = 0; i < np; i++) {
        char ch = piece[i];
        if (*skipping) {
            if (ch == '\n' || ch == '\r' || ch == '\t') continue;
            if (ch == ' ' && prompt_ends_space) continue;
            *skipping = 0;
        }
        if (ch == '\n' || ch == '\r') return 1;
        if (ch == ' ' && *written > 0 && out[*written - 1] != ' ') {
            (*words_done)++;
            if (*words_done >= max_words) return 1;
        }
        if (*written < out_cap - 1) { out[(*written)++] = ch; out[*written] = '\0'; }
        else return 1;
    }
    return 0;
}

// SPECULATIVE DECODING (greedy): o rascunho propõe K tokens; o target verifica os
// K de uma vez (1 forward em lote) e aceita o maior prefixo que bate com a SUA
// escolha gulosa, corrigindo o 1º que diverge. Saída IDÊNTICA ao greedy do
// target, com menos forwards do modelo grande. `tokens`/`n` = prompt já
// prefillado no target (logits em -1 = dist do token n). Reaproveita o KV.
static int spec_generate(sombra_ctx * c, const llama_token * tokens, int n,
                         char * out, int out_cap, int max_tokens, int max_words,
                         int prompt_ends_space, const int * cur_gen, int my_gen) {
    const int n_vocab = llama_vocab_n_tokens(c->vocab);
    llama_memory_t tmem = llama_get_memory(c->ctx);
    llama_memory_t dmem = llama_get_memory(c->draft_ctx);

    // Prefill do RASCUNHO com o mesmo prompt (reaproveitando o KV do rascunho).
    int dcommon = 0;
    while (dcommon < n && dcommon < c->draft_cached_n && tokens[dcommon] == c->draft_cached[dcommon]) dcommon++;
    int dreuse = (dcommon < n) ? dcommon : (n - 1);
    if (dreuse < 0) dreuse = 0;
    if (!llama_memory_seq_rm(dmem, 0, dreuse, -1)) { llama_memory_clear(dmem, true); dreuse = 0; }
    if (llama_decode(c->draft_ctx, llama_batch_get_one((llama_token *)tokens + dreuse, n - dreuse)) != 0) return 0;
    if (c->draft_cached_cap < n) {
        c->draft_cached = (llama_token *)realloc(c->draft_cached, sizeof(llama_token) * n);
        c->draft_cached_cap = n;
    }
    memcpy(c->draft_cached, tokens, sizeof(llama_token) * n);
    c->draft_cached_n = n;

    const int K = 4;                       // tokens propostos por rodada
    llama_batch tb = llama_batch_init(K, 0, 1);
    llama_token draft[K];

    int written = 0, words_done = 0, emitted = 0, skipping = 1;
    // g0 = escolha gulosa do target para a posição n (dos logits do prefill).
    llama_token g0 = argmax_token(llama_get_logits_ith(c->ctx, -1), n_vocab);
    int n_past = n;
    int stop = 0;

    while (!stop && emitted < max_tokens) {
        if (cur_gen && *cur_gen != my_gen) break;   // pedido obsoleto

        // 1) Rascunho propõe até K tokens (gulosos), exceto fim-de-geração.
        int dk = 0;
        for (; dk < K; dk++) {
            llama_token dt = argmax_token(llama_get_logits_ith(c->draft_ctx, -1), n_vocab);
            if (llama_vocab_is_eog(c->draft_vocab, dt)) break;
            draft[dk] = dt;
            if (llama_decode(c->draft_ctx, llama_batch_get_one(&draft[dk], 1)) != 0) { stop = 1; break; }
        }

        // 2) Target verifica os dk de uma vez (lote, com logits em cada posição).
        if (dk > 0) {
            tb.n_tokens = dk;
            for (int i = 0; i < dk; i++) {
                tb.token[i] = draft[i];
                tb.pos[i] = n_past + i;
                tb.n_seq_id[i] = 1;
                tb.seq_id[i][0] = 0;
                tb.logits[i] = 1;
            }
            if (llama_decode(c->ctx, tb) != 0) break;
        }

        // 3) Aceita o maior prefixo onde o rascunho == escolha gulosa do target.
        int j = 0;
        while (j < dk) {
            llama_token g = (j == 0) ? g0 : argmax_token(llama_get_logits_ith(c->ctx, j - 1), n_vocab);
            if (draft[j] != g) break;
            j++;
        }
        // Token correto na posição n_past+j (correção, ou bônus se aceitou tudo).
        llama_token corr;
        if (j < dk)        corr = (j == 0) ? g0 : argmax_token(llama_get_logits_ith(c->ctx, j - 1), n_vocab);
        else if (dk > 0)   corr = argmax_token(llama_get_logits_ith(c->ctx, dk - 1), n_vocab);
        else               corr = g0;       // rascunho não propôs nada

        // 4) Emite: os aceitos + a correção (parando em eog/linha/limite).
        for (int i = 0; i < j && !stop; i++) {
            if (spec_emit(c->vocab, draft[i], out, &written, out_cap, &words_done, max_words,
                          &skipping, prompt_ends_space)) stop = 1;
            emitted++;
        }
        int corr_eog = llama_vocab_is_eog(c->vocab, corr);
        if (!stop && corr_eog) stop = 1;
        if (!stop) {
            if (spec_emit(c->vocab, corr, out, &written, out_cap, &words_done, max_words,
                          &skipping, prompt_ends_space)) stop = 1;
            emitted++;
        }

        // 5) Sincroniza o KV dos dois p/ ...+corr, e avança. (Decodifica corr nos
        //    dois → logits do próximo passo; g0 = nova escolha gulosa do target.)
        llama_memory_seq_rm(tmem, 0, n_past + j, -1);
        llama_memory_seq_rm(dmem, 0, n_past + j, -1);
        if (corr_eog) break;
        tb.n_tokens = 1; tb.token[0] = corr; tb.pos[0] = n_past + j;
        tb.n_seq_id[0] = 1; tb.seq_id[0][0] = 0; tb.logits[0] = 1;
        if (llama_decode(c->ctx, tb) != 0) break;
        g0 = argmax_token(llama_get_logits_ith(c->ctx, 0), n_vocab);
        if (llama_decode(c->draft_ctx, llama_batch_get_one(&corr, 1)) != 0) break;
        n_past += j + 1;
    }

    llama_batch_free(tb);
    // Restaura o KV ao prompt (coerente com cached_n) p/ a próxima chamada.
    llama_memory_seq_rm(tmem, 0, n, -1);
    llama_memory_seq_rm(dmem, 0, n, -1);
    while (written > 0 && out[written - 1] == ' ') out[--written] = '\0';
    return written;
}

int sombra_complete(sombra_ctx * c,
                    const char * prompt,
                    char * out, int out_cap,
                    int max_tokens,
                    int max_words,
                    bool stop_on_newline,
                    const int * cur_gen, int my_gen) {
    if (!c || !out || out_cap <= 1) return -1;
    // Pedido já obsoleto antes de começar (o usuário digitou de novo): aborta.
    if (cur_gen && *cur_gen != my_gen) return 0;
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

    // Zera o estado do sampler (buffer da repetition penalty). Sem isso, os
    // tokens da sugestão ANTERIOR continuam penalizados na próxima chamada,
    // degenerando a geração (sugestões cada vez mais curtas/vazias). A penalidade
    // ainda atua DENTRO desta geração, evitando loops na própria sugestão.
    if (c->sampler) llama_sampler_reset(c->sampler);

    int written = 0;
    int words_done = 0;     // palavras completas (contadas pelos espaços)
    bool skipping_leading = true;
    char piece[256];
    bool stop = false;

    // Cancelamento por FRONTEIRA DE PALAVRA: se chegou um pedido mais novo
    // (você continuou digitando), paramos — mas só ao terminar a palavra atual,
    // NUNCA no meio dela. Assim a palavra que você está digitando é sempre
    // completada ("compl" -> "completo"), e só as palavras EXTRAS de uma frase
    // longa são abortadas (controle de calor/backlog). O teto `max_tokens` ainda
    // limita o caso degenerado de uma "palavra" sem espaço.
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
                // Pedido obsoleto: a palavra atual já está completa -> para aqui
                // (em vez de cortar no meio da próxima).
                if (cur_gen && *cur_gen != my_gen) { stop = true; break; }
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

// argmax dos logits (token mais provável), pulando nada — usado na continuação
// gulosa de cada ramo do leque.
static llama_token argmax_token(const float * logits, int n_vocab) {
    llama_token best = 0;
    float best_lg = -1e30f;
    for (int v = 0; v < n_vocab; v++) {
        if (logits[v] > best_lg) { best_lg = logits[v]; best = v; }
    }
    return best;
}

int sombra_candidates(sombra_ctx * c, const char * prompt, int k,
                      int max_words, int max_tokens_each,
                      char * out, int out_cap,
                      const int * cur_gen, int my_gen) {
    if (!c || !out || out_cap <= 1) return -1;
    if (cur_gen && *cur_gen != my_gen) return 0;
    out[0] = '\0';
    if (k < 1) k = 1;
    if (k > 16) k = 16;                 // teto do leque (e dos buffers locais)
    if (max_words < 1) max_words = 1;
    if (max_tokens_each < 1) max_tokens_each = 8;

    // 1) Tokeniza + reaproveita o KV-cache (idêntico ao sombra_complete).
    const int prompt_len = (int)strlen(prompt);
    int cap = prompt_len + 8;
    llama_token * tokens = (llama_token *)malloc(sizeof(llama_token) * cap);
    int n = llama_tokenize(c->vocab, prompt, prompt_len, tokens, cap, true, true);
    if (n < 0) {
        cap = -n;
        tokens = (llama_token *)realloc(tokens, sizeof(llama_token) * cap);
        n = llama_tokenize(c->vocab, prompt, prompt_len, tokens, cap, true, true);
    }
    if (n <= 0) { free(tokens); return -1; }

    llama_memory_t mem = llama_get_memory(c->ctx);
    int common = 0;
    while (common < n && common < c->cached_n &&
           tokens[common] == c->cached_tokens[common]) common++;
    int reuse = (common < n) ? common : (n - 1);
    if (reuse < 0) reuse = 0;
    if (!llama_memory_seq_rm(mem, 0, reuse, -1)) { llama_memory_clear(mem, true); reuse = 0; }
    if (llama_decode(c->ctx, llama_batch_get_one(tokens + reuse, n - reuse)) != 0) {
        free(tokens); return -1;
    }
    if (c->cached_cap < n) {
        c->cached_tokens = (llama_token *)realloc(c->cached_tokens, sizeof(llama_token) * n);
        c->cached_cap = n;
    }
    memcpy(c->cached_tokens, tokens, sizeof(llama_token) * n);
    c->cached_n = n;
    free(tokens);
    const int n_prefill = n;

    // 2) top-k tokens INICIAIS por logit (exclui fim-de-geração). É a parte de
    //    graça: a 1ª distribuição já saiu do prefill.
    const float * logits = llama_get_logits_ith(c->ctx, -1);
    if (!logits) return -1;
    const int n_vocab = llama_vocab_n_tokens(c->vocab);
    llama_token top_id[16];
    float       top_lg[16];
    int kk = 0;
    for (int v = 0; v < n_vocab; v++) {
        if (llama_vocab_is_eog(c->vocab, v)) continue;
        float lg = logits[v];
        if (kk < k) {
            int j = kk++;
            while (j > 0 && top_lg[j - 1] < lg) { top_lg[j] = top_lg[j - 1]; top_id[j] = top_id[j - 1]; j--; }
            top_lg[j] = lg; top_id[j] = v;
        } else if (lg > top_lg[k - 1]) {
            int j = k - 1;
            while (j > 0 && top_lg[j - 1] < lg) { top_lg[j] = top_lg[j - 1]; top_id[j] = top_id[j - 1]; j--; }
            top_lg[j] = lg; top_id[j] = v;
        }
    }

    // 3) Para cada token inicial: trunca o KV de volta ao prefill, FORÇA o token e
    //    continua gulosamente (argmax) até `max_words` palavras / max_tokens_each.
    //    A continuação gulosa mantém o leque ESTÁVEL para o mesmo contexto.
    int written = 0;
    int n_cand = 0;
    char piece[256];
    for (int ci = 0; ci < kk; ci++) {
        if (cur_gen && *cur_gen != my_gen) break;
        if (!llama_memory_seq_rm(mem, 0, n_prefill, -1)) { llama_memory_clear(mem, true); break; }

        llama_token id = top_id[ci];
        char cand[256];
        int cl = 0;
        int words_done = 0;
        bool skipping_leading = true;
        bool stop = false;

        for (int t = 0; t < max_tokens_each && !stop; t++) {
            int np = llama_token_to_piece(c->vocab, id, piece, (int)sizeof(piece), 0, false);
            if (np < 0) np = 0;
            for (int i = 0; i < np; i++) {
                char ch = piece[i];
                if (skipping_leading) {
                    if (ch == '\n' || ch == '\r' || ch == '\t' || ch == ' ') continue;
                    skipping_leading = false;          // 1º caractere de conteúdo
                }
                if (ch == '\n' || ch == '\r') { stop = true; break; }
                if (ch == ' ' && cl > 0 && cand[cl - 1] != ' ') {
                    words_done++;
                    if (words_done >= max_words) { stop = true; break; }
                }
                if (cl < (int)sizeof(cand) - 1) { cand[cl++] = ch; cand[cl] = '\0'; }
                else { stop = true; break; }
            }
            if (stop) break;
            // Realimenta o token e pega o próximo por argmax.
            if (llama_decode(c->ctx, llama_batch_get_one(&id, 1)) != 0) break;
            const float * lg = llama_get_logits_ith(c->ctx, -1);
            if (!lg) break;
            id = argmax_token(lg, n_vocab);
            if (llama_vocab_is_eog(c->vocab, id)) break;
        }

        while (cl > 0 && cand[cl - 1] == ' ') cand[--cl] = '\0';
        if (cl > 0) {
            for (int i = 0; i < cl && written < out_cap - 1; i++) out[written++] = cand[i];
            if (written < out_cap - 1) out[written++] = '\n';   // separador
            out[written] = '\0';
            n_cand++;
        }
    }

    // Restaura o KV ao prefill (coerente com cached_n) para a próxima chamada.
    llama_memory_seq_rm(mem, 0, n_prefill, -1);
    return n_cand;
}

int sombra_rank(sombra_ctx * c, const char * context, const char * candidates_nl,
                char * out, int out_cap, const int * cur_gen, int my_gen) {
    if (!c || !out || out_cap <= 1 || !context || !candidates_nl) return -1;
    if (cur_gen && *cur_gen != my_gen) return 0;
    out[0] = '\0';

    enum { MAXC = 24 };
    char cand[MAXC][192];
    int  ncand = 0;
    {
        const char * p = candidates_nl;
        while (*p && ncand < MAXC) {
            int l = 0;
            while (*p && *p != '\n' && l < 191) cand[ncand][l++] = *p++;
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            cand[ncand][l] = '\0';
            if (l > 0) ncand++;
        }
    }
    if (ncand == 0) return 0;

    const int n_vocab = llama_vocab_n_tokens(c->vocab);
    llama_memory_t mem = llama_get_memory(c->ctx);

    // Tokeniza o contexto (referência p/ achar onde cada candidato diverge —
    // o espaço final do contexto FUNDE com a 1ª subpalavra do candidato).
    const int ctx_len = (int)strlen(context);
    int cap_ctx = ctx_len + 8;
    llama_token * ctok = (llama_token *)malloc(sizeof(llama_token) * cap_ctx);
    int n_ctx = llama_tokenize(c->vocab, context, ctx_len, ctok, cap_ctx, true, true);
    if (n_ctx < 0) {
        cap_ctx = -n_ctx; ctok = (llama_token *)realloc(ctok, sizeof(llama_token) * cap_ctx);
        n_ctx = llama_tokenize(c->vocab, context, ctx_len, ctok, cap_ctx, true, true);
    }
    if (n_ctx <= 0) { free(ctok); return -1; }

    // Prefill do contexto (1×, reaproveitando o KV se possível).
    {
        int common = 0;
        while (common < n_ctx && common < c->cached_n && ctok[common] == c->cached_tokens[common]) common++;
        int reuse = (common < n_ctx) ? common : (n_ctx - 1);
        if (reuse < 0) reuse = 0;
        if (!llama_memory_seq_rm(mem, 0, reuse, -1)) { llama_memory_clear(mem, true); reuse = 0; }
        if (llama_decode(c->ctx, llama_batch_get_one(ctok + reuse, n_ctx - reuse)) != 0) { free(ctok); return -1; }
    }

    char * full = (char *)malloc((size_t)ctx_len + 256);
    llama_token * ftok = NULL; int fcap = 0;
    float score[MAXC];
    for (int i = 0; i < ncand; i++) score[i] = -1e30f;

    for (int ci = 0; ci < ncand; ci++) {
        if (cur_gen && *cur_gen != my_gen) break;
        snprintf(full, (size_t)ctx_len + 256, "%s%s", context, cand[ci]);
        int flen = (int)strlen(full);
        if (fcap < flen + 8) { fcap = flen + 8; ftok = (llama_token *)realloc(ftok, sizeof(llama_token) * fcap); }
        int n_full = llama_tokenize(c->vocab, full, flen, ftok, fcap, true, true);
        if (n_full <= 0) continue;
        // LCP com o contexto → onde começam os tokens do candidato.
        int lcp = 0;
        while (lcp < n_ctx && lcp < n_full && ftok[lcp] == ctok[lcp]) lcp++;
        if (lcp < 1) lcp = 1;            // BOS sempre compartilhado
        if (lcp >= n_full) continue;     // candidato não acrescenta token (improvável)

        // Posições 0..lcp-2 são contexto puro (nunca sobrescritas). Trunca para
        // lcp-1 e redecodifica ftok[lcp-1] (último token compartilhado) p/ obter
        // os logits da posição lcp. Depois pontua os tokens do candidato.
        if (!llama_memory_seq_rm(mem, 0, lcp - 1, -1)) { llama_memory_clear(mem, true); }
        if (llama_decode(c->ctx, llama_batch_get_one(&ftok[lcp - 1], 1)) != 0) continue;

        double s = 0.0; int scored = 0;
        for (int j = lcp; j < n_full; j++) {
            const float * lg = llama_get_logits_ith(c->ctx, -1);
            if (!lg) break;
            float mx = -1e30f;
            for (int v = 0; v < n_vocab; v++) if (lg[v] > mx) mx = lg[v];
            double sum = 0.0;
            for (int v = 0; v < n_vocab; v++) sum += exp((double)(lg[v] - mx));
            double lse = (double)mx + log(sum);
            s += (double)lg[ftok[j]] - lse;
            scored++;
            if (llama_decode(c->ctx, llama_batch_get_one(&ftok[j], 1)) != 0) break;
        }
        if (scored > 0) score[ci] = (float)(s / scored);   // normaliza por nº de tokens
    }
    free(ctok); free(full); if (ftok) free(ftok);
    c->cached_n = 0;   // mexemos no KV livremente → próxima chamada reprocessa

    // Ordena os índices por score desc (seleção, n pequeno).
    int order[MAXC];
    for (int i = 0; i < ncand; i++) order[i] = i;
    for (int i = 0; i < ncand; i++)
        for (int j = i + 1; j < ncand; j++)
            if (score[order[j]] > score[order[i]]) { int t = order[i]; order[i] = order[j]; order[j] = t; }

    int written = 0, n_out = 0;
    for (int k = 0; k < ncand; k++) {
        int idx = order[k];
        if (score[idx] <= -1e29f) continue;
        const char * w = cand[idx];
        for (int i = 0; w[i] && written < out_cap - 1; i++) out[written++] = w[i];
        if (written < out_cap - 1) out[written++] = '\n';
        out[written] = '\0';
        n_out++;
    }
    return n_out;
}
