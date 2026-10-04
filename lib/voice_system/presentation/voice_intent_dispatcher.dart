import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state_provider.dart';
import '../../screens/language_selection_screen.dart';
import '../application/language_manager.dart';

import '../../screens/braille_learning_screen.dart';
import '../../screens/camera_recognition_screen.dart';
import '../../screens/cyber_safety_screen.dart';
import '../../screens/melody_memory_screen.dart';
import '../../screens/number_games_screen.dart';
import '../../screens/picture_book_screen.dart';
import '../../screens/rhythm_tap_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/sound_identification_screen.dart';
import '../../screens/sound_memory_screen.dart';
import '../../screens/spatial_orientation_screen.dart';
import '../../screens/story_choices_screen.dart';
import '../../screens/voice_pong_screen.dart';
import '../../services/voice_assistant_service.dart';
import '../../utils/accessibility_utils.dart';
import '../domain/entities/voice_intent.dart';

/// Maps normalized intents to navigation + spoken feedback (screen-reader friendly).
Future<void> dispatchVoiceIntent({
  required BuildContext context,
  required VoiceIntent intent,
  required VoiceAssistantService voiceAssistant,
  required String systemWifiUnavailableMessage,
}) async {
  /// Клучеви за однапред снимените имиња на играта (assets/audio/home/<јазик>/<audioKey>.mp3),
  /// исти клучеви како во листата на почетниот екран (`_HomeFeature.audioKey`) -
  /// се користат за да не се изговара името на играта со вграден TTS кога е
  /// избрана преку гласовна команда.
  const audioKeyByAction = <String, String>{
    'navigate_braille': 'braille_alphabet',
    'navigate_picture_book': 'picture_book',
    'navigate_number_games': 'number_games',
    'navigate_camera_recognition': 'camera_recognition',
    'navigate_spatial_orientation': 'spatial_orientation',
    'navigate_sound_identification': 'sound_identification',
    'navigate_cyber_safety': 'cyber_security',
    'navigate_sound_memory': 'sound_memory',
    'navigate_voice_pong': 'voice_pong',
    'navigate_melody_memory': 'melody_memory',
    'navigate_rhythm_tap': 'rhythm_tap',
    'navigate_story_choices': 'story_choices',
  };

  void go(Widget screen, String announcement) {
    final langCode = context.locale.languageCode;
    final audioKey = audioKeyByAction[intent.action];
    AccessibilityUtils.provideFeedback(
      context: context,
      audioFeedback: announcement,
      voiceAssistant: voiceAssistant,
      clipAssetPath: audioKey != null ? 'audio/home/$langCode/$audioKey.mp3' : null,
    );
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  switch (intent.action) {
    case 'change_language':
      voiceAssistant.stop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LanguageSelectionScreen()),
      );
      return;

    case 'set_language':
      const locales = {
        'mk': ('Македонски', Locale('mk', 'MK')),
        'en': ('English', Locale('en', 'US')),
        'sq': ('Shqip', Locale('sq', 'AL')),
      };
      final code = intent.params['lang'] as String?;
      final data = locales[code];
      if (code == null || data == null) {
        // Непознат јазик - отвори го екранот за избор.
        voiceAssistant.stop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const LanguageSelectionScreen()),
        );
        return;
      }
      await context.setLocale(data.$2);
      if (!context.mounted) return;
      Provider.of<AppStateProvider>(context, listen: false).setLanguage(code);
      Provider.of<LanguageManager>(context, listen: false).setUserUiLanguageCode(code);
      // Потврда: името на јазикот со снимката од екранот за избор на јазик.
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: data.$1,
        voiceAssistant: voiceAssistant,
        clipAssetPath: 'audio/language/$code/name.mp3',
      );
      return;

    case 'system_wifi':
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: systemWifiUnavailableMessage,
        voiceAssistant: voiceAssistant,
      );
      return;

    case 'open_settings':
      go(const SettingsScreen(), 'settings.opening'.tr());
      return;

    case 'navigate_braille':
      go(const BrailleLearningScreen(), 'features.braille'.tr());
      return;
    case 'navigate_picture_book':
      go(const PictureBookScreen(), 'features.picture_book'.tr());
      return;
    case 'navigate_number_games':
      go(const NumberGamesScreen(), 'features.number_games'.tr());
      return;
    case 'navigate_camera_recognition':
      go(const CameraRecognitionScreen(), 'features.camera_recognition'.tr());
      return;
    case 'navigate_spatial_orientation':
      go(const SpatialOrientationScreen(), 'features.spatial_orientation'.tr());
      return;
    case 'navigate_sound_identification':
      go(const SoundIdentificationScreen(), 'features.sound_identification'.tr());
      return;
    case 'navigate_cyber_safety':
      go(const CyberSafetyScreen(), 'features.cyber_safety'.tr());
      return;
    case 'navigate_sound_memory':
      go(const SoundMemoryScreen(), 'features.sound_memory'.tr());
      return;
    case 'navigate_voice_pong':
      go(const VoicePongScreen(), 'features.voice_pong'.tr());
      return;
    case 'navigate_melody_memory':
      go(const MelodyMemoryScreen(), 'features.melody_memory'.tr());
      return;
    case 'navigate_rhythm_tap':
      go(const RhythmTapScreen(), 'features.rhythm_tap'.tr());
      return;
    case 'navigate_story_choices':
      go(const StoryChoicesScreen(), 'features.story_choices'.tr());
      return;

    case 'unknown':
    default:
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: 'voice.not_recognized'.tr(),
        voiceAssistant: voiceAssistant,
      );
      return;
  }
}