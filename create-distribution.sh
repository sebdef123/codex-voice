#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/Codex Voice 2.app"
OUT_DIR="$ROOT_DIR/Distribution/out"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/CodexVoice/Info.plist")"
PACKAGE_NAME="Codex Voice 2-$VERSION-apple-silicon"
STAGING_DIR="$OUT_DIR/$PACKAGE_NAME"
ZIP_PATH="$OUT_DIR/$PACKAGE_NAME.zip"

zsh "$ROOT_DIR/test-codex-voice.sh"
zsh "$ROOT_DIR/build-codex-voice.sh"

rm -rf "$STAGING_DIR" "$ZIP_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Codex Voice 2.app"
cp "$ROOT_DIR/Distribution/README-START-HERE.md" "$STAGING_DIR/README-START-HERE.md"
cp "$ROOT_DIR/Distribution/Preparer Voxtral.command" "$STAGING_DIR/Preparer Voxtral.command"
chmod +x "$STAGING_DIR/Preparer Voxtral.command"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR" "$ZIP_PATH"

echo "Archive creee: $ZIP_PATH"
