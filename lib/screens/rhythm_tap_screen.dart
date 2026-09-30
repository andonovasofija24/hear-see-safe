import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

/// Ритмичка игра: [Пушти звук] -> откриваат се [Удари], [Потврди: N] и
/// [Пушти звук повторно]. Секое притискање на "Удари" го зголемува бројот
/// прикажан на копчето "Потврди". Кога детето мисли дека тој број е точен,
/// притиска "Потврди" - тоа е конечниот одговор за таа рунда. Играта трае
/// вкупно 10 рунди, а на крајот се прикажува колку рунди се погодени.
class RhythmTapScreen extends StatefulWidget {
  const RhythmTapScreen({super.key});

  @override
  State<RhythmTapScreen> createState() => _RhythmTapScreenState();
}

class _RhythmTapScreenState extends State<RhythmTapScreen> {
  late VoiceAssistantService _voiceAssistant;
  /// Одделен плеер за говорни клипови (само за објаснувањето сега).
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратки звучни ефекти (удари, точно/грешно), за да не
  /// се прекинуваат меѓусебно кога се пуштаат близу еден до друг.
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final Random _random = Random();
  StreamSubscription? _completeSub;

  static const int _totalRounds = 10;

  /// Секој ударувачки mp3 си има свој ТОЧЕН број потребни тапкања. Прилагоди
  /// ги бројките тука според твоите вистински снимки, и додади нови
  /// инструменти по потреба.
  static const Map<String, int> _instrumentTapTargets = {
    'drum': 10,
    'wood': 7,
    'clap': 5,
    'heels': 9,
    'heart-beat': 16,
    'door-knock': 3,
  };
  static const List<String> _instruments = [
    'drum',
    'wood',
    'clap',
    'heels',
    'heart-beat',
    'door-knock',
  ];

  /// Временски моменти (во милисекунди од почеток на звукот) на секој
  /// удар - користени за да го засветат и вибрираат копчето точно кога се
  /// слуша ударот. Проценето според твоите описи; прилагоди ги ако не се
  /// совпаѓаат совршено со вистинските снимки.
  static const Map<String, List<int>> _instrumentBeatTimesMs = {
    'clap': [0, 1000, 2000, 3000, 4000],
    'door-knock': [0, 300, 600],
    'drum': [0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500],
    'heels': [0, 450, 1000, 1450, 2000, 2450, 3000, 3350, 3700],
    'wood': [0, 570, 1140, 1710, 2280, 2850, 3420],
    'heart-beat': [
      250, 400, 1500, 1650, 2750, 2900, 4000, 4150,
      5250, 5400, 6500, 6650, 7750, 7900, 9000, 9150,
    ],
  };

  String _currentInstrument = 'drum';
  final TextEditingController _tapController = TextEditingController();

  /// false = само копчето "Пушти звук" е видливо (без автоматско пуштање).
  /// true = откриени се полето за внес и "Потврди".
  bool _revealed = false;
  bool _isPlaying = false;
  /// Кратко трепкање на копчето, точно на секој удар - одделно од
  /// _isPlaying (кое трае цело време додека звукот свири).
  bool _flashPulse = false;
  int _pulseToken = 0;
  int _round = 0;
  int _hits = 0;
  bool _confirmLocked = false;
  bool _gameOver = false;
  bool _explanationOpen = false;

  /// Заклучено додека не се притисне СТАРТ - тогаш засекогаш се отклучува.
  bool _gameLocked = true;

  /// Обиди во тековната рунда - дозволени се вкупно 3 обиди пред рундата
  /// автоматски да продолжи натаму (без поен).
  int _attemptsThisRound = 0;
  static const int _maxAttempts = 3;

  /// Колку пати е пуштен звукот оваа рунда - "Пушти звук" смее само
  /// еднаш (го поставува на 1), "Пушти звук повторно" смее уште двапати
  /// (до вкупно 3).
  int _playCount = 0;
  static const int _maxPlays = 3;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _completeSub = _effectsPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
    _pickNewInstrument();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _voiceAssistant.stop();
    _completeSub?.cancel();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _pickNewInstrument() {
    _tapController.clear();
    setState(() {
      _currentInstrument = _instruments[_random.nextInt(_instruments.length)];
      _revealed = false;
      _isPlaying = false;
      _confirmLocked = false;
      _attemptsThisRound = 0;
      _playCount = 0;
    });
  }

  /// СТАРТ - се притиска еднаш, ги отклучува сите останати копчиња засекогаш.
  void _startGame() {
    if (!_gameLocked) return;
    setState(() => _gameLocked = false);
  }

  /// Секое притискање го зголемува бројот во полето за внес - помош на
  /// детето да го следи ритамот со тапкање, без да мора рачно да пишува.
  void _onHelperTap() {
    if (_gameLocked || _confirmLocked) return;
    final current = int.tryParse(_tapController.text.trim()) ?? 0;
    setState(() => _tapController.text = (current + 1).toString());
    VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 40);
    });
  }

  /// Го трепка и вибрира копчето со звукот точно на секој удар - според
  /// времињата во _instrumentBeatTimesMs.
  Future<void> _runBeatPulses(String instrument) async {
    final beats = _instrumentBeatTimesMs[instrument];
    if (beats == null || beats.isEmpty) return;
    final myToken = ++_pulseToken;
    final hasVibrator = await VibrationUtils.hasVibrator();
    var lastTime = 0;
    for (final t in beats) {
      final wait = t - lastTime;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      lastTime = t;
      if (!mounted || myToken != _pulseToken) return;
      setState(() => _flashPulse = true);
      if (hasVibrator) {
        VibrationUtils.vibrate(duration: 90);
      }
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted || myToken != _pulseToken) return;
      setState(() => _flashPulse = false);
    }
  }

  /// Пробува однапред снимена звучна датотека (твоја снимка), а само ако
  /// не постои паѓа назад на системскиот text-to-speech. Само за говорни,
  /// СТАТИЧНИ фрази (само објаснувањето).
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/rhythm_tap/$_langCode/$key.mp3';
    try {
      await _voicePlayer.stop();
    } catch (_) {}

    bool reachedPlaying = false;
    final startedCompleter = Completer<void>();
    final finishedCompleter = Completer<void>();
    late final StreamSubscription<PlayerState> stateSub;
    stateSub = _voicePlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        reachedPlaying = true;
        if (!startedCompleter.isCompleted) startedCompleter.complete();
      }
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (!startedCompleter.isCompleted) startedCompleter.complete();
        if (!finishedCompleter.isCompleted) finishedCompleter.complete();
      }
    });

    bool playCallSucceeded = false;
    try {
      await _voicePlayer.play(AssetSource(relativePath));
      playCallSucceeded = true;
    } catch (_) {
      playCallSucceeded = false;
    }

    if (playCallSucceeded) {
      await startedCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      if (reachedPlaying) {
        await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
      }
    }
    await stateSub.cancel();

    if (!mounted) return;
    if (!(playCallSucceeded && reachedPlaying)) {
      await _voiceAssistant.speakWithLanguage(fallbackText, _langCode, vibrate: false);
    }
  }

  /// Заедничка логика за реално пуштање на клипот + трепкање/вибрација.
  Future<void> _playSoundInternal() async {
    setState(() => _isPlaying = true);
    try {
      await _effectsPlayer.stop();
      await _effectsPlayer.play(AssetSource('sounds/rhythm/$_currentInstrument.mp3'));
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
    _runBeatPulses(_currentInstrument);
  }

  /// "Пушти звук" - смее да се притисне САМО ЕДНАШ по рунда. За да се
  /// слушне повторно, детето мора да го користи "Пушти звук повторно".
  Future<void> _playInstrumentSound() async {
    if (_gameLocked || _playCount != 0) return;
    setState(() {
      _playCount = 1;
      _revealed = true;
    });
    await _playSoundInternal();
  }

  /// "Пушти звук повторно" - смее да се притисне уште најмногу 2 пати
  /// (значи вкупно 3 пуштања по рунда, вклучувајќи го првото).
  Future<void> _playAgainSound() async {
    if (_gameLocked || _playCount == 0 || _playCount >= _maxPlays) return;
    setState(() => _playCount++);
    await _playSoundInternal();
  }

  /// "Потврди" - го потврдува впишаниот број како конечен одговор за оваа
  /// рунда. Заклучено додека трае обработката, за да не се смета двојно/
  /// тројно ако детето го притисне копчето повеќе пати додека чека.
  Future<void> _onConfirm() async {
    if (_confirmLocked || _gameLocked) return;
    _confirmLocked = true;

    final entered = int.tryParse(_tapController.text.trim()) ?? -1;
    final target = _instrumentTapTargets[_currentInstrument] ?? 1;
    final isCorrect = entered == target;

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: isCorrect ? 220 : 100);
    }

    if (isCorrect) {
      setState(() => _hits++);
      await _playClip('correct', 'rhythm.great'.tr());
      await Future.delayed(const Duration(milliseconds: 1000));
      _confirmLocked = false;
      if (!mounted) return;
      _nextRound();
      return;
    }

    // Неточно - дозволени вкупно 3 обиди по рунда пред автоматски да се
    // продолжи натаму (без поен за таа рунда).
    _attemptsThisRound++;
    await _playClip('incorrect', 'rhythm.incorrect'.tr());
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    if (_attemptsThisRound < _maxAttempts) {
      setState(() {
        _tapController.clear();
        _confirmLocked = false;
      });
    } else {
      _confirmLocked = false;
      _nextRound();
    }
  }

  void _nextRound() {
    final newRound = _round + 1;
    if (newRound >= _totalRounds) {
      setState(() {
        _round = newRound;
        _gameOver = true;
      });
    } else {
      setState(() => _round = newRound);
      _pickNewInstrument();
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _hits = 0;
      _gameOver = false;
    });
    _pickNewInstrument();
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation', 'rhythm.explanation_text'.tr());
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  /// Затемнета/осветлена нијанса на дадена боја - користена за "3D" рабови
  /// и сенки на копчињата (без разлика на бојата на копчето).
  Color _shade(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness * factor).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  /// Заедничка "3D" (испакната) декорација за сите копчиња во играта -
  /// градиент светло->база одозгора надолу, потемнет долен раб + мека
  /// сенка за вистински волумен. Во контраст-режим останува рамно (само
  /// поисполнета боја + бел раб), за да не се губи читливоста/контрастот.
  BoxDecoration _threeD({
    required Color base,
    required bool hc,
    required Color contrast,
    double radius = 16,
  }) {
    if (hc) {
      return BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: contrast, width: 3),
      );
    }
    final light = _shade(base, 1.35);
    final dark = _shade(base, 0.6);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        colors: [light, base],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      border: Border.all(color: dark, width: 1.5),
      boxShadow: [
        // Потемнет "раб" веднаш под копчето - создава испакнат/3D изглед.
        BoxShadow(color: dark, offset: const Offset(0, 5), blurRadius: 0),
        // Мека амбиентална сенка околу него.
        BoxShadow(color: Colors.black.withOpacity(0.32), offset: const Offset(0, 9), blurRadius: 14),
      ],
    );
  }

  /// Генеричко правоаголно "3D" копче (со икона + текст) - користено за
  /// Објаснување, Потврди и Играј повторно.
  Widget _build3dButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color base,
    required bool hc,
    required Color contrast,
    double iconSize = 22,
    double fontSize = 16,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: 14),
    double radius = 16,
  }) {
    final disabled = onPressed == null;
    return Semantics(
      label: label,
      button: !disabled,
      child: Opacity(
        opacity: disabled ? 0.45 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              width: double.infinity,
              padding: padding,
              decoration: _threeD(base: base, hc: hc, contrast: contrast, radius: radius),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: iconSize, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: const Color(0xFFE11D48),
      title: 'features.rhythm_tap'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrast),
            if (_explanationOpen) _buildExplanationPanel(contrast),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _gameOver
                    ? 'rhythm.game_over_title'.tr()
                    : 'rhythm.rounds_progress'.tr(args: [
                        (_round + 1).toString(),
                        _totalRounds.toString(),
                      ]),
                style: GameTypography.heading(context, contrast, 20),
              ),
            ),
            Expanded(
              child: _gameOver
                  ? _buildEndScreen(contrast)
                  : _buildStage(contrast, hc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final label = _explanationOpen
        ? 'rhythm.explanation_toggle_close'.tr()
        : 'rhythm.explanation_toggle_open'.tr();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _build3dButton(
        label: label,
        icon: _explanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded,
        onPressed: _toggleExplanation,
        base: _explanationOpen ? AccessibilityUtils.getDisabledColor(context) : const Color(0xFFE11D48),
        hc: hc,
        contrast: contrast,
        iconSize: 26,
        fontSize: 17,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildExplanationPanel(Color contrast) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48).withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: Color(0xFFE11D48)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'rhythm.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'rhythm.explanation_text'.tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
        ],
      ),
    );
  }

  /// Точна шема 3x3 (E=празно, F=полно):
  ///   E F E   <- ред 1: старт во средината
  ///   E F E   <- ред 2: пушти звук + пушти звук повторно, заедно во средината
  ///   F E F   <- ред 3: помошно копче (лево) | празно | внес+потврди (десно)
  Widget _buildStage(Color contrast, bool hc) {
    return Stack(
      children: [
        Positioned.fill(child: _buildRhythmScene(hc)),
        _buildStageContent(contrast, hc),
      ],
    );
  }

  /// Видлива "сцена" во позадина - темна градиентска подлога (како
  /// концертна сцена), со централен "рефлектор" (spotlight) зад копчињата,
  /// разбушени светла и еквилајзер-ленти. Многу повидлива од претходната
  /// верзија, но сепак секое копче стои на сопствена контрастна плоча
  /// (_threeD/панелите), па читливоста и контрастот остануваат зачувани.
  Widget _buildRhythmScene(bool hc) {
    if (hc) return const SizedBox.shrink(); // без декорации во контраст-режим
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A0510), Color(0xFF3B0A1E), Color(0xFF1A0510)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            const positions = [0.06, 0.16, 0.26, 0.36, 0.5, 0.64, 0.74, 0.84, 0.94];
            const heights = [0.4, 0.7, 0.3, 0.85, 0.55, 0.9, 0.35, 0.75, 0.45];
            return Stack(
              children: [
                // Централен "рефлектор" - светла топка зад главните копчиња.
                Align(
                  alignment: const Alignment(0, -0.35),
                  child: Container(
                    width: w * 0.95,
                    height: h * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFE11D48).withOpacity(0.38),
                          const Color(0xFFE11D48).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Разбушени "сценски" светла по аглите.
                Positioned(
                  top: -40,
                  left: -40,
                  child: _sceneGlow(140, const Color(0xFFFACC15)),
                ),
                Positioned(
                  top: -30,
                  right: -30,
                  child: _sceneGlow(120, const Color(0xFF60A5FA)),
                ),
                // Еквилајзер-ленти долж дното - поживи и повидливи.
                for (var i = 0; i < positions.length; i++)
                  Positioned(
                    left: positions[i] * w - 12,
                    bottom: 0,
                    width: 24,
                    height: heights[i] * h * 0.42,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFB7185).withOpacity(0.55),
                            const Color(0xFFFB7185).withOpacity(0.15),
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Мала кружна "светлосна дамка" - декоративен елемент за сцената.
  Widget _sceneGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.30), color.withOpacity(0.0)],
        ),
      ),
    );
  }

  Widget _buildStageContent(Color contrast, bool hc) {
    // Текст исцртан ДИРЕКТНО врз сцената (не внатре во бела картичка) мора
    // да биде светол за да остане читлив на темната позадина; во HC-режим
    // веќе се користи бела/жолта боја преку `contrast`, па таму не менуваме.
    final sceneTextColor = hc ? contrast : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Text(
            'rhythm.score'.tr(args: [_hits.toString()]),
            style: GameTypography.body(context, sceneTextColor, 16),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                // Ред 1: E F E - старт копчето.
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Expanded(child: Center(child: _buildStartButton(contrast, hc))),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
                // Ред 2: E F E - звучните копчиња.
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _gameLocked,
                          child: Opacity(
                            opacity: _gameLocked ? 0.35 : 1.0,
                            child: _buildPlayButtonsCell(contrast, hc, sceneTextColor),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
                // Ред 3: F E F - копчето за УДИРАЊЕ (лево) сега е многу
                // поголемо - зазема многу поголем дел (flex: 5) отколку
                // претходно, растејќи од каде што стоеше сега сè до дното
                // на екранот; десно останува внесот на бројот + Потврди.
                Expanded(
                  flex: 5,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _gameLocked || !_revealed,
                          child: Opacity(
                            opacity: (_gameLocked || !_revealed) ? 0.35 : 1.0,
                            child: _buildHelperCell(contrast, hc),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: _gameLocked || !_revealed,
                          child: Opacity(
                            opacity: (_gameLocked || !_revealed) ? 0.35 : 1.0,
                            child: _buildEntryCell(contrast, hc),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// СТАРТ - правоаголно, со икона, сега во "3D" стил - го исполнува целиот
  /// свој дел од шемата. Ги отклучува останатите копчиња засекогаш штом ќе
  /// се притисне.
  Widget _buildStartButton(Color contrast, bool hc) {
    final base = _gameLocked ? const Color(0xFFE11D48) : const Color(0xFF16A34A);
    return Semantics(
      label: 'rhythm.start_button'.tr(),
      button: _gameLocked,
      child: SizedBox(
        width: 170,
        height: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _gameLocked ? _startGame : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: _threeD(base: base, hc: hc, contrast: contrast, radius: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'rhythm.start_button'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Пушти звук (само еднаш) + Пушти звук повторно (до 2 пати повеќе) -
  /// заедно вкупно 3 пуштања по рунда, со бројач X/3.
  Widget _buildPlayButtonsCell(Color contrast, bool hc, Color labelColor) {
    final canPlayFirst = _playCount == 0;
    final canPlayAgain = _playCount > 0 && _playCount < _maxPlays;
    // LayoutBuilder + FittedBox: оваа ќелија добива фиксна (флекс) висина
    // од родителот, која варира со висината на екранот. Претходно
    // круговите имаа ФИКСЕН дијаметар (150/130) кој на пониски екрани/
    // прозорци не стигаше (RenderFlex overflow). Сега содржината се
    // смета според вистински достапниот простор и, ако сепак остане
    // тесно, FittedBox ја смалува пропорционално - без overflow, без
    // разлика на висината.
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
        // ~34px за размаците + бројачот текст, остатокот за кругот+натпис.
        final circleAreaHeight = (availableHeight - 34).clamp(70.0, 220.0);
        final bigDiameter = (circleAreaHeight * 0.72).clamp(70.0, 150.0);
        final smallDiameter = bigDiameter * (130 / 150);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: canPlayFirst ? 1.0 : 0.35,
                    child: AbsorbPointer(
                      absorbing: !canPlayFirst,
                      child: _buildCircleButton(
                        contrast: contrast,
                        hc: hc,
                        labelColor: labelColor,
                        icon: Icons.volume_up_rounded,
                        label: 'rhythm.play_button'.tr(),
                        flash: _flashPulse,
                        onTap: _playInstrumentSound,
                        diameter: bigDiameter,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Opacity(
                    opacity: canPlayAgain ? 1.0 : 0.35,
                    child: AbsorbPointer(
                      absorbing: !canPlayAgain,
                      child: _buildCircleButton(
                        contrast: contrast,
                        hc: hc,
                        labelColor: labelColor,
                        icon: Icons.replay_rounded,
                        label: 'rhythm.play_again_button'.tr(),
                        flash: false,
                        onTap: _playAgainSound,
                        diameter: smallDiameter,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$_playCount/$_maxPlays',
                style: GameTypography.body(context, labelColor, 15),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Кратко објаснување + голем "3D" копче за удирање - копчето сега го
  /// зазема речиси целиот преостанат простор во оваа ќелија (Expanded),
  /// растејќи од каде што почнуваше сè до дното на екранот, со голема
  /// икона која асоцира на удирање/тапкање (тропната дланка).
  Widget _buildHelperCell(Color contrast, bool hc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hc ? const Color(0xFFE11D48).withOpacity(0.08) : Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE11D48).withOpacity(hc ? 0.35 : 0.6),
          width: 1.5,
        ),
        boxShadow: hc
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'rhythm.helper_explanation'.tr(),
            textAlign: TextAlign.center,
            style: GameTypography.body(context, contrast, 12),
          ),
          const SizedBox(height: 8),
          // Големото копче за удирање - пополнува сè до дното на екранот.
          Expanded(
            child: Semantics(
              label: 'rhythm.hit_button'.tr(),
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _onHelperTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: double.infinity,
                    decoration: _threeD(
                      base: const Color(0xFFBE123C),
                      hc: hc,
                      contrast: contrast,
                      radius: 20,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final iconSize = (constraints.maxHeight * 0.42).clamp(40.0, 96.0);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.back_hand_rounded, size: iconSize, color: Colors.white),
                            const SizedBox(height: 6),
                            Text(
                              'rhythm.hit_button'.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Поле за внес на број + копче Потврди - заедно го исполнуваат целиот
  /// свој дел од шемата. Копчето Потврди НЕ е низ цел екран - само ја
  /// зафаќа ширината на овој дел.
  Widget _buildEntryCell(Color contrast, bool hc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc ? const Color(0xFFE11D48).withOpacity(0.08) : Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE11D48).withOpacity(hc ? 0.35 : 0.6),
          width: 1.5,
        ),
        boxShadow: hc
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'rhythm.entry_explanation'.tr(),
            textAlign: TextAlign.center,
            style: GameTypography.body(context, contrast, 13),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'rhythm.enter_taps_label'.tr(),
            textField: true,
            child: TextField(
              controller: _tapController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: false,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: contrast.withOpacity(0.06),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: contrast, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE11D48), width: 2.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _build3dButton(
            label: 'rhythm.confirm_button'.tr(),
            icon: Icons.check_circle_rounded,
            onPressed: _confirmLocked ? null : _onConfirm,
            base: const Color(0xFF16A34A),
            hc: hc,
            contrast: contrast,
            fontSize: 16,
            padding: const EdgeInsets.symmetric(vertical: 14),
            radius: 14,
          ),
        ],
      ),
    );
  }

  /// Заедничкиот голем круг-копче користен и за "Пушти звук" и за "Удари" -
  /// сега со изразена "3D" (испакната) сенка + блесок (визуелен + тактилен
  /// преку вибрација) секогаш кога се тапне.
  Widget _buildCircleButton({
    required Color contrast,
    required bool hc,
    required IconData icon,
    required String label,
    required bool flash,
    required VoidCallback onTap,
    Color? labelColor,
    double diameter = 150,
  }) {
    final darkEdge = _shade(const Color(0xFFE11D48), 0.55);
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: flash ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hc
                      ? null
                      : LinearGradient(
                          colors: flash
                              ? [const Color(0xFFFB7185), const Color(0xFFFCA5A5)]
                              : [const Color(0xFFFB7185), const Color(0xFFBE123C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: hc ? const Color(0xFFE11D48) : null,
                  border: Border.all(color: contrast, width: hc ? 3 : 0),
                  boxShadow: hc
                      ? const <BoxShadow>[]
                      : [
                          // Потемнет полукружен "раб" долу-десно - "3D" волумен.
                          BoxShadow(
                            color: darkEdge.withOpacity(0.9),
                            offset: const Offset(0, 6),
                            blurRadius: 0,
                          ),
                          BoxShadow(
                            color: const Color(0xFFE11D48).withOpacity(flash ? 0.6 : 0.35),
                            offset: const Offset(0, 4),
                            blurRadius: flash ? 34 : 18,
                            spreadRadius: flash ? 5 : 1,
                          ),
                        ],
                ),
                child: Icon(icon, size: diameter * 0.35, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GameTypography.heading(context, labelColor ?? contrast, diameter >= 130 ? 17 : 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndScreen(Color contrast) {
    final misses = _totalRounds - _hits;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: Color(0xFFE11D48)),
            const SizedBox(height: 16),
            Text(
              'rhythm.final_summary'.tr(args: [
                _hits.toString(),
                misses.toString(),
                _totalRounds.toString(),
              ]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 220,
              child: _build3dButton(
                label: 'rhythm.play_again'.tr(),
                icon: Icons.refresh_rounded,
                onPressed: _restart,
                base: const Color(0xFFE11D48),
                hc: AccessibilityUtils.isHighContrast(context),
                contrast: contrast,
                fontSize: 16,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}