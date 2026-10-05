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

/// Колку пати е поголем текстот на екранот за идентификација на звук.
const double _kSidText = 1.6;

/// Идентификација на звук: детето слуша еден звук (копче Пушти звук,
/// никогаш автоматски) и избира од понудените одговори кое животно/предмет
/// го создава тој звук. Играта трае вкупно 20 рунди, а на крајот се
/// прикажува колку рунди се погодени, а колку промашени.
class SoundIdentificationScreen extends StatefulWidget {
  const SoundIdentificationScreen({super.key});

  @override
  State<SoundIdentificationScreen> createState() =>
      _SoundIdentificationScreenState();
}

class _SoundIdentificationScreenState extends State<SoundIdentificationScreen> {
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

  final Random _random = Random();

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
    _pickTarget();
  }

  @override
  void dispose() {
    _voiceAssistant.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _pickTarget() {
    String next;
    do {
      next = _soundIds[_random.nextInt(_soundIds.length)];
    } while (next == _target && _soundIds.length > 1);
    setState(() {
      _target = next;
      _roundStarted = false;
      _pickedId = null;
      _pickedCorrect = null;
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
    if (_target == null) return;
    setState(() {
      _isPlaying = true;
      _roundStarted = true;
    });
    try {
      final path = _soundAssets[_target]!;
      final relative = path.startsWith('assets/') ? path.substring(7) : path;
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(relative));
    } catch (_) {}
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 60);
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isPlaying = false);
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
    });
    _pickTarget();
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
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
      bodyBackground: const EmojiBackdrop(
        emojis: ['🔊', '🐶', '🚗', '🌧️', '🐦', '🔔'],
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
                const SizedBox(height: 26),
                Center(
                  child: SoundOrb(
                    icon: Icons.volume_up_rounded,
                    label: 'sound.start'.tr(),
                    onTap: _playTargetSound,
                    active: _isPlaying,
                    size: 150,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: PlayfulGhostButton(
                    icon: Icons.replay_rounded,
                    label: 'sound.replay'.tr(),
                    onTap: _playTargetSound,
                  ),
                ),
                const SizedBox(height: 18),
                PlayfulHint('sound.choose'.tr()),
                const SizedBox(height: 16),
                _buildGrid(constraints.maxWidth - side * 2),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(double width) {
    final columns = width < 360 ? 2 : 3;
    return PlayfulGrid(
      columns: columns,
      children: [
        for (var i = 0; i < _soundIds.length; i++)
          PopIn(index: i, stepMs: 45, child: _answerCard(_soundIds[i])),
      ],
    );
  }

  Widget _answerCard(String id) {
    final isPicked = _pickedId == id;
    final interactive = _roundStarted && _pickedId == null;
    return SoundTile(
      icon: _soundIcons[id]!,
      label: 'sound.name_$id'.tr(),
      color: _soundColors[id]!,
      onTap: () => _onChoose(id),
      enabled: interactive,
      // Затемнети додека не се притисне „Пушти звук“; по изборот -
      // останатите малку се повлекуваат.
      dimmed: !_roundStarted || (_pickedId != null && !isPicked),
      state: isPicked ? _pickedCorrect : null,
    );
  }
}