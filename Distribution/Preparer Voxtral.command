#!/bin/zsh
set -euo pipefail

MODEL_ID="mlx-community/Voxtral-4B-TTS-2603-mlx-4bit"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Codex Voice 2 Voxtral requiert un Mac Apple Silicon."
  read -r "?Appuie sur Entree pour fermer cette fenetre."
  exit 1
fi

if [[ -x "$HOME/.local/bin/uv" ]]; then
  UV="$HOME/.local/bin/uv"
elif [[ -x "/opt/homebrew/bin/uv" ]]; then
  UV="/opt/homebrew/bin/uv"
else
  UV="$(command -v uv || true)"
fi

if [[ -z "$UV" ]]; then
  echo "uv est requis pour preparer Voxtral."
  echo "Installe-le depuis https://docs.astral.sh/uv/ puis relance ce fichier."
  read -r "?Appuie sur Entree pour fermer cette fenetre."
  exit 1
fi

echo "Preparation de Voxtral. Le premier lancement telecharge les dependances et le modele local."
"$UV" run --python 3.11 --with 'mlx-audio[tts]==0.4.5' --with numpy --with soundfile python -c "from mlx_audio.utils import load_model; load_model('$MODEL_ID'); print('Voxtral est pret.')"
echo "Preparation terminee. Tu peux maintenant choisir Voxtral Streaming dans Codex Voice 2."
read -r "?Appuie sur Entree pour fermer cette fenetre."
