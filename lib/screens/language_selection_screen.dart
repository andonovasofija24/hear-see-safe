import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_screen.dart';
import '../providers/app_state_provider.dart';
import '../providers/accessibility_provider.dart';
import '../services/voice_assistant_service.dart';
import '../voice_system/application/language_manager.dart';
import '../voice_system/application/voice_command_orchestrator.dart';
import '../voice_system/data/repositories/heuristic_voice_intent_repository.dart';
import '../utils/accessibility_utils.dart';
import '../utils/voice_level.dart';
import '../widgets/playful_ui.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  bool _listening = false;

  /// Објаснувањето се пушта тука (не преку општиот плеер), за да се знае
  /// докаде стигнало - и додека се спомнува секој јазик, неговото балонче
  /// светнува.
  final AudioPlayer _introPlayer = AudioPlayer();
  StreamSubscription<Duration>? _introPosSub;

  /// Кое балонче моментално свети ('mk' / 'en' / 'sq' / null).
  final ValueNotifier<String?> _spotlight = ValueNotifier<String?>(null);
  Timer? _spotlightTimer;

  /// Редоследот на јазиците во voice_explain.mp3 и од кој дел (0..1) од
  /// снимката почнува секој. Ако во снимката се во друг редослед или се
  /// со различна должина - смени ги овие две листи.
  static const List<String> _introOrder = ['mk', 'en', 'sq'];
  static const List<double> _introStarts = [0.0, 0.34, 0.67];

  /// Веб прелистувачите (Chrome итн.) НЕ дозволуваат звук ниту микрофон пред
  /// корисникот прво да допре нешто на страницата („autoplay“ правило). Затоа
  /// на веб, при прво отворање, се чека еден допир / копче - тој допир го
  /// „отклучува“ звукот, па веднаш се пушта воведот. На телефон ова не е
  /// потребно и воведот почнува сам.
  static bool _webAudioUnlocked = false;
  late bool _awaitingFirstTap = kIsWeb && !_webAudioUnlocked;
  final FocusNode _unlockFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    if (!_awaitingFirstTap) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playExplanation());
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _introPosSub?.cancel();
    _introPlayer.dispose();
    _spotlightTimer?.cancel();
    _spotlight.dispose();
    VoiceLevel.speaking.value = false;
    _unlockFocus.dispose();
    super.dispose();
  }

  /// Копчето М (физичкото M - исто на кирилица и латиница) го вклучува
  /// микрофонот, исто како допир на копчето-микрофон.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.physicalKey != PhysicalKeyboardKey.keyM) return false;
    if (!mounted || _awaitingFirstTap || _listening) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _startVoiceLanguagePick(context, voiceAssistant);
    return true;
  }

  /// Тројазичен потсетник под копчето-микрофон: „М“ на тастатура = микрофон.
  Widget _keyHint({required bool highContrast}) {
    final fg = highContrast ? AccessibilityUtils.getContrastColor(context) : Playful.ink;
    Widget line(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(text, style: GoogleFonts.lexend(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35, color: fg)),
        );
    final key = highContrast
        ? KeyCap('M',
            background: AccessibilityUtils.getAccentColor(context),
            foreground: AccessibilityUtils.getPrimaryButtonForeground(context))
        : const KeyCap('M');
    return Semantics(
      label: 'М: микрофон. M: microphone. M: mikrofoni.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highContrast ? null : const Color(0xFFFFF6DA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              key,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line('М – вклучи микрофон'),
                    line('M – turn on the microphone'),
                    line('M – ndiz mikrofonin'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _unlockAndStart() {
    if (!_awaitingFirstTap) return;
    _webAudioUnlocked = true;
    setState(() => _awaitingFirstTap = false);
    _playExplanation(delay: Duration.zero);
  }

  /// Цел екран „допри било каде“ - само на веб, пред првиот допир.
  Widget _buildUnlockOverlay() {
    const text = 'Допри било каде за да започнеш\nTap anywhere to start\nPrek kudo për të filluar';
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Focus(
        focusNode: _unlockFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            _unlockAndStart();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          label: text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _unlockAndStart,
            child: Container(
              color: Colors.black.withValues(alpha: 0.82),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app_rounded, color: Colors.white, size: 120),
                  const SizedBox(height: 28),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Тројазичното објаснување - при отворање на екранот, и достапно за
  /// повторување со допир на текстот на картичката. Копчето-микрофон
  /// НИКОГАШ не го повикува ова - тоа служи исклучиво за слушање.
  Future<void> _playExplanation({Duration delay = const Duration(milliseconds: 400)}) async {
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    if (delay > Duration.zero) await Future.delayed(delay);
    if (!mounted) return;
    await _stopIntro();
    if (!mounted) return;

    Duration? total;
    late final StreamSubscription<Duration> sub;
    sub = _introPlayer.onPositionChanged.listen((pos) async {
      total ??= await _introPlayer.getDuration();
      final ms = total?.inMilliseconds ?? 0;
      if (ms <= 0 || !mounted) return;
      final p = pos.inMilliseconds / ms;
      var lang = _introOrder.first;
      for (var i = 0; i < _introOrder.length; i++) {
        if (p >= _introStarts[i]) lang = _introOrder[i];
      }
      if (_spotlightTimer == null && identical(_introPosSub, sub)) _spotlight.value = lang;
    });
    _introPosSub = sub;

    try {
      // Крај: снимката заврши или е запрена (микрофон, избор на јазик).
      // „Запрена“ се брои дури откако навистина почнала.
      final done = Completer<void>();
      var seenPlaying = false;
      final stateSub = _introPlayer.onPlayerStateChanged.listen((st) {
        if (st == PlayerState.playing) seenPlaying = true;
        if (st == PlayerState.completed || (st == PlayerState.stopped && seenPlaying)) {
          if (!done.isCompleted) done.complete();
        }
      });
      try {
        await _introPlayer.play(AssetSource('audio/language/voice_explain.mp3'));
        VoiceLevel.speaking.value = true;
        await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
      } finally {
        await stateSub.cancel();
      }
    } catch (_) {
      // Снимката ја нема / не може да се пушти - системски глас.
      if (!mounted) return;
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: 'language.voice_assistant_ready'.tr(),
        voiceAssistant: voiceAssistant,
      );
    } finally {
      await sub.cancel();
      if (identical(_introPosSub, sub)) {
        _introPosSub = null;
        VoiceLevel.speaking.value = false;
        if (mounted && _spotlightTimer == null) _spotlight.value = null;
      }
    }
  }

  Future<void> _stopIntro() async {
    await _introPosSub?.cancel();
    _introPosSub = null;
    VoiceLevel.speaking.value = false;
    try {
      await _introPlayer.stop();
    } catch (_) {}
    if (mounted && _spotlightTimer == null) _spotlight.value = null;
  }

  /// Накратко го осветлува балончето на јазикот (при преслушување или кога
  /// јазикот е препознаен со глас).
  void _flash(String langCode, {Duration duration = const Duration(milliseconds: 1600)}) {
    _spotlightTimer?.cancel();
    _spotlight.value = langCode;
    _spotlightTimer = Timer(duration, () {
      _spotlightTimer = null;
      if (mounted) _spotlight.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!_awaitingFirstTap) return content;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        _buildUnlockOverlay(),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    final hc = Provider.of<AccessibilityProvider>(context).highContrastMode;

    if (hc) {
      return Scaffold(
        backgroundColor: AccessibilityUtils.getBackgroundColor(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'app.title'.tr(),
                  style: GoogleFonts.lexend(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AccessibilityUtils.getContrastColor(context),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'language.welcome'.tr(),
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AccessibilityUtils.getContrastColor(context),
                  ),
                ),
                const SizedBox(height: 28),
                _voiceAssistantCard(context, voiceAssistant, highContrast: true),
                const SizedBox(height: 24),
                _languageRow(
                  context: context,
                  code: 'MK',
                  name: 'Македонски',
                  locale: const Locale('mk', 'MK'),
                  langCode: 'mk',
                  greeting: 'Здраво!',
                  accent: const Color(0xFFFFC400),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
                const SizedBox(height: 18),
                _languageRow(
                  context: context,
                  code: 'EN',
                  name: 'English',
                  locale: const Locale('en', 'US'),
                  langCode: 'en',
                  greeting: 'Hello!',
                  accent: const Color(0xFF4A90E2),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
                const SizedBox(height: 18),
                _languageRow(
                  context: context,
                  code: 'SQ',
                  name: 'Shqip',
                  locale: const Locale('sq', 'AL'),
                  langCode: 'sq',
                  greeting: 'Përshëndetje!',
                  accent: const Color(0xFFFF1E2D),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Нормален режим: темна позадина со лебдечки брајови точки, големи
    // светли картички со темен текст (силен контраст).
    return Scaffold(
      backgroundColor: Playful.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BrailleBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Листата е широка колку екранот (лизгачот е скроз десно),
                // а содржината е во средина, до 720 широка.
                final maxWidth = constraints.maxWidth > 720 ? 720.0 : constraints.maxWidth;
                return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: (constraints.maxHeight - 40).clamp(0.0, double.infinity)),
                      child: Center(
                      child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PopIn(
                            index: 0,
                            child: Column(
                              children: [
                                const BrailleCellMark(size: 72),
                                const SizedBox(height: 18),
                                Text(
                                  'app.title'.tr(),
                                  textAlign: TextAlign.center,
                                  style: Playful.display(38),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'language.welcome'.tr(),
                                  textAlign: TextAlign.center,
                                  style: Playful.body(18, color: Playful.mist),
                                ),
                                const SizedBox(height: 18),
                                ExcludeSemantics(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _senseBadge(Icons.hearing_rounded, const Color(0xFF5EEAD4)),
                                      const SizedBox(width: 14),
                                      _senseBadge(Icons.visibility_rounded, Playful.sun),
                                      const SizedBox(width: 14),
                                      _senseBadge(Icons.front_hand_rounded, const Color(0xFFF9A8D4)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          PopIn(index: 1, child: _voiceAssistantCard(context, voiceAssistant, highContrast: false)),
                          const SizedBox(height: 32),
                          PopIn(
                            index: 2,
                            child: Text(
                              'language.choose'.tr(),
                              textAlign: TextAlign.center,
                              style: Playful.title(24),
                            ),
                          ),
                          const SizedBox(height: 18),
                          PopIn(
                            index: 3,
                            child: _languageRow(
                              context: context,
                              code: 'MK',
                              name: 'Македонски',
                              locale: const Locale('mk', 'MK'),
                              langCode: 'mk',
                              greeting: 'Здраво!',
                              accent: Playful.sun,
                              voiceAssistant: voiceAssistant,
                              highContrast: false,
                            ),
                          ),
                          const SizedBox(height: 18),
                          PopIn(
                            index: 4,
                            child: _languageRow(
                              context: context,
                              code: 'EN',
                              name: 'English',
                              locale: const Locale('en', 'US'),
                              langCode: 'en',
                              greeting: 'Hello!',
                              accent: const Color(0xFF7DD3FC),
                              voiceAssistant: voiceAssistant,
                              highContrast: false,
                            ),
                          ),
                          const SizedBox(height: 18),
                          PopIn(
                            index: 5,
                            child: _languageRow(
                              context: context,
                              code: 'SQ',
                              name: 'Shqip',
                              locale: const Locale('sq', 'AL'),
                              langCode: 'sq',
                              greeting: 'Përshëndetje!',
                              accent: const Color(0xFFFDA4AF),
                              voiceAssistant: voiceAssistant,
                              highContrast: false,
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                      ),
                    ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Три сетила (слух, вид, допир) - украс под насловот.
  Widget _senseBadge(IconData icon, Color color) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Icon(icon, color: Playful.ink, size: 30),
    );
  }

  /// Ги препознава клучните зборови за трите јазици (независно од UI-јазик,
  /// бидејќи сè уште не е избран).
  String? _matchLanguage(String transcript) =>
      HeuristicVoiceIntentRepository.namedLanguage(transcript.toLowerCase());


  static const Map<String, (String, Locale)> _langData = {
    'mk': ('Македонски', Locale('mk', 'MK')),
    'en': ('English', Locale('en', 'US')),
    'sq': ('Shqip', Locale('sq', 'AL')),
  };

  Future<void> _selectLanguage(BuildContext context, String langCode, VoiceAssistantService voiceAssistant) async {
    // Ако сè уште свири објаснувањето (или нешто друго) кога јазикот ќе се
    // избере, веднаш запри го пред да се премине понатаму.
    await _stopIntro();
    await AccessibilityUtils.stopFeedback();
    voiceAssistant.stop();

    final data = _langData[langCode]!;
    await context.setLocale(data.$2);
    if (!context.mounted) return;
    Provider.of<AppStateProvider>(context, listen: false).setLanguage(langCode);
    Provider.of<LanguageManager>(context, listen: false).setUserUiLanguageCode(langCode);
    // Никаков изговор на "јазик: Македонски" тука - директно на почетниот
    // екран, каде ќе проговори пораката за добредојде.
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  /// Микрофон-копче: ИСКЛУЧИВО слуша - веднаш почнува, без да го пушта
  /// објаснувањето прво (тоа е одделна функција, погоре).
  Future<void> _startVoiceLanguagePick(BuildContext context, VoiceAssistantService voiceAssistant) async {
    if (_listening) return;
    // Ако објаснувањето (voice_explain) сè уште свири, веднаш прекини го -
    // микрофонот треба веднаш да почне да слуша, не да чека тоа да заврши.
    await _stopIntro();
    await AccessibilityUtils.stopFeedback();
    voiceAssistant.stop();

    setState(() => _listening = true);

    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);

    try {
      final transcript = await orchestrator.listenOnce(
        timeout: const Duration(seconds: 6),
      );
      if (!mounted) return;

      final matched = transcript == null ? null : _matchLanguage(transcript);
      if (matched != null) {
        // Покажи кој јазик е препознаен (балончето светнува), па продолжи.
        _flash(matched, duration: const Duration(milliseconds: 900));
        await Future.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        await _selectLanguage(context, matched, voiceAssistant);
        return; // веќе навигиравме - не враќај _listening на false на стар екран
      }
      // Не е препознаен јазик - кажи го тоа (порано екранот молчеше) и
      // покажи што е чуено, за да се знае што да се повтори.
      final heard = (transcript ?? '').trim();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            heard.isEmpty
                ? 'Не те слушнав - обиди се повторно / I didn\'t hear you - try again / Nuk të dëgjova - provo përsëri'
                : 'Чув / I heard / Dëgjova: „$heard“',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
      await AccessibilityUtils.provideFeedback(
        context: context,
        vibrate: true,
        clipAssetPath: 'audio/voice/mk/not_recognized.mp3',
      );
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Widget _voiceAssistantCard(
    BuildContext context,
    VoiceAssistantService voiceAssistant, {
    required bool highContrast,
  }) {
    final listenLabel = '${'language.voice_title'.tr()}. ${'language.voice_ready'.tr()}';
    void listen() => _startVoiceLanguagePick(context, voiceAssistant);

    if (highContrast) {
      final accent = AccessibilityUtils.getAccentColor(context);
      final contrast = AccessibilityUtils.getContrastColor(context);
      final micButton = Semantics(
        label: listenLabel,
        button: true,
        child: Material(
          color: _listening ? AccessibilityUtils.getDisabledColor(context) : accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _listening ? null : listen,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Icon(_listening ? Icons.hearing_rounded : Icons.mic_rounded, color: Colors.white, size: 40),
            ),
          ),
        ),
      );
      final textArea = Semantics(
        label: listenLabel,
        button: true,
        child: Material(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _playExplanation,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('language.voice_title'.tr(), style: GoogleFonts.lexend(fontSize: 22, fontWeight: FontWeight.w700, color: contrast)),
                        const SizedBox(height: 4),
                        Text(_listening ? 'voice.listening'.tr() : 'language.voice_ready'.tr(),
                            style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.w500, color: contrast)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.volume_up_rounded, size: 26, color: accent),
                ],
              ),
            ),
          ),
        ),
      );
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AccessibilityUtils.getCardBackgroundColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [micButton, const SizedBox(width: 18), Expanded(child: textArea)]),
            const SizedBox(height: 14),
            _keyHint(highContrast: true),
          ],
        ),
      );
    }

    // Голем микрофон со звучни бранови; текстот до него повторно го пушта
    // објаснувањето (мп3) - одделно од микрофонот кој служи само за слушање.
    const micColor = Color(0xFF4338CA);
    final micButton = Semantics(
      label: listenLabel,
      button: true,
      child: RippleRings(
        color: micColor,
        active: _listening,
        spread: 16,
        child: PressableScale(
          enabled: !_listening,
          child: Material(
            color: _listening ? const Color(0xFFBE123C) : micColor,
            shape: const CircleBorder(),
            elevation: 6,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _listening ? null : listen,
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Icon(_listening ? Icons.hearing_rounded : Icons.mic_rounded, color: Colors.white, size: 42),
              ),
            ),
          ),
        ),
      ),
    );

    final textArea = Semantics(
      label: listenLabel,
      button: true,
      child: Material(
        color: const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: _playExplanation,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('language.voice_title'.tr(), style: Playful.title(22, color: Playful.ink)),
                      const SizedBox(height: 6),
                      if (_listening) ...[
                        // Гласот се гледа додека се слуша.
                        const SoundWave(color: micColor, bars: 11, height: 30),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        _listening ? 'voice.listening'.tr() : 'language.voice_ready'.tr(),
                        style: Playful.body(17, color: const Color(0xFF34336B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.volume_up_rounded, size: 28, color: micColor),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Playful.sun, width: 4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: micButton),
              const SizedBox(width: 14),
              Expanded(child: textArea),
            ],
          ),
          const SizedBox(height: 18),
          _keyHint(highContrast: false),
        ],
      ),
    );
  }

  Widget _languageRow({
    required BuildContext context,
    required String code,
    required String name,
    required Locale locale,
    required String langCode,
    String greeting = '',
    required Color accent,
    required VoiceAssistantService voiceAssistant,
    required bool highContrast,
  }) {
    Future<void> select() => _selectLanguage(context, langCode, voiceAssistant);

    Future<void> preview() async {
      await _stopIntro();
      _flash(langCode);
      if (!context.mounted) return;
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: name,
        voiceAssistant: voiceAssistant,
        clipAssetPath: 'audio/language/$langCode/name.mp3',
      );
    }

    if (highContrast) {
      return Semantics(
        button: true,
        label: '$name. ${'language.choose'.tr()}',
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: AccessibilityUtils.getCardBackgroundColor(context),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: select,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AccessibilityUtils.getAccentColor(context), width: 2),
                    ),
                    child: Row(
                      children: [
                        Text(
                          code,
                          style: GoogleFonts.lexend(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AccessibilityUtils.getAccentColor(context),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.lexend(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: AccessibilityUtils.getContrastColor(context),
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, color: AccessibilityUtils.getContrastColor(context), size: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              iconSize: 36,
              padding: const EdgeInsets.all(20),
              style: IconButton.styleFrom(
                backgroundColor: AccessibilityUtils.getPrimaryButtonBackground(context),
                foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
              ),
              onPressed: preview,
              icon: const Icon(Icons.volume_up_rounded),
            ),
          ],
        ),
      );
    }

    // Балонче за говор во бојата на јазикот: голем поздрав („Здраво!“),
    // истиот поздрав на Брајово писмо и името на јазикот. Темен текст врз
    // светла боја (силен контраст). Свети и се зголемува додека воведот го
    // спомнува тој јазик, при преслушување и кога е препознаен со глас.
    final deep = Color.lerp(accent, Colors.black, 0.3)!;
    return Semantics(
      button: true,
      label: '$name. ${'language.choose'.tr()}',
      child: ValueListenableBuilder<String?>(
        valueListenable: _spotlight,
        builder: (context, spot, _) {
          final lit = spot == langCode;
          final dimmed = spot != null && !lit;
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: dimmed ? 0.55 : 1,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              scale: lit ? 1.05 : 1.0,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                turns: lit ? -0.008 : 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PressableScale(
                        child: Material(
                          color: accent,
                          elevation: lit ? 18 : 8,
                          shadowColor: lit ? accent : Colors.black.withValues(alpha: 0.45),
                          shape: SpeechBubbleBorder(
                            side: BorderSide(color: lit ? Colors.white : deep, width: lit ? 5 : 3),
                          ),
                          child: InkWell(
                            customBorder: const SpeechBubbleBorder(),
                            onTap: select,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(22, 18, 16, 18 + 18),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(greeting, style: Playful.display(34, color: Playful.ink)),
                                        ),
                                        const SizedBox(height: 8),
                                        BrailleWordReveal(
                                          text: greeting,
                                          lang: brailleLangFor(langCode),
                                          cellSize: 15,
                                          dotColor: Playful.ink,
                                          showLetters: false,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(color: Playful.ink, borderRadius: BorderRadius.circular(10)),
                                              child: Text(code, style: Playful.title(16, color: accent)),
                                            ),
                                            const SizedBox(width: 10),
                                            Flexible(child: Text(name, style: Playful.title(22, color: Playful.ink))),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: const BoxDecoration(color: Playful.ink, shape: BoxShape.circle),
                                    child: Icon(Icons.arrow_forward_rounded, color: accent, size: 30),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PressableScale(
                      child: Material(
                        color: Playful.nightRaised,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: preview,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: accent, width: 3),
                            ),
                            child: lit
                                ? Center(child: SoundWave(color: accent, bars: 5, height: 34, barWidth: 5))
                                : Icon(Icons.volume_up_rounded, color: accent, size: 36),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}