#!/usr/bin/env bash
# Empacota o Sombra.app num .dmg (com atalho para /Applications) em ./dist.
# Não faz assinatura Developer ID/notarização — é para uso local/compartilhamento
# simples. Para distribuição pública, assine e notarize separadamente.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Sombra.app"
DIST="$ROOT/dist"
STAGE="$DIST/.stage"
DMG="$DIST/Sombra.dmg"
VOL="Sombra"

# Garante que o .app está construído e atualizado.
if [ ! -d "$APP" ]; then
    echo "==> .app não encontrado; construindo…"
    "$ROOT/scripts/bundle.sh" release
fi

echo "==> Preparando staging…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # atalho para arrastar

echo "==> Gerando DMG…"
mkdir -p "$DIST"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGE"

SIZE="$(du -h "$DMG" | cut -f1)"
echo "==> Pronto: $DMG ($SIZE)"
echo "    Para instalar: abra o .dmg e arraste a Sombra para Applications."
