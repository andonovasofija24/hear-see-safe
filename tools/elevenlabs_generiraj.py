#!/usr/bin/env python3
"""
Генерирање снимки со ElevenLabs, збор по збор.

Чита список (TSV: име_на_датотека <TAB> текст) и за секој ред зачувува
<излезна_папка>/<име>.mp3. Користи само стандардна Python библиотека -
не треба pip ни sudo.

Употреба:
    export ELEVENLABS_API_KEY="твојот_клуч"
    export ELEVENLABS_VOICE_ID="id_на_гласот"
    python3 elevenlabs_generiraj.py kamera_sq.tsv ~/hear-see-safe/assets/audio/camera/sq

Опции (по избор, како променливи на околината):
    ELEVENLABS_MODEL_ID   модел (стандардно: eleven_multilingual_v2; за v3: eleven_v3)
    ELEVENLABS_LANGUAGE   задолжителен јазик (language override): mk, en, sq
                          (не работи со eleven_multilingual_v2 - таму се прескокнува)
    ELEVENLABS_SPEED      брзина на говор 0.7-1.2 (1.0 = нормално, 0.85 = побавно)
    ELEVENLABS_STABILITY  0.0-1.0 (стандардно: 0.5; кај v3 само 0.0, 0.5 или 1.0)
    ELEVENLABS_SIMILARITY 0.0-1.0 (стандардно: 0.75)
    ELEVENLABS_OVERWRITE  1 = пресними и постоечките датотеки

Веќе направените датотеки се прескокнуваат, па ако скриптата прекине
(интернет, лимит на кредити), само пушти ја повторно - продолжува.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128"


def generate(text, voice_id, api_key, model_id, stability, similarity, language=None, speed=None):
    settings = {"stability": stability, "similarity_boost": similarity}
    if speed is not None:
        settings["speed"] = speed
    body = {
        "text": text,
        "model_id": model_id,
        "voice_settings": settings,
    }
    if language:
        body["language_code"] = language
    req = urllib.request.Request(
        API_URL.format(voice_id=voice_id),
        data=json.dumps(body).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    list_path, out_dir = sys.argv[1], os.path.expanduser(sys.argv[2])

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    voice_id = os.environ.get("ELEVENLABS_VOICE_ID")
    if not api_key or not voice_id:
        print("Постави ELEVENLABS_API_KEY и ELEVENLABS_VOICE_ID (види го упатството горе во датотеката).")
        sys.exit(1)
    model_id = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
    stability = float(os.environ.get("ELEVENLABS_STABILITY", "0.5"))
    similarity = float(os.environ.get("ELEVENLABS_SIMILARITY", "0.75"))
    overwrite = os.environ.get("ELEVENLABS_OVERWRITE") == "1"
    language = os.environ.get("ELEVENLABS_LANGUAGE") or None
    if language and model_id == "eleven_multilingual_v2":
        print("Напомена: eleven_multilingual_v2 не прима ELEVENLABS_LANGUAGE - го прескокнувам.")
        language = None
    speed = os.environ.get("ELEVENLABS_SPEED")
    speed = float(speed) if speed else None
    print(f"Модел: {model_id} | јазик: {language or 'автоматски'} | брзина: {speed or 1.0}")

    os.makedirs(out_dir, exist_ok=True)

    rows = []
    with open(list_path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            if "\t" not in line:
                print(f"Ред {n}: нема TAB помеѓу името и текстот - прескокнувам: {line}")
                continue
            name, text = line.split("\t", 1)
            rows.append((name.strip(), text.strip()))

    done = skipped = failed = 0
    for i, (name, text) in enumerate(rows, 1):
        path = os.path.join(out_dir, name if name.endswith(".mp3") else name + ".mp3")
        if os.path.exists(path) and os.path.getsize(path) > 0 and not overwrite:
            skipped += 1
            continue
        for attempt in range(1, 6):
            try:
                audio = generate(text, voice_id, api_key, model_id, stability, similarity, language, speed)
                with open(path, "wb") as out:
                    out.write(audio)
                done += 1
                print(f"[{i}/{len(rows)}] ✓ {os.path.basename(path)}  ←  {text}")
                break
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:300]
                if e.code == 429 or e.code >= 500:
                    wait = 5 * attempt
                    print(f"   {e.code} - чекам {wait} с и пробувам пак ({attempt}/5)...")
                    time.sleep(wait)
                    continue
                if e.code in (400, 422) and speed is not None and "speed" in detail.lower():
                    print("   Моделот не прима брзина (ELEVENLABS_SPEED) - продолжувам без неа.")
                    speed = None
                    continue
                if e.code in (400, 422) and language and "language" in detail.lower():
                    print(f"   Моделот не го прима јазикот '{language}' - продолжувам без него.")
                    language = None
                    continue
                print(f"[{i}/{len(rows)}] ✗ {name}: HTTP {e.code} {detail}")
                if e.code in (401, 403):
                    print("Проблем со API клучот или дозволите - прекинувам.")
                    sys.exit(1)
                failed += 1
                break
            except Exception as e:  # мрежа, timeout...
                wait = 5 * attempt
                print(f"   грешка ({e}) - чекам {wait} с ({attempt}/5)...")
                time.sleep(wait)
        else:
            failed += 1
            print(f"[{i}/{len(rows)}] ✗ {name}: не успеа по 5 обиди")
        time.sleep(0.3)  # мала пауза меѓу барањата

    print(f"\nГотово: нови {done}, веќе постоеја {skipped}, неуспешни {failed}.")
    if failed:
        print("Пушти ја скриптата пак - ќе ги проба само неуспешните.")


if __name__ == "__main__":
    main()