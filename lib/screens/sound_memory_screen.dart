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
    'water': Icons.water_rounded,
    'glass': Icons.local_bar_rounded,
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
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.sound_memory'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrast),
            if (_explanationOpen) _buildExplanationPanel(contrast),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _gameOver
                    ? 'sound_memory.game_over_title'.tr()
                    : 'sound_memory.rounds_progress'.tr(args: [
                        (_round + 1).toString(),
                        _totalRounds.toString(),
                      ]),
                style: GameTypography.heading(context, contrast, 20),
              ),
            ),
            if (!_gameOver)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'sound_memory.moves'.tr(args: [_moves.toString()]),
                  style: GameTypography.body(context, contrast, 15),
                ),
              ),
            Expanded(
              child: _gameOver ? _buildEndScreen(contrast) : _buildBoard(contrast, hc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final label = _explanationOpen
        ? 'sound_memory.explanation_toggle_close'.tr()
        : 'sound_memory.explanation_toggle_open'.tr();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        label: label,
        button: true,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _toggleExplanation,
            icon: Icon(
              _explanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded,
              size: 26,
            ),
            label: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _explanationOpen
                  ? AccessibilityUtils.getDisabledColor(context)
                  : _moduleAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplanationPanel(Color contrast) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _moduleAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _moduleAccent.withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_rounded, color: _moduleAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'sound_memory.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'sound_memory.explanation_text'.tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(Color contrast, bool hc) {
    // Картичките се СЕКОГАШ видливи (затворени, затемнети, недостапни за
    // допир) - копчето старт стои над нив, исто како кај Идентификација на
    // звук, за просторот да не изгледа празен пред почеток.
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildStartCircle(contrast, hc),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              itemCount: _cardSound.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (context, index) => _cardWidget(index, contrast, hc),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartCircle(Color contrast, bool hc) {
    return Semantics(
      label: 'sound_memory.start_button'.tr(),
      button: true,
      child: GestureDetector(
        onTap: _startDemo,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hc
                    ? null
                    : LinearGradient(
                        colors: [_moduleAccent, Color.lerp(_moduleAccent, Colors.white, 0.4)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: hc ? _moduleAccent : null,
                border: Border.all(color: contrast, width: hc ? 3 : 0),
                boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text('sound_memory.start_button'.tr(), style: GameTypography.heading(context, contrast, 16)),
          ],
        ),
      ),
    );
  }

  Widget _cardWidget(int index, Color contrast, bool hc) {
    final revealed = _cardRevealed[index] || _cardMatched[index];
    final soundId = _cardSound[index];
    final baseColor = _soundColors[soundId] ?? _moduleAccent;
    final interactive = _started && !_demoPlaying && !_gameOver && !_inputLocked;
    // Пред почеток (сè уште не е притиснато старт), картичките стојат
    // видливи но затемнети и недостапни - исто како кај Идентификација на
    // звук пред "Пушти звук".
    final gameActive = _started || _demoPlaying;

    return Opacity(
      opacity: gameActive ? 1.0 : 0.35,
      child: Semantics(
        label: revealed ? 'sound.name_$soundId'.tr() : 'sound_memory.card_closed'.tr(),
        button: interactive,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: interactive ? () => _onCardTap(index) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: revealed && !hc
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [baseColor, Color.lerp(baseColor, Colors.white, 0.25)!],
                      )
                    : null,
                color: revealed
                    ? (hc ? baseColor.withOpacity(0.9) : null)
                    : (hc ? const Color(0xFF1A1A1A) : _moduleAccent.withOpacity(0.18)),
                border: Border.all(color: contrast, width: 2),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Иста големина како кај Идентификација на звук - иконата
                  // зафаќа барем 70% од пократката страна на картичката.
                  final iconSize = min(constraints.maxWidth, constraints.maxHeight) * 0.7;
                  return Center(
                    child: revealed
                        ? Icon(_soundIcons[soundId], color: Colors.white, size: iconSize)
                        : Icon(Icons.music_note_rounded, color: contrast.withOpacity(0.4), size: iconSize),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndScreen(Color contrast) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text(
              'sound_memory.win'.tr(args: [_moves.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _restartGame,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('sound_memory.play_again'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _moduleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}