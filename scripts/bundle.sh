#!/usr/bin/env bash
# Compila a Sombra e monta um Sombra.app executável (sem precisar do Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Sombra.app"

echo "==> Compilando ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sombra"

echo "==> Montando bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Sombra"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Bibliotecas do llama.cpp (resolvidas em runtime via @executable_path/../Frameworks).
if [ -d "$ROOT/Frameworks" ]; then
    cp -f "$ROOT/Frameworks/"*.dylib "$APP/Contents/Frameworks/"
fi

# Modelo .gguf empacotado (se já baixado).
if compgen -G "$ROOT/models/"*.gguf > /dev/null; then
    mkdir -p "$APP/Contents/Resources/models"
    cp -f "$ROOT/models/"*.gguf "$APP/Contents/Resources/models/"
    echo "    Modelo incluído no bundle."
else
    echo "    (Sem modelo em ./models — rode scripts/download_model.sh; o app cai no heurístico.)"
fi

# Assinatura ad-hoc: necessária para Acessibilidade/Event Tap persistirem
# a permissão de forma estável entre execuções.
echo "==> Assinando (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "==> Pronto: $APP"
echo "    Rode com: open \"$APP\"   (ou ./build/Sombra.app/Contents/MacOS/Sombra para ver logs)"
