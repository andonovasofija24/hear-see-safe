import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

/// Множител за големината на текстот на овој екран (поголеми букви).
const double _kRhythmText = 1.6;

/// Ритмичка игра: [Почни] -> [Пушти звук] -> откриваат се тапанот
/// [Удари], полето со бројот + [Потврди] и [Пушти звук повторно]. Секое притискање на "Удари" го зголемува бројот
/// прикажан на копчето "Потврди". Кога детето мисли дека тој број е точен,
/// притиска "Потврди" - тоа е конечниот одговор за таа рунда. Играта трае
/// вкупно 10 рунди, а на крајот се прикажува колку рунди се погодени.
class RhythmTapScreen extends StatefulWidget {
  const RhythmTapScreen({super.key});

  @override
  State<RhythmTapScreen> createState() => _RhythmTapScreenState();
}

class _RhythmTapScreenState extends State<RhythmTapScreen> {
  late VoiceAssistantService _voiceAssistant;
  /// Одделен плеер за говорни клипови (само за објаснувањето сега).
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратки звучни ефекти (удари, точно/грешно), за да не
  /// се прекинуваат меѓусебно кога се пуштаат близу еден до друг.
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final Random _random = Random();
  StreamSubscription? _completeSub;

  static const int _totalRounds = 10;

  /// Секој ударувачки mp3 си има свој ТОЧЕН број потребни тапкања. Прилагоди
  /// ги бројките тука според твоите вистински снимки, и додади нови
  /// инструменти по потреба.
  static const Map<String, int> _instrumentTapTargets = {
    'drum': 10,
    'wood': 7,
    'clap': 5,
    'heels': 9,
    'heart-beat': 16,
    'door-knock': 3,
  };
  static const List<String> _instruments = [
    'drum',
    'wood',
    'clap',
    'heels',
    'heart-beat',
    'door-knock',
  ];

  /// Временски моменти (во милисекунди од почеток на звукот) на секој
  /// удар - користени за да го засветат и вибрираат копчето точно кога се
  /// слуша ударот. Проценето според твоите описи; прилагоди ги ако не се
  /// совпаѓаат совршено со вистинските снимки.
  static const Map<String, List<int>> _instrumentBeatTimesMs = {
    'clap': [0, 1000, 2000, 3000, 4000],
    'door-knock': [0, 300, 600],
    'drum': [0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500],
    'heels': [0, 450, 1000, 1450, 2000, 2450, 3000, 3350, 3700],
    'wood': [0, 570, 1140, 1710, 2280, 2850, 3420],
    'heart-beat': [
      250, 400, 1500, 1650, 2750, 2900, 4000, 4150,
      5250, 5400, 6500, 6650, 7750, 7900, 9000, 9150,
    ],
  };

  String _currentInstrument = 'drum';
  final TextEditingController _tapController = TextEditingController();

  /// false = само копчето "Пушти звук" е видливо (без автоматско пуштање).
  /// true = откриени се полето за внес и "Потврди".
  bool _revealed = false;
  bool _isPlaying = false;
  /// Кратко трепкање на копчето, точно на секој удар - одделно од
  /// _isPlaying (кое трае цело време додека звукот свири).
  bool _flashPulse = false;
  int _pulseToken = 0;
  int _round = 0;
  int _hits = 0;
  bool _confirmLocked = false;
  bool _gameOver = false;
  bool _explanationOpen = false;

  /// Заклучено додека не се притисне СТАРТ - тогаш засекогаш се отклучува.
  bool _gameLocked = true;

  /// Обиди во тековната рунда - дозволени се вкупно 3 обиди пред рундата
  /// автоматски да продолжи натаму (без поен).
  int _attemptsThisRound = 0;
  static const int _maxAttempts = 3;

  /// Колку пати е пуштен звукот оваа рунда - "Пушти звук" смее само
  /// еднаш (го поставува на 1), "Пушти звук повторно" смее уште двапати
  /// (до вкупно 3).
  int _playCount = 0;
  static const int _maxPlays = 3;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _completeSub = _effectsPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
    _pickNewInstrument();
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _voiceAssistant.stop();
    _completeSub?.cancel();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _pickNewInstrument() {
    _tapController.clear();
    setState(() {
      _currentInstrument = _instruments[_random.nextInt(_instruments.length)];
      _revealed = false;
      _isPlaying = false;
      _confirmLocked = false;
      _attemptsThisRound = 0;
      _playCount = 0;
    });
  }

  /// СТАРТ - се притиска еднаш, ги отклучува сите останати копчиња засекогаш.
  void _startGame() {
    if (!_gameLocked) return;
    setState(() => _gameLocked = false);
  }

  /// Секое притискање го зголемува бројот во полето за внес - помош на
  /// детето да го следи ритамот со тапкање, без да мора рачно да пишува.
  void _onHelperTap() {
    if (_gameLocked || _confirmLocked) return;
    final current = int.tryParse(_tapController.text.trim()) ?? 0;
    setState(() => _tapController.text = (current + 1).toString());
    VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 40);
    });
  }

  /// Го трепка и вибрира копчето со звукот точно на секој удар - според
  /// времињата во _instrumentBeatTimesMs.
  Future<void> _runBeatPulses(String instrument) async {
    final beats = _instrumentBeatTimesMs[instrument];
    if (beats == null || beats.isEmpty) return;
    final myToken = ++_pulseToken;
    final hasVibrator = await VibrationUtils.hasVibrator();
    var lastTime = 0;
    for (final t in beats) {
      final wait = t - lastTime;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      lastTime = t;
      if (!mounted || myToken != _pulseToken) return;
      setState(() => _flashPulse = true);
      if (hasVibrator) {
        VibrationUtils.vibrate(duration: 90);
      }
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted || myToken != _pulseToken) return;
      setState(() => _flashPulse = false);
    }
  }

  /// Пробува однапред снимена звучна датотека (твоја снимка), а само ако
  /// не постои паѓа назад на системскиот text-to-speech. Само за говорни,
  /// СТАТИЧНИ фрази (само објаснувањето).
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/rhythm_tap/$_langCode/$key.mp3';
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

  /// Заедничка логика за реално пуштање на клипот + трепкање/вибрација.
  Future<void> _playSoundInternal() async {
    setState(() => _isPlaying = true);
    try {
      await _effectsPlayer.stop();
      await _effectsPlayer.play(AssetSource('sounds/rhythm/$_currentInstrument.mp3'));
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
    _runBeatPulses(_currentInstrument);
  }

  /// "Пушти звук" - смее да се притисне САМО ЕДНАШ по рунда. За да се
  /// слушне повторно, детето мора да го користи "Пушти звук повторно".
  Future<void> _playInstrumentSound() async {
    if (_gameLocked || _playCount != 0) return;
    setState(() {
      _playCount = 1;
      _revealed = true;
    });
    await _playSoundInternal();
  }

  /// "Пушти звук повторно" - смее да се притисне уште најмногу 2 пати
  /// (значи вкупно 3 пуштања по рунда, вклучувајќи го првото).
  Future<void> _playAgainSound() async {
    if (_gameLocked || _playCount == 0 || _playCount >= _maxPlays) return;
    setState(() => _playCount++);
    await _playSoundInternal();
  }

  /// "Потврди" - го потврдува впишаниот број како конечен одговор за оваа
  /// рунда. Заклучено додека трае обработката, за да не се смета двојно/
  /// тројно ако детето го притисне копчето повеќе пати додека чека.
  Future<void> _onConfirm() async {
    if (_confirmLocked || _gameLocked) return;
    _confirmLocked = true;

    final entered = int.tryParse(_tapController.text.trim()) ?? -1;
    final target = _instrumentTapTargets[_currentInstrument] ?? 1;
    final isCorrect = entered == target;

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: isCorrect ? 220 : 100);
    }

    if (isCorrect) {
      setState(() => _hits++);
      await _playClip('correct', 'rhythm.great'.tr());
      await Future.delayed(const Duration(milliseconds: 1000));
      _confirmLocked = false;
      if (!mounted) return;
      _nextRound();
      return;
    }

    // Неточно - дозволени вкупно 3 обиди по рунда пред автоматски да се
    // продолжи натаму (без поен за таа рунда).
    _attemptsThisRound++;
    await _playClip('incorrect', 'rhythm.incorrect'.tr());
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    if (_attemptsThisRound < _maxAttempts) {
      setState(() {
        _tapController.clear();
        _confirmLocked = false;
      });
    } else {
      _confirmLocked = false;
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
      _pickNewInstrument();
    }
  }

  void _restart() {
    setState(() {
      _round = 0;
      _hits = 0;
      _gameOver = false;
    });
    _pickNewInstrument();
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation', 'rhythm.explanation_text'.tr());
    } else {
      // Враќање кон играта: веднаш запри го говорот на објаснувањето.
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  // ===================================================================
  // Гласовни команди: бројот на удари („седум“, „7“), „потврди“,
  // „пушти“ / „пушти повторно“, „почни“, „избриши“. Може и заедно:
  // „седум потврди“ го внесува бројот и веднаш потврдува.
  // ===================================================================

  /// Броевите со зборови (мк / en / sq). Албанските се без „ë/ç“, бидејќи
  /// препознавањето понекогаш ги испушта - транскриптот се нормализира исто.
  static const Map<String, int> _numberWords = {
    // македонски
    'нула': 0, 'еден': 1, 'една': 1, 'едно': 1, 'два': 2, 'две': 2, 'три': 3,
    'четири': 4, 'пет': 5, 'шест': 6, 'седум': 7, 'осум': 8, 'девет': 9,
    'десет': 10, 'единаесет': 11, 'дванаесет': 12, 'тринаесет': 13,
    'четиринаесет': 14, 'петнаесет': 15, 'шеснаесет': 16, 'седумнаесет': 17,
    'осумнаесет': 18, 'деветнаесет': 19, 'дваесет': 20,
    // english
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
    // shqip
    'nje': 1, 'dy': 2, 'tre': 3, 'tri': 3, 'kater': 4, 'pese': 5,
    'gjashte': 6, 'shtate': 7, 'tete': 8, 'nente': 9, 'dhjete': 10,
    'njembedhjete': 11, 'dymbedhjete': 12, 'trembedhjete': 13,
    'katermbedhjete': 14, 'pesembedhjete': 15, 'gjashtembedhjete': 16,
    'shtatembedhjete': 17, 'tetembedhjete': 18, 'nentembedhjete': 19,
    'njezet': 20,
  };

  /// Англиски зборови што звучат како број - се прифаќаат само ако се
  /// единствениот збор во командата („to“ = 2, „for“ = 4, ...).
  static const Map<String, int> _soundAlikeNumbers = {
    'to': 2, 'too': 2, 'for': 4, 'fore': 4, 'won': 1, 'ate': 8, 'tree': 3,
  };

  static const List<String> _confirmWords = [
    'потврд', 'готово', 'confirm', 'done', 'konfirm', 'gati',
  ];
  static const List<String> _againWords = [
    'повторно', 'пак', 'again', 'repeat', 'perseri', 'serish',
  ];
  static const List<String> _playWords = [
    'пушти', 'слушни', 'слушај', 'play', 'listen', 'luaj', 'degjo',
  ];
  static const List<String> _startWords = [
    'почни', 'старт', 'start', 'begin', 'fillo',
  ];
  static const List<String> _clearWords = [
    'избриши', 'бриши', 'clear', 'delete', 'erase', 'fshi',
  ];

  /// Дејството што `_matchVoice` го пронашол - го извршува `_runVoice`.
  VoidCallback? _pendingVoice;

  static List<String> _voiceTokens(String t) {
    final clean = t
        .toLowerCase()
        .replaceAll('ë', 'e')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[.,!?;:„“"()]'), ' ')
        .trim();
    return clean.isEmpty ? const [] : clean.split(RegExp(r'\s+'));
  }

  static bool _hasWord(List<String> tokens, List<String> stems) =>
      tokens.any((tok) => stems.any(tok.startsWith));

  /// Првиот број во командата (цифри или збор), или null.
  static int? _spokenNumber(List<String> tokens) {
    for (final tok in tokens) {
      final digits = RegExp(r'^\d{1,3}$').firstMatch(tok);
      if (digits != null) return int.parse(digits.group(0)!);
      final n = _numberWords[tok];
      if (n != null) return n;
    }
    if (tokens.length == 1) return _soundAlikeNumbers[tokens.first];
    return null;
  }

  bool _matchVoice(String transcript) {
    _pendingVoice = null;
    if (_gameOver) return false;
    final tokens = _voiceTokens(transcript);
    if (tokens.isEmpty) return false;

    if (_gameLocked) {
      if (_hasWord(tokens, _startWords)) _pendingVoice = _startGame;
      return _pendingVoice != null;
    }

    final wantsAgain = _hasWord(tokens, _againWords);
    final wantsPlay = _hasWord(tokens, _playWords);
    if (wantsAgain || wantsPlay) {
      if (_playCount == 0) {
        _pendingVoice = _playInstrumentSound;
      } else if (_playCount < _maxPlays) {
        _pendingVoice = _playAgainSound;
      }
      return _pendingVoice != null;
    }

    // Бројот и потврдата важат само откако звукот е пуштен.
    if (!_revealed || _confirmLocked) return false;

    final number = _spokenNumber(tokens);
    final wantsConfirm = _hasWord(tokens, _confirmWords);
    if (number != null) {
      _pendingVoice = () {
        setState(() => _tapController.text = number.toString());
        if (wantsConfirm) _onConfirm();
      };
      return true;
    }
    if (_hasWord(tokens, _clearWords)) {
      _pendingVoice = () => setState(_tapController.clear);
      return true;
    }
    if (wantsConfirm) {
      _pendingVoice = _onConfirm;
      return true;
    }
    return false;
  }

  void _runVoice() {
    final action = _pendingVoice;
    _pendingVoice = null;
    action?.call();
  }

  List<VoiceCategoryOption> get _voiceOptions => [
        VoiceCategoryOption(keywords: const [], matches: _matchVoice, onSelected: _runVoice),
      ];

  /// Микрофонот не смее да го слуша објаснувањето.
  void _onVoiceListenStart() {
    _voiceAssistant.stop();
    _voicePlayer.stop();
  }

  static const Color _accent = Color(0xFFE11D48);

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

    return GameScreenChrome(
      accent: _accent,
      title: 'features.rhythm_tap'.tr(),
      voiceOptions: _voiceOptions,
      bodyBackground: const EmojiBackdrop(
        emojis: ['🥁', '👏', '🚪', '❤️', '👠', '🎵'],
        tint: _accent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
            final inner = constraints.maxWidth - side * 2;
            final header = <Widget>[
              PlayfulExplainButton(
                open: _explanationOpen,
                label: _explanationOpen
                    ? 'rhythm.explanation_toggle_close'.tr()
                    : 'rhythm.explanation_toggle_open'.tr(),
                onTap: _toggleExplanation,
              ),
              if (_explanationOpen)
                PlayfulExplainPanel(
                  icon: Icons.graphic_eq_rounded,
                  title: 'rhythm.explanation_title'.tr(),
                  text: 'rhythm.explanation_text'.tr(),
                  accent: _accent,
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
                            'rhythm.game_over_title'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.display(26 * _kRhythmText, color: fg),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: PlayfulResult(
                      text: 'rhythm.final_summary'.tr(args: [
                        _hits.toString(),
                        misses.toString(),
                        _totalRounds.toString(),
                      ]),
                      buttonLabel: 'rhythm.play_again'.tr(),
                      onAgain: _restart,
                      stars: _hits,
                      total: _totalRounds,
                    ),
                  ),
                ],
              );
            }

            final answerLocked = _gameLocked || !_revealed;
            final pad = _gated(answerLocked, _buildDrumPad(hc));
            final entry = _gated(answerLocked, _buildEntryCard(hc));

            return ListView(
              padding: EdgeInsets.fromLTRB(side, 12, side, 28),
              children: [
                ...header,
                RoundProgress(
                  label: 'rhythm.rounds_progress'.tr(args: [
                    (_round + 1).toString(),
                    _totalRounds.toString(),
                  ]),
                  current: _round,
                  total: _totalRounds,
                  extra: 'rhythm.score'.tr(args: [_hits.toString()]),
                ),
                const SizedBox(height: 22),
                // Чекор 1: Почни (само еднаш - потоа исчезнува).
                if (_gameLocked) ...[
                  Center(child: _buildStartButton(hc)),
                  const SizedBox(height: 22),
                ],
                // Чекор 2: слушај (Пушти звук + Пушти повторно, вкупно 3).
                _gated(_gameLocked, _buildListenStage(hc, fg)),
                const SizedBox(height: 24),
                // Чекор 3: тапан за броење + поле со бројот и Потврди.
                if (inner >= 760)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: pad),
                      const SizedBox(width: 16),
                      Expanded(child: entry),
                    ],
                  )
                else ...[
                  pad,
                  const SizedBox(height: 16),
                  entry,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Затемнето и недопирливо додека делот не е отклучен.
  Widget _gated(bool locked, Widget child) {
    return AbsorbPointer(
      absorbing: locked,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: locked ? 0.35 : 1.0,
        child: child,
      ),
    );
  }

  /// „Почни“ - широко златно копче што пулсира додека не се притисне.
  Widget _buildStartButton(bool hc) {
    final label = 'rhythm.start_button'.tr();
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: RippleRings(
          color: hc ? Colors.white : Playful.sun,
          active: true,
          spread: 16,
          child: PressableScale(
            child: Material(
              color: hc ? Colors.black : Playful.sun,
              borderRadius: BorderRadius.circular(40),
              child: InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: _startGame,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white, width: hc ? 3 : 4),
                    boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 22)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 44, color: hc ? Colors.white : Playful.ink),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Playful.display(24 * _kRhythmText, color: hc ? Colors.white : Playful.ink),
                        ),
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

  /// Големиот круг „Пушти звук“ (трепка на секој удар), помал круг
  /// „Пушти повторно“ и три звучници што покажуваат колку пуштања остануваат.
  Widget _buildListenStage(bool hc, Color fg) {
    final canPlayFirst = _playCount == 0;
    final canPlayAgain = _playCount > 0 && _playCount < _maxPlays;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 36,
          runSpacing: 20,
          children: [
            _gated(
              !canPlayFirst && !_isPlaying,
              AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: _flashPulse ? 1.12 : 1.0,
                child: SoundOrb(
                  icon: Icons.volume_up_rounded,
                  label: 'rhythm.play_button'.tr(),
                  onTap: canPlayFirst ? _playInstrumentSound : null,
                  active: _isPlaying,
                  size: 130,
                ),
              ),
            ),
            _gated(
              !canPlayAgain,
              SoundOrb(
                icon: Icons.replay_rounded,
                label: 'rhythm.play_again_button'.tr(),
                onTap: canPlayAgain ? _playAgainSound : null,
                size: 92,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          label: '$_playCount/$_maxPlays',
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _maxPlays; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _playCount
                            ? (hc ? Colors.white24 : Colors.white.withValues(alpha: 0.12))
                            : (hc ? Colors.black : Playful.sun),
                        border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.7), width: 2),
                      ),
                      child: Icon(
                        i < _playCount ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        size: 20,
                        color: i < _playCount ? fg.withValues(alpha: 0.6) : (hc ? Colors.white : Playful.ink),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text('$_playCount/$_maxPlays', style: Playful.title(18 * _kRhythmText, color: fg)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Темна картичка со бел раб - подлога за тапанот и за полето за број.
  BoxDecoration _cardDecoration(bool hc) {
    return BoxDecoration(
      color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.5), width: hc ? 2 : 2.5),
      boxShadow: hc ? null : [BoxShadow(color: _accent.withValues(alpha: 0.3), blurRadius: 18)],
    );
  }

  /// Тапанот: голема тркалезна плоча - секој допир е еден удар (+1).
  Widget _buildDrumPad(bool hc) {
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    final label = 'rhythm.hit_button'.tr();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(hc),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'rhythm.helper_explanation'.tr(),
            textAlign: TextAlign.center,
            style: Playful.body(15.5 * _kRhythmText, color: fg),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: label,
            button: true,
            child: ExcludeSemantics(
              child: PressableScale(
                child: GestureDetector(
                  onTap: _onHelperTap,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : null,
                      gradient: hc
                          ? null
                          : const RadialGradient(
                              colors: [Color(0xFFFB7185), _accent, Color(0xFF881337)],
                              stops: [0.0, 0.6, 1.0],
                            ),
                      border: Border.all(color: hc ? Colors.white : Playful.sun, width: hc ? 3 : 6),
                      boxShadow: hc
                          ? null
                          : [
                              BoxShadow(color: _accent.withValues(alpha: 0.55), blurRadius: 26),
                              const BoxShadow(color: Color(0xFF4C0519), offset: Offset(0, 8)),
                            ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.back_hand_rounded, size: 76, color: Colors.white),
                        const SizedBox(height: 4),
                        // Тапанот е со фиксна големина - натписот се смалува ако не собира.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, style: Playful.display(24 * _kRhythmText, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Бројот на удари (може и рачно) + преостанати обиди + „Потврди“.
  Widget _buildEntryCard(bool hc) {
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    final attemptsLeft = (_maxAttempts - _attemptsThisRound).clamp(0, _maxAttempts);
    final confirmLabel = 'rhythm.confirm_button'.tr();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(hc),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'rhythm.entry_explanation'.tr(),
            textAlign: TextAlign.center,
            style: Playful.body(15.5 * _kRhythmText, color: fg),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'rhythm.enter_taps_label'.tr(),
            textField: true,
            child: TextField(
              controller: _tapController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: false,
              style: Playful.display(44 * 1.3, color: hc ? Colors.white : Playful.ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: hc ? Colors.black : Colors.white,
                hintText: '0',
                hintStyle: Playful.display(44 * 1.3, color: (hc ? Colors.white : Playful.ink).withValues(alpha: 0.25)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: hc ? Colors.white : Playful.sun, width: 3),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: hc ? const Color(0xFFFFFF00) : _accent, width: 4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Преостанати обиди во рундата (срца).
          Semantics(
            label: '$attemptsLeft/$_maxAttempts',
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _maxAttempts; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        i < attemptsLeft ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 36,
                        color: i < attemptsLeft
                            ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFFB7185))
                            : fg.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildVoiceRow(hc, fg),
          const SizedBox(height: 14),
          Semantics(
            label: confirmLabel,
            button: !_confirmLocked,
            child: ExcludeSemantics(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _confirmLocked ? 0.5 : 1.0,
                child: PressableScale(
                  enabled: !_confirmLocked,
                  child: Material(
                    color: hc ? Colors.black : const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _confirmLocked ? null : _onConfirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: hc ? 2 : 3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 36, color: Colors.white),
                            const SizedBox(width: 10),
                            Flexible(child: Text(confirmLabel, textAlign: TextAlign.center, style: Playful.title(20 * _kRhythmText, color: Colors.white))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Златно копче за глас + потсетник што може да се каже.
  Widget _buildVoiceRow(bool hc, Color fg) {
    return Column(
      children: [
        CategoryVoiceCommandButton(
          options: _voiceOptions,
          onListenStart: _onVoiceListenStart,
          respondToHotkey: true,
          compact: true,
          background: hc ? null : Playful.sun,
          foreground: hc ? null : Playful.ink,
        ),
        const SizedBox(height: 8),
        Text(
          'rhythm.voice_hint'.tr(),
          textAlign: TextAlign.center,
          style: Playful.body(14.5 * _kRhythmText, color: hc ? fg : Colors.white.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}