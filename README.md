# Hear & See Safe

Hear & See Safe is a Flutter app with learning games for children who are blind, have low vision, or are deaf or hard of hearing. Every activity can be played by sound, by touch and vibration, or visually, and most can be controlled by voice. The app is available in Macedonian, English and Albanian.

The guiding rule for every screen was that no game should depend on a single sense. If something is shown, it is also heard or felt; if something is heard, there is also a visual or haptic cue.

## What's inside

| Module | What the child does |
|---|---|
| **Braille alphabet** | A six-dot main menu (one dot per section): introduction, the "Secrets of Braille" lab, letters and numbers, signs, a quick reference and three games (word game, free writing, sentence writing). Dots can be entered by touch, by keyboard (F D S / J K L) or by voice. |
| **Picture book** | Eight categories (institutions, cultures, nutrition, animals, nature, objects, space, music), each with its own illustrated scene, narrated items and a short quiz. Categories are browsed as a 3D book on desktop and a spiral notebook on phones. |
| **Number games** | Ten games on a rotating "number planet": recognising numbers, bigger/smaller, addition and subtraction, multiplication and division, counting objects, a tactile counter, a number locator, magic sequences, ordering and sudoku. Several games have alternative modes (towers, balloons, laser division, sound-only, visual-only). |
| **Camera recognition** | Recognises objects, colours and clothing, and has a search mode: the child names an object and the camera scans for up to 40 seconds while the torch helps in the dark. |
| **Spatial orientation** | Direction memory (each direction has its own number of vibrations), a maze, a radar game and a compass game that uses the phone's sensor. |
| **Sound identification** | Cards travel along a curved ribbon into an ear; each card plays its sound before it goes in, and the child stops the ribbon at the right one. |
| **Melody memory** | A sequence of sounds plays on the same ribbon; the child rebuilds it in order by touch or by saying the names. |
| **Sound memory** | A memory game with jigsaw pieces. Matching pairs snap together and wake up part of a sleeping garden. |
| **Voice pong** | Pong played by ear: a stereo guide tells the player where the ball is going. |
| **Rhythm tap, story choices, cyber safety** | Rhythm repetition, branching stories and a quiz about staying safe online. |

## Accessibility

- **High contrast mode** and large text across the app, independent of the system setting.
- **Recorded speech.** Instructions, feedback and numbers are pre-recorded clips in all three languages instead of the system text-to-speech, so pronunciation is consistent on every device.
- **Haptics** carry meaning, not just confirmation (counts of pulses, stronger vibration for bigger values, "hot/cold" feedback while searching).
- **Stereo audio** for position-based games (locator, voice pong, sound memory).
- **Voice commands** on every screen through the microphone button or the keyboard shortcut.
- **Touch and keyboard layouts.** On phones the screens switch to touch-specific instructions and clips; on desktop every action has a keyboard shortcut.
- **Reduced motion** is respected: animations are replaced with instant changes when the system asks for it.
- Screen reader labels are provided for interactive elements.

## Tech stack

- Flutter 3 / Dart 3, Material 3
- `provider` for app state, `easy_localization` for translations (`assets/translations/*.json`)
- Audio: `audioplayers`, `just_audio`, `flutter_tts` (fallback only), `speech_to_text`, `record`
- Device: `vibration`, `flutter_compass`, `camera`, `permission_handler`
- Image recognition: Google ML Kit image labeling on device, with optional Google Cloud Vision for a wider vocabulary
- Storage: `shared_preferences`, `path_provider`

## Getting started

Requirements: Flutter SDK 3.x, Android SDK (min SDK 26) for the mobile build, Chrome for the web build.

```bash
flutter pub get
flutter run                 # connected Android phone or emulator
flutter run -d chrome       # web
```

Release builds:

```bash
flutter build apk --release --split-per-abi
flutter build web --release
```

The camera, vibration and compass only work in the Android app. The web build is fine for everything else.

### Optional: Cloud Vision

On-device ML Kit works without any setup. To enable the extra online recognizer, pass a key at build time (never commit it, and never use it for the web build):

```bash
flutter build apk --release --split-per-abi \
  --dart-define=GOOGLE_VISION_API_KEY=... \
  --dart-define=GOOGLE_VISION_ANDROID_CERT=...
```

See `docs/cloud_vision_setup.md` for details.

## Audio content

All recordings live in `assets/audio/<module>/<language>/` and sound effects in `assets/sounds/<module>/`. Each clip has a short name (for example `what_number.mp3`) and the app picks the right one for the current language. If a clip is missing, the game simply stays silent at that point instead of failing. Recordings were generated with Eleven Labs.

## Project layout

```
lib/
  screens/        one file per module (home, settings, braille, number games, ...)
  widgets/        shared UI (screen chrome, playful components) and per-module art
                  (sphere menu, ear ribbon, braille lab, camera lens, ...)
  services/       voice assistant, speech commands, image recognition, camera clips
  voice_system/   voice command orchestration and intent handling
  providers/      app state (language, accessibility settings)
  braille/        braille tables (Macedonian, English, Albanian)
  utils/          accessibility helpers, vibration, input mode, hotkeys
assets/
  translations/   en-US, mk-MK, sq-AL
  audio/          recorded speech per module and language
  sounds/         sound effects
docs/             setup notes and recording lists
```

## Testing

```bash
flutter analyze
flutter test
```

Most of the behaviour is audio and haptic, so changes should also be tried by hand on a real Android phone and in Chrome, in all three languages and with high contrast turned on.

A short guide for users in Macedonian is in `README_KORISNIK_MK.md`.