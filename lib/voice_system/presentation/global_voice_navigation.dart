import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../utils/accessibility_utils.dart';
import '../../utils/navigation.dart';
import 'voice_intent_dispatcher.dart';

/// Гласовна навигација од БИЛО КОЈА игра: имиња на другите игри,
/// „поставки“ и „главно мени“. Ги користи секое копче за гласовна команда во
/// игрите (CategoryVoiceCommandButton), покрај „назад“ и локалните опции.
///
/// Се бараат ЦЕЛИ имиња (или многу карактеристични зборови), за да не се
/// судрат со категориите во самата игра (пр. „броеви“ во Брајовата азбука е
/// категорија, а „игри со броеви“ е посебната игра).
abstract final class GlobalVoiceNavigation {
  static const Map<String, List<String>> _phrases = {
    'go_home': [
      'главно мени', 'главното мени', 'почетна', 'почетен екран', 'мени со игри',
      'main menu', 'home screen', 'go home',
      'menyja kryesore', 'menyja', 'faqja kryesore',
    ],
    'open_settings': ['поставки', 'поставките', 'settings', 'cilësimet', 'cilesimet'],
    'navigate_braille': [
      'брајова азбука', 'брајовата азбука', 'брајова', 'брајово писмо',
      'braille alphabet', 'braille', 'alfabeti braille', 'alfabeti brail',
    ],
    'navigate_picture_book': [
      'учи и слушај', 'сликовница', 'сликовницата',
      'learn and listen', 'learn & listen', 'picture book',
      'mëso dhe dëgjo', 'meso dhe degjo',
    ],
    'navigate_number_games': ['игри со броеви', 'игра со броеви', 'number games', 'number game', 'lojëra me numra', 'lojera me numra'],
    'navigate_camera_recognition': [
      'распознавање на камера', 'камера', 'камерата',
      'camera recognition', 'camera',
      'njohja e kamerasë', 'njohja e kameres', 'kamera',
    ],
    'navigate_spatial_orientation': [
      'просторна ориентација', 'просторна', 'ориентација',
      'spatial orientation', 'orientation',
      'orientimi hapësinor', 'orientimi hapesinor', 'orientimi',
    ],
    'navigate_sound_identification': [
      'идентификација на звук', 'идентификација на звуци',
      'sound identification',
      'identifikimi i zërit', 'identifikimi i zerit',
    ],
    'navigate_cyber_safety': ['кибер безбедност', 'кибер', 'cyber safety', 'cyber', 'siguria kibernetike', 'kibernetik'],
    'navigate_sound_memory': ['меморија на звуци', 'меморија на звук', 'sound memory', 'memoria e zërit', 'memoria e zerit'],
    'navigate_voice_pong': ['пинг понг', 'пинг-понг', 'понг', 'ping pong', 'ping-pong', 'pong'],
    'navigate_melody_memory': ['меморија на мелодија', 'мелодија', 'melody memory', 'melody', 'memoria e melodisë', 'memoria e melodise', 'melodi'],
    'navigate_rhythm_tap': ['ритмичка игра', 'ритмичка', 'ритам', 'rhythm tap', 'rhythm', 'ritim'],
    'navigate_story_choices': [
      'приказна твој избор', 'приказна', 'приказната',
      'story your choice', 'your choice', 'story',
      'histori zgjedhja', 'zgjedhja jote', 'histori',
    ],
  };

  /// Ја враќа акцијата ако транскриптот (мали букви) содржи име на игра /
  /// „поставки“ / „главно мени“; подолгите фрази имаат предност.
  static String? matchAction(String transcript) {
    final t = transcript.toLowerCase().replaceAll('–', ' ').replaceAll('-', ' ');
    String? best;
    var bestLen = 0;
    for (final e in _phrases.entries) {
      for (final p in e.value) {
        final phrase = p.replaceAll('-', ' ');
        if (phrase.length > bestLen && t.contains(phrase)) {
          best = e.key;
          bestLen = phrase.length;
        }
      }
    }
    return best;
  }

  /// Оди директно таму: прво назад до главното мени, па (ако е игра или
  /// поставки) ја отвора. Го изговара името на играта со снимката од менито.
  static void go(BuildContext context, String action) {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final audioKey = kVoiceActionAudioKeys[action];
    if (audioKey != null) {
      AccessibilityUtils.provideFeedback(
        context: context,
        clipAssetPath: 'audio/home/${context.locale.languageCode}/$audioKey.mp3',
      );
    }
    nav.popUntil((route) => route.isFirst);
    if (action == 'go_home') return;
    final screen = screenForVoiceAction(action);
    if (screen != null) {
      nav.push(MaterialPageRoute<void>(builder: (_) => screen));
    }
  }
}