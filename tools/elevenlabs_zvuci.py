#!/usr/bin/env python3
"""
Генерирање звучни ефекти со ElevenLabs Sound Effects.

Чита список (TSV: име_на_датотека <TAB> англиски опис <TAB> траење_во_секунди)
и за секој ред зачувува <излезна_папка>/<име>.mp3. Користи само стандардна
Python библиотека - не треба pip ни sudo.

Употреба:
    export ELEVENLABS_API_KEY="твојот_клуч"
    python3 elevenlabs_zvuci.py sliko_zvuci.tsv ~/hear-see-safe/assets/sounds/sound_identification

Опции (по избор, како променливи на околината):
    ELEVENLABS_PROMPT_INFLUENCE  0.0-1.0 (стандардно: 0.5) - колку строго да го следи описот
    ELEVENLABS_OVERWRITE         1 = пресними ги и постоечките датотеки

Веќе направените датотеки се прескокнуваат, па ако скриптата прекине
(интернет, лимит на кредити), само пушти ја повторно - продолжува.
Ако некој звук не ти се допаѓа, избриши ја датотеката и пушти ја пак.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"


def generate(text, duration, api_key, prompt_influence):
    body = {"text": text, "prompt_influence": prompt_influence}
    if duration is not None:
        body["duration_seconds"] = duration
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    list_path, out_dir = sys.argv[1], os.path.expanduser(sys.argv[2])

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        print("Постави ELEVENLABS_API_KEY (види го упатството горе во датотеката).")
        sys.exit(1)
    prompt_influence = float(os.environ.get("ELEVENLABS_PROMPT_INFLUENCE", "0.5"))
    overwrite = os.environ.get("ELEVENLABS_OVERWRITE") == "1"

    os.makedirs(out_dir, exist_ok=True)

    rows = []
    with open(list_path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                print(f"Ред {n}: нема TAB помеѓу името и описот - прескокнувам: {line}")
                continue
            name, text = parts[0].strip(), parts[1].strip()
            duration = None
            if len(parts) >= 3 and parts[2].strip():
                try:
                    duration = float(parts[2].strip())
                except ValueError:
                    print(f"Ред {n}: траењето „{parts[2]}“ не е број - ќе користам автоматско.")
            if duration is not None:
                duration = min(30.0, max(0.5, duration))  # API дозволува 0.5-30 с
            rows.append((name, text, duration))

    done = skipped = failed = 0
    for i, (name, text, duration) in enumerate(rows, 1):
        path = os.path.join(out_dir, name if name.endswith(".mp3") else name + ".mp3")
        if os.path.exists(path) and os.path.getsize(path) > 0 and not overwrite:
            skipped += 1
            print(f"[{i}/{len(rows)}] веќе постои: {os.path.basename(path)} - прескокнувам")
            continue
        for attempt in range(1, 6):
            try:
                audio = generate(text, duration, api_key, prompt_influence)
                with open(path, "wb") as out:
                    out.write(audio)
                done += 1
                print(f"[{i}/{len(rows)}] ✓ {os.path.basename(path)}  ←  {text} ({duration or 'авто'} с)")
                break
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:300]
                if e.code == 429 or e.code >= 500:
                    wait = 5 * attempt
                    print(f"   {e.code} - чекам {wait} с и пробувам пак ({attempt}/5)...")
                    time.sleep(wait)
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
        time.sleep(0.5)  # мала пауза меѓу барањата

    print(f"\nГотово: нови {done}, веќе постоеја {skipped}, неуспешни {failed}.")
    if failed:
        print("Пушти ја скриптата пак - ќе ги проба само неуспешните.")


if __name__ == "__main__":
    main()
