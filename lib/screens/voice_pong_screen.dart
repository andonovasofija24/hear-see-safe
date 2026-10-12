import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
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
  /// Геометрија во пиксели (иста како на цртежот): палката е 12 px од
  /// левиот раб и широка 18 px, топчето е 32 px (радиус 16).
  static const double _paddleLeftPx = 12;
  static const double _paddleWidthPx = 18;
  static const double _ballRadiusPx = 16;

  /// Големина на теренот - се ажурира при секое цртање.
  double _fieldW = 400;
  double _fieldH = 300;

  /// Топчето ја промаши палката и сега поминува зад неа (до левиот раб).
  bool _passing = false;

  /// Најгласно што смее водичот - малку потивко од тик-звукот и звукот за
  /// погодок (тие се на полна јачина 1.0).
  static const double _guideMaxVol = 0.88;

  /// Дали веќе вибрирало предупредувањето „ќе промашиш“ за ова доаѓање на
  /// топчето (еднаш по доаѓање).
  bool _warnedThisPass = false;

  /// Сонар: часовник за анимациите на екранот и бранови од топчето.
  final Stopwatch _clock = Stopwatch()..start();
  final List<_Ripple> _ripples = [];

  void _addRipple(Color color) {
    _ripples.add(_Ripple(Offset(_ballX, _ballY), _clock.elapsedMilliseconds, color));
    if (_ripples.length > 12) _ripples.removeAt(0);
  }

  /// Каде (0-1) центарот на топчето ја допира предната страна на палката.
  double get _contactX => (_paddleLeftPx + _paddleWidthPx + _ballRadiusPx) / _fieldW;
  double get _rx => _ballRadiusPx / _fieldW;
  double get _ry => _ballRadiusPx / _fieldH;

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

  /// Звучен водич: кога топчето е во левата половина и оди кон палката.
  /// guide_good.mp3 (позитивен) свири кога палката е на патот на топчето и
  /// станува сè погласен како што топчето се приближува; guide_bad.mp3
  /// (негативен) свири кога палката не е на патот - толку погласно колку
  /// што палката е подалеку од местото каде што ќе стигне топчето.
  final AudioPlayer _goodPlayer = AudioPlayer();
  final AudioPlayer _badPlayer = AudioPlayer();
  bool _guideReady = false;
  bool _goodStarted = false;
  bool _badStarted = false;
  /// 0 = тишина, 1 = позитивен, 2 = негативен.
  int _guideMode = 0;
  double _goodVol = -1;
  double _badVol = -1;

  /// Колку најмногу смее палката да е оддалечена од пресметаното место на
  /// топчето за да се смета дека „оди кон палката“ (малку помалку од
  /// половина палка - позитивниот звук значи сигурен погодок).
  static const double _guideAimTolerance = _paddleHalfHeight * 0.9;

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
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _loadBest();
    _initGuide();
  }

  Future<void> _initGuide() async {
    try {
      await _goodPlayer.setReleaseMode(ReleaseMode.loop);
      await _badPlayer.setReleaseMode(ReleaseMode.loop);
      _guideReady = true;
    } catch (_) {
      _guideReady = false;
    }
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Каде (0-1, вертикално) ќе стигне топчето кога ќе дојде до палката,
  /// со отскоците од горниот и долниот ѕид.
  double _predictYAtPaddle() {
    if (_vx >= 0) return _ballY;
    final steps = (_ballX - _contactX) / -_vx;
    final raw = _ballY + _vy * steps;
    // Топчето отскокнува кога неговиот раб ќе го допре ѕидот, т.е. центарот
    // се движи меѓу _ry и 1 - _ry.
    final span = math.max(0.0001, 1 - 2 * _ry);
    final m = ((raw - _ry) / span) % 2.0; // Dart: секогаш во [0, 2)
    return _ry + (m <= 1.0 ? m : 2.0 - m) * span;
  }

  /// Се повикува на секој чекор од играта.
  void _updateGuide() {
    if (_vx > 0) _warnedThisPass = false;
    if (!_playing || _passing || _vx >= 0 || _ballX > 0.5) {
      _setGuide(0, 0);
      return;
    }
    final miss = (_predictYAtPaddle() - _paddleY).abs();
    // 0 кога топчето штотуку влегло во левата половина, 1 кај палката.
    final approach = (1 - (_ballX - _contactX) / math.max(0.05, 0.5 - _contactX)).clamp(0.0, 1.0).toDouble();
    if (miss <= _guideAimTolerance) {
      final vol = 0.4 + (_guideMaxVol - 0.4) * approach * (1 - 0.4 * miss / _guideAimTolerance);
      _setGuide(1, vol.clamp(0.0, 1.0).toDouble());
    } else {
      final far = ((miss - _guideAimTolerance) / 0.5).clamp(0.0, 1.0).toDouble();
      _setGuide(2, 0.4 + (_guideMaxVol - 0.4) * far);
      // Телефон: „лоша“ вибрација кога топчето е блиску, а палката не е на
      // патот - последно предупредување пред промашување.
      if (approach > 0.7 && !_warnedThisPass) {
        _warnedThisPass = true;
        VibrationUtils.hasVibrator().then((ok) {
          if (ok) VibrationUtils.vibrate(pattern: const [0, 260, 90, 260, 90, 260]);
        });
      }
    }
  }

  void _setGuide(int mode, double vol) {
    if (!_guideReady) return;
    if (mode != _guideMode) {
      final prev = _guideMode;
      _guideMode = mode;
      if (prev == 1) unawaited(_safe(() => _goodPlayer.pause()));
      if (prev == 2) unawaited(_safe(() => _badPlayer.pause()));
      if (mode == 1) {
        _goodVol = vol;
        unawaited(_startLoop(_goodPlayer, 'guide_good.mp3', vol, true));
      } else if (mode == 2) {
        _badVol = vol;
        unawaited(_startLoop(_badPlayer, 'guide_bad.mp3', vol, false));
      }
      return;
    }
    // Јачината се менува само кога разликата се слуша - не на секои 35 ms.
    if (mode == 1 && (vol - _goodVol).abs() > 0.03) {
      _goodVol = vol;
      unawaited(_safe(() => _goodPlayer.setVolume(vol)));
    } else if (mode == 2 && (vol - _badVol).abs() > 0.03) {
      _badVol = vol;
      unawaited(_safe(() => _badPlayer.setVolume(vol)));
    }
  }

  Future<void> _startLoop(AudioPlayer player, String file, double vol, bool good) async {
    try {
      await player.setVolume(vol);
      final started = good ? _goodStarted : _badStarted;
      if (started) {
        await player.resume();
      } else {
        await player.play(AssetSource('sounds/pong/$file'), volume: vol);
        if (good) {
          _goodStarted = true;
        } else {
          _badStarted = true;
        }
      }
      // Ако во меѓувреме режимот се сменил, веднаш паузирај.
      final wanted = good ? 1 : 2;
      if (_guideMode != wanted) await player.pause();
    } catch (_) {
      // Снимката ја нема - водичот тивко не работи.
    }
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
    _voiceAssistant.stop();
    _gameTimer?.cancel();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _goodPlayer.dispose();
    _badPlayer.dispose();
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
      _newRecord = false;
      _hits = 0;
      _speedFactor = 1.0;
      _ballX = 0.85;
      _ballY = 0.5;
      _vx = -_baseVx;
      _vy = _baseVy;
      _paddleY = 0.5;
      _passing = false;
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

    if (_ballY <= _ry) {
      setState(() {
        _ballY = _ry;
        _vy = _vy.abs();
      });
      bounced = true;
    } else if (_ballY >= 1 - _ry) {
      setState(() {
        _ballY = 1 - _ry;
        _vy = -_vy.abs();
      });
      bounced = true;
    }

    if (_ballX >= 1 - _rx) {
      setState(() {
        _ballX = 1 - _rx;
        _vx = -_vx.abs();
      });
      bounced = true;
    }

    if (bounced) {
      final pan = (_ballX * 2) - 1; // десно (+1) -> лево (-1)
      _playTick(pan);
      _addRipple(const Color(0xFF7CF7C0));
      VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(duration: 20);
      });
    }

    // Отскок од ПРЕДНАТА страна на палката (не од ѕидот зад неа). Ако
    // палката не е таму, топчето продолжува зад неа и дури на левиот раб
    // е промашување.
    if (!_passing && _vx < 0 && _ballX <= _contactX) {
      final reach = _paddleHalfHeight * _fieldH + _ballRadiusPx * 0.6;
      final withinPaddle = (_ballY - _paddleY).abs() * _fieldH <= reach;
      if (withinPaddle) {
        _addRipple(const Color(0xFFFFE08A));
        _onPaddleHit();
      } else {
        _passing = true;
      }
    }
    if (_passing && _ballX * _fieldW < -_ballRadiusPx) {
      _onMiss();
    }
    _updateGuide();
  }

  Future<void> _onPaddleHit() async {
    setState(() {
      _ballX = _contactX;
      _vx = _vx.abs();
      _speedFactor = (_speedFactor * _speedGrowth).clamp(1.0, _maxSpeedFactor);
      _hits++;
      _paddleFlash = true;
    });

    if (await VibrationUtils.hasVibrator()) {
      // „Добра“ вибрација: два кратки весели удари.
      await VibrationUtils.vibrate(pattern: const [0, 70, 60, 70]);
    }
    await _playEffect('hit.mp3');

    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _paddleFlash = false);
  }

  Future<void> _onMiss() async {
    _gameTimer?.cancel();
    _guideMode = -1; // принуди пауза на двата
    _setGuide(0, 0);
    unawaited(_safe(() => _goodPlayer.pause()));
    unawaited(_safe(() => _badPlayer.pause()));
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
    // Новиот рекорд само се пишува (без снимка и без системски глас).
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
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: _ledPanel(hc, Icons.emoji_events_rounded, text, bright: _newRecord, gold: _newRecord),
      ),
    );
  }

  Widget _scorePill(bool hc) {
    final text = 'pong.score'.tr(args: [_hits.toString()]);
    return Semantics(
      label: text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _paddleFlash ? 1.15 : 1.0,
          child: _ledPanel(hc, Icons.sports_tennis_rounded, text, bright: true),
        ),
      ),
    );
  }

  /// Табла како на стар осцилоскоп: црна, со зелени светечки букви.
  Widget _ledPanel(bool hc, IconData icon, String text, {bool bright = false, bool gold = false}) {
    final glow = gold ? Playful.sun : _sonarGreen;
    final fgc = hc ? Colors.white : glow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: hc ? Colors.black : const Color(0xFF02140F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hc ? Colors.white : glow.withValues(alpha: bright ? 0.95 : 0.6), width: hc ? 2 : 2.5),
        boxShadow: hc ? null : [BoxShadow(color: glow.withValues(alpha: bright ? 0.45 : 0.25), blurRadius: 16)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: fgc),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 21 * _kPongText,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: fgc,
                shadows: hc ? null : [Shadow(color: glow.withValues(alpha: 0.8), blurRadius: 10)],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const Color _sonarGreen = Color(0xFF39FF9A);

  Widget _buildPlayArea(bool hc) {
    return Semantics(
      label: 'pong.explanation_text'.tr(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          const ballSize = _ballRadiusPx * 2;
          final paddleHeight = _paddleHalfHeight * 2 * h;
          // Судирите се пресметуваат во пиксели - иста геометрија како цртежот.
          _fieldW = w;
          _fieldH = h;

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
                    : const RadialGradient(
                        radius: 1.2,
                        colors: [Color(0xFF07332A), Color(0xFF021612)],
                      ),
                borderRadius: BorderRadius.circular(26),
                // Рамка како кутија на стар осцилоскоп.
                border: Border.all(color: hc ? AccessibilityUtils.getContrastColor(context) : const Color(0xFF5B6B66), width: hc ? 4 : 6),
                boxShadow: hc ? null : [
                  const BoxShadow(color: Color(0xAA000000), blurRadius: 18, offset: Offset(0, 8)),
                  BoxShadow(color: _sonarGreen.withValues(alpha: 0.25), blurRadius: 30),
                ],
              ),
              child: Stack(
                children: [
                  // Терен: испрекината средна линија, светнат десен ѕид.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SonarPainter(
                          highContrast: hc,
                          t: _clock.elapsedMilliseconds,
                          ripples: List.of(_ripples),
                          guideMode: _playing ? _guideMode : 0,
                          guideVol: _guideMode == 1 ? _goodVol : (_guideMode == 2 ? _badVol : 0),
                        ),
                      ),
                    ),
                  ),
                  // Палка - подвижна, лево (без анимација на позиција,
                  // за да ја следи прецизно раката без задршка).
                  Positioned(
                    left: _paddleLeftPx,
                    top: (_paddleY * h) - paddleHeight / 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _paddleWidthPx,
                      height: paddleHeight,
                      decoration: BoxDecoration(
                        color: hc ? (_paddleFlash ? const Color(0xFFFFFF00) : Colors.white) : null,
                        gradient: hc
                            ? null
                            : LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: _paddleFlash
                                    ? [Colors.white, const Color(0xFFE6FFF3)]
                                    : [const Color(0xFFB8FFE0), _sonarGreen, const Color(0xFF0B8F5A)],
                              ),
                        borderRadius: BorderRadius.circular(9),
                        border: hc ? null : Border.all(color: Colors.white, width: 2),
                        boxShadow: hc
                            ? null
                            : [
                                BoxShadow(
                                  color: _sonarGreen.withValues(alpha: _paddleFlash ? 0.95 : 0.55),
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
                                  colors: [Colors.white, Color(0xFFE6FFF3), Color(0xFF7CF7C0)],
                                  stops: [0.0, 0.55, 1.0],
                                ),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: hc
                              ? null
                              : [
                                  BoxShadow(
                                    color: _sonarGreen.withValues(alpha: 0.85),
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
/// Еден бран од сонарот: каде се создал (0-1), кога (ms) и боја.
class _Ripple {
  _Ripple(this.pos, this.startMs, this.color);
  final Offset pos;
  final int startMs;
  final Color color;
}

/// Обележјето на Гласовен Понг: екран на **сонар / осцилоскоп**. Теренот е
/// зелен фосфорен екран со мрежа и линии на скенирање; секој отскок пушта
/// кружни бранови (како звукот што се шири); долу е бранова линија што
/// го црта звучниот водич - мазен зелен бран кога палката е на патот,
/// назабен црвен кога не е, рамна линија кога е тивко.
class _SonarPainter extends CustomPainter {
  _SonarPainter({
    required this.highContrast,
    required this.t,
    required this.ripples,
    required this.guideMode,
    required this.guideVol,
  });

  final bool highContrast;
  final int t;
  final List<_Ripple> ripples;
  final int guideMode;
  final double guideVol;

  static const Color _green = Color(0xFF39FF9A);
  static const Color _red = Color(0xFFFF4D5E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hc = highContrast;

    // Мрежа на осцилоскоп.
    final grid = Paint()
      ..color = hc ? Colors.white24 : _green.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    const cols = 10;
    const rows = 6;
    for (var i = 1; i < cols; i++) {
      final x = w * i / cols;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (var j = 1; j < rows; j++) {
      final y = h * j / rows;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    // Средна линија (испрекината) - половината на теренот.
    final dash = Paint()
      ..color = hc ? Colors.white54 : _green.withValues(alpha: 0.35)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var y = 10.0; y < h - 10; y += 22) {
      canvas.drawLine(Offset(w / 2, y), Offset(w / 2, math.min(h - 10, y + 10)), dash);
    }

    if (!hc) {
      // Ротирачки зрак на сонарот од средината (тивко, во позадина).
      final c = Offset(w / 2, h / 2);
      final r = math.max(w, h) * 0.75;
      final a = (t / 4000.0) * math.pi * 2;
      canvas.drawCircle(c, r * 0.32, Paint()..color = _green.withValues(alpha: 0.07)..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawCircle(c, r * 0.18, Paint()..color = _green.withValues(alpha: 0.07)..style = PaintingStyle.stroke..strokeWidth = 2);
      final sweep = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: r), a - 0.35, 0.35, false)
        ..close();
      canvas.drawPath(
        sweep,
        Paint()
          ..shader = SweepGradient(
            center: Alignment.center,
            startAngle: 0,
            endAngle: math.pi * 2,
            transform: GradientRotation(a - 0.35),
            colors: [_green.withValues(alpha: 0.0), _green.withValues(alpha: 0.10)],
            stops: const [0.0, 0.056],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      // Линии на скенирање и потемнети агли (CRT екран).
      final scan = Paint()..color = Colors.black.withValues(alpha: 0.12);
      for (var y = 0.0; y < h; y += 4) {
        canvas.drawRect(Rect.fromLTWH(0, y, w, 1.2), scan);
      }
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            radius: 0.95,
            colors: [Color(0x00000000), Color(0x88000000)],
            stops: [0.65, 1.0],
          ).createShader(rect),
      );
      // Светнат десен ѕид.
      final wall = Rect.fromLTWH(w - 10, 0, 10, h);
      canvas.drawRect(
        wall,
        Paint()
          ..shader = LinearGradient(colors: [_green.withValues(alpha: 0.0), _green.withValues(alpha: 0.45)]).createShader(wall),
      );
    }

    // Бранови од отскоците.
    for (final rp in ripples) {
      final age = (t - rp.startMs) / 700.0;
      if (age < 0 || age > 1) continue;
      final p = Offset(rp.pos.dx * w, rp.pos.dy * h);
      for (var k = 0; k < 2; k++) {
        final a2 = (age - k * 0.18).clamp(0.0, 1.0).toDouble();
        if (a2 <= 0) continue;
        canvas.drawCircle(
          p,
          16 + a2 * 70,
          Paint()
            ..color = (hc ? const Color(0xFFFFFF00) : rp.color).withValues(alpha: (1 - a2) * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    // Бранова линија на звучниот водич (долу).
    final baseY = h * 0.9;
    final amp = h * 0.05 * (0.4 + guideVol);
    final wave = Path()..moveTo(0, baseY);
    final phase = t / 180.0;
    for (var x = 0.0; x <= w; x += 4) {
      double y;
      if (guideMode == 1) {
        y = baseY + math.sin(x / 22 + phase) * amp;
      } else if (guideMode == 2) {
        // Назабен, нервозен бран.
        final saw = ((x / 14 + phase * 1.6) % 2.0) - 1.0;
        final jitter = math.sin(x * 1.7 + phase * 5) * 0.35;
        y = baseY + (saw + jitter) * amp;
      } else {
        y = baseY + math.sin(x / 30 + phase) * 1.5;
      }
      wave.lineTo(x, y);
    }
    final waveColor = hc
        ? (guideMode == 2 ? Colors.white : const Color(0xFFFFFF00))
        : (guideMode == 2 ? _red : (guideMode == 1 ? _green : _green.withValues(alpha: 0.35)));
    if (!hc && guideMode != 0) {
      canvas.drawPath(
        wave,
        Paint()
          ..color = waveColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = waveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = guideMode == 0 ? 2 : 3.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SonarPainter old) =>
      old.t != t || old.highContrast != highContrast || old.guideMode != guideMode || old.guideVol != guideVol || old.ripples.length != ripples.length;
}