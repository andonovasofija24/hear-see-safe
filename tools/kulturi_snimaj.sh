#!/usr/bin/env bash
# Снимки за новата категорија „Културите на светот“ во сликовницата (60 по јазик: _name, _explanation, _desc и 3 знаменитости по земја).
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/kulturi_snimaj.sh          # сите три јазици
#   bash tools/kulturi_snimaj.sh mk       # само македонски
#
# Листа: tools/kulturi_<ј>.tsv -> assets/audio/picture_book/<ј>/
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
  tsv="tools/kulturi_$l.tsv"
  if [ ! -f "$tsv" ]; then echo "Ја нема $tsv - прескокнувам."; continue; fi
  echo
  echo "===== Јазик: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE="$OW" \
    python3 tools/elevenlabs_generiraj.py "$tsv" "assets/audio/picture_book/$l"
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"
