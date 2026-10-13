import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/widgets/echo_puzzle_art.dart';
import 'package:flutter/scheduler.dart';

/// Колку пати е поголем текстот на екранот за меморија на звуци.
const double _kSmemText = 1.6;

/// Меморија на звуци - „Ехо сложувалка“: 10 рунди со 6, 12 или 18 делчиња
/// од сложувалка (3, 6 или 9 пара исти звуци). При старт делчињата се
/// отвораат едно по едно (звук + сликичка). Потоа детето бара парови:
///  * ехо - кога ќе отвори делче, неговиот пар тивко одговара (од неговата
///    страна во стерео) и трепери; ехото слабее низ рундите;
///  * топло-ладно - со лизгање на прстот срцето чука побрзо кон парот;
///  * пронајден пар - делчињата се вклопуваат (јазиче во вдлабнатина) и
///    во „заспаната градина“ оживува тој поим; на крајот - мал концерт;
///  * „жива сложувалка“ - во последните две рунди преостанатите делчиња
///    се преместуваат по секој пар.
class SoundMemoryScreen extends StatefulWidget {
  const SoundMemoryScreen({super.key});

  @override
  State<SoundMemoryScreen> createState() => _SoundMemoryScreenState();
}

class _SoundMemoryScreenState extends State<SoundMemoryScreen> with SingleTickerProviderStateMixin {
  static const Color _moduleAccent = Color(0xFFDB2777);

  /// Број на парови во рундата [round] (од 0): по две рунди 6 картички,
  /// две по 12, две по 6, две по 12, а последните две рунди 18 картички.
  static int _pairsForRound(int round) {
    if (round >= _totalRounds - 2) return 9; // 18 картички
    return (round ~/ 2) % 2 == 0 ? 3 : 6; // 6 или 12 картички
  }

  /// Парови на ТЕКОВНОТО поле (не според _round - тој се зголемува малку
  /// пред да се изгради новото поле).
  int get _pairCount => _cardSound.length ~/ 2;

  late VoiceAssistantService _voiceAssistant;
  /// Одделен плеер за говорни клипови (објаснување, пар/не е пар, победа).
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за звуците на предметите/животните на картичките.
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final Random _random = Random();

  // Ист пул звуци како кај Идентификација на звук.
  static const List<String> _allSoundIds = [
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

  List<String> _cardSound = [];
  List<bool> _cardRevealed = [];
  List<bool> _cardMatched = [];

  /// Обликот на секое делче (рабови) и дали е „левото“ од парот.
  List<PuzzleEdges> _edges = [];
  List<bool> _isLeft = [];
  List<bool> _squareTabs = [];

  /// На кое место (во мрежата) стои секое делче - се менува кај „живата
  /// сложувалка“.
  List<int> _slot = [];

  /// Делчиња што се спојуваат: целна позиција (горен лев агол) во полето.
  final Map<int, Offset> _joinAt = {};

  /// Споени и „одлетани“ во градината.
  final Set<int> _gone = {};
  final Set<int> _wrong = {};

  /// Разбудените поими во градината и кој „пее“ (концерт).
  final Set<String> _awake = {};
  String? _bounce;

  bool _demoPlaying = false;
  bool _started = false;
  bool _inputLocked = false;
  int? _firstIndex;
  int _moves = 0;
  int _round = 0;
  static const int _totalRounds = 10;
  bool _gameOver = false;
  bool _explanationOpen = false;
  bool _shuffling = false;

  // Ехо и топло-ладно.
  final AudioPlayer _echoPlayer = AudioPlayer();
  final AudioPlayer _beatPlayer = AudioPlayer();
  int? _echoIndex;
  double _echoStart = 0;
  Timer? _beatTimer;
  bool _beatOn = false;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _clock = 0;

  /// Геометрија на полето (од последниот build) - за топло-ладно.
  List<Rect> _slotRects = [];

  String get _langCode => context.locale.languageCode;
  bool get _reduce => Playful.reduceMotion(context);

  /// „Жива сложувалка“ во последните две рунди.
  bool get _living => _round >= _totalRounds - 2;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
      _lastTick = elapsed;
      if (!mounted) return;
      setState(() => _clock += dt);
    })..start();
    _setupRoundBoard();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _ticker.dispose();
    _beatTimer?.cancel();
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _echoPlayer.dispose();
    _beatPlayer.dispose();
    super.dispose();
  }

  /// Ново поле делчиња за ЕДНА рунда - бројот на парови зависи од рундата
  /// (3, 6 или 9). Секој пар има РАЗЛИЧЕН звук и свој облик.
  void _setupRoundBoard() {
    final pairs = _pairsForRound(_round);
    final previous = _cardSound.toSet();
    final fresh = _allSoundIds.where((s) => !previous.contains(s)).toList()..shuffle(_random);
    final used = _allSoundIds.where(previous.contains).toList()..shuffle(_random);
    final pool = [...fresh, ...used];
    final chosen = <String>[for (var i = 0; i < pairs; i++) pool[i % pool.length]];
    final sounds = <String>[];
    final edges = <PuzzleEdges>[];
    final left = <bool>[];
    final square = <bool>[];
    // Сите делчиња имаат ИСТ облик (јазиче десно, вдлабнатина лево) - обликот
    // не открива кој е парот, а секои две делчиња сепак се вклопуваат.
    const uniform = PuzzleEdges(1, 1, -1, -1);
    for (var p = 0; p < pairs; p++) {
      sounds..add(chosen[p])..add(chosen[p]);
      edges..add(uniform)..add(uniform);
      left..add(true)..add(false);
      square..add(false)..add(false);
    }
    final slots = List<int>.generate(sounds.length, (i) => i)..shuffle(_random);
    _stopBeat();
    setState(() {
      _cardSound = sounds;
      _edges = edges;
      _isLeft = left;
      _squareTabs = square;
      _slot = slots;
      _cardRevealed = List.filled(sounds.length, false);
      _cardMatched = List.filled(sounds.length, false);
      _joinAt.clear();
      _gone.clear();
      _wrong.clear();
      _awake.clear();
      _bounce = null;
      _demoPlaying = false;
      _started = false;
      _inputLocked = false;
      _firstIndex = null;
      _echoIndex = null;
    });
  }

  /// Целосен нов почеток на играта (првата рунда, потезите на нула).
  void _restartGame() {
    setState(() {
      _round = 0;
      _moves = 0;
      _gameOver = false;
    });
    _setupRoundBoard();
  }

  int _partnerOf(int i) {
    for (var j = 0; j < _cardSound.length; j++) {
      if (j != i && _cardSound[j] == _cardSound[i]) return j;
    }
    return i;
  }

  /// Пробува однапред снимена звучна датотека (твоја снимка, по јазик), а
  /// само ако не постои паѓа назад на системскиот text-to-speech.
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/sound_memory/$_langCode/$key.mp3';
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

  Future<void> _playSound(String soundId, {double volume = 1, double balance = 0, AudioPlayer? player}) async {
    final path = _soundAssets[soundId];
    if (path == null) return;
    final relative = path.startsWith('assets/') ? path.substring(7) : path;
    final pl = player ?? _effectsPlayer;
    try {
      await pl.stop();
    } catch (_) {}
    // Секое подесување посебно: ако некое не е поддржано (пр. стерео на
    // веб), звукот сепак мора да се пушти.
    try {
      await pl.setVolume(volume);
    } catch (_) {}
    try {
      await pl.setBalance(balance);
    } catch (_) {}
    try {
      await pl.play(AssetSource(relative));
    } catch (_) {}
  }

  Future<void> _playFx(String asset) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.setVolume(1);
    } catch (_) {}
    try {
      await _effectsPlayer.setBalance(0);
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource(asset));
    } catch (_) {}
  }

  Future<void> _startDemo() async {
    setState(() {
      _demoPlaying = true;
      _started = false;
    });

    final order = List<int>.generate(_cardSound.length, (i) => i)..shuffle(_random);
    // Секое делче е отворено 2 секунди, во секоја рунда.
    const showMs = 2000;
    for (final idx in order) {
      if (!mounted || _explanationOpen) {
        if (mounted) setState(() => _demoPlaying = false);
        return;
      }
      setState(() => _cardRevealed[idx] = true);
      await _playSound(_cardSound[idx]);
      unawaited(VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(duration: 40);
      }));
      await Future.delayed(const Duration(milliseconds: showMs));
      if (!mounted) return;
      setState(() => _cardRevealed[idx] = false);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;
    setState(() {
      _demoPlaying = false;
      _started = true;
    });
  }

  void _stopBeat() {
    _beatOn = false;
    _beatTimer?.cancel();
    _beatTimer = null;
    try {
      _beatPlayer.stop();
    } catch (_) {}
  }

  Future<void> _onCardTap(int index) async {
    if (_demoPlaying || !_started || _gameOver || _inputLocked || _shuffling) return;
    if (_cardMatched[index] || _cardRevealed[index]) return;

    setState(() {
      _cardRevealed[index] = true;
      _moves++;
      _echoIndex = null;
    });
    await _playSound(_cardSound[index]);
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 40);
    }));

    if (_firstIndex == null) {
      _firstIndex = index;
      return;
    }

    final first = _firstIndex!;
    _firstIndex = null;
    _stopBeat();
    setState(() {
      _inputLocked = true;
      _echoIndex = null;
    });

    final isMatch = _cardSound[first] == _cardSound[index];
    if (isMatch) {
      await _joinPair(first, index);
      if (!mounted) return;
      if (_cardMatched.every((m) => m)) {
        await _onRoundComplete();
      } else {
        if (_living && !_reduce) await _shuffleSome();
        if (mounted) setState(() => _inputLocked = false);
      }
    } else {
      setState(() => _wrong..add(first)..add(index));
      unawaited(VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }));
      // Нежно „одбивање“ - без казна.
      await _playFx('sounds/sound_memory/puzzle_bounce.mp3');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _wrong.clear();
        _cardRevealed[first] = false;
        _cardRevealed[index] = false;
        _inputLocked = false;
      });
    }
  }

  /// Пронајден пар: делчињата летаат едно кон друго и се вклопуваат
  /// (јазиче во вдлабнатина), „клик“, па одлетуваат во градината.
  Future<void> _joinPair(int a, int b) async {
    final left = _isLeft[a] ? a : b;
    final right = left == a ? b : a;
    setState(() {
      _cardMatched[a] = true;
      _cardMatched[b] = true;
    });
    if (_slotRects.isNotEmpty) {
      final ra = _slotRects[_slot[left]], rb = _slotRects[_slot[right]];
      final mid = Offset((ra.center.dx + rb.center.dx) / 2, (ra.center.dy + rb.center.dy) / 2);
      final w = ra.width, h = ra.height;
      final tab = min(w, h) * 0.2;
      setState(() {
        // Десниот раб на телото на левото = левиот раб на телото на десното.
        _joinAt[left] = Offset(mid.dx - (w - tab), mid.dy - h / 2);
        _joinAt[right] = Offset(mid.dx - tab, mid.dy - h / 2);
      });
    }
    await Future.delayed(Duration(milliseconds: _reduce ? 100 : 520));
    if (!mounted) return;
    unawaited(_playFx('sounds/sound_memory/puzzle_snap.mp3'));
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(pattern: const [0, 60, 50, 180]);
    }));
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    // Одлетуваат во градината - таму оживува поимот.
    setState(() {
      _gone..add(a)..add(b);
      _awake.add(_cardSound[a]);
    });
    // Звукот на парот (посебен плеер - не го прекинува „кликот“).
    await _playSound(_cardSound[a], player: _echoPlayer);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// „Жива сложувалка“: неколку преостанати делчиња си ги менуваат местата.
  Future<void> _shuffleSome() async {
    final rest = [for (var i = 0; i < _cardSound.length; i++) if (!_cardMatched[i]) i]..shuffle(_random);
    if (rest.length < 4) return;
    setState(() => _shuffling = true);
    final swaps = min(2, rest.length ~/ 2);
    setState(() {
      for (var k = 0; k < swaps; k++) {
        final x = rest[2 * k], y = rest[2 * k + 1];
        final t = _slot[x];
        _slot[x] = _slot[y];
        _slot[y] = t;
      }
    });
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(pattern: const [0, 40, 60, 40, 60, 40]);
    }));
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) setState(() => _shuffling = false);
  }

  /// Сите парови се пронајдени: мал концерт во градината, па нова рунда
  /// или крај на играта.
  Future<void> _onRoundComplete() async {
    unawaited(VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 350);
    }));
    // Градината е будна - кратка пауза (без повторно пуштање на звуците).
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final newRound = _round + 1;
    if (newRound >= _totalRounds) {
      setState(() {
        _round = newRound;
        _gameOver = true;
      });
      await _playClip('win', 'sound_memory.win'.tr(args: [_moves.toString()]));
    } else {
      setState(() => _round = newRound);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      _setupRoundBoard();
    }
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _stopBeat();
      _playClip('explanation', 'sound_memory.explanation_text'.tr());
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.sound_memory'.tr(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['🧩', '🎵', '🌙', '🌱', '🔔', '✨'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 760) / 2).clamp(16.0, double.infinity);
            final width = constraints.maxWidth - side * 2;
            final header = <Widget>[
              PlayfulExplainButton(
                open: _explanationOpen,
                label: _explanationOpen
                    ? 'sound_memory.explanation_toggle_close'.tr()
                    : 'sound_memory.explanation_toggle_open'.tr(),
                onTap: _toggleExplanation,
              ),
              if (_explanationOpen)
                PlayfulExplainPanel(
                  icon: Icons.extension_rounded,
                  title: 'sound_memory.explanation_title'.tr(),
                  text: 'sound_memory.explanation_text'.tr(),
                  accent: _moduleAccent,
                ),
              const SizedBox(height: 16),
            ];

            if (_gameOver) {
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
                            'sound_memory.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26 * _kSmemText, color: fg),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: PlayfulResult(
                      text: 'sound_memory.win'.tr(args: [_moves.toString()]),
                      buttonLabel: 'sound_memory.play_again'.tr(),
                      onAgain: _restartGame,
                    ),
                  ),
                ],
              );
            }

            final pairs = _pairCount;
            final gardenH = (width * 0.42).clamp(150.0, 240.0).toDouble();
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 12, side, 28),
              children: [
                ...header,
                RoundProgress(
                  label: 'sound_memory.rounds_progress'.tr(args: [
                    (_round + 1).toString(),
                    _totalRounds.toString(),
                  ]),
                  current: _round,
                  total: _totalRounds,
                  extra: 'sound_memory.moves'.tr(args: [_moves.toString()]),
                ),
                const SizedBox(height: 12),
                // „Заспаната градина“ - се буди со секој пар.
                Semantics(
                  label: 'sound_memory.garden_awake'.tr(args: [_awake.length.toString(), pairs.toString()]),
                  child: ExcludeSemantics(
                    child: Container(
                      height: gardenH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: hc ? Colors.white : Playful.sun.withValues(alpha: 0.85), width: 3),
                        boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.35), blurRadius: 18)],
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GardenScene(
                              awake: _awake,
                              progress: pairs == 0 ? 0 : _awake.length / pairs,
                              t: _clock,
                              bounce: _bounce,
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _awake.length == pairs && pairs > 0
                                    ? 'sound_memory.garden_done'.tr()
                                    : 'sound_memory.garden_awake'.tr(args: [_awake.length.toString(), pairs.toString()]),
                                style: Playful.title(14 * 1.3, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (!_started)
                  Center(
                    child: SoundOrb(
                      icon: Icons.extension_rounded,
                      label: 'sound_memory.start_button'.tr(),
                      onTap: _demoPlaying ? null : _startDemo,
                      active: _demoPlaying,
                      size: 112,
                    ),
                  )
                else
                  PlayfulHint((_living ? 'sound_memory.living_hint' : 'sound_memory.pairs_hint').tr()),
                const SizedBox(height: 14),
                _buildBoard(width, constraints.maxHeight),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Распоред според бројот на делчиња:
  ///  6 -> 3x2;  12 -> 3x4 (телефон) или 4x3;  18 -> 3x6 (телефон) или 6x3.
  Widget _buildBoard(double width, double height) {
    final count = _cardSound.length;
    const spacing = 2.0;
    double cardW(int cols) => (width - spacing * (cols - 1)) / cols;
    var columns = 3;
    if (count > 6) {
      final wide = count <= 12 ? 4 : 6;
      final shortScreen = width >= 480 && height.isFinite && height < 520;
      if (cardW(wide) >= 110 || (shortScreen && cardW(wide) >= 80)) columns = wide;
    }
    final w = cardW(columns);
    final h = w * 0.92;
    final rows = (count / columns).ceil();
    _slotRects = [
      for (var s = 0; s < count; s++) Rect.fromLTWH((s % columns) * (w + spacing), (s ~/ columns) * (h + spacing), w, h),
    ];
    final boardH = rows * h + (rows - 1) * spacing;
    final reduce = _reduce;
    return SizedBox(
      child: SizedBox(
        width: width,
        height: boardH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < count; i++) _piece(i, w, h, reduce),
          ],
        ),
      ),
    );
  }

  Widget _piece(int i, double w, double h, bool reduce) {
    final slotRect = _slotRects[_slot[i]];
    final join = _joinAt[i];
    final pos = join ?? slotRect.topLeft;
    final gone = _gone.contains(i);
    final open = _cardRevealed[i] || _cardMatched[i];
    final id = _cardSound[i];
    final interactive = _started && !_demoPlaying && !_gameOver && !_inputLocked && !_shuffling;
    final gameActive = _started || _demoPlaying;
    final echo = _echoIndex == i ? ((_clock - _echoStart) * 0.9) % 1.0 : 0.0;
    final echoOn = _echoIndex == i && _clock - _echoStart < 1.8;
    final shake = _wrong.contains(i) && !reduce ? sin(_clock * 40) * 5 : 0.0;
    final cols = max(1, _slotRects.where((r) => r.top == _slotRects.first.top).length);
    final row = _slot[i] ~/ cols + 1;
    final col = _slot[i] % cols + 1;
    return AnimatedPositioned(
      key: ValueKey('piece-$i-${_round}'),
      duration: Duration(milliseconds: reduce ? 0 : (join != null ? 480 : 900)),
      curve: join != null ? Curves.easeOutBack : Curves.easeInOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: w,
      height: h,
      child: IgnorePointer(
        ignoring: gone,
        child: AnimatedOpacity(
          duration: Duration(milliseconds: reduce ? 0 : 450),
          opacity: gone ? 0 : (gameActive ? 1 : 0.4),
          child: AnimatedScale(
            duration: Duration(milliseconds: reduce ? 0 : 450),
            scale: gone ? 0.3 : 1,
            child: Semantics(
              button: interactive && !open,
              label: open
                  ? 'sound.name_$id'.tr()
                  : '${'sound_memory.card_closed'.tr()}, $row/$col',
              onTap: interactive && !open ? () => _onCardTap(i) : null,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: interactive ? () => _onCardTap(i) : null,
                  child: Transform.translate(
                    // Погрешен пар - делчето малку се тресе.
                    offset: Offset(shake, 0),
                    child: reduce
                      ? _pieceFace(i, open, echoOn ? echo : 0)
                      : TweenAnimationBuilder<double>(
                          // Превртување при отворање/затворање.
                          tween: Tween(end: open ? 1 : 0),
                          duration: const Duration(milliseconds: 360),
                          builder: (context, v, _) {
                            final angle = (1 - (v - 0.5).abs() * 2) * (pi / 2);
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0012)
                                ..rotateY(angle * 0.98),
                              child: _pieceFace(i, v >= 0.5, echoOn ? echo : 0),
                            );
                          },
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pieceFace(int i, bool open, double echo) {
    final id = _cardSound[i];
    return PuzzlePiece(
      edges: _edges[i],
      square: _squareTabs[i],
      open: open,
      emoji: _soundEmojis[id]!,
      label: 'sound.name_$id'.tr(),
      color: _soundColors[id] ?? _moduleAccent,
      accent: _moduleAccent,
      matched: _cardMatched[i],
      wrong: _wrong.contains(i),
      echo: echo,
    );
  }
}