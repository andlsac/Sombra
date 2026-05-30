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
int sombra_complete(sombra_ctx * c,
                    const char * prompt,
                    char * out, int out_cap,
                    int max_tokens,
                    int max_words,
                    bool stop_on_newline);

#ifdef __cplusplus
}
#endif

#endif // SOMBRA_LLAMA_H
