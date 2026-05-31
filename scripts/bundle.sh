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

# Ícone do app + ícones da barra de menu.
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp -f "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
[ -f "$ROOT/Resources/menu-black.png" ] && cp -f "$ROOT/Resources/menu-black.png" "$APP/Contents/Resources/"
[ -f "$ROOT/Resources/menu-white.png" ] && cp -f "$ROOT/Resources/menu-white.png" "$APP/Contents/Resources/"
[ -f "$ROOT/Resources/indicator.png" ] && cp -f "$ROOT/Resources/indicator.png" "$APP/Contents/Resources/"

# Bibliotecas do llama.cpp (resolvidas em runtime via @executable_path/../Frameworks).
if [ -d "$ROOT/Frameworks" ]; then
    cp -f "$ROOT/Frameworks/"*.dylib "$APP/Contents/Frameworks/"
fi

# Modelo .gguf: por padrão NÃO embutimos (app leve — o usuário escolhe e baixa
# o modelo no onboarding). Use SOMBRA_EMBED_MODEL=1 para embutir (ex.: build
# offline/demo).
if [ "${SOMBRA_EMBED_MODEL:-0}" = "1" ] && compgen -G "$ROOT/models/"*.gguf > /dev/null; then
    mkdir -p "$APP/Contents/Resources/models"
    cp -f "$ROOT/models/"*.gguf "$APP/Contents/Resources/models/"
    echo "    Modelo embutido (SOMBRA_EMBED_MODEL=1)."
else
    echo "    App sem modelo embutido (leve). O modelo é baixado no onboarding."
fi

# Assinatura ad-hoc: necessária para Acessibilidade/Event Tap persistirem
# a permissão de forma estável entre execuções.
echo "==> Assinando (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "==> Pronto: $APP"
echo "    Rode com: open \"$APP\"   (ou ./build/Sombra.app/Contents/MacOS/Sombra para ver logs)"
