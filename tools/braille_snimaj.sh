#!/usr/bin/env bash
# Снимки за „Braille Lab“ (тајните на Брајовото писмо) со ElevenLabs v3.
#
# Употреба (од која било папка):
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/braille_snimaj.sh            # сите три јазици
#   bash tools/braille_snimaj.sh mk         # само македонски
#
# Листи:
#   tools/braille_lab_<ј>.tsv        -> assets/audio/braille/<ј>/
#       secrets_name_* и secrets_intro_* - СЕКОГАШ се пребришуваат (нови текстови)
#   tools/braille_lab_kratki_<ј>.tsv -> assets/audio/braille/<ј>/  (dot_1..dot_6, char_number_sign)
#   tools/braille_lab_broevi_<ј>.tsv -> assets/audio/number_games/<ј>/  (plus, minus)
#       кратките се прават само ако ги нема; SITE_ODNOVO=1 ги пребришува и нив.
#
# Опции: MK_SPEED=0.85 (македонски), OTHER_SPEED=1.0, ELEVENLABS_MODEL_ID=eleven_v3

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
LANGS="${*:-mk en sq}"

run() { # $1 = tsv, $2 = папка, $3 = јазик, $4 = брзина, $5 = пребриши (0/1)
  if [ ! -f "$1" ]; then echo "Ја нема $1 - прескокнувам."; return; fi
  echo "--- $1  ->  $2"
  ELEVENLABS_LANGUAGE="$3" ELEVENLABS_SPEED="$4" ELEVENLABS_OVERWRITE="$5" \
    python3 tools/elevenlabs_generiraj.py "$1" "$2"
}

for l in $LANGS; do
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  echo
  echo "===== Јазик: $l (брзина $sp) ====="
  run "tools/braille_lab_$l.tsv" "assets/audio/braille/$l" "$l" "$sp" 1
  run "tools/braille_lab_kratki_$l.tsv" "assets/audio/braille/$l" "$l" "$sp" "$OW"
  run "tools/braille_lab_broevi_$l.tsv" "assets/audio/number_games/$l" "$l" "$sp" "$OW"
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"
