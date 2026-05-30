#!/usr/bin/env bash
# Clona e compila o llama.cpp como bibliotecas dinâmicas, com Metal
# embutido (compila os shaders em RUNTIME — não precisa do compilador
# `metal` do Xcode completo). Copia dylibs e headers para o projeto.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/llama.cpp"
BUILD="$SRC/build"
DEST_LIB="$ROOT/Frameworks"
DEST_INC="$ROOT/vendor/include"

# Tag fixada para reprodutibilidade (pode atualizar depois).
LLAMA_TAG="${LLAMA_TAG:-master}"

if [ ! -d "$SRC/.git" ]; then
    echo "==> Clonando llama.cpp ($LLAMA_TAG)…"
    git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$SRC"
else
    echo "==> llama.cpp já clonado em $SRC"
fi

echo "==> Configurando (Metal embutido, libs dinâmicas)…"
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_SERVER=OFF

echo "==> Compilando (apenas a lib llama + backends ggml)…"
# Alvo `llama` puxa ggml-base/cpu/metal/blas como dependências e evita
# alvos de binário (ex.: llama-app) que exigem headers gerados.
cmake --build "$BUILD" --config Release --target llama -j"$(sysctl -n hw.ncpu)"

echo "==> Copiando artefatos…"
mkdir -p "$DEST_LIB" "$DEST_INC"
# dylibs (libllama + ggml*)
find "$BUILD" -name '*.dylib' -exec cp -f {} "$DEST_LIB/" \;
# headers públicos
cp -f "$SRC/include/llama.h" "$DEST_INC/"
cp -f "$SRC/ggml/include/"*.h "$DEST_INC/" 2>/dev/null || true

echo "==> Bibliotecas em $DEST_LIB:"
ls -1 "$DEST_LIB"
echo "==> Headers em $DEST_INC:"
ls -1 "$DEST_INC"
echo "==> OK"
