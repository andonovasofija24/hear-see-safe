import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/voice_assistant_service.dart';
import '../voice_system/application/voice_command_orchestrator.dart';

/// Клучни зборови (mk/en/sq) кои значат "врати се назад" - се препознаваат
/// автоматски на секое копче за гласовна команда, независно од `options`,
/// доколку е поставено `onBack`.
const List<String> kVoiceBackKeywords = [
  'назад',
  'врати се',
  'back',
  'go back',
  'prapa',
  'kthehu',
  'kthehu prapa',
];

/// Една категорија/потстраница што може да се избере со глас во рамки на
/// одреден екран (пр. "Група 1" во Брајова азбука, "Собирање" во Игри со
/// броеви). `keywords` треба да содржи клучни зборови/фрази на сите 3 јазици
/// (mk/en/sq), веќе во мали букви, без интерпункција.
class VoiceCategoryOption {
  const VoiceCategoryOption({
    required this.keywords,
    required this.onSelected,
  });

  final List<String> keywords;
  final VoidCallback onSelected;
}

/// Копче за гласовна команда што се користи ЛОКАЛНО во рамки на еден екран
/// за да се препознае која подкатегорија/игра корисникот сака да ја избере
/// (наспроти глобалната гласовна команда на почетниот екран која навигира
/// меѓу целите функции на апликацијата).
///
/// Го користи истиот `VoiceCommandOrchestrator` (преку `listenOnce`, кое е
/// едноставно еднократно слушање без целото решавање на намери), но
/// совпаѓањето со категориите се прави локално, со едноставни клучни зборови,
/// бидејќи категориите се специфични за екранот, а не глобални дејства.
///
/// НЕ изговара никаков прашалник/потсетник пред да почне да слуша - веднаш
/// слуша штом се притисне копчето (тивко). Единствениот звук што може да се
/// слушне е готовиот „не разбрав" клип (`audio/voice/<јазик>/not_recognized.mp3`)
/// доколку зборот не е препознаен.
class CategoryVoiceCommandButton extends StatefulWidget {
  const CategoryVoiceCommandButton({
    super.key,
    required this.options,
    this.background,
    this.foreground,
    this.compact = false,
    this.onBack,
  });

  final List<VoiceCategoryOption> options;
  final Color? background;
  final Color? foreground;

  /// Помал/потесен изглед - корисно кога екранот веќе е преполнет.
  final bool compact;

  /// Ако е зададено, зборувањето на некој од `kVoiceBackKeywords` ("назад",
  /// "back", ...) го повикува ова наместо да се бара совпаѓање во `options`.
  final VoidCallback? onBack;

  @override
  State<CategoryVoiceCommandButton> createState() => _CategoryVoiceCommandButtonState();
}

class _CategoryVoiceCommandButtonState extends State<CategoryVoiceCommandButton> {
  bool _isListening = false;
  final AudioPlayer _feedbackPlayer = AudioPlayer();

  @override
  void dispose() {
    _feedbackPlayer.dispose();
    super.dispose();
  }

  /// Го пробува готовиот мп3 клип (assets/audio/voice/<јазик>/<клуч>.mp3);
  /// само ако тоа падне/не постои се паѓа назад на системскиот TTS.
  Future<void> _playFeedbackClip(String key, String langCode, VoiceAssistantService voiceAssistant) async {
    bool reachedPlaying = false;
    try {
      await _feedbackPlayer.stop();
      await _feedbackPlayer.play(AssetSource('audio/voice/$langCode/$key.mp3'));
      reachedPlaying = true;
    } catch (_) {
      reachedPlaying = false;
    }
    if (!reachedPlaying) {
      await voiceAssistant.speakWithLanguage('voice.$key'.tr(), langCode, vibrate: false);
    }
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    setState(() => _isListening = true);

    final langCode = context.locale.languageCode;
    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);

    try {
      // Веднаш слуша, без никаков говорен прашалник пред тоа.
      final transcript = await orchestrator.listenOnce();
      if (!mounted) return;

      if (transcript == null || transcript.trim().isEmpty) {
        setState(() => _isListening = false);
        await _playFeedbackClip('not_recognized', langCode, voiceAssistant);
        return;
      }

      final t = transcript.toLowerCase().trim();

      if (widget.onBack != null && kVoiceBackKeywords.any((k) => t.contains(k))) {
        setState(() => _isListening = false);
        widget.onBack!();
        return;
      }

      VoiceCategoryOption? match;
      for (final option in widget.options) {
        if (option.keywords.any((k) => t.contains(k))) {
          match = option;
          break;
        }
      }

      setState(() => _isListening = false);

      if (match != null) {
        match.onSelected();
      } else {
        await _playFeedbackClip('not_recognized', langCode, voiceAssistant);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? const Color(0xFF115E59);
    final fg = widget.foreground ?? Colors.white;
    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 14);

    return Semantics(
      button: true,
      label: _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
      child: Material(
        color: _isListening ? bg.withValues(alpha: 0.6) : bg,
        borderRadius: BorderRadius.circular(18),
        elevation: 4,
        child: InkWell(
          onTap: _isListening ? null : _startListening,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: pad,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isListening ? Icons.mic_rounded : Icons.record_voice_over_rounded,
                  color: fg,
                  size: widget.compact ? 20 : 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
                  style: GoogleFonts.lexend(
                    fontSize: widget.compact ? 13 : 15,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}