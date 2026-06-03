// Shim C fino sobre o llama.cpp, expondo só o necessário para a Sombra.
// Mantém a manipulação de ponteiros/batches/sampler em C, longe do Swift.
#ifndef SOMBRA_LLAMA_H
#define SOMBRA_LLAMA_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sombra_ctx sombra_ctx;

// Carrega o modelo GGUF. n_gpu_layers<0 = todas as camadas na GPU (Metal).
// Retorna NULL em falha.
sombra_ctx * sombra_load(const char * model_path, int n_ctx, int n_gpu_layers);

void sombra_free(sombra_ctx * c);

// Gera uma continuação para `prompt`.
// Escreve até out_cap-1 bytes (UTF-8, terminado em \0) em `out`.
// Para em: token de fim, `max_words` palavras, nova linha (se stop_on_newline)
// ou `max_tokens` (limite de segurança). Espaços/quebras iniciais são pulados.
// Retorna o nº de bytes escritos (>=0), ou -1 em erro.
// `cur_gen`/`my_gen`: cancelamento cooperativo. Se cur_gen != NULL e
// *cur_gen != my_gen durante a geração, ela é abortada (pedido obsoleto).
int sombra_complete(sombra_ctx * c,
                    const char * prompt,
                    char * out, int out_cap,
                    int max_tokens,
                    int max_words,
                    bool stop_on_newline,
                    const int * cur_gen, int my_gen);

// Gera o "leque": até `k` candidatos de CONTINUAÇÃO para `prompt`, expandindo os
// top-k tokens iniciais mais prováveis e completando cada um (gulosamente) até
// `max_words` palavras (ou `max_tokens_each`). Reaproveita o prefill do prompt
// entre os candidatos → barato (1 prefill + ramos curtos). Escreve os candidatos
// separados por '\n' (UTF-8) em `out`. Retorna o nº de candidatos (>=0) ou -1.
// Cancelável (cur_gen/my_gen), como sombra_complete. Restaura o KV ao prefill.
int sombra_candidates(sombra_ctx * c, const char * prompt, int k,
                      int max_words, int max_tokens_each,
                      char * out, int out_cap,
                      const int * cur_gen, int my_gen);

// Reordena `candidates_nl` (palavras separadas por '\n', cada uma já começando
// com o que o usuário digitou) pela probabilidade que o MODELO dá a cada uma
// como continuação de `context` (texto antes da palavra). O DICIONÁRIO garante
// as letras certas; o MODELO escolhe a que cabe no contexto. Escreve os
// candidatos reordenados (melhor primeiro) em `out`, '\n'-separados. Retorna o
// nº pontuado (>=0) ou -1. Cancelável (cur_gen/my_gen).
int sombra_rank(sombra_ctx * c, const char * context, const char * candidates_nl,
                char * out, int out_cap, const int * cur_gen, int my_gen);

// Personalização: favorece (logit bias) os tokens iniciais das palavras dadas
// (separadas por '\n'). `strength` é o bônus em logits (0 = desliga).
// Reconstrói o sampler interno. Passar NULL/0 remove o viés.
void sombra_set_bias(sombra_ctx * c, const char * words_nl, float strength);

// Temperatura de amostragem: 0 = greedy (determinístico); >0 = amostragem leve
// (mais natural). Reconstrói o sampler preservando o viés. Padrão 0.6.
void sombra_set_temp(sombra_ctx * c, float temp);

// true se o modelo traz template de chat embutido (instruct/it/chat).
bool sombra_has_chat_template(sombra_ctx * c);

// Monta o prefixo via template de chat: turno `user` = `instruction`, com o
// turno do assistente aberto. O chamador concatena o texto a continuar logo
// após (prefill), fazendo o modelo CONTINUAR em vez de "responder".
// Escreve UTF-8 terminado em \0 em `out`. Retorna nº de bytes (>=0) ou -1.
int sombra_build_chat_prefix(sombra_ctx * c, const char * instruction,
                             char * out, int out_cap);

#ifdef __cplusplus
}
#endif

#endif // SOMBRA_LLAMA_H
