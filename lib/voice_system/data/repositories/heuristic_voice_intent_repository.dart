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
  /// Кој јазик е спомнат по име (mk / en / sq), или null.
  static String? namedLanguage(String t) {
    bool has(List<String> keys) => keys.any((k) => t.contains(k));
    // Вклучени се и облиците што ги враќа препознавањето на говор кога
    // името е кажано на друг јазик (пр. „инглиш“, „шќип“).
    if (has(['македон', 'makedon', 'macedonian', 'maqedon'])) return 'mk';
    if (has(['англ', 'anglisk', 'english', 'anglisht', 'инглиш', 'ингли', 'енглес'])) return 'en';
    if (has(['албан', 'albansk', 'albanian', 'shqip', 'шкип', 'шќип', 'шчип'])) return 'sq';
    return null;
  }

  VoiceIntent resolve(String transcript) {
    final t = transcript.toLowerCase().trim();

    bool has(List<String> keys) => keys.any((k) => t.contains(k));

    // Јазик: ако е спомнат конкретен јазик („англиски“, „смени на албански“)
    // - директно се менува; ако е речено само „јазик“ / „промени јазик“ - се
    // отвора екранот за избор на јазик.
    final lang = namedLanguage(t);
    if (lang != null) {
      return VoiceIntent(action: 'set_language', params: {'lang': lang});
    }
    if (has(['јазик', 'јазикот', 'јазици', 'language', 'gjuh', 'jezik'])) {
      return const VoiceIntent(action: 'change_language');
    }

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