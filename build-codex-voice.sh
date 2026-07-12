#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/Codex Voice 2.app"
INSTALL_APP="/Applications/Codex Voice 2.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CACHE_DIR="$ROOT_DIR/.build-cache/codex-voice"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$CACHE_DIR"
cp "$ROOT_DIR/CodexVoice/Info.plist" "$CONTENTS_DIR/Info.plist"

CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" swiftc \
  "$ROOT_DIR"/CodexVoice/Sources/*.swift \
  -o "$MACOS_DIR/CodexVoice2" \
  -target arm64-apple-macos12.0 \
  -module-cache-path "$CACHE_DIR/swift" \
  -framework AppKit \
  -framework AVFoundation

rm -rf "$RESOURCES_DIR/Scripts"
mkdir -p "$RESOURCES_DIR/Scripts"
cp "$ROOT_DIR/CodexVoice/Resources/Scripts/voxtral_server.py" "$RESOURCES_DIR/Scripts/"
cp "$ROOT_DIR/CodexVoice/Resources/Scripts/start-voxtral-server.sh" "$RESOURCES_DIR/Scripts/"
cp "$ROOT_DIR/CodexVoice/Resources/Scripts/voxtral_text.py" "$RESOURCES_DIR/Scripts/"
rm -rf "$RESOURCES_DIR/Pronunciation"
mkdir -p "$RESOURCES_DIR/Pronunciation"
cp "$ROOT_DIR/CodexVoice/Resources/Pronunciation/pronunciations.csv" "$RESOURCES_DIR/Pronunciation/"
chmod +x "$MACOS_DIR/CodexVoice2" "$RESOURCES_DIR/Scripts"/*.py "$RESOURCES_DIR/Scripts"/*.sh

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "App creee: $APP_DIR"

if [[ "${CODEX_VOICE_SKIP_INSTALL:-0}" != "1" ]]; then
  if [[ ! -w "/Applications" ]]; then
    echo "Installation impossible: /Applications n'est pas accessible en ecriture." >&2
    echo "Utilise CODEX_VOICE_SKIP_INSTALL=1 pour ne produire que le bundle local." >&2
    exit 1
  fi

  rm -rf "$INSTALL_APP"
  ditto "$APP_DIR" "$INSTALL_APP"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$INSTALL_APP" >/dev/null
    codesign --verify --deep --strict "$INSTALL_APP"
  fi
  echo "App installee: $INSTALL_APP"
fi
