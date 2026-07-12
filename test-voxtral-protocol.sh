#!/bin/zsh
set -euo pipefail

BASE_URL="${VOXTRAL_BASE_URL:-http://127.0.0.1:8765}"
TEXT="${1:-Bonjour, ceci est le test de protocole local.}"
VOICE="${2:-fr_female}"
OUTPUT_FILE="$(mktemp -t codex-voice2-voxtral.XXXXXX)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

health="$(curl -fsS --max-time 2 "$BASE_URL/health")"
echo "$health" | jq -e '.ok == true' >/dev/null

payload="$(jq -nc --arg text "$TEXT" --arg voice "$VOICE" '{text: $text, voice: $voice}')"
curl -fsS --max-time 180 \
  -H 'Content-Type: application/json' \
  -X POST "$BASE_URL/speak/stream" \
  --data "$payload" \
  --output "$OUTPUT_FILE"

test -s "$OUTPUT_FILE"
grep -a -q '"audioSeconds"' "$OUTPUT_FILE"
grep -a -q '"generationSeconds"' "$OUTPUT_FILE"
grep -a -q '"mlxPeakMemoryBytes"' "$OUTPUT_FILE"

echo "Voxtral protocol: ok (voice=$VOICE, bytes=$(wc -c < "$OUTPUT_FILE" | tr -d ' '))"
