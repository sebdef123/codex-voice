#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
TEST_DIR="$ROOT/.build-cache/tests"
PYTHON_CACHE_DIR="$TEST_DIR/python-cache"
mkdir -p "$TEST_DIR"

swiftc \
  "$ROOT/CodexVoice/Sources/CommentaryDeliveryPolicy.swift" \
  "$ROOT/CodexVoice/Sources/ContentFilter.swift" \
  "$ROOT/CodexVoice/Sources/PronunciationDictionary.swift" \
  "$ROOT/CodexVoice/Sources/VoiceTypes.swift" \
  "$ROOT/Tests/ContentFilterRegression.swift" \
  -o "$TEST_DIR/content-filter-regression"

CODEX_VOICE_PRONUNCIATION_FILE="$ROOT/CodexVoice/Resources/Pronunciation/pronunciations.csv" "$TEST_DIR/content-filter-regression"

swiftc \
  "$ROOT/CodexVoice/Sources/PronunciationDictionary.swift" \
  "$ROOT/Tests/PronunciationDictionaryTransferRegression.swift" \
  -o "$TEST_DIR/pronunciation-dictionary-transfer-regression"

TRANSFER_HOME="$TEST_DIR/dictionary-transfer-home"
rm -rf "$TRANSFER_HOME"
mkdir -p "$TRANSFER_HOME"
HOME="$TRANSFER_HOME" "$TEST_DIR/pronunciation-dictionary-transfer-regression"

PYTHONPYCACHEPREFIX="$PYTHON_CACHE_DIR" python3 -m py_compile "$ROOT/CodexVoice/Resources/Scripts/voxtral_server.py"
python3 "$ROOT/Tests/VoxtralTextSegmentationRegression.py"
plutil -lint "$ROOT/CodexVoice/Info.plist" >/dev/null
grep -q '<string>1.0.0</string>' "$ROOT/CodexVoice/Info.plist"
grep -q "mlx-audio\[tts\]==0.4.5" "$ROOT/CodexVoice/Resources/Scripts/start-voxtral-server.sh"
zsh -n "$ROOT/create-distribution.sh"
zsh -n "$ROOT/Distribution/Preparer Voxtral.command"

swiftc \
  "$ROOT/CodexVoice/Sources/AudioDebugLogger.swift" \
  "$ROOT/CodexVoice/Sources/CommentaryDeliveryPolicy.swift" \
  "$ROOT/CodexVoice/Sources/TranscriptWatcher.swift" \
  "$ROOT/Tests/TranscriptWatcherRegression.swift" \
  -o "$TEST_DIR/transcript-watcher-regression"

"$TEST_DIR/transcript-watcher-regression"

grep -q 'PronunciationDictionary.applyForMacOSVoice' "$ROOT/CodexVoice/Sources/SpeechController.swift"
if rg -q 'PronunciationDictionary' "$ROOT/CodexVoice/Sources/VoiceOutputController.swift"; then
  echo "Voxtral path must not apply the macOS pronunciation dictionary" >&2
  exit 1
fi

swiftc \
  "$ROOT/CodexVoice/Sources/AudioDebugLogger.swift" \
  "$ROOT/Tests/AudioDebugLoggerRegression.swift" \
  -o "$TEST_DIR/audio-debug-logger-regression"

LOGGER_TEST_LOG="$TEST_DIR/audio-debug-logger-events.jsonl"
: > "$LOGGER_TEST_LOG"
CODEX_VOICE_LOG_FILE="$LOGGER_TEST_LOG" "$TEST_DIR/audio-debug-logger-regression"

swiftc \
  "$ROOT/CodexVoice/Sources/VoiceTypes.swift" \
  "$ROOT/CodexVoice/Sources/VoxtralServerManager.swift" \
  "$ROOT/Tests/VoxtralServerManagerAttachRegression.swift" \
  -o "$TEST_DIR/voxtral-server-manager-attach-regression"

"$TEST_DIR/voxtral-server-manager-attach-regression"

swiftc \
  "$ROOT/CodexVoice/Sources/AudioDebugLogger.swift" \
  "$ROOT/CodexVoice/Sources/PronunciationDictionary.swift" \
  "$ROOT/CodexVoice/Sources/ResourceSampler.swift" \
  "$ROOT/CodexVoice/Sources/SpeechController.swift" \
  "$ROOT/CodexVoice/Sources/VoiceOutputController.swift" \
  "$ROOT/CodexVoice/Sources/VoiceTypes.swift" \
  "$ROOT/CodexVoice/Sources/VoxtralServerManager.swift" \
  "$ROOT/CodexVoice/Sources/VoxtralStreamingController.swift" \
  "$ROOT/Tests/VoxtralCancellationRegression.swift" \
  -o "$TEST_DIR/voxtral-cancellation-regression" \
  -framework AVFoundation

mkdir -p "$TEST_DIR/cancellation-home"
TEST_LOG="$TEST_DIR/voxtral-cancellation-events.jsonl"
: > "$TEST_LOG"
CODEX_VOICE_LOG_FILE="$TEST_LOG" HOME="$TEST_DIR/cancellation-home" "$TEST_DIR/voxtral-cancellation-regression"
if [ -s "$TEST_LOG" ]; then
  grep -q '"event":"tts_requested"' "$TEST_LOG"
  grep -q '"event":"tts_interrupted"' "$TEST_LOG"
  grep -q '"interruptionReason":"test_cancel_before_ready"' "$TEST_LOG"
fi

echo "Codex Voice 2 tests: ok"
