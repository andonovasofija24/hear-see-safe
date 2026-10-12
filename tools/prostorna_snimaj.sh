#!/usr/bin/env bash
# Снимки за „Просторна ориентација“: „Сврти се кон север/југ/исток/запад“
# (компас на телефон) и новото објаснување за „Насоки“ (број на вибрации).
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/prostorna_snimaj.sh          # сите три јазици
#   bash tools/prostorna_snimaj.sh mk       # само македонски
#
# Листа: tools/prostorna_<ј>.tsv -> assets/audio/spatial_orientation/<ј>/
# Сите снимки од листата се пребришуваат (explanation_simon има нов текст).
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
  tsv="tools/prostorna_$l.tsv"
  if [ ! -f "$tsv" ]; then echo "Ја нема $tsv - прескокнувам."; continue; fi
  echo
  echo "===== Јазик: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE=1 \
    python3 tools/elevenlabs_generiraj.py "$tsv" "assets/audio/spatial_orientation/$l"
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"
