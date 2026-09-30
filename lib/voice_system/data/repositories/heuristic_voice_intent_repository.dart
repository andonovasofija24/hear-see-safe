// import '../../domain/entities/voice_intent.dart';

// /// Offline keyword routing (MK / EN / SQ) when OpenAI is unavailable.
// class HeuristicVoiceIntentRepository {
//   VoiceIntent resolve(String transcript) {
//     final t = transcript.toLowerCase().trim();

//     bool has(List<String> keys) => keys.any((k) => t.contains(k));

//     if (has(['wifi', 'wi-fi', 'вифи', 'вай-фај', 'wireless'])) {
//       return const VoiceIntent(
//         action: 'system_wifi',
//         params: {'state': 'disable'},
//         requiresConfirmation: true,
//       );
//     }

//     if (has(['settings', 'поставки', 'postavki', 'cilësimet', 'cilësim'])) {
//       return const VoiceIntent(action: 'open_settings');
//     }

//     if (has(['braille', 'брај', 'braj', 'brajova', 'azbuka', 'родители', 'prindër'])) {
//       return const VoiceIntent(action: 'navigate_braille');
//     }
//     if (has(['picture', 'book', 'learn', 'listen', 'учи', 'слушај', 'сликовница', 'mëso', 'dëgjo'])) {
//       return const VoiceIntent(action: 'navigate_picture_book');
//     }
//     if (has(['number', 'broevi', 'броеви', 'numra', 'calculate'])) {
//       return const VoiceIntent(action: 'navigate_number_games');
//     }
//     if (has(['camera', 'камера', 'recognize', 'распознавање', 'kamerë'])) {
//       return const VoiceIntent(action: 'navigate_camera_recognition');
//     }
//     if (has(['spatial', 'orientation', 'просторна', 'ориентација', 'hapësirë'])) {
//       return const VoiceIntent(action: 'navigate_spatial_orientation');
//     }
//     if (has(['cyber', 'safety', 'кибер', 'безбедност', 'siguria'])) {
//       return const VoiceIntent(action: 'navigate_cyber_safety');
//     }
//     if (has(['sound memory', 'меморија звуци', 'kujtesë']) &&
//         !has(['melody', 'мелодија'])) {
//       return const VoiceIntent(action: 'navigate_sound_memory');
//     }
//     if (has(['sound', 'identification', 'звук', 'идентификација', 'tingull']) &&
//         !has(['memory', 'меморија', 'kujtesë'])) {
//       return const VoiceIntent(action: 'navigate_sound_identification');
//     }
//     if (has(['pong', 'понг', 'voice pong'])) {
//       return const VoiceIntent(action: 'navigate_voice_pong');
//     }
//     if (has(['melody', 'мелодија', 'simon'])) {
//       return const VoiceIntent(action: 'navigate_melody_memory');
//     }
//     if (has(['rhythm', 'ритми', 'tap', 'ритам'])) {
//       return const VoiceIntent(action: 'navigate_rhythm_tap');
//     }
//     if (has(['story', 'приказна', 'choice', 'histori'])) {
//       return const VoiceIntent(action: 'navigate_story_choices');
//     }

//     return VoiceIntent(action: 'unknown', params: {'transcript': transcript});
//   }
// }
import '../../domain/entities/voice_intent.dart';

/// Offline keyword routing (MK / EN / SQ) when OpenAI is unavailable.
class HeuristicVoiceIntentRepository {
  VoiceIntent resolve(String transcript) {
    final t = transcript.toLowerCase().trim();

    bool has(List<String> keys) => keys.any((k) => t.contains(k));

    if (has(['wifi', 'wi-fi', 'вифи', 'вай-фај', 'wireless'])) {
      return const VoiceIntent(
        action: 'system_wifi',
        params: {'state': 'disable'},
        requiresConfirmation: true,
      );
    }

    if (has(['settings', 'поставки', 'postavki', 'cilësimet', 'cilësim'])) {
      return const VoiceIntent(action: 'open_settings');
    }

    if (has(['braille', 'брај', 'braj', 'brajova', 'azbuka', 'родители', 'prindër'])) {
      return const VoiceIntent(action: 'navigate_braille');
    }
    if (has(['picture', 'book', 'learn', 'listen', 'учи', 'слушај', 'сликовница', 'mëso', 'dëgjo'])) {
      return const VoiceIntent(action: 'navigate_picture_book');
    }
    if (has(['number', 'broevi', 'броеви', 'numra', 'calculate'])) {
      return const VoiceIntent(action: 'navigate_number_games');
    }
    if (has(['camera', 'камера', 'recognize', 'распознавање', 'kamerë'])) {
      return const VoiceIntent(action: 'navigate_camera_recognition');
    }
    if (has(['spatial', 'orientation', 'просторна', 'ориентација', 'hapësirë'])) {
      return const VoiceIntent(action: 'navigate_spatial_orientation');
    }
    if (has(['cyber', 'safety', 'кибер', 'безбедност', 'siguria'])) {
      return const VoiceIntent(action: 'navigate_cyber_safety');
    }
    if ((has(['sound memory', 'меморија звуци', 'меморија на звуци', 'kujtesë']) ||
            (has(['меморија']) && has(['звук']))) &&
        !has(['melody', 'мелодија'])) {
      return const VoiceIntent(action: 'navigate_sound_memory');
    }
    if (has(['sound', 'identification', 'звук', 'идентификација', 'tingull']) &&
        !has(['memory', 'меморија', 'kujtesë'])) {
      return const VoiceIntent(action: 'navigate_sound_identification');
    }
    if (has(['pong', 'понг', 'понк', 'voice pong', 'гласовен понг', 'пинг понг', 'пинг-понг'])) {
      return const VoiceIntent(action: 'navigate_voice_pong');
    }
    if (has(['melody', 'мелодија', 'simon'])) {
      return const VoiceIntent(action: 'navigate_melody_memory');
    }
    if (has(['rhythm', 'ритми', 'tap', 'ритам'])) {
      return const VoiceIntent(action: 'navigate_rhythm_tap');
    }
    if (has(['story', 'приказна', 'choice', 'histori'])) {
      return const VoiceIntent(action: 'navigate_story_choices');
    }

    return VoiceIntent(action: 'unknown', params: {'transcript': transcript});
  }
}