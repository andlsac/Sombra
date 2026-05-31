#!/usr/bin/env bash
# Baixa o modelo base embutido (Qwen2.5-0.5B base, GGUF) para ./models.
# Modelo BASE (continuação pura): continua o seu texto em vez de "responder"
# como um chatbot — o que dá o melhor autocomplete.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/models"
NAME="Qwen2.5-0.5B.Q8_0.gguf"
URL="${SOMBRA_MODEL_URL:-https://huggingface.co/QuantFactory/Qwen2.5-0.5B-GGUF/resolve/main/Qwen2.5-0.5B.Q8_0.gguf}"

mkdir -p "$DEST"
OUT="$DEST/$NAME"

if [ -f "$OUT" ]; then
    echo "==> Já existe: $OUT ($(du -h "$OUT" | cut -f1))"
    exit 0
fi

echo "==> Baixando $NAME (~506 MB)…"
curl -L --fail --progress-bar -o "$OUT.part" "$URL"
mv "$OUT.part" "$OUT"
echo "==> Pronto: $OUT ($(du -h "$OUT" | cut -f1))"
