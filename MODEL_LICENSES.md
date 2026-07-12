# Model and dependency notices

## Voxtral TTS model weights

Codex Voice optionally loads:

`mlx-community/Voxtral-4B-TTS-2603-mlx-4bit`

The application does not bundle, mirror, or redistribute these weights. The model is downloaded directly by the user’s local environment when Voxtral setup is requested.

Mistral lists Voxtral TTS under **CC BY-NC 4.0**. This means the local Voxtral feature must not be used commercially. Users are responsible for reviewing and complying with the model card and all upstream terms before use.

- Mistral model information: https://docs.mistral.ai/models/model-selection-guide?models=voxtral-tts-26-03
- MLX Community model card: https://huggingface.co/mlx-community/Voxtral-4B-TTS-2603-mlx-4bit

## mlx-audio

The release preparation script pins `mlx-audio[tts]` to `0.4.5`, the version used to validate this release. Its license and transitive dependency notices remain those of their respective authors.

## OpenAI naming

Codex Voice is independent software. It does not include OpenAI code, credentials, APIs, logos, or model weights.
