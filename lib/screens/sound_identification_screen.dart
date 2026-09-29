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
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.sound_identification'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrast),
            if (_explanationOpen) _buildExplanationPanel(contrast),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _gameOver
                    ? 'sound.game_over_title'.tr()
                    : 'sound.rounds_progress'.tr(args: [
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
        ? 'sound.explanation_toggle_close'.tr()
        : 'sound.explanation_toggle_open'.tr();
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
              Icon(Icons.hearing_rounded, color: _moduleAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'sound.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'sound.explanation_text'.tr(),
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
        Semantics(
          label: 'sound.start'.tr(),
          button: true,
          child: GestureDetector(
            onTap: _playTargetSound,
            child: AnimatedScale(
              scale: _isPlaying ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hc
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_moduleAccent, Color.lerp(_moduleAccent, const Color(0xFF5EEAD4), 0.45)!],
                        ),
                  color: hc ? AccessibilityUtils.getPrimaryButtonBackground(context) : null,
                  border: Border.all(color: contrast, width: hc ? 3 : 0),
                  boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
                ),
                child: const Icon(Icons.volume_up_rounded, size: 56, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('sound.start'.tr(), style: GameTypography.heading(context, contrast, 16)),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _playTargetSound,
          icon: const Icon(Icons.replay_rounded),
          label: Text('sound.replay'.tr()),
        ),
        const SizedBox(height: 8),
        Text(
          'sound.choose'.tr(),
          style: GameTypography.body(context, contrast, 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.95,
              children: _soundIds.map((id) => _answerCard(id, hc)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _answerCard(String id, bool hc) {
    final baseColor = _soundColors[id]!;
    final label = 'sound.name_$id'.tr();
    final contrast = AccessibilityUtils.getContrastColor(context);
    final isPicked = _pickedId == id;
    final interactive = _roundStarted && _pickedId == null;

    // Боја на картичката: нормална, или позитивна/негативна ако е одбрана.
    Color bg = baseColor;
    if (isPicked && _pickedCorrect != null) {
      bg = _pickedCorrect!
          ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A))
          : (hc ? const Color(0xFF3A3A3A) : const Color(0xFF6B7280));
    }

    return Semantics(
      label: label,
      button: interactive,
      child: Opacity(
        // Затемнета и неактивна додека не се притисне "Пушти звук".
        opacity: !_roundStarted ? 0.35 : 1.0,
        child: AbsorbPointer(
          absorbing: !interactive,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            elevation: hc ? 0 : 7,
            shadowColor: Colors.black.withOpacity(0.5),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _onChoose(id),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: hc
                      ? Border.all(color: contrast, width: 2)
                      : Border.all(color: Colors.white.withOpacity(0.35), width: 1),
                  gradient: hc
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color.lerp(bg, Colors.white, 0.22)!, bg],
                        ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Иконата зафаќа барем 70% од пократката страна на картичката.
                    final iconSize = min(constraints.maxWidth, constraints.maxHeight) * 0.7;
                    return Stack(
                      children: [
                        Center(
                          child: Icon(_soundIcons[id], size: iconSize, color: Colors.white),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.28),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                            ),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
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
              'sound.final_summary'.tr(args: [
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
              label: Text('sound.play_again'.tr()),
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