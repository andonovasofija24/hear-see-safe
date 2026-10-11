import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
/// Колку пати е поголем текстот на екранот за гласовен понг.
const double _kPongText = 1.6;
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
  /// Одделен плеер за говорни клипови (објаснување, "Удар!", "Пропуштено.")
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратки звучни ефекти (тик/удар/промашување), за да не
  /// го прекинуваат говорниот клип и обратно кога се пуштаат близу еден до друг.
  final AudioPlayer _effectsPlayer = AudioPlayer();

  // Independent looping guidance tracks. Neither interrupts hits or speech.
  final AudioPlayer _positiveGuide = AudioPlayer();
  final AudioPlayer _negativeGuide = AudioPlayer();
  bool _guidesReady = false;
  bool _guidesStarting = false;
  DateTime _lastGuideUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _guideUpdateInterval = Duration(milliseconds: 90);
  static const double _guideMaxVolume = 0.65;
  static const double _guideThresholdMargin = 0.045;

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
  // Рекорд: најмногу погодоци некогаш (се чува трајно на уредот).
  static const String _bestKey = 'pong_best_hits';
  int _best = 0;
  bool _newRecord = false;
  String get _langCode => context.locale.languageCode;
  @override
  void initState() {
    super.initState();
    _loadBest();
  }
  Future<void> _loadBest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_bestKey) ?? 0;
      if (mounted && v > _best) setState(() => _best = v);
    } catch (_) {}
  }
  Future<void> _saveBest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bestKey, _best);
    } catch (_) {}
  }
  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _gameTimer?.cancel();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _positiveGuide.dispose();
    _negativeGuide.dispose();
    super.dispose();
  }
  /// Исклучиво однапред снимен MP3 клип; без системски TTS.
  /// Ако датотеката недостасува или не може да се пушти, останува тишина.
  Future<void> _playClip(String key) async {
    if (!mounted) return;
    final relativePath = 'audio/voice_pong/$_langCode/$key.mp3';
    try {
      await _voicePlayer.stop();
      await _voicePlayer.play(AssetSource(relativePath));
    } catch (error) {
      debugPrint('Voice Pong: MP3 не е достапен ($relativePath): $error');
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
  /// Start both seamless loop tracks muted. Volume is driven by the ball.
  Future<void> _startGuidance() async {
    if (_guidesStarting || _guidesReady || !_playing) return;
    _guidesStarting = true;
    try {
      await _positiveGuide.setReleaseMode(ReleaseMode.loop);
      await _negativeGuide.setReleaseMode(ReleaseMode.loop);
      await _positiveGuide.setVolume(0);
      await _negativeGuide.setVolume(0);
      await Future.wait([
        _positiveGuide.play(AssetSource('sounds/pong/guide_positive.mp3')),
        _negativeGuide.play(AssetSource('sounds/pong/guide_negative.mp3')),
      ]);
      if (!_playing || !mounted) {
        await _stopGuidance();
      } else {
        _guidesReady = true;
        _updateGuidance(force: true);
      }
    } catch (_) {
      // Missing guide files must not prevent the game from working.
      await _stopGuidance();
    } finally {
      _guidesStarting = false;
    }
  }

  Future<void> _stopGuidance() async {
    _guidesReady = false;
    try { await _positiveGuide.stop(); } catch (_) {}
    try { await _negativeGuide.stop(); } catch (_) {}
  }

  /// Predicted vertical intercept, accounting for reflections at y=0 and y=1.
  double _predictedImpactY() {
    if (_vx >= 0) return _ballY;
    final steps = ((_ballX - _paddleXThreshold) / (-_vx * _speedFactor)).clamp(0.0, 10000.0);
    final raw = _ballY + _vy * _speedFactor * steps;
    final phase = ((raw % 2.0) + 2.0) % 2.0;
    return phase <= 1.0 ? phase : 2.0 - phase;
  }

  void _updateGuidance({bool force = false}) {
    if (!_guidesReady) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastGuideUpdate) < _guideUpdateInterval) return;
    _lastGuideUpdate = now;

    // Only sound guidance while the ball is approaching from the left half.
    if (!_playing || _ballX > 0.5 || _vx >= 0) {
      unawaited(_positiveGuide.setVolume(0));
      unawaited(_negativeGuide.setVolume(0));
      return;
    }

    final missDistance = (_predictedImpactY() - _paddleY).abs();
    final safeLimit = _paddleHalfHeight + _guideThresholdMargin;
    final approach = ((0.5 - _ballX) / (0.5 - _paddleXThreshold)).clamp(0.0, 1.0);
    final positive = missDistance <= safeLimit;
    // Positive grows towards impact, and falls when alignment deteriorates.
    final alignment = (1.0 - missDistance / safeLimit).clamp(0.0, 1.0);
    final positiveVolume = positive
        ? _guideMaxVolume * (0.18 + 0.82 * approach) * (0.3 + 0.7 * alignment)
        : 0.0;
    // Negative grows as the predicted miss gets larger; moving paddle closer
    // reduces it immediately, even when the ball continues approaching.
    final error = ((missDistance - safeLimit) / (1.0 - safeLimit)).clamp(0.0, 1.0);
    final negativeVolume = positive
        ? 0.0
        : _guideMaxVolume * (0.16 + 0.84 * error) * (0.35 + 0.65 * approach);
    unawaited(_positiveGuide.setVolume(positiveVolume.clamp(0.0, 1.0)));
    unawaited(_negativeGuide.setVolume(negativeVolume.clamp(0.0, 1.0)));
  }

  void _startGame() {
    unawaited(_stopGuidance());
    setState(() {
      _playing = true;
      _gameOver = false;
      _newRecord = false;
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
    unawaited(_startGuidance());
  }
  void _onPaddleDrag(double localDy, double areaHeight) {
    if (!_playing) return;
    final norm = (localDy / areaHeight).clamp(_paddleHalfHeight, 1 - _paddleHalfHeight);
    setState(() => _paddleY = norm);
    _updateGuidance(force: true);
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
    _updateGuidance();

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
    _updateGuidance(force: true);
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
    unawaited(_stopGuidance());
    final record = _hits > _best;
    setState(() {
      _playing = false;
      _gameOver = true;
      _newRecord = record;
      if (record) _best = _hits;
    });
    if (record) unawaited(_saveBest());
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 250);
    }
    await _playEffect('miss.mp3');
    if (record && mounted && _gameOver) {
      await _playClip('new_record');
    }
  }
  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation');
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
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
                        if (_gameOver) ...[
                          Text(
                            'pong.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26 * _kPongText, color: fg),
                          ),
                          const SizedBox(height: 10),
                          Center(child: _recordPill(hc)),
                        ] else
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 10,
                              children: [_scorePill(hc), _recordPill(hc)],
                            ),
                          ),
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
  /// Рекордот (најмногу погодоци некогаш). По игра со нов рекорд пишува
  /// „Нов рекорд!“ и свети.
  Widget _recordPill(bool hc) {
    final text = _newRecord
        ? 'pong.new_record'.tr(args: [_best.toString()])
        : 'pong.record'.tr(args: [_best.toString()]);
    final glow = _newRecord && !hc;
    return Semantics(
      label: text,
      liveRegion: _newRecord,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: hc ? Colors.black : (glow ? Playful.sun : Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white, width: hc ? 2 : 2.5),
            boxShadow: glow ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.6), blurRadius: 22)] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, size: 32, color: hc ? Colors.white : (glow ? Playful.ink : Playful.sun)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Playful.display(20 * _kPongText, color: hc ? Colors.white : (glow ? Playful.ink : Colors.white)),
                ),
              ),
            ],
          ),
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
                Icon(Icons.sports_tennis_rounded, size: 34, color: hc ? Colors.white : Playful.ink),
                const SizedBox(width: 10),
                Flexible(child: Text(text, textAlign: TextAlign.center, style: Playful.display(22 * _kPongText, color: hc ? Colors.white : Playful.ink))),
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
                  if (!_playing)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: StartHotkeyListener(onTrigger: _startGame, child: _startButton(hc)),
                      ),
                    ),
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
                      Icon(Icons.sports_tennis_rounded, size: 46, color: hc ? Colors.white : Playful.ink),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(label, textAlign: TextAlign.center, style: Playful.display(26 * _kPongText, color: hc ? Colors.white : Playful.ink)),
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