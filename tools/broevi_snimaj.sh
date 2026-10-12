#!/usr/bin/env bash
# Игри со броеви - новите варијанти:
#  1. tools/broevi_zvuci.tsv -> assets/sounds/number_games/
#     (heartbeat, locator_ping, tower_crash, balloon_pop, laser_cut, safe_unlock, drum_hit)
#     Ако не ти се допаѓа некој звук: избриши ја датотеката и пушти пак.
#  2. tools/broevi_<ј>.tsv   -> assets/audio/number_games/<ј>/
#     (which_sign, balloons_sum, balloons_diff, laser_prompt)
#
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/broevi_snimaj.sh            # звуци + сите три јазици
#   bash tools/broevi_snimaj.sh mk         # звуци + само македонски
#   SAMO_ZVUCI=1 bash tools/broevi_snimaj.sh
# Опции: MK_SPEED=0.85, OTHER_SPEED=1.0, ELEVENLABS_MODEL_ID=eleven_v3

set -e
cd "$(dirname "$0")/.."

if [ -z "$ELEVENLABS_API_KEY" ]; then
  echo "Прво постави ELEVENLABS_API_KEY (export ...)."
  exit 1
fi

echo "===== Звуци ====="
python3 tools/elevenlabs_zvuci.py tools/broevi_zvuci.tsv assets/sounds/number_games

[ "$SAMO_ZVUCI" = "1" ] && exit 0
if [ -z "$ELEVENLABS_VOICE_ID" ]; then
  echo "За снимките постави и ELEVENLABS_VOICE_ID."
  exit 1
fi

export ELEVENLABS_MODEL_ID="${ELEVENLABS_MODEL_ID:-eleven_v3}"
export ELEVENLABS_STABILITY="${ELEVENLABS_STABILITY:-0.5}"
MK_SPEED="${MK_SPEED:-0.85}"
OTHER_SPEED="${OTHER_SPEED:-1.0}"
for l in ${*:-mk en sq}; do
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  echo
  echo "===== Снимки: $l (брзина $sp) ====="
  ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" \
    python3 tools/elevenlabs_generiraj.py "tools/broevi_$l.tsv" "assets/audio/number_games/$l"
done
echo
echo "Готово. Во pubspec.yaml мора да постои ред:  - assets/sounds/number_games/"
