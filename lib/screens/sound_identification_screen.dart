import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/widgets/sound_ear_art.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';

/// Колку пати е поголем текстот на екранот за идентификација на звук.
const double _kSidText = 1.6;

/// Идентификација на звук: детето слуша еден звук (копче Пушти звук,
/// никогаш автоматски), а потоа картичките тргнуваат по свиткана лента кон
/// големо уво. Пред секоја картичка да влезе во увото, застанува и се слуша
/// НЕЈЗИНИОТ звук - детето може да запре („ова е тоа!“) или да продолжи.
/// Одговор и со допир на картичката или со глас (име / „запри“).
/// Играта трае вкупно 20 рунди.
class SoundIdentificationScreen extends StatefulWidget {
  const SoundIdentificationScreen({super.key});

  @override
  State<SoundIdentificationScreen> createState() =>
      _SoundIdentificationScreenState();
}

class _SoundIdentificationScreenState extends State<SoundIdentificationScreen> with SingleTickerProviderStateMixin {
  static const Color _moduleAccent = Color(0xFF0D9488);
  static const int _totalRounds = 20;

  late VoiceAssistantService _voiceAssistant;
  final AudioPlayer _audioPlayer = AudioPlayer();

  static const List<String> _soundIds = [
    'dog', 'car', 'cat', 'rain', 'heels', 'wind', 'bird', 'water', 'glass',
  ];

  static const Map<String, String> _soundAssets = {
    'dog': 'assets/sounds/sound_identification/bark.mp3',
    'car': 'assets/sounds/sound_identification/car.mp3',
    'cat': 'assets/sounds/sound_identification/meow.mp3',
    'rain': 'assets/sounds/sound_identification/rain.mp3',
    'heels': 'assets/sounds/sound_identification/heels.mp3',
    'wind': 'assets/sounds/sound_identification/wind.mp3',
    'bird': 'assets/sounds/sound_identification/bird.mp3',
    'water': 'assets/sounds/sound_identification/water.mp3',
    'glass': 'assets/sounds/sound_identification/glass.mp3',
  };

  static const Map<String, IconData> _soundIcons = {
    'dog': Icons.cruelty_free_rounded,
    'car': Icons.directions_car_filled_rounded,
    'cat': Icons.pets_rounded,
    'rain': Icons.water_drop_rounded,
    'heels': Icons.directions_walk_rounded,
    'wind': Icons.air_rounded,
    'bird': Icons.flutter_dash_rounded,
    'water': Icons.local_drink_rounded,
    'glass': Icons.window_rounded,
  };

  static const Map<String, Color> _soundColors = {
    'dog': Color(0xFFD97706),
    'car': Color(0xFF2563EB),
    'cat': Color(0xFF9333EA),
    'rain': Color(0xFF0D9488),
    'heels': Color(0xFFDB2777),
    'wind': Color(0xFF64748B),
    'bird': Color(0xFF16A34A),
    'water': Color(0xFF0EA5E9),
    'glass': Color(0xFF71717A),
  };

  /// Сликички за картичките.
  static const Map<String, String> _soundEmojis = {
    'dog': '🐶',
    'car': '🚗',
    'cat': '🐱',
    'rain': '🌧️',
    'heels': '👠',
    'wind': '🌬️',
    'bird': '🐦',
    'water': '🚰',
    'glass': '🥂',
  };

  final Random _random = Random();

  // ---------------------------------------------------------------------
  // Лентата до увото.
  // ---------------------------------------------------------------------

  /// „Портата“ пред увото - тука картичката застанува и се слуша.
  static const double _gate = 0.74;

  /// Брзина (дел од патеката во секунда): бавно / нормално.
  static const double _slowSpeed = 0.06;
  static const double _normalSpeed = 0.1;

  final AudioPlayer _cardPlayer = AudioPlayer();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _clock = 0;
  List<String> _beltIds = [];
  double _beltOffset = 0;
  bool _moving = false;
  bool _slow = false;

  /// Индекс (во [_beltIds]) на картичката што стои пред увото.
  int? _gateIndex;
  bool _gateSounding = false;
  Timer? _resumeTimer;
  EarBeltGeometry? _geo;

  bool _explanationOpen = false;
  bool _isPlaying = false;
  /// Дали е притиснато "Пушти звук" барем еднаш во тековната рунда - додека
  /// не е точно, картичките не смеат да се допираат (нема да се брои како
  /// промашена рунда пред воопшто да почне).
  bool _roundStarted = false;
  /// За визуелна повратна информација - која картичка е избрана и дали е точна.
  String? _pickedId;
  bool? _pickedCorrect;
  String? _target;
  int _round = 0;
  int _hits = 0;
  bool _gameOver = false;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _beltIds = [..._soundIds]..shuffle(_random);
    _ticker = createTicker(_onTick)..start();
    HardwareKeyboard.instance.addHandler(_onKey);
    _pickTarget();
  }

  bool get _reduce => Playful.reduceMotion(context);

  /// Положбата на картичката [i] по патеката: 0 = почеток, 1 = во увото,
  /// над 1 = „невидливо патување“ до почетокот.
  double _sOf(int i, [double? offset]) =>
      (((offset ?? _beltOffset) + i / _beltIds.length) % 1.0) * EarBeltGeometry.loop;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    if (!mounted) return;
    _clock += dt;
    if (!_moving || _gameOver || _pickedId != null || _reduce) {
      // Брановите се движат и кога лентата мирува.
      if (_isPlaying || _gateSounding) setState(() {});
      return;
    }
    final next = _beltOffset + dt * (_slow ? _slowSpeed : _normalSpeed) / EarBeltGeometry.loop;
    for (var i = 0; i < _beltIds.length; i++) {
      final a = _sOf(i), b = _sOf(i, next);
      if (a < _gate && b >= _gate && b - a < 0.5) {
        // Картичката стигна пред увото - точно на портата.
        setState(() => _beltOffset += (_gate - a) / EarBeltGeometry.loop);
        _arriveAtGate(i);
        return;
      }
    }
    setState(() => _beltOffset = next);
  }

  /// Со исклучени анимации: скок до следната картичка пред увото.
  void _jumpToNextGate() {
    var best = 99.0;
    var bestI = 0;
    for (var i = 0; i < _beltIds.length; i++) {
      var d = (_gate - _sOf(i)) % EarBeltGeometry.loop;
      if (d < 1e-6) d += EarBeltGeometry.loop;
      if (d < best) {
        best = d;
        bestI = i;
      }
    }
    setState(() => _beltOffset += best / EarBeltGeometry.loop);
    _arriveAtGate(bestI);
  }

  /// Картичката застанува пред увото и го пушта СВОЈОТ звук; потоа (ако
  /// детето не запре) лентата сама продолжува.
  Future<void> _arriveAtGate(int i) async {
    _resumeTimer?.cancel();
    setState(() {
      _moving = false;
      _gateIndex = i;
      _gateSounding = true;
    });
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 50);
    }));
    final id = _beltIds[i];
    final done = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _cardPlayer.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _cardPlayer.stop();
      final path = _soundAssets[id]!;
      await _cardPlayer.play(AssetSource(path.startsWith('assets/') ? path.substring(7) : path));
      await done.future.timeout(const Duration(seconds: 4), onTimeout: () {});
    } catch (_) {}
    await sub.cancel();
    if (!mounted || _gateIndex != i) return;
    setState(() => _gateSounding = false);
    // Време за одлука: „Запри“ или „Продолжи“; инаку - продолжува само.
    _resumeTimer = Timer(Duration(milliseconds: _slow ? 2600 : 1600), () {
      if (mounted && _gateIndex == i && _pickedId == null) _resumeBelt();
    });
  }

  /// „Продолжи“ - лентата пак тргнува.
  void _resumeBelt() {
    // Додека е отворено објаснувањето - лентата мирува.
    if (_gameOver || !_roundStarted || _pickedId != null || _explanationOpen) return;
    _resumeTimer?.cancel();
    _cardPlayer.stop();
    setState(() {
      _gateIndex = null;
      _gateSounding = false;
      _moving = true;
    });
    if (_reduce) _jumpToNextGate();
  }

  /// „Запри - ова е тоа!“: одговор е картичката пред увото (или најблиската
  /// до него ако лентата уште се движи).
  void _stopBelt() {
    if (_gameOver || !_roundStarted || _pickedId != null) return;
    var idx = _gateIndex;
    if (idx == null) {
      var best = 2.0;
      for (var i = 0; i < _beltIds.length; i++) {
        final s = _sOf(i);
        if (s > 0.97) continue;
        final d = (s - _gate).abs();
        if (d < best) {
          best = d;
          idx = i;
        }
      }
    }
    if (idx == null) return;
    _onChoose(_beltIds[idx]);
  }

  void _haltBelt() {
    _resumeTimer?.cancel();
    _cardPlayer.stop();
    _moving = false;
    _gateSounding = false;
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _cardPlayer.dispose();
    _voiceAssistant.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _pickTarget() {
    String next;
    do {
      next = _soundIds[_random.nextInt(_soundIds.length)];
    } while (next == _target && _soundIds.length > 1);
    _haltBelt();
    setState(() {
      _target = next;
      _roundStarted = false;
      _pickedId = null;
      _pickedCorrect = null;
      _gateIndex = null;
    });
  }

  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голтa" грешка и никогаш не влегува во состојба
  /// "playing". Затоа не се потпираме само на тоа дали .play() фрлил
  /// исклучок - експлицитно чекаме потврда дека звукот НАВИСТИНА почнал,
  /// инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/sound_identification/$_langCode/$key.mp3';
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    bool reachedPlaying = false;
    final startedCompleter = Completer<void>();
    final finishedCompleter = Completer<void>();
    late final StreamSubscription<PlayerState> stateSub;
    stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
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
      await _audioPlayer.play(AssetSource(relativePath));
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

  Future<void> _playTargetSound() async {
    if (_target == null || _pickedId != null) return;
    final firstTime = !_roundStarted;
    // Додека се слуша целниот звук - лентата мирува.
    _haltBelt();
    setState(() {
      _isPlaying = true;
      _roundStarted = true;
      _gateIndex = null;
    });
    final done = Completer<void>();
    final sub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      final path = _soundAssets[_target]!;
      final relative = path.startsWith('assets/') ? path.substring(7) : path;
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(relative));
    } catch (_) {
      if (!done.isCompleted) done.complete();
    }
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 60);
    }));
    // Чека звукот да заврши (најмногу 5 s), па кратка пауза.
    await Future.wait([
      done.future.timeout(const Duration(seconds: 5), onTimeout: () {}),
      Future.delayed(const Duration(milliseconds: 900)),
    ]);
    await sub.cancel();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _isPlaying = false);
    // По звукот лентата тргнува (и по „Повтори звук“ продолжува).
    if (_pickedId == null && !_gameOver && !_moving && (firstTime || _gateIndex == null)) {
      _resumeBelt();
    }
  }

  /// hit.mp3 / miss.mp3 од assets/sounds/pong/ - позитивен/негативен звук
  /// за одговор.
  Future<void> _playPongEffect(String fileName) async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _audioPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  Future<void> _onChoose(String id) async {
    // Додека не е притиснато "Пушти звук", картичките се неактивни - не
    // смее да се регистрира одговор пред рундата воопшто да почне.
    if (_gameOver || !_roundStarted || _pickedId != null) return;
    final isCorrect = id == _target;
    _haltBelt();
    setState(() {
      _pickedId = id;
      _pickedCorrect = isCorrect;
    });

    if (await VibrationUtils.hasVibrator()) {
      if (isCorrect) {
        await VibrationUtils.vibrate(duration: 200);
      } else {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
    }

    if (isCorrect) {
      setState(() => _hits++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _nextRound();
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
      _pickTarget();
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _hits = 0;
      _gameOver = false;
      _beltIds = [..._soundIds]..shuffle(_random);
      _beltOffset = 0;
    });
    _pickTarget();
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    if (opening) {
      // Лентата запира и картичката не свири преку објаснувањето.
      _haltBelt();
      _gateIndex = null;
    }
    setState(() => _explanationOpen = opening);
    if (!opening && _roundStarted && _pickedId == null && !_isPlaying) _resumeBelt();
    if (opening) {
      _playClip('explanation', 'sound.explanation_text'.tr());
    } else {
      _voiceAssistant.stop();
      _audioPlayer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.sound_identification'.tr(),
      voiceOptions: _voiceOptions(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['🔊', '🎵', '👂', '🎶', '〰️', '🔔'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
            final header = <Widget>[
              PlayfulExplainButton(
                open: _explanationOpen,
                label: _explanationOpen
                    ? 'sound.explanation_toggle_close'.tr()
                    : 'sound.explanation_toggle_open'.tr(),
                onTap: _toggleExplanation,
              ),
              if (_explanationOpen)
                PlayfulExplainPanel(
                  icon: Icons.hearing_rounded,
                  title: 'sound.explanation_title'.tr(),
                  text: 'sound.explanation_text'.tr(),
                  accent: _moduleAccent,
                ),
              const SizedBox(height: 16),
            ];

            if (_gameOver) {
              final misses = _totalRounds - _hits;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...header,
                          Text(
                            'sound.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26 * _kSidText, color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: PlayfulResult(
                      text: 'sound.final_summary'.tr(args: [
                        _hits.toString(),
                        misses.toString(),
                        _totalRounds.toString(),
                      ]),
                      buttonLabel: 'sound.play_again'.tr(),
                      onAgain: _restart,
                      stars: _hits,
                      total: _totalRounds,
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(side, 12, side, 28),
              children: [
                ...header,
                RoundProgress(
                  label: 'sound.rounds_progress'.tr(args: [
                    (_round + 1).toString(),
                    _totalRounds.toString(),
                  ]),
                  current: _round,
                  total: _totalRounds,
                  extra: '⭐ $_hits',
                ),
                const SizedBox(height: 14),
                // Лентата до увото.
                _buildBelt(constraints.maxWidth - side * 2, hc),
                const SizedBox(height: 14),
                _buildControls(hc),
                const SizedBox(height: 10),
                PlayfulHint(_roundStarted ? 'sound.belt_hint'.tr() : 'sound.belt_start_hint'.tr()),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Изглед: лента, уво, картички, копчиња.
  // ---------------------------------------------------------------------

  Widget _buildBelt(double width, bool hc) {
    final h = (width * (width < 600 ? 0.95 : 0.6)).clamp(320.0, 520.0).toDouble();
    final size = Size(width, h);
    var geo = _geo;
    if (geo == null || geo.size != size) {
      geo = EarBeltGeometry(size);
      _geo = geo;
    }
    final n = _beltIds.length;
    // Прво поблиските до увото (помали), па големите - над нив.
    final order = [for (var i = 0; i < n; i++) (i, _sOf(i))]..sort((a, b) => b.$2.compareTo(a.$2));
    final sounding = _isPlaying || _gateSounding;
    final Color? glow = _pickedCorrect == null ? null : (_pickedCorrect! ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: EarBeltPainter(geo: geo, offset: _beltOffset, color: _moduleAccent, hc: hc, gate: _gate),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: EarBackPainter(geo: geo, hc: hc, pulse: sounding && !_reduce ? (_clock * 0.9) % 1.0 : 0, glow: glow),
              ),
            ),
          ),
          // „Пушти звук“ - во средината на полукругот.
          Positioned(
            left: geo.orbCenter.dx - geo.orbSize / 2 - 20,
            top: geo.orbCenter.dy - geo.orbSize / 2,
            width: geo.orbSize + 40,
            child: SoundOrb(
              icon: _roundStarted ? Icons.replay_rounded : Icons.volume_up_rounded,
              label: _roundStarted ? 'sound.replay'.tr() : 'sound.start'.tr(),
              onTap: _pickedId == null ? _playTargetSound : null,
              active: _isPlaying,
              size: geo.orbSize,
            ),
          ),
          for (final (i, s) in order)
            if (s < 0.985) _beltCard(i, s, geo, hc),
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: EarFrontPainter(geo: geo, hc: hc))),
          ),
        ],
      ),
    );
  }

  Widget _beltCard(int i, double s, EarBeltGeometry geo, bool hc) {
    final id = _beltIds[i];
    final size = geo.cardAt(s);
    final p = geo.pointAt(s);
    // Пред каналот картичката бледее и „влегува“ во увото.
    final fade = s > 0.9 ? ((0.985 - s) / 0.085).clamp(0.0, 1.0) : 1.0;
    final atGate = _gateIndex == i;
    final isPicked = _pickedId == id;
    final name = 'sound.name_$id'.tr();
    final card = SoundCard(
      emoji: _soundEmojis[id]!,
      label: name,
      color: _soundColors[id]!,
      size: size,
      hc: hc,
      atGate: atGate,
      playing: atGate && _gateSounding,
      state: isPicked ? _pickedCorrect : null,
      wave: (_clock * 1.2) % 1.0,
    );
    return Positioned(
      key: ValueKey('belt-$id'),
      left: p.dx - size / 2,
      top: p.dy - size * 0.575,
      width: size,
      height: size * 1.15,
      child: Opacity(
        opacity: (_roundStarted ? 1.0 : 0.7) * fade,
        child: Transform.rotate(
          // Картичката малку се навалува по лентата.
          angle: geo.angleAt(s) * 0.12,
          child: Semantics(
            button: true,
            enabled: _roundStarted && _pickedId == null,
            label: name,
            onTap: () => _onChoose(id),
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onChoose(id),
                child: AnimatedScale(
                  // Пред увото картичката се зголемува - добро се гледа.
                  scale: atGate || isPicked ? 1.35 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _beltButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required bool hc,
    bool big = false,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: PressableScale(
            enabled: onTap != null,
            child: Material(
              color: hc ? Colors.black : color,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: Container(
                  constraints: BoxConstraints(minHeight: big ? 72 : 60),
                  padding: EdgeInsets.symmetric(horizontal: big ? 20 : 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: hc ? const Color(0xFFFFFF00) : Colors.white, width: big ? 4 : 3),
                    boxShadow: hc ? null : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: big ? 36 : 30, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(child: Text(label, style: Playful.title((big ? 17 : 15) * 1.4, color: Colors.white))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(bool hc) {
    final canAct = _roundStarted && _pickedId == null && !_gameOver;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 12,
          children: [
            _beltButton(
              icon: Icons.front_hand_rounded,
              label: 'sound.belt_stop'.tr(),
              color: const Color(0xFFDC2626),
              onTap: canAct ? _stopBelt : null,
              hc: hc,
              big: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            _beltButton(
              icon: Icons.play_arrow_rounded,
              label: 'sound.belt_continue'.tr(),
              color: const Color(0xFF0D9488),
              onTap: canAct && !_moving && !_isPlaying ? _resumeBelt : null,
              hc: hc,
            ),
            _beltButton(
              icon: _slow ? Icons.directions_run_rounded : Icons.directions_walk_rounded,
              label: _slow ? 'sound.belt_fast'.tr() : 'sound.belt_slow'.tr(),
              color: const Color(0xFF6D28D9),
              onTap: () => setState(() => _slow = !_slow),
              hc: hc,
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Гласовни команди: име на картичка, „запри“, „продолжи“, „пушти“.
  // ---------------------------------------------------------------------

  List<VoiceCategoryOption> _voiceOptions() {
    if (_gameOver) return const [];
    return [
      VoiceCategoryOption(
        keywords: const ['запри', 'стоп', 'ова е', 'тоа е', 'stop', 'this one', 'that one', 'ndalo', 'ndal', 'ky është'],
        beforeGlobal: true,
        onSelected: _stopBelt,
      ),
      VoiceCategoryOption(
        keywords: const ['продолжи', 'понатаму', 'следна', 'следно', 'continue', 'next', 'go on', 'vazhdo', 'tjetra'],
        beforeGlobal: true,
        onSelected: _resumeBelt,
      ),
      VoiceCategoryOption(
        keywords: const ['пушти', 'повтори', 'play', 'replay', 'again', 'luaj', 'përsëri'],
        beforeGlobal: true,
        onSelected: _playTargetSound,
      ),
      for (final id in _soundIds)
        VoiceCategoryOption(
          keywords: [
            'sound.name_$id'.tr().toLowerCase(),
            if (_extraNames[id] != null) ..._extraNames[id]!,
          ],
          beforeGlobal: true,
          onSelected: () => _onChoose(id),
        ),
    ];
  }

  /// Дополнителни зборови за картичките (сите јазици).
  static const Map<String, List<String>> _extraNames = {
    'dog': ['куче', 'dog', 'qen'],
    'car': ['автомобил', 'кола', 'car', 'makin'],
    'cat': ['мачка', 'маче', 'cat', 'mace', 'mac'],
    'rain': ['дожд', 'rain', 'shi'],
    'heels': ['штикли', 'штикла', 'heels', 'taka'],
    'wind': ['ветер', 'wind', 'erë', 'ere'],
    'bird': ['птица', 'птиче', 'bird', 'zog'],
    'water': ['вода', 'water', 'ujë', 'uje'],
    'glass': ['стакло', 'чаша', 'glass', 'xham', 'gotë'],
  };

  /// Тастатура: Enter / Space = запри, → = продолжи, P = пушти звук.
  bool _onKey(KeyEvent e) {
    if (!mounted || e is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      if (!_roundStarted) {
        _playTargetSound();
      } else {
        _stopBelt();
      }
      return true;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _resumeBelt();
      return true;
    }
    if (k == LogicalKeyboardKey.keyP) {
      _playTargetSound();
      return true;
    }
    return false;
  }
}