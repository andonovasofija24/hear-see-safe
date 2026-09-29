import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

/// Гласовен Понг за деца со оштетен вид и/или слух - верзија со подвижна
/// палка.
///
/// Палката се движи горе-долу по левиот раб со повлекување на прст.
/// Топчето отскокнува од горниот, долниот и десниот ѕид (тик-звук,
/// панорамиран во стерео + вибрација на секој отскок). Ако палката го
/// пресретне топчето на левиот раб - удар, и топчето се забрзува секој
/// следен пат. Ако топчето помине покрај палката - крај на играта.
class VoicePongScreen extends StatefulWidget {
  const VoicePongScreen({super.key});

  @override
  State<VoicePongScreen> createState() => _VoicePongScreenState();
}

class _VoicePongScreenState extends State<VoicePongScreen> {
  static const double _paddleXThreshold = 0.045;

  /// Половина од висината на палката, во нормализирани (0-1) единици.
  static const double _paddleHalfHeight = 0.12;

  static const double _baseVx = 0.012;
  static const double _baseVy = 0.005;
  static const double _speedGrowth = 1.06;
  static const double _maxSpeedFactor = 2.6;

  late VoiceAssistantService _voiceAssistant;
  /// Одделен плеер за говорни клипови (објаснување, "Удар!", "Пропуштено.")
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратки звучни ефекти (тик/удар/промашување), за да не
  /// го прекинуваат говорниот клип и обратно кога се пуштаат близу еден до друг.
  final AudioPlayer _effectsPlayer = AudioPlayer();

  Timer? _gameTimer;

  double _paddleY = 0.5; // нормализирана позиција (0 = горе, 1 = долу)
  double _ballX = 0.85;
  double _ballY = 0.5;
  double _vx = -_baseVx;
  double _vy = _baseVy;
  double _speedFactor = 1.0;

  bool _playing = false;
  bool _gameOver = false;
  bool _paddleFlash = false;
  int _hits = 0;
  bool _explanationOpen = false;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _voiceAssistant.stop();
    _gameTimer?.cancel();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    super.dispose();
  }

  /// Пробува однапред снимена звучна датотека (твоја снимка), а само ако
  /// не постои паѓа назад на системскиот text-to-speech. Само за говорни,
  /// СТАТИЧНИ фрази.
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/voice_pong/$_langCode/$key.mp3';
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

  /// Звучни ефекти (не говор) - тик/удар/промашување. Нема TTS резерва.
  Future<void> _playTick(double pan) async {
    try {
      await _effectsPlayer.setBalance(pan.clamp(-1.0, 1.0));
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/tick.mp3'));
    } catch (_) {}
  }

  Future<void> _playEffect(String fileName) async {
    try {
      await _effectsPlayer.setBalance(0);
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  void _startGame() {
    setState(() {
      _playing = true;
      _gameOver = false;
      _hits = 0;
      _speedFactor = 1.0;
      _ballX = 0.85;
      _ballY = 0.5;
      _vx = -_baseVx;
      _vy = _baseVy;
      _paddleY = 0.5;
    });
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 35), (_) => _tick());
  }

  void _onPaddleDrag(double localDy, double areaHeight) {
    if (!_playing) return;
    final norm = (localDy / areaHeight).clamp(_paddleHalfHeight, 1 - _paddleHalfHeight);
    setState(() => _paddleY = norm);
  }

  void _tick() {
    if (!_playing || !mounted) return;

    setState(() {
      _ballX += _vx * _speedFactor;
      _ballY += _vy * _speedFactor;
    });

    bool bounced = false;

    if (_ballY <= 0) {
      setState(() {
        _ballY = 0;
        _vy = _vy.abs();
      });
      bounced = true;
    } else if (_ballY >= 1) {
      setState(() {
        _ballY = 1;
        _vy = -_vy.abs();
      });
      bounced = true;
    }

    if (_ballX >= 1) {
      setState(() {
        _ballX = 1;
        _vx = -_vx.abs();
      });
      bounced = true;
    }

    if (bounced) {
      final pan = (_ballX * 2) - 1; // десно (+1) -> лево (-1)
      _playTick(pan);
      VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(duration: 20);
      });
    }

    if (_ballX <= _paddleXThreshold) {
      final withinPaddle = (_ballY - _paddleY).abs() <= _paddleHalfHeight;
      if (withinPaddle) {
        _onPaddleHit();
      } else {
        _onMiss();
      }
    }
  }

  Future<void> _onPaddleHit() async {
    setState(() {
      _ballX = _paddleXThreshold;
      _vx = _vx.abs();
      _speedFactor = (_speedFactor * _speedGrowth).clamp(1.0, _maxSpeedFactor);
      _hits++;
      _paddleFlash = true;
    });

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 120);
    }
    await _playEffect('hit.mp3');

    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _paddleFlash = false);
  }

  Future<void> _onMiss() async {
    _gameTimer?.cancel();
    setState(() {
      _playing = false;
      _gameOver = true;
    });

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 250);
    }
    await _playEffect('miss.mp3');
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation', 'pong.explanation_text'.tr());
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: const Color(0xFFD97706),
      title: 'features.voice_pong'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrastColor),
            if (_explanationOpen) _buildExplanationPanel(contrastColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _gameOver
                    ? 'pong.game_over_title'.tr()
                    : 'pong.score'.tr(args: [_hits.toString()]),
                style: GameTypography.heading(context, contrastColor, 20),
              ),
            ),
            Expanded(
              child: _gameOver
                  ? _buildEndScreen(contrastColor)
                  : _buildPlayArea(contrastColor, hc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final label = _explanationOpen
        ? 'pong.explanation_toggle_close'.tr()
        : 'pong.explanation_toggle_open'.tr();
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
                  : const Color(0xFFD97706),
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
        color: const Color(0xFFD97706).withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD97706).withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_tennis_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'pong.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'pong.explanation_text'.tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayArea(Color contrastColor, bool hc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: Semantics(
              label: 'pong.explanation_text'.tr(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final ballSize = 32.0;
                  final paddleHeight = _paddleHalfHeight * 2 * h;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onPaddleDrag(d.localPosition.dy, h),
                    onPanStart: (d) => _onPaddleDrag(d.localPosition.dy, h),
                    onPanUpdate: (d) => _onPaddleDrag(d.localPosition.dy, h),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: hc ? const Color(0xFF1A1A1A) : Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: contrastColor, width: 4),
                        boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
                      ),
                      child: Stack(
                        children: [
                          // Палка - подвижна, лево (без анимација на позиција,
                          // за да ја следи прецизно раката без задршка)
                          Positioned(
                            left: 12,
                            top: (_paddleY * h) - paddleHeight / 2,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 16,
                              height: paddleHeight,
                              decoration: BoxDecoration(
                                color: _paddleFlash
                                    ? const Color(0xFFFFEB3B)
                                    : AccessibilityUtils.getAccentColor(context),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _paddleFlash
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFFEB3B).withOpacity(0.7),
                                          blurRadius: 20,
                                          spreadRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                          // Топче - светла боја (не зависи од темата) + сјај,
                          // за да остане видливо на темната позадина.
                          // Користи ја ИСТАТА координатна основа како палката
                          // (_paddleY * h), за да се совпаѓаат визуелно.
                          if (_playing)
                            Positioned(
                              left: (_ballX * w) - ballSize / 2,
                              top: (_ballY * h) - ballSize / 2,
                              child: Container(
                                width: ballSize,
                                height: ballSize,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEE58),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFEE58).withOpacity(0.8),
                                      blurRadius: 14,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (!_playing)
                            Center(
                              child: Semantics(
                                label: 'pong.start_button'.tr(),
                                button: true,
                                child: ElevatedButton.icon(
                                  onPressed: _startGame,
                                  icon: const Icon(Icons.sports_tennis_rounded, size: 38),
                                  label: Text(
                                    'pong.start_button'.tr(),
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97706),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
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
            const Icon(Icons.emoji_events_rounded, size: 72, color: Color(0xFFD97706)),
            const SizedBox(height: 16),
            Text(
              'pong.final_summary_survival'.tr(args: [_hits.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('pong.play_again'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
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