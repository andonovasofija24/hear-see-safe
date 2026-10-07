#!/usr/bin/env bash
# Ги снима сите говорни снимки за сликовницата („Учи и слушај“)
# со ElevenLabs v3, со задолжителен јазик (language override).
#
# Употреба (од која било папка):
#   export ELEVENLABS_API_KEY="твојот_клуч"
#   export ELEVENLABS_VOICE_ID="id_на_гласот"
#   bash tools/sliko_snimaj.sh            # сите три јазици
#   bash tools/sliko_snimaj.sh mk         # само македонски
#
# Што прави за секој јазик:
#   1. sliko_presnimi_<ј>.tsv - СТАРИТЕ снимки, се ПРЕБРИШУВААТ со новиот глас
#   2. sliko_stari_<ј>.tsv    - снимки што недостасуваа кај старите поими
#   3. sliko_novi_<ј>.tsv     - снимки за новите поими
#   (2 и 3 ги прескокнуваат веќе направените; SITE_ODNOVO=1 ги прави и нив одново)
#
# Опции:
#   MK_SPEED=0.85    брзина за македонски (помало = побавно, 0.7-1.2)
#   OTHER_SPEED=1.0  брзина за англиски и албански
#   ELEVENLABS_MODEL_ID=eleven_v3

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
LANGS="${*:-mk en sq}"

for l in $LANGS; do
  out="assets/audio/picture_book/$l"
  if [ "$l" = "mk" ]; then sp="$MK_SPEED"; else sp="$OTHER_SPEED"; fi
  echo
  echo "===== Јазик: $l (брзина $sp) ====="
  for list in presnimi stari novi; do
    tsv="tools/sliko_${list}_$l.tsv"
    if [ ! -f "$tsv" ]; then echo "Ја нема $tsv - прескокнувам."; continue; fi
    ow=0
    if [ "$list" = "presnimi" ] || [ "$SITE_ODNOVO" = "1" ]; then ow=1; fi
    echo "--- $tsv"
    ELEVENLABS_LANGUAGE="$l" ELEVENLABS_SPEED="$sp" ELEVENLABS_OVERWRITE="$ow" \
      python3 tools/elevenlabs_generiraj.py "$tsv" "$out"
  done
done
echo
echo "Готово. Сега: flutter build apk --release --split-per-abi"