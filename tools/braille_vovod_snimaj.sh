#!/usr/bin/env bash
# Снимки за новата категорија Вовед во Брајовата азбука (game_name = со тастатура, game_name_touch = за телефон).
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/braille_vovod_snimaj.sh          # сите три јазици
#   bash tools/braille_vovod_snimaj.sh mk       # само македонски
#
# Листа: tools/braille_vovod_<ј>.tsv -> assets/audio/braille/<ј>/
# Веќе направените се прескокнуваат; SITE_ODNOVO=1 ги пребришува.
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
OW=0; [ "$SITE_ODNOVO" = "1" ] && OW=1

for l in ${*:-mk en sq}; do
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  tsv="tools/braille_vovod_$l.tsv"
  if [ ! -f "$tsv" ]; then echo "Ја нема $tsv - прескокнувам."; continue; fi
  echo
  echo "===== Јазик: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE="$OW" \
    python3 tools/elevenlabs_generiraj.py "$tsv" "assets/audio/braille/$l"
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"
