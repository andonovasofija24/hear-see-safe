#!/usr/bin/env bash
# Идентификација на звук: ново објаснување (лентата до увото).
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/zvuk_snimaj.sh          # сите три јазици
#   bash tools/zvuk_snimaj.sh mk       # само македонски
#
# tools/zvuk_<ј>.tsv -> assets/audio/sound_identification/<ј>/explanation.mp3 (се пребришува)
# Опции: MK_SPEED=0.85, OTHER_SPEED=1.0, ELEVENLABS_MODEL_ID=eleven_v3

set -e
cd "$(dirname "$0")/.."
if [ -z "$ELEVENLABS_API_KEY" ] || [ -z "$ELEVENLABS_VOICE_ID" ]; then
  echo "Прво постави ELEVENLABS_API_KEY и ELEVENLABS_VOICE_ID (export ...)."
  exit 1
fi
export ELEVENLABS_MODEL_ID="${ELEVENLABS_MODEL_ID:-eleven_v3}"
export ELEVENLABS_STABILITY="${ELEVENLABS_STABILITY:-0.5}"
MK_SPEED="${MK_SPEED:-0.85}"
OTHER_SPEED="${OTHER_SPEED:-1.0}"
for l in ${*:-mk en sq}; do
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  echo
  echo "===== Објаснување: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE=1 \
    python3 tools/elevenlabs_generiraj.py "tools/zvuk_$l.tsv" "assets/audio/sound_identification/$l"
done
echo
echo "Готово."
