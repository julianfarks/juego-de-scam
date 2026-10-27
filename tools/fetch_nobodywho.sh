#!/bin/bash
# Descarga las bibliotecas nativas de NobodyWho (IA local) que no se guardan en Git
# por su tamaño. Uso: tools/fetch_nobodywho.sh [linux|android|all]
set -e
VER=12.1.0
DEST="$(cd "$(dirname "$0")/.." && pwd)/addons/nobodywho"
URL="https://github.com/nobodywho-ooo/nobodywho/releases/download/nobodywho-godot-v$VER/nobodywho-godot-nobodywho-godot-v$VER.zip"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/nw.zip" "$URL"
case "${1:-all}" in
  linux) PAT="*x86_64-unknown-linux-gnu*" ;;
  android) PAT="*linux-android*" ;;
  *) PAT="*linux-android* *x86_64-unknown-linux-gnu*" ;;
esac
for p in $PAT; do unzip -o -j -q "$TMP/nw.zip" "bin/addons/nobodywho/$p" -d "$DEST"; done
rm -rf "$TMP"
ls -la "$DEST"
