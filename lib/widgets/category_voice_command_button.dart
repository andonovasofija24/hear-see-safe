import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/voice_assistant_service.dart';
import '../utils/voice_hotkey.dart';
import '../voice_system/application/voice_command_orchestrator.dart';
import '../voice_system/presentation/global_voice_navigation.dart';

/// Множител за натписот на копчето (и пораката „чуено“).
const double _kVoiceText = 1.55;

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
    this.matches,
    this.beforeGlobal = false,
  });

  final List<String> keywords;
  final VoidCallback onSelected;

  /// По избор: сопствена проверка на транскриптот (мали букви) - ако е
  /// зададена, опцијата се избира кога ова врати true (покрај `keywords`).
  final bool Function(String transcript)? matches;

  /// Се проверува ПРЕД имињата на другите игри (пр. „Брајово писмо“ како
  /// начин на одговор во Игри со броеви, наместо премин во Брајовата азбука).
  final bool beforeGlobal;
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
    this.trigger,
    this.iconOnly = false,
    this.respondToHotkey,
    this.hotkeyPriority = 1,
    this.onListenStart,
  });

  /// По избор: се повикува штом почне слушањето (пр. да се запре говорот
  /// на екранот, за микрофонот да не го слуша).
  final VoidCallback? onListenStart;

  /// Само кружна икона-микрофон (за горниот десен агол на екранот).
  final bool iconOnly;

  /// Дали копчето Г го активира ова копче. Ако не е зададено: да, ако има
  /// свои опции и нема сопствен `trigger`.
  final bool? respondToHotkey;

  /// Ако на екранот има повеќе копчиња што реагираат на Г, се активира
  /// она со најголем приоритет (копчињата во самата содржина имаат 1, а
  /// општото копче горе десно 0).
  final int hotkeyPriority;

  /// По избор: секоја промена на вредноста го активира слушањето исто како
  /// допир на копчето (пр. копчето Г на тастатура во Брајовата азбука).
  final ValueListenable<int>? trigger;

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

  /// Сите моментално прикажани копчиња - на Г се активира САМО едно (на
  /// екранот што е најгоре, со најголем приоритет, последно прикажаното).
  static final List<_CategoryVoiceCommandButtonState> _registry = [];
  static bool _hotkeyHooked = false;

  static void _onGlobalHotkey() {
    _CategoryVoiceCommandButtonState? best;
    for (final s in _registry) {
      if (!s._eligibleForHotkey) continue;
      if (best == null || s.widget.hotkeyPriority >= best.widget.hotkeyPriority) best = s;
    }
    best?._startListening();
  }

  bool get _eligibleForHotkey {
    if (!mounted) return false;
    final responds = widget.respondToHotkey ?? (widget.trigger == null && widget.options.isNotEmpty);
    if (!responds) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  @override
  void initState() {
    super.initState();
    widget.trigger?.addListener(_onTrigger);
    _registry.add(this);
    if (!_hotkeyHooked) {
      _hotkeyHooked = true;
      VoiceHotkey.pressed.addListener(_onGlobalHotkey);
    }
  }

  @override
  void didUpdateWidget(covariant CategoryVoiceCommandButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      oldWidget.trigger?.removeListener(_onTrigger);
      widget.trigger?.addListener(_onTrigger);
    }
  }

  void _onTrigger() {
    if (mounted) _startListening();
  }

  @override
  void dispose() {
    widget.trigger?.removeListener(_onTrigger);
    _registry.remove(this);
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
    widget.onListenStart?.call();
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
      // Препознавањето понекогаш го дели зборот („кви з“) - затоа се
      // споредува и без празни места.
      final compact = t.replaceAll(RegExp(r'\s+'), '');
      bool hasKeyword(String k) => t.contains(k) || compact.contains(k.replaceAll(' ', ''));

      if (widget.onBack != null && kVoiceBackKeywords.any((k) => t.contains(k))) {
        setState(() => _isListening = false);
        widget.onBack!();
        return;
      }

      // Опции што имаат предност пред имињата на другите игри.
      for (final option in widget.options) {
        if (!option.beforeGlobal) continue;
        if ((option.matches?.call(t) ?? false) || option.keywords.any(hasKeyword)) {
          setState(() => _isListening = false);
          option.onSelected();
          return;
        }
      }

      // Име на друга игра / „поставки“ / „главно мени“ - директно таму, од
      // било која игра или категорија.
      final globalAction = GlobalVoiceNavigation.matchAction(t);
      if (globalAction != null) {
        setState(() => _isListening = false);
        GlobalVoiceNavigation.go(context, globalAction);
        return;
      }

      VoiceCategoryOption? match;
      for (final option in widget.options) {
        if ((option.matches?.call(t) ?? false) || option.keywords.any(hasKeyword)) {
          match = option;
          break;
        }
      }

      setState(() => _isListening = false);

      if (match != null) {
        match.onSelected();
      } else {
        // Покажи што точно е чуено - помага да се види зошто командата не е
        // препознаена (пр. препознавањето враќа друг збор).
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('voice.heard'.tr(args: [transcript]), style: const TextStyle(fontSize: 16 * _kVoiceText)),
            duration: const Duration(seconds: 4),
          ),
        );
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
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 16);

    if (widget.iconOnly) {
      return Semantics(
        button: true,
        label: _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Material(
            color: _isListening ? Colors.white.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.22),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isListening ? null : _startListening,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  _isListening ? Icons.mic_rounded : Icons.record_voice_over_rounded,
                  color: fg,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                  size: widget.compact ? 26 : 32,
                ),
                const SizedBox(width: 10),
                // Ограничена ширина (не Flexible - копчето понекогаш е во Row
                // без ограничување), па подолг натпис оди во втор ред.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                  child: Text(
                    _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: (widget.compact ? 13 : 15) * _kVoiceText,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
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