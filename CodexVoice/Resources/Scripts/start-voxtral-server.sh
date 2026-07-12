#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
if [[ -x "$HOME/.local/bin/uv" ]]; then
  UV="$HOME/.local/bin/uv"
elif [[ -x "/opt/homebrew/bin/uv" ]]; then
  UV="/opt/homebrew/bin/uv"
else
  UV="$(command -v uv || true)"
fi

if [[ -z "$UV" ]]; then
  echo "uv was not found. Install it first: https://docs.astral.sh/uv/" >&2
  exit 1
fi

echo "Starting the Voxtral 4B 4bit bridge. --preload warms the model before the server accepts speech."
exec "$UV" run --python 3.11 --with 'mlx-audio[tts]==0.4.5' --with numpy --with soundfile python "$ROOT/voxtral_server.py" "$@"
