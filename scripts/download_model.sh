#!/usr/bin/env bash
# Baixa o modelo SmolLM2-360M-Instruct quantizado (GGUF) para ./models.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/models"
NAME="SmolLM2-360M-Instruct-Q8_0.gguf"
URL="${SOMBRA_MODEL_URL:-https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf}"

mkdir -p "$DEST"
OUT="$DEST/$NAME"

if [ -f "$OUT" ]; then
    echo "==> Já existe: $OUT ($(du -h "$OUT" | cut -f1))"
    exit 0
fi

echo "==> Baixando $NAME (~390 MB)…"
curl -L --fail --progress-bar -o "$OUT.part" "$URL"
mv "$OUT.part" "$OUT"
echo "==> Pronto: $OUT ($(du -h "$OUT" | cut -f1))"
