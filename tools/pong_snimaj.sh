#!/usr/bin/env bash
# Гласовен понг: звучниот водич (2 звуци во круг) и новото објаснување.
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/pong_snimaj.sh
#
# 1. tools/pong_zvuci.tsv  -> assets/sounds/pong/  (guide_good, guide_bad)
#    Ако не ти се допаѓа некој звук: избриши ја датотеката и пушти пак.
# 2. tools/pong_<ј>.tsv    -> assets/audio/voice_pong/<ј>/  (explanation - се пребришува)
# Опции: MK_SPEED=0.85, OTHER_SPEED=1.0, ELEVENLABS_MODEL_ID=eleven_v3, само звуци: SAMO_ZVUCI=1

set -e
cd "$(dirname "$0")/.."

if [ -z "$ELEVENLABS_API_KEY" ]; then
  echo "Прво постави ELEVENLABS_API_KEY (export ...)."
  exit 1
fi

echo "===== Звуци за водичот ====="
ELEVENLABS_LOOP=1 python3 tools/elevenlabs_zvuci.py tools/pong_zvuci.tsv assets/sounds/pong

[ "$SAMO_ZVUCI" = "1" ] && exit 0
if [ -z "$ELEVENLABS_VOICE_ID" ]; then
  echo "За објаснувањето постави и ELEVENLABS_VOICE_ID."
  exit 1
fi

export ELEVENLABS_MODEL_ID="${ELEVENLABS_MODEL_ID:-eleven_v3}"
export ELEVENLABS_STABILITY="${ELEVENLABS_STABILITY:-0.5}"
MK_SPEED="${MK_SPEED:-0.85}"
OTHER_SPEED="${OTHER_SPEED:-1.0}"
for l in mk en sq; do
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  echo
  echo "===== Објаснување: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE=1 \
    python3 tools/elevenlabs_generiraj.py "tools/pong_$l.tsv" "assets/audio/voice_pong/$l"
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"
