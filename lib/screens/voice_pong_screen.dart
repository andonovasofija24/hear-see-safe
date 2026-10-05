import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

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

  static const Color _accent = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

    return GameScreenChrome(
      accent: _accent,
      title: 'features.voice_pong'.tr(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['🏓', '🎾', '⚡', '🔊', '⭐', '🎧'],
        tint: _accent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 900) / 2).clamp(16.0, double.infinity);
            final header = <Widget>[
              PlayfulExplainButton(
                open: _explanationOpen,
                label: _explanationOpen
                    ? 'pong.explanation_toggle_close'.tr()
                    : 'pong.explanation_toggle_open'.tr(),
                onTap: _toggleExplanation,
              ),
              if (_explanationOpen)
                PlayfulExplainPanel(
                  icon: Icons.sports_tennis_rounded,
                  title: 'pong.explanation_title'.tr(),
                  text: 'pong.explanation_text'.tr(),
                  accent: _accent,
                ),
              const SizedBox(height: 12),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Објаснувањето може да е долго - се лизга и зазема најмногу
                // 40% од висината, за теренот секогаш да има место.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.4),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...header,
                        if (_gameOver)
                          Text(
                            'pong.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26, color: fg),
                          )
                        else
                          Center(child: _scorePill(hc)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _gameOver
                      ? PlayfulResult(
                          text: 'pong.final_summary_survival'.tr(args: [_hits.toString()]),
                          buttonLabel: 'pong.play_again'.tr(),
                          onAgain: _startGame,
                        )
                      : Padding(
                          padding: EdgeInsets.fromLTRB(side, 12, side, 16),
                          child: _buildPlayArea(hc),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Бројот на удари во златна ознака што „отскокнува“ при секој удар.
  Widget _scorePill(bool hc) {
    final text = 'pong.score'.tr(args: [_hits.toString()]);
    return Semantics(
      label: text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _paddleFlash ? 1.15 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: hc ? Colors.black : Playful.sun,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: hc ? 2 : 3),
              boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 18)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_tennis_rounded, size: 26, color: hc ? Colors.white : Playful.ink),
                const SizedBox(width: 10),
                Text(text, style: Playful.display(22, color: hc ? Colors.white : Playful.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayArea(bool hc) {
    return Semantics(
      label: 'pong.explanation_text'.tr(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          const ballSize = 32.0;
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
                color: hc ? const Color(0xFF1A1A1A) : null,
                gradient: hc
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Playful.nightDeep, Playful.night, Color(0xFF2A1A5E)],
                      ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white, width: hc ? 4 : 3),
                boxShadow: hc ? null : [BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 26)],
              ),
              child: Stack(
                children: [
                  // Терен: испрекината средна линија, светнат десен ѕид.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CourtPainter(highContrast: hc)),
                    ),
                  ),
                  // Палка - подвижна, лево (без анимација на позиција,
                  // за да ја следи прецизно раката без задршка).
                  Positioned(
                    left: 12,
                    top: (_paddleY * h) - paddleHeight / 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 18,
                      height: paddleHeight,
                      decoration: BoxDecoration(
                        color: hc ? (_paddleFlash ? const Color(0xFFFFFF00) : Colors.white) : null,
                        gradient: hc
                            ? null
                            : LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _paddleFlash
                                    ? [Colors.white, const Color(0xFFFFF4C2)]
                                    : [const Color(0xFFFFE08A), Playful.sun, _accent],
                              ),
                        borderRadius: BorderRadius.circular(9),
                        border: hc ? null : Border.all(color: Colors.white, width: 2),
                        boxShadow: hc
                            ? null
                            : [
                                BoxShadow(
                                  color: Playful.sun.withValues(alpha: _paddleFlash ? 0.9 : 0.5),
                                  blurRadius: _paddleFlash ? 26 : 14,
                                  spreadRadius: _paddleFlash ? 5 : 1,
                                ),
                              ],
                      ),
                    ),
                  ),
                  // Топче - светло, со сјај, за да е видливо на темната
                  // позадина. Иста координатна основа како палката.
                  if (_playing)
                    Positioned(
                      left: (_ballX * w) - ballSize / 2,
                      top: (_ballY * h) - ballSize / 2,
                      child: Container(
                        width: ballSize,
                        height: ballSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hc ? const Color(0xFFFFFF00) : null,
                          gradient: hc
                              ? null
                              : const RadialGradient(
                                  colors: [Colors.white, Color(0xFFFFE08A), Playful.sun],
                                  stops: [0.0, 0.55, 1.0],
                                ),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: hc
                              ? null
                              : [
                                  BoxShadow(
                                    color: Playful.sun.withValues(alpha: 0.85),
                                    blurRadius: 18,
                                    spreadRadius: 4,
                                  ),
                                ],
                        ),
                      ),
                    ),
                  if (!_playing) Center(child: _startButton(hc)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// „Почни“ - златно копче со бранови среде теренот.
  Widget _startButton(bool hc) {
    final label = 'pong.start_button'.tr();
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: RippleRings(
          color: hc ? Colors.white : Playful.sun,
          active: true,
          spread: 18,
          child: PressableScale(
            child: Material(
              color: hc ? Colors.black : Playful.sun,
              borderRadius: BorderRadius.circular(40),
              child: InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: _startGame,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white, width: hc ? 3 : 4),
                    boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: 24)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_tennis_rounded, size: 36, color: hc ? Colors.white : Playful.ink),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(label, style: Playful.display(26, color: hc ? Colors.white : Playful.ink)),
                      ),
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
}

/// Терен: испрекината линија по средината и светнат десен ѕид (од каде
/// што топчето се одбива).
class _CourtPainter extends CustomPainter {
  _CourtPainter({required this.highContrast});

  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = highContrast ? Colors.white54 : Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const dashLen = 14.0;
    const gap = 14.0;
    final x = size.width / 2;
    for (var y = 12.0; y < size.height - 12; y += dashLen + gap) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dashLen).clamp(0, size.height - 12).toDouble()), dash);
    }
    if (!highContrast) {
      // Мек круг во средината.
      canvas.drawCircle(
        Offset(x, size.height / 2),
        size.shortestSide * 0.16,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // Светнат десен ѕид.
      final wall = Rect.fromLTWH(size.width - 10, 0, 10, size.height);
      canvas.drawRect(
        wall,
        Paint()
          ..shader = LinearGradient(
            colors: [Playful.sun.withValues(alpha: 0.0), Playful.sun.withValues(alpha: 0.45)],
          ).createShader(wall),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CourtPainter old) => old.highContrast != highContrast;
}
