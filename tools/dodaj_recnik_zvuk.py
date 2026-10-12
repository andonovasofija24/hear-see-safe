#!/usr/bin/env python3
"""
Идентификација на звук - лентата до увото: ги додава новите зборови
(belt_*) и го менува објаснувањето (explanation_text) во делот "sound"
во трите речници. Останатото не се менува. Безбедно е да се пушти пак.

Употреба (од папката на проектот):
    python3 tools/dodaj_recnik_zvuk.py
"""
import json
import os
import re

NOVI = {
    "mk-MK": {
        "belt_stop": "Запри – ова е тоа!",
        "belt_continue": "Продолжи",
        "belt_slow": "Побавно",
        "belt_fast": "Побрзо",
        "belt_start_hint": "Притисни „Пушти звук“ – потоа картичките тргнуваат кон увото.",
        "belt_hint": "Пред увото секоја картичка застанува и го пушта својот звук. Кога ќе го чуеш истиот звук – запри! Може и да допреш картичка или да го кажеш нејзиното име.",
        "explanation_text": "Играта има 20 рунди. Притисни „Пушти звук“ и слушни го звукот. Потоа картичките тргнуваат по свитканата лента кон увото. Пред секоја картичка да влезе во увото, таа застанува и се слуша нејзиниот звук. Кога ќе го чуеш истиот звук што го слушна на почетокот, притисни „Запри – ова е тоа!“ или кажи „запри“. Ако не е тоа, притисни „Продолжи“ или почекај малку и лентата сама ќе продолжи. Може и директно да ја допреш картичката или да го кажеш нејзиното име. Со копчето „Побавно“ лентата оди полека. На крајот ќе видиш колку си погодил."
    },
    "en-US": {
        "belt_stop": "Stop – this is it!",
        "belt_continue": "Continue",
        "belt_slow": "Slower",
        "belt_fast": "Faster",
        "belt_start_hint": "Tap “Play sound” – then the cards start moving toward the ear.",
        "belt_hint": "In front of the ear each card stops and plays its sound. When you hear the same sound – stop! You can also tap a card or say its name.",
        "explanation_text": "The game has 20 rounds. Tap “Play sound” and listen. Then the cards start moving along the curved ribbon toward the ear. Before each card goes into the ear, it stops and plays its own sound. When you hear the same sound you heard at the start, tap “Stop – this is it!” or say “stop”. If it is not the one, tap “Continue” or wait a moment and the ribbon moves on by itself. You can also tap a card directly or say its name. With “Slower” the ribbon moves slowly. At the end you will see how many you got right."
    },
    "sq-AL": {
        "belt_stop": "Ndalo – ky është!",
        "belt_continue": "Vazhdo",
        "belt_slow": "Më ngadalë",
        "belt_fast": "Më shpejt",
        "belt_start_hint": "Prek “Luaj zërin” – pastaj kartat nisen drejt veshit.",
        "belt_hint": "Para veshit çdo kartë ndalon dhe luan tingullin e saj. Kur dëgjon të njëjtin tingull – ndalo! Mund edhe të prekësh një kartë ose të thuash emrin e saj.",
        "explanation_text": "Loja ka 20 raunde. Prek “Luaj zërin” dhe dëgjo. Pastaj kartat nisen nëpër shiritin e lakuar drejt veshit. Para se çdo kartë të hyjë në vesh, ajo ndalon dhe luan tingullin e vet. Kur dëgjon të njëjtin tingull që dëgjove në fillim, prek “Ndalo – ky është!” ose thuaj “ndalo”. Nëse nuk është ai, prek “Vazhdo” ose prit pak dhe shiriti vazhdon vetë. Mund edhe ta prekësh kartën drejtpërdrejt ose të thuash emrin e saj. Me “Më ngadalë” shiriti lëviz ngadalë. Në fund do të shohësh sa ke qëlluar."
    }
}

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
for ime, zborovi in NOVI.items():
    pat = os.path.join("assets", "translations", ime + ".json")
    with open(pat, encoding="utf-8") as f:
        text = f.read()
    anchor = '"sound": {'
    i = text.find(anchor)
    if i < 0:
        print(f"{ime}: не го најдов делот sound - прескокнувам.")
        continue
    # Крајот на делот "sound" (заградата што го затвора).
    depth, j = 0, i + len(anchor) - 1
    while True:
        ch = text[j]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        elif ch == '"':
            j += 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
        j += 1
    del_ = text[i:j + 1]
    postoi = json.loads(del_[len('"sound": '):])
    promeni = 0
    for k, v in zborovi.items():
        nov = f"{json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}"
        if k in postoi:
            if postoi[k] == v:
                continue
            # Замена на постоечката вредност (само за explanation_text).
            del_ = re.sub(re.escape(json.dumps(k)) + r'\s*:\s*"(?:[^"\\]|\\.)*"', lambda m: nov, del_, count=1)
        else:
            del_ = del_.replace(anchor, anchor + "\n  " + nov + ",", 1)
        promeni += 1
    text = text[:i] + del_ + text[j + 1:]
    json.loads(text)
    with open(pat, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{ime}: {promeni} промени.")
print("Готово.")
