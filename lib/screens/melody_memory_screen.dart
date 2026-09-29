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

/// Мемorија на звуци: детето слуша НИЗА звуци по ред (пр. мачка, мачка,
/// куче, автомобил) - никогаш автоматски, само по притискање на Почни да
/// слушаш. Потоа треба да ги тапне истите звуци, во истиот редослед.
/// Должината на низата расте од 2 до 7 звуци низ 20-те вкупни рунди. На
/// крајот се прикажува колку рунди се погодени, а колку промашени.
class MelodyMemoryScreen extends StatefulWidget {
  const MelodyMemoryScreen({super.key});

  @override
  State<MelodyMemoryScreen> createState() => _MelodyMemoryScreenState();
}

class _MelodyMemoryScreenState extends State<MelodyMemoryScreen> {
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

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _prepareRound();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
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

  Future<void> _playSequence() async {
    setState(() {
      _isPlaying = true;
      _revealed = true;
      _userIndex = 0;
    });

    for (final id in _sequence) {
      if (!mounted) return;
      setState(() => _flashingId = id);
      await _playSoundEffect(id);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 50);
      }
      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _flashingId = null);
      await Future.delayed(const Duration(milliseconds: 180));
    }

    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _onTapIcon(String id) async {
    if (_isPlaying || !_revealed || _gameOver) return;

    setState(() => _flashingId = id);
    await _playSoundEffect(id);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 60);
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _flashingId = null);

    final isCorrectStep = id == _sequence[_userIndex];

    if (!isCorrectStep) {
      await _playClip('incorrect', 'melody.incorrect'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      _nextRound();
      return;
    }

    setState(() => _userIndex++);

    if (_userIndex >= _sequence.length) {
      setState(() => _hits++);
      await _playClip('correct', 'melody.correct'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
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
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.melody_memory'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrast),
            if (_explanationOpen) _buildExplanationPanel(contrast),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _gameOver
                    ? 'melody.game_over_title'.tr()
                    : 'melody.rounds_progress'.tr(args: [
                        (_round + 1).toString(),
                        _totalRounds.toString(),
                      ]),
                style: GameTypography.heading(context, contrast, 20),
              ),
            ),
            Expanded(
              child: _gameOver ? _buildEndScreen(contrast) : _buildRound(contrast, hc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final label = _explanationOpen
        ? 'melody.explanation_toggle_close'.tr()
        : 'melody.explanation_toggle_open'.tr();
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
              Icon(Icons.volume_up_rounded, color: _moduleAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'melody.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'melody.explanation_text'.tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
        ],
      ),
    );
  }

  Widget _buildRound(Color contrast, bool hc) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'melody.score'.tr(args: [_hits.toString()]),
          style: GameTypography.body(context, contrast, 16),
        ),
        const SizedBox(height: 12),
        if (!_revealed)
          _buildStartButton(contrast, hc)
        else ...[
          Text(
            'melody.choose_prompt'.tr(),
            textAlign: TextAlign.center,
            style: GameTypography.body(context, contrast, 16),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _isPlaying ? null : _playSequence,
            icon: const Icon(Icons.replay_rounded),
            label: Text('melody.listen_again'.tr()),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(child: _buildIconGrid(hc)),
      ],
    );
  }

  Widget _buildStartButton(Color contrast, bool hc) {
    return Semantics(
      label: 'melody.start_listening'.tr(),
      button: true,
      child: GestureDetector(
        onTap: _playSequence,
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hc
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF9333EA), Color(0xFFC084FC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: hc ? _moduleAccent : null,
                border: Border.all(color: contrast, width: hc ? 3 : 0),
                boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text('melody.start_listening'.tr(), style: GameTypography.heading(context, contrast, 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildIconGrid(bool hc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.15,
        children: _soundIds.map((id) => _iconCard(id, hc)).toList(),
      ),
    );
  }

  Widget _iconCard(String id, bool hc) {
    final baseColor = _soundColors[id]!;
    final label = _soundLabelKeys[id]!.tr();
    final contrast = AccessibilityUtils.getContrastColor(context);
    final isFlashing = _flashingId == id;
    final interactive = _revealed && !_isPlaying && !_gameOver;

    return Semantics(
      label: label,
      button: interactive,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: interactive ? () => _onTapIcon(id) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: hc
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isFlashing
                          ? [Colors.white, Color.lerp(baseColor, Colors.white, 0.5)!]
                          : [baseColor, Color.lerp(baseColor, Colors.white, 0.25)!],
                    ),
              color: hc ? baseColor.withOpacity(isFlashing ? 0.5 : 0.9) : null,
              border: Border.all(
                color: isFlashing ? Colors.white : (hc ? contrast : Colors.transparent),
                width: isFlashing ? 4 : 2,
              ),
              boxShadow: hc
                  ? const <BoxShadow>[]
                  : [
                      BoxShadow(
                        color: baseColor.withOpacity(isFlashing ? 0.6 : 0.25),
                        blurRadius: isFlashing ? 24 : 8,
                        spreadRadius: isFlashing ? 3 : 0,
                      ),
                    ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Иста големина како кај Идентификација на звук - иконата
                // зафаќа барем 70% од пократката страна на картичката.
                final iconSize = min(constraints.maxWidth, constraints.maxHeight) * 0.7;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_soundIcons[id], size: iconSize, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                );
              },
            ),
          ),
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
            Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text(
              'melody.final_summary'.tr(args: [
                _hits.toString(),
                misses.toString(),
                _totalRounds.toString(),
              ]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('melody.play_again'.tr()),
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