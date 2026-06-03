#!/usr/bin/env bash
# Aponta o app de teste (bundle id com.sombra.autocomplete.teste) para um modelo,
# pra comparar 4B vs 1.7B na completação "dicionário + ranqueio do modelo".
# Uso: ./scripts/use_model_teste.sh [4b|1.7b|<caminho.gguf>]
set -euo pipefail
M="$HOME/Library/Application Support/Sombra/models"
arg="${1:-1.7b}"
case "$arg" in
  4b|4B)     path="$M/Qwen3-4B-Q4_K_M.gguf";;
  1.7b|1.7B) path="$M/Qwen3-1.7B-Q4_K_M.gguf";;
  *)         path="$arg";;
esac
[ -f "$path" ] || { echo "modelo não encontrado: $path" >&2; exit 1; }
defaults write com.sombra.autocomplete.teste modelPath "$path"
echo "app de teste → $(basename "$path")"
echo "(reinicie o \"Sombra teste\", ou use Recarregar modelo ⌘R no menu, p/ aplicar)"
