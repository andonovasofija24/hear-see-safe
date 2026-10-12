import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/scheduler.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/widgets/sound_ear_art.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';

/// Колку пати е поголем текстот на екранот за мелодиска меморија.
const double _kMelText = 1.6;

/// Мемorија на звуци: детето слуша НИЗА звуци по ред (пр. мачка, мачка,
/// куче, автомобил) - никогаш автоматски, само по притискање на Почни да
/// слушаш. Картичките од низата одат по свитканата лента кон увото и пред
/// да влезат секоја го пушта својот звук. Потоа детето ја наредува низата
/// во полето: со допир на картичките или со глас (ги кажува имињата по
/// ред и полето само се пополнува), па „Потврди“.
/// Должината на низата расте од 2 до 7 звуци низ 20-те вкупни рунди. На
/// крајот се прикажува колку рунди се погодени, а колку промашени.
class MelodyMemoryScreen extends StatefulWidget {
  const MelodyMemoryScreen({super.key});

  @override
  State<MelodyMemoryScreen> createState() => _MelodyMemoryScreenState();
}

class _MelodyMemoryScreenState extends State<MelodyMemoryScreen> with SingleTickerProviderStateMixin {
  static const Color _moduleAccent = Color(0xFF9333EA);
  static const int _totalRounds = 20;

  late VoiceAssistantService _voiceAssistant;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Random _random = Random();

  static const List<String> _soundIds = ['cat', 'dog', 'car', 'rain'];

  static const Map<String, String> _soundAssets = {
    'cat': 'assets/sounds/sound_identification/meow.mp3',
    'dog': 'assets/sounds/sound_identification/bark.mp3',
    'car': 'assets/sounds/sound_identification/car.mp3',
    'rain': 'assets/sounds/sound_identification/rain.mp3',
  };

  static const Map<String, IconData> _soundIcons = {
    'cat': Icons.pets_rounded,
    'dog': Icons.cruelty_free_rounded,
    'car': Icons.directions_car_filled_rounded,
    'rain': Icons.water_drop_rounded,
  };

  static const Map<String, String> _soundLabelKeys = {
    'cat': 'melody.sound1',
    'dog': 'melody.sound2',
    'car': 'melody.sound3',
    'rain': 'melody.sound4',
  };

  static const Map<String, String> _soundEmojis = {
    'cat': '🐱',
    'dog': '🐶',
    'car': '🚗',
    'rain': '🌧️',
  };

  /// Зборови за гласовното наредување (сите јазици).
  static const Map<String, List<String>> _voiceNames = {
    'cat': ['мачка', 'маче', 'мачката', 'cat', 'kitty', 'mace', 'macja', 'maçe'],
    'dog': ['куче', 'кучето', 'dog', 'puppy', 'qen', 'qeni'],
    'car': ['автомобил', 'кола', 'колата', 'car', 'auto', 'makina', 'makinë', 'veturë', 'veture'],
    'rain': ['дожд', 'дождот', 'rain', 'shi', 'shiu'],
  };

  static const Map<String, Color> _soundColors = {
    'cat': Color(0xFF9333EA),
    'dog': Color(0xFFD97706),
    'car': Color(0xFF2563EB),
    'rain': Color(0xFF0D9488),
  };

  /// Должина на низата по рунда: 2,3,4,5,6,7, па се повторува пак од 2 - за
  /// вкупно 20 рунди.
  late final List<int> _lengthPerRound =
      List.generate(_totalRounds, (i) => 2 + (i % 6));

  List<String> _sequence = [];
  int _userIndex = 0;
  bool _revealed = false;
  bool _isPlaying = false;
  String? _flashingId;
  int _round = 0;
  int _hits = 0;
  bool _gameOver = false;
  bool _explanationOpen = false;

  /// Рундата е одговорена (точно или погрешно) и се чека преминот кон
  /// следната. Блокира секој дополнителен допир/копче до `_prepareRound`.
  bool _answered = false;

  // ---------------------------------------------------------------------
  // Лентата до увото (слушање на низата).
  // ---------------------------------------------------------------------

  static const double _gate = 0.74;
  static const double _speed = 0.16;

  /// Растојание меѓу картичките на лентата (во делови од патеката).
  static const double _gap = 0.26;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _clock = 0;

  /// Каде е првата картичка (останатите се [_gap] зад неа).
  double _beltT = 0;
  bool _moving = false;
  int? _gateIndex;
  bool _gateSounding = false;
  EarBeltGeometry? _geo;

  /// Полето: што наредило детето (по ред).
  final List<String> _placed = [];

  /// По проверката: за секое место дали е точно.
  List<bool>? _checked;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _ticker = createTicker(_onTick)..start();
    _prepareRound();
  }

  bool get _reduce => Playful.reduceMotion(context);

  double _sOf(int k, [double? t]) => (t ?? _beltT) - k * _gap;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    if (!mounted) return;
    _clock += dt;
    if (!_moving || _reduce) {
      if (_gateSounding) setState(() {});
      return;
    }
    final next = _beltT + dt * _speed;
    for (var k = 0; k < _sequence.length; k++) {
      final a = _sOf(k), b = _sOf(k, next);
      if (a < _gate && b >= _gate) {
        setState(() => _beltT = _gate + k * _gap);
        _arriveAtGate(k);
        return;
      }
    }
    setState(() => _beltT = next);
    // Последната картичка влезе во увото - крај на слушањето.
    if (_sOf(_sequence.length - 1) >= 1.0) _finishListening();
  }

  /// Без анимации: скок од картичка до картичка пред увото.
  void _jumpNext() {
    for (var k = 0; k < _sequence.length; k++) {
      if (_sOf(k) < _gate - 1e-6) {
        setState(() => _beltT = _gate + k * _gap);
        _arriveAtGate(k);
        return;
      }
    }
    setState(() => _beltT = 1.0 + (_sequence.length - 1) * _gap);
    _finishListening();
  }

  /// Картичката [k] пред увото: застанува, го пушта својот звук и влегува.
  Future<void> _arriveAtGate(int k) async {
    setState(() {
      _moving = false;
      _gateIndex = k;
      _gateSounding = true;
      _flashingId = _sequence[k];
    });
    final done = Completer<void>();
    final sub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await _playSoundEffect(_sequence[k]);
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 50);
    }));
    await Future.any([
      done.future,
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    await sub.cancel();
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted || _gateIndex != k || !_isPlaying) return;
    setState(() {
      _gateSounding = false;
      _gateIndex = null;
      _flashingId = null;
      _moving = true;
    });
    if (_reduce) _jumpNext();
  }

  void _finishListening() {
    if (!_isPlaying) return;
    setState(() {
      _moving = false;
      _isPlaying = false;
      _gateIndex = null;
      _flashingId = null;
    });
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _ticker.dispose();
    _voiceAssistant.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _prepareRound() {
    final length = _lengthPerRound[_round];
    setState(() {
      _sequence = List.generate(length, (_) => _soundIds[_random.nextInt(_soundIds.length)]);
      _userIndex = 0;
      _revealed = false;
      _isPlaying = false;
      _answered = false;
      _flashingId = null;
      _moving = false;
      _gateIndex = null;
      _gateSounding = false;
      _beltT = 0;
      _placed.clear();
      _checked = null;
    });
  }

  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/melody_memory/$_langCode/$key.mp3';
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

  Future<void> _playSoundEffect(String id) async {
    final path = _soundAssets[id];
    if (path == null) return;
    try {
      final relative = path.startsWith('assets/') ? path.substring(7) : path;
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(relative));
    } catch (_) {}
  }

  /// „Почни да слушаш“ / „Слушни повторно“: картичките од низата тргнуваат
  /// по лентата кон увото (наредувањето во полето останува).
  Future<void> _playSequence() async {
    if (_isPlaying || _answered || _gameOver || _explanationOpen) return;
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = true;
      _revealed = true;
      _beltT = 0;
      _gateIndex = null;
      _gateSounding = false;
      _moving = true;
    });
    if (_reduce) _jumpNext();
  }

  /// Допир на картичка од изборот: оди на следното празно место во полето.
  Future<void> _placeCard(String id) async {
    if (_isPlaying || !_revealed || _gameOver || _answered) return;
    if (_placed.length >= _sequence.length) return;
    setState(() {
      _placed.add(id);
      _flashingId = id;
    });
    await _playSoundEffect(id);
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 50);
    }));
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted && _flashingId == id) setState(() => _flashingId = null);
  }

  /// Допир на место во полето: ја вади картичката (останатите се поместуваат).
  void _removeAt(int i) {
    if (_answered || i >= _placed.length) return;
    setState(() => _placed.removeAt(i));
  }

  void _undo() {
    if (_answered || _placed.isEmpty) return;
    setState(() => _placed.removeLast());
  }

  void _clearPlaced() {
    if (_answered) return;
    setState(_placed.clear);
  }

  /// Гласовно наредување: „мачка куче мачка дожд“ -> полето се пополнува
  /// по редот на зборовите.
  bool _voiceFill(String transcript) {
    if (_isPlaying || !_revealed || _answered || _gameOver) return false;
    final words = transcript.toLowerCase().split(RegExp(r'[\s,.!?;:]+')).where((w) => w.isNotEmpty);
    final found = <String>[];
    for (final w in words) {
      for (final e in _voiceNames.entries) {
        if (e.value.any((n) => w == n || (n.length >= 4 && w.startsWith(n)))) {
          found.add(e.key);
          break;
        }
      }
    }
    if (found.isEmpty) return false;
    _pendingVoice = found;
    return true;
  }

  List<String>? _pendingVoice;

  Future<void> _applyVoice() async {
    final ids = _pendingVoice;
    _pendingVoice = null;
    if (ids == null) return;
    for (final id in ids) {
      if (_placed.length >= _sequence.length) break;
      await _placeCard(id);
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  /// „Потврди“: проверка на полето.
  Future<void> _confirm() async {
    if (_isPlaying || !_revealed || _gameOver || _answered) return;
    if (_placed.length < _sequence.length) {
      unawaited(VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(pattern: const [0, 80, 60, 80]);
      }));
      return;
    }
    final roundAtTap = _round;
    final marks = [for (var i = 0; i < _sequence.length; i++) _placed[i] == _sequence[i]];
    final ok = marks.every((m) => m);
    setState(() {
      _checked = marks;
      _answered = true;
      _userIndex = marks.where((m) => m).length;
      if (ok) _hits++;
    });
    unawaited(VibrationUtils.hasVibrator().then((has) {
      if (has) VibrationUtils.vibrate(pattern: ok ? const [0, 200] : const [0, 120, 100, 120]);
    }));
    await _playClip(ok ? 'correct' : 'incorrect', (ok ? 'melody.correct' : 'melody.incorrect').tr());
    // Погрешно: подолго, за да се види точната низа.
    await Future.delayed(Duration(milliseconds: ok ? 900 : 2600));
    if (!mounted) return;
    _advanceFrom(roundAtTap);
  }

  /// Единствено место каде што `_round` се зголемува: точно еднаш по
  /// одговорена рунда (точно или погрешно). Ако рундата веќе е сменета
  /// (пр. рестарт во меѓувреме), повикот се игнорира.
  void _advanceFrom(int answeredRound) {
    if (!_answered || _round != answeredRound || _gameOver) return;
    final newRound = _round + 1;
    if (newRound >= _totalRounds) {
      setState(() {
        _round = _totalRounds - 1;
        _gameOver = true;
        _answered = false;
      });
    } else {
      setState(() => _round = newRound);
      _prepareRound();
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _hits = 0;
      _gameOver = false;
    });
    _prepareRound();
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    if (opening && _isPlaying) {
      // Објаснувањето го прекинува слушањето - лентата запира.
      _moving = false;
      _isPlaying = false;
      _gateIndex = null;
      _gateSounding = false;
      _flashingId = null;
    }
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation', 'melody.explanation_text'.tr());
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
      _voiceAssistant.stop();
      _audioPlayer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.melody_memory'.tr(),
      voiceOptions: _voiceOptions(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['🎹', '🎵', '🎶', '🐱', '🐶', '🌧️'],
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
                    ? 'melody.explanation_toggle_close'.tr()
                    : 'melody.explanation_toggle_open'.tr(),
                onTap: _toggleExplanation,
              ),
              if (_explanationOpen)
                PlayfulExplainPanel(
                  icon: Icons.volume_up_rounded,
                  title: 'melody.explanation_title'.tr(),
                  text: 'melody.explanation_text'.tr(),
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
                            'melody.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26 * _kMelText, color: fg),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: PlayfulResult(
                      text: 'melody.final_summary'.tr(args: [
                        _hits.toString(),
                        misses.toString(),
                        _totalRounds.toString(),
                      ]),
                      buttonLabel: 'melody.play_again'.tr(),
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
                  label: 'melody.rounds_progress'.tr(args: [
                    (_round + 1).toString(),
                    _totalRounds.toString(),
                  ]),
                  current: _round,
                  total: _totalRounds,
                  extra: 'melody.score'.tr(args: [_hits.toString()]),
                ),
                const SizedBox(height: 14),
                // Лентата до увото - по неа доаѓа низата.
                _buildBelt(constraints.maxWidth - side * 2, hc),
                const SizedBox(height: 14),
                if (!_revealed || _isPlaying)
                  PlayfulHint((_isPlaying ? 'melody.belt_listen_hint' : 'melody.belt_start_hint').tr())
                else
                  _buildArrangeField(constraints.maxWidth - side * 2, hc),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Лентата до увото.
  // ---------------------------------------------------------------------

  Widget _buildBelt(double width, bool hc) {
    final h = (width * (width < 600 ? 0.9 : 0.56)).clamp(300.0, 480.0).toDouble();
    final size = Size(width, h);
    var geo = _geo;
    if (geo == null || geo.size != size) {
      geo = EarBeltGeometry(size, cards: 6);
      _geo = geo;
    }
    final n = _sequence.length;
    final order = [
      for (var k = 0; k < n; k++)
        if (_isPlaying && _sOf(k) >= 0 && _sOf(k) < 0.985) (k, _sOf(k)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final Color? glow = _checked == null ? null : (_checked!.every((m) => m) ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: EarBeltPainter(geo: geo, offset: _beltT, color: _moduleAccent, hc: hc, gate: _gate),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: EarBackPainter(geo: geo, hc: hc, pulse: _gateSounding && !_reduce ? (_clock * 0.9) % 1.0 : 0, glow: glow),
              ),
            ),
          ),
          // Копчето за слушање - во средината на полукругот.
          Positioned(
            left: geo.orbCenter.dx - geo.orbSize / 2 - 20,
            top: geo.orbCenter.dy - geo.orbSize / 2,
            width: geo.orbSize + 40,
            child: SoundOrb(
              icon: _revealed ? Icons.replay_rounded : Icons.play_arrow_rounded,
              label: (_revealed ? 'melody.listen_again' : 'melody.start_listening').tr(),
              onTap: (_isPlaying || _answered) ? null : _playSequence,
              active: _isPlaying,
              size: geo.orbSize,
            ),
          ),
          for (final (k, s) in order) _beltCard(k, s, geo, hc),
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: EarFrontPainter(geo: geo, hc: hc))),
          ),
          // Колку звуци има низата - бројач горе десно.
          Positioned(
            right: 4,
            top: 0,
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: hc ? Colors.white : Playful.sun, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note_rounded, size: 22, color: hc ? Colors.white : Playful.sun),
                    const SizedBox(width: 4),
                    Text('× ${_sequence.length}', style: Playful.title(18, color: hc ? Colors.white : Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _beltCard(int k, double s, EarBeltGeometry geo, bool hc) {
    final id = _sequence[k];
    final size = geo.cardAt(s);
    final p = geo.pointAt(s);
    final fade = s > 0.9 ? ((0.985 - s) / 0.085).clamp(0.0, 1.0) : 1.0;
    final atGate = _gateIndex == k;
    return Positioned(
      key: ValueKey('mel-belt-$k'),
      left: p.dx - size / 2,
      top: p.dy - size * 0.575,
      width: size,
      height: size * 1.15,
      child: IgnorePointer(
        child: Opacity(
          opacity: fade,
          child: Transform.rotate(
            angle: geo.angleAt(s) * 0.12,
            child: AnimatedScale(
              scale: atGate ? 1.35 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: SoundCard(
                emoji: _soundEmojis[id]!,
                label: _soundLabelKeys[id]!.tr(),
                color: _soundColors[id]!,
                size: size,
                hc: hc,
                atGate: atGate,
                playing: atGate && _gateSounding,
                wave: (_clock * 1.2) % 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Полето за наредување.
  // ---------------------------------------------------------------------

  Widget _buildArrangeField(double width, bool hc) {
    final n = _sequence.length;
    final slot = ((width - 24 - (n - 1) * 8) / n).clamp(44.0, 96.0).toDouble();
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    final interactive = !_answered && !_gameOver;
    final pick = (width / 4 - 14).clamp(64.0, 120.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayfulHint('melody.arrange_prompt'.tr()),
        const SizedBox(height: 10),
        // Полето со местата 1..n.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: hc ? Colors.white : Playful.sun, width: 3),
            boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.4), blurRadius: 20)],
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < n; i++) _slot(i, slot, hc, interactive),
            ],
          ),
        ),
        // По погрешен одговор - точната низа (мала).
        if (_checked != null && !_checked!.every((m) => m)) ...[
          const SizedBox(height: 10),
          Semantics(
            label: '${'melody.right_order'.tr()} ${[for (final id in _sequence) _soundLabelKeys[id]!.tr()].join(', ')}',
            child: ExcludeSemantics(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text('melody.right_order'.tr(), style: Playful.title(15 * 1.4, color: fg)),
                  for (final id in _sequence) Text(_soundEmojis[id]!, style: const TextStyle(fontSize: 30)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        // Изборот: четирите картички.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final id in _soundIds)
              Semantics(
                button: true,
                enabled: interactive && _placed.length < n,
                label: _soundLabelKeys[id]!.tr(),
                onTap: () => _placeCard(id),
                child: ExcludeSemantics(
                  child: PressableScale(
                    enabled: interactive && _placed.length < n,
                    child: GestureDetector(
                      onTap: () => _placeCard(id),
                      child: AnimatedScale(
                        scale: _flashingId == id ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: SoundCard(
                          emoji: _soundEmojis[id]!,
                          label: _soundLabelKeys[id]!.tr(),
                          color: _soundColors[id]!,
                          size: pick,
                          hc: hc,
                          playing: _flashingId == id,
                          wave: (_clock * 1.2) % 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            _actionButton(Icons.undo_rounded, 'melody.undo'.tr(), const Color(0xFF64748B), interactive && _placed.isNotEmpty ? _undo : null, hc),
            _actionButton(Icons.delete_sweep_rounded, 'melody.clear'.tr(), const Color(0xFF64748B), interactive && _placed.isNotEmpty ? _clearPlaced : null, hc),
            _actionButton(Icons.check_rounded, 'melody.confirm'.tr(), const Color(0xFF16A34A), interactive && _placed.length == n ? _confirm : null, hc, big: true),
          ],
        ),
      ],
    );
  }

  Widget _slot(int i, double size, bool hc, bool interactive) {
    final id = i < _placed.length ? _placed[i] : null;
    final mark = _checked == null || i >= _checked!.length ? null : _checked![i];
    final label = id == null ? '${i + 1}' : '${i + 1}. ${_soundLabelKeys[id]!.tr()}';
    return Semantics(
      button: id != null && interactive,
      label: label,
      onTap: id != null && interactive ? () => _removeAt(i) : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: id != null && interactive ? () => _removeAt(i) : null,
          child: SizedBox(
            width: size,
            height: size * 1.15,
            child: id == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(size * 0.2),
                      color: Colors.white.withValues(alpha: hc ? 0 : 0.06),
                      border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.55), width: 2),
                    ),
                    child: Center(
                      child: Text('${i + 1}', style: Playful.display(size * 0.4, color: hc ? Colors.white : Colors.white.withValues(alpha: 0.6))),
                    ),
                  )
                : PopIn(
                    key: ValueKey('slot-$i-$id'),
                    startMs: 0,
                    child: SoundCard(
                      emoji: _soundEmojis[id]!,
                      label: _soundLabelKeys[id]!.tr(),
                      color: _soundColors[id]!,
                      size: size,
                      hc: hc,
                      state: mark,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback? onTap, bool hc, {bool big = false}) {
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
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Container(
                  constraints: BoxConstraints(minHeight: big ? 68 : 58),
                  padding: EdgeInsets.symmetric(horizontal: big ? 22 : 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: hc ? const Color(0xFFFFFF00) : Colors.white, width: big ? 4 : 2.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: big ? 34 : 28, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(label, style: Playful.title((big ? 17 : 15) * 1.4, color: Colors.white)),
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

  // ---------------------------------------------------------------------
  // Глас: имињата по ред (се пополнува полето), „потврди“, „врати“,
  // „избриши“, „слушај“.
  // ---------------------------------------------------------------------

  List<VoiceCategoryOption> _voiceOptions() {
    if (_gameOver) return const [];
    return [
      VoiceCategoryOption(
        keywords: const ['потврди', 'готово', 'confirm', 'done', 'check', 'konfirmo', 'gati'],
        beforeGlobal: true,
        onSelected: _confirm,
      ),
      VoiceCategoryOption(
        keywords: const ['врати', 'назад една', 'undo', 'kthe'],
        beforeGlobal: true,
        onSelected: _undo,
      ),
      VoiceCategoryOption(
        keywords: const ['избриши', 'исчисти', 'clear', 'erase', 'fshi', 'pastro'],
        beforeGlobal: true,
        onSelected: _clearPlaced,
      ),
      VoiceCategoryOption(
        keywords: const ['слушај', 'слушни', 'пушти', 'повтори', 'listen', 'play', 'again', 'dëgjo', 'degjo', 'luaj'],
        beforeGlobal: true,
        onSelected: _playSequence,
      ),
      VoiceCategoryOption(
        keywords: const [],
        beforeGlobal: true,
        matches: _voiceFill,
        onSelected: _applyVoice,
      ),
    ];
  }
}