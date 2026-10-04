import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

/// Меморија на звуци: 12 картички (6 пара исти звуци), сите почетно
/// затворени. При старт, системот ги отвора сите картички една по една
/// (случаен редослед) - секоја покажува икона + го пушта својот звук, па
/// повторно се затвора. Потоа детето допира по две картички за да ги
/// најде паровите. Секое отворање на картичка од страна на детето се
/// брои како потег.
class SoundMemoryScreen extends StatefulWidget {
  const SoundMemoryScreen({super.key});

  @override
  State<SoundMemoryScreen> createState() => _SoundMemoryScreenState();
}

class _SoundMemoryScreenState extends State<SoundMemoryScreen> {
  static const Color _moduleAccent = Color(0xFFDB2777);
  static const int _pairCount = 3; // 6 картички вкупно

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

  List<String> _cardSound = [];
  List<bool> _cardRevealed = [];
  List<bool> _cardMatched = [];
  bool _demoPlaying = false;
  bool _started = false;
  bool _inputLocked = false;
  int? _firstIndex;
  int _moves = 0;
  int _round = 0;
  static const int _totalRounds = 10;
  bool _gameOver = false;
  bool _explanationOpen = false;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _setupRoundBoard();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    super.dispose();
  }

  /// Ново поле картички за ЕДНА рунда - секоја рунда зема случајни 6 звуци
  /// (различни од претходната рунда кога е можно), но не го ресетира бројот
  /// на потези ниту тековната рунда.
  void _setupRoundBoard() {
    final pool = List<String>.from(_allSoundIds)..shuffle(_random);
    final chosen = pool.take(_pairCount).toList();
    final cards = [...chosen, ...chosen]..shuffle(_random);
    setState(() {
      _cardSound = cards;
      _cardRevealed = List.filled(_pairCount * 2, false);
      _cardMatched = List.filled(_pairCount * 2, false);
      _demoPlaying = false;
      _started = false;
      _inputLocked = false;
      _firstIndex = null;
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

  Future<void> _playSound(String soundId) async {
    final path = _soundAssets[soundId];
    if (path == null) return;
    final relative = path.startsWith('assets/') ? path.substring(7) : path;
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource(relative));
    } catch (_) {}
  }

  /// За "пар" се користи готовиот hit.mp3 звучен ефект од Гласовен Понг (не
  /// е говор, не зависи од јазик - не треба нова снимка).
  Future<void> _playHitSound() async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/hit.mp3'));
    } catch (_) {}
  }

  /// За "не е пар" се користи готовиот miss.mp3 звучен ефект од Гласовен
  /// Понг (не е говор, не зависи од јазик - не треба нова снимка).
  Future<void> _playMissSound() async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/miss.mp3'));
    } catch (_) {}
  }

  Future<void> _startDemo() async {
    setState(() {
      _demoPlaying = true;
      _started = false;
    });

    final order = List<int>.generate(_cardSound.length, (i) => i)..shuffle(_random);
    for (final idx in order) {
      if (!mounted) return;
      setState(() => _cardRevealed[idx] = true);
      await _playSound(_cardSound[idx]);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 40);
      }
      await Future.delayed(const Duration(milliseconds: 700));
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

  Future<void> _onCardTap(int index) async {
    if (_demoPlaying || !_started || _gameOver || _inputLocked) return;
    if (_cardMatched[index] || _cardRevealed[index]) return;

    setState(() {
      _cardRevealed[index] = true;
      _moves++;
    });
    await _playSound(_cardSound[index]);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 40);
    }

    if (_firstIndex == null) {
      _firstIndex = index;
      return;
    }

    final first = _firstIndex!;
    _firstIndex = null;
    setState(() => _inputLocked = true);

    final isMatch = _cardSound[first] == _cardSound[index];
    if (isMatch) {
      setState(() {
        _cardMatched[first] = true;
        _cardMatched[index] = true;
      });
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 200);
      }
      await _playHitSound();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _inputLocked = false);
      if (_cardMatched.every((m) => m)) {
        await _onRoundComplete();
      }
    } else {
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
      await _playMissSound();
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _cardRevealed[first] = false;
        _cardRevealed[index] = false;
        _inputLocked = false;
      });
    }
  }

  /// Сите 6 пара во оваа рунда се пронајдени. Ако имало уште рунди, се
  /// подготвува ново поле со различни (случајно избрани) звуци. Инаку
  /// играта завршува со вкупниот број потези од сите рунди.
  Future<void> _onRoundComplete() async {
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 350);
    }
    final newRound = _round + 1;
    if (newRound >= _totalRounds) {
      setState(() {
        _round = newRound;
        _gameOver = true;
      });
      await _playClip('win', 'sound_memory.win'.tr(args: [_moves.toString()]));
    } else {
      setState(() => _round = newRound);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      _setupRoundBoard();
    }
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
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
        emojis: ['🧠', '🃏', '🎵', '🔔', '🐶', '🐦'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 760) / 2).clamp(16.0, double.infinity);
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
                  icon: Icons.psychology_rounded,
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
                            style: Playful.display(26, color: fg),
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

            final matchedPairs = _cardMatched.where((m) => m).length ~/ 2;
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
                const SizedBox(height: 14),
                _buildPairDots(matchedPairs, hc),
                const SizedBox(height: 18),
                // Картичките се СЕКОГАШ видливи (затворени, затемнети,
                // недостапни за допир) - копчето старт стои над нив.
                Center(
                  child: SoundOrb(
                    icon: Icons.grid_view_rounded,
                    label: 'sound_memory.start_button'.tr(),
                    onTap: _demoPlaying ? null : _startDemo,
                    active: _demoPlaying,
                    size: 112,
                  ),
                ),
                const SizedBox(height: 20),
                _buildBoard(constraints.maxWidth - side * 2),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Колку парови се пронајдени во рундата (срца што се палат).
  Widget _buildPairDots(int matched, bool hc) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _pairCount; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                scale: i < matched ? 1.15 : 1.0,
                child: Icon(
                  i < matched ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 32,
                  color: i < matched
                      ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
                      : (hc ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard(double width) {
    return PlayfulGrid(
      columns: 3,
      spacing: 14,
      aspectRatio: width < 420 ? 0.85 : 1.1,
      children: [
        for (var i = 0; i < _cardSound.length; i++) PopIn(index: i, child: _cardWidget(i)),
      ],
    );
  }

  Widget _cardWidget(int index) {
    final revealed = _cardRevealed[index] || _cardMatched[index];
    final soundId = _cardSound[index];
    final interactive = _started && !_demoPlaying && !_gameOver && !_inputLocked;
    // Пред почеток картичките стојат видливи но затемнети и недостапни.
    final gameActive = _started || _demoPlaying;
    final reduceMotion = Playful.reduceMotion(context);

    final face = revealed
        ? SoundTile(
            key: const ValueKey('open'),
            icon: _soundIcons[soundId]!,
            label: 'sound.name_$soundId'.tr(),
            color: _soundColors[soundId] ?? _moduleAccent,
            onTap: null,
            enabled: false,
            showLabel: false,
            flash: _demoPlaying,
            state: _cardMatched[index] ? true : null,
          )
        : _closedCard(index, interactive, key: const ValueKey('closed'));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: gameActive ? 1.0 : 0.35,
      child: reduceMotion
          ? face
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current],
              ),
              // Превртување на картичката: старата страна се врти до 90°,
              // па новата се враќа од 90° до 0°.
              transitionBuilder: (child, animation) => AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  final angle = (1 - animation.value) * math.pi;
                  if (angle > math.pi / 2) return const SizedBox.shrink();
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    child: child,
                  );
                },
              ),
              child: face,
            ),
    );
  }

  Widget _closedCard(int index, bool interactive, {Key? key}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      key: key,
      label: 'sound_memory.card_closed'.tr(),
      button: interactive,
      child: PressableScale(
        enabled: interactive,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: interactive ? () => _onCardTap(index) : null,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: hc ? const Color(0xFF1A1A1A) : null,
                gradient: hc
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Playful.nightRaised, Color.lerp(Playful.night, _moduleAccent, 0.25)!],
                      ),
                border: Border.all(color: hc ? Colors.white : Playful.sun.withValues(alpha: 0.85), width: 3),
                boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.35), blurRadius: 14)],
              ),
              child: ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final iconSize = math.min(constraints.maxWidth, constraints.maxHeight) * 0.5;
                    return Center(
                      child: Icon(
                        Icons.music_note_rounded,
                        size: iconSize,
                        color: hc ? Colors.white54 : Playful.sun.withValues(alpha: 0.9),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}