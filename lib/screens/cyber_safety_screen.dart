import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/utils/voice_level.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';

enum _View { modeSelect, phishing, phishingResult, quiz, quizResult, password, agent, agentResult }

class _ScamMessage {
  final String textKey;
  final String senderKey;
  final bool isSafe;
  const _ScamMessage({required this.textKey, required this.senderKey, required this.isSafe});
}

class CyberSafetyQuestion {
  final String question;
  final List<String> options;
  final int correctAnswer;
  final String explanation;

  CyberSafetyQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });
}

class CyberSafetyScreen extends StatefulWidget {
  const CyberSafetyScreen({super.key});

  @override
  State<CyberSafetyScreen> createState() => _CyberSafetyScreenState();
}

class _CyberSafetyScreenState extends State<CyberSafetyScreen> {
  static const Color _moduleAccent = Color(0xFFDC2626);
  static const int _phishingRounds = 6;

  /// Единствен плеер за говорни/наративни снимки (прашања, пораки,
  /// објаснувања). НЕМА системски text-to-speech ниту резерва на TTS во
  /// целиот овој екран - ако снимка недостасува, тивко не се пушта ништо
  /// (намерно, по барање: играта работи ИСКЛУЧИВО со сопствени mp3 снимки).
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратките звучни ефекти (точно/погрешно).
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final Random _random = Random();

  _View _view = _View.modeSelect;
  int _narrationToken = 0;

  String get _langCode => context.locale.languageCode;

  // --- Пораки за "Волк во овча кожа" ---
  static const List<_ScamMessage> _messages = [
    _ScamMessage(textKey: 'cyber.msg_safe1', senderKey: 'cyber.sender_safe1', isSafe: true),
    _ScamMessage(textKey: 'cyber.msg_safe2', senderKey: 'cyber.sender_safe2', isSafe: true),
    _ScamMessage(textKey: 'cyber.msg_safe3', senderKey: 'cyber.sender_safe3', isSafe: true),
    _ScamMessage(textKey: 'cyber.msg_danger1', senderKey: 'cyber.sender_danger1', isSafe: false),
    _ScamMessage(textKey: 'cyber.msg_danger2', senderKey: 'cyber.sender_danger2', isSafe: false),
    _ScamMessage(textKey: 'cyber.msg_danger3', senderKey: 'cyber.sender_danger3', isSafe: false),
  ];

  List<_ScamMessage> _phishingRoundList = [];
  int _phishingIndex = 0;
  int _phishingScore = 0;
  bool _phishingLocked = false;
  bool? _phishingPickedSafe;
  bool? _phishingPickedCorrect;

  // --- Квиз ---
  late final List<CyberSafetyQuestion> _questions = [
    CyberSafetyQuestion(
      question: 'cyber.question1'.tr(),
      options: ['cyber.option1a'.tr(), 'cyber.option1b'.tr(), 'cyber.option1c'.tr()],
      correctAnswer: 0,
      explanation: 'cyber.explanation1'.tr(),
    ),
    CyberSafetyQuestion(
      question: 'cyber.question2'.tr(),
      options: ['cyber.option2a'.tr(), 'cyber.option2b'.tr(), 'cyber.option2c'.tr()],
      correctAnswer: 1,
      explanation: 'cyber.explanation2'.tr(),
    ),
    CyberSafetyQuestion(
      question: 'cyber.question3'.tr(),
      options: ['cyber.option3a'.tr(), 'cyber.option3b'.tr(), 'cyber.option3c'.tr()],
      correctAnswer: 0,
      explanation: 'cyber.explanation3'.tr(),
    ),
    CyberSafetyQuestion(
      question: 'cyber.question4'.tr(),
      options: ['cyber.option4a'.tr(), 'cyber.option4b'.tr(), 'cyber.option4c'.tr()],
      correctAnswer: 1,
      explanation: 'cyber.explanation4'.tr(),
    ),
  ];

  int _quizIndex = 0;
  /// Колку е „отклучено“ од тековното прашање (како кај „Приказна - твој
  /// избор“): 0 = ништо, 1 = прашањето, 2 = + опција 1, 3 = + опција 2,
  /// 4 = + опција 3. Опцијата станува допирлива откако ќе се прочита.
  int _quizUnlocked = 0;
  /// Која опција моментално се чита (за нагласување), или null.
  int? _quizReadingOption;
  int _quizScore = 0;
  int? _quizPicked;
  bool _quizShowingExplanation = false;

  // --- Изгради го замокот (сила на лозинка) ---
  int _castleLength = 0;
  final Set<String> _castleCategories = {};
  int _castleLevel = -1; // -1 = ништо сè уште, 0=слаб, 1=среден, 2=силен
  /// Пораката што последна е изговорена (и се прикажува на екранот) -
  /// 'cyber.castle_medium_msg' / 'cyber.castle_strong_msg', или null.
  String? _castleMessageKey;

  // --- Таен агент (социјален инженеринг) ---
  static const List<String> _agentQuestionKeys = [
    'cyber.agent_q1', 'cyber.agent_q2', 'cyber.agent_q3',
    'cyber.agent_q4', 'cyber.agent_q5', 'cyber.agent_q6',
  ];
  List<String> _agentRoundList = [];
  int _agentIndex = 0;
  int _agentScore = 0;
  bool _agentLocked = false;
  bool? _agentPickedRefuse;

  // --- Објаснување на почетокот на секоја игра ---
  /// Клучот на објаснувањето за тековната игра ('cyber.intro_...').
  String? _introKey;
  /// Ја поставува играта: објаснувањето (само текст на екранот) и
  /// првото прашање / порака.
  void _beginGame(String introKey, Future<void> Function()? announce) {
    setState(() => _introKey = introKey);
    if (announce != null) announce();
  }

  /// Прекинува сè што се изговара (пред одговор или гласовна команда).
  void _stopNarration() {
    _narrationToken++;
    _voicePlayer.stop();
    VoiceLevel.speaking.value = false;
  }

  @override
  void dispose() {
    VoiceLevel.speaking.value = false;
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    super.dispose();
  }

  /// ПРАВИЛО: секоја снимка се вика ТОЧНО како клучот на текстот што стои
  /// на екранот, без 'cyber.' (пр. текстот 'cyber.msg_danger1' ->
  /// audio/cyber_safety/<јазик>/msg_danger1.mp3). Така текстот на екранот и
  /// снимката секогаш се иста реченица. Целосен список: docs/cyber_snimki.md.
  String _audioKey(String translationKey) =>
      translationKey.startsWith('cyber.') ? translationKey.substring(6) : translationKey;

  /// Пушта една однапред снимена mp3 датотека (по јазик) и чека да заврши.
  /// НЕМА резерва на текст-до-говор - ако снимката недостасува или не може
  /// да се пушти, тивко не се случува ништо (намерно, по барање на
  /// корисникот: играта работи исклучиво со сопствени mp3 снимки, никогаш
  /// со системски глас).
  Future<void> _speak(String key) async {
    if (!mounted) return;
    final relativePath = 'audio/cyber_safety/$_langCode/$key.mp3';
    try {
      await _voicePlayer.stop();
    } catch (_) {}

    final finishedCompleter = Completer<void>();
    late final StreamSubscription<PlayerState> stateSub;
    stateSub = _voicePlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (!finishedCompleter.isCompleted) finishedCompleter.complete();
      }
    });

    try {
      await _voicePlayer.play(AssetSource(relativePath));
      await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    } catch (_) {
      // Снимката недостасува - намерно тивко, без резерва на говор.
    }
    await stateSub.cancel();
  }

  /// hit.mp3 / miss.mp3 од Гласовен Понг - без потреба од нови снимки.
  Future<void> _playPongEffect(String fileName) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  void _backToModeSelect() {
    _stopNarration();
    setState(() {
      _view = _View.modeSelect;
      _introKey = null;
    });
  }

  // =====================================================================
  // Волк во овча кожа (препознавање фишинг).
  // =====================================================================

  void _startPhishing() {
    _narrationToken++;
    final pool = List<_ScamMessage>.from(_messages)..shuffle(_random);
    setState(() {
      _phishingRoundList = pool.take(_phishingRounds).toList();
      _phishingIndex = 0;
      _phishingScore = 0;
      _phishingLocked = false;
      _phishingPickedSafe = null;
      _phishingPickedCorrect = null;
      _view = _View.phishing;
    });
    _beginGame('cyber.intro_phishing', _announcePhishingMessage);
  }

  Future<void> _announcePhishingMessage() async {
    final myToken = ++_narrationToken;
    final msg = _phishingRoundList[_phishingIndex];
    await _speak(_audioKey('cyber.phishing_prompt'));
    if (myToken != _narrationToken || !mounted) return;
    await _speak(_audioKey(msg.textKey));
  }

  Future<void> _answerPhishing(bool pickedSafe) async {
    if (_phishingLocked) return;
    _stopNarration();
    final msg = _phishingRoundList[_phishingIndex];
    final correct = pickedSafe == msg.isSafe;
    setState(() {
      _phishingLocked = true;
      _phishingPickedSafe = pickedSafe;
      _phishingPickedCorrect = correct;
    });

    if (await VibrationUtils.hasVibrator()) {
      if (correct) {
        await VibrationUtils.vibrate(duration: 200);
      } else {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
    }
    if (!mounted || _view != _View.phishing) return;
    if (correct) {
      setState(() => _phishingScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 1100));
    // Детето можеби веќе отишло во друга игра.
    if (!mounted || _view != _View.phishing) return;

    final next = _phishingIndex + 1;
    if (next >= _phishingRoundList.length) {
      setState(() => _view = _View.phishingResult);
      await _speak(_audioKey('cyber.phishing_done'));
    } else {
      setState(() {
        _phishingIndex = next;
        _phishingLocked = false;
        _phishingPickedSafe = null;
        _phishingPickedCorrect = null;
      });
      _announcePhishingMessage();
    }
  }

  // =====================================================================
  // Изгради го замокот (сила на лозинка).
  // =====================================================================

  void _startCastle() {
    _narrationToken++;
    setState(() {
      _castleLength = 0;
      _castleCategories.clear();
      _castleLevel = -1;
      _castleMessageKey = null;
      _view = _View.password;
    });
    _beginGame('cyber.intro_castle', null);
    _speak(_audioKey('cyber.castle_intro'));
  }

  int _computeCastleLevel() {
    final cats = _castleCategories.length;
    if (cats >= 3 && _castleLength >= 8) return 2; // силен
    if (cats >= 2 && _castleLength >= 4) return 1; // среден
    return 0; // слаб
  }

  Future<void> _addIngredient(String category) async {
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 60);
    }
    if (!mounted) return;
    setState(() {
      _castleLength++;
      _castleCategories.add(category);
    });
    final newLevel = _computeCastleLevel();
    if (newLevel != _castleLevel) {
      setState(() => _castleLevel = newLevel);
      if (newLevel == 2) {
        if (await VibrationUtils.hasVibrator()) {
          await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150, 100, 250]);
        }
        await _playPongEffect('hit.mp3');
        if (!mounted) return;
        setState(() => _castleMessageKey = 'cyber.castle_strong_msg');
        await _speak(_audioKey('cyber.castle_strong_msg'));
      } else if (newLevel == 1) {
        setState(() => _castleMessageKey = 'cyber.castle_medium_msg');
        await _speak(_audioKey('cyber.castle_medium_msg'));
      }
    }
  }

  void _resetCastle() {
    setState(() {
      _castleLength = 0;
      _castleCategories.clear();
      _castleLevel = -1;
      _castleMessageKey = null;
    });
    _speak(_audioKey('cyber.castle_intro'));
  }

  // =====================================================================
  // Таен агент (социјален инженеринг).
  // =====================================================================

  void _startAgent() {
    _narrationToken++;
    final pool = List<String>.from(_agentQuestionKeys)..shuffle(_random);
    setState(() {
      _agentRoundList = pool;
      _agentIndex = 0;
      _agentScore = 0;
      _agentLocked = false;
      _agentPickedRefuse = null;
      _view = _View.agent;
    });
    _beginGame('cyber.intro_agent', _announceAgentQuestion);
  }

  Future<void> _announceAgentQuestion() async {
    final myToken = ++_narrationToken;
    await _speak(_audioKey('cyber.agent_prompt'));
    if (myToken != _narrationToken || !mounted) return;
    await _speak(_audioKey(_agentRoundList[_agentIndex]));
  }

  Future<void> _answerAgent(bool refused) async {
    if (_agentLocked) return;
    _stopNarration();
    // Точниот одговор е секогаш да се одбие - никогаш не се дели лична
    // информација со непознат.
    final correct = refused;
    setState(() {
      _agentLocked = true;
      _agentPickedRefuse = refused;
    });

    if (await VibrationUtils.hasVibrator()) {
      if (correct) {
        await VibrationUtils.vibrate(duration: 200);
      } else {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
    }
    if (!mounted || _view != _View.agent) return;
    if (correct) {
      setState(() => _agentScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted || _view != _View.agent) return;

    final next = _agentIndex + 1;
    if (next >= _agentRoundList.length) {
      setState(() => _view = _View.agentResult);
      await _speak(_audioKey('cyber.agent_done'));
    } else {
      setState(() {
        _agentIndex = next;
        _agentLocked = false;
        _agentPickedRefuse = null;
      });
      _announceAgentQuestion();
    }
  }

  // =====================================================================
  // Квиз.
  // =====================================================================

  void _startQuiz() {
    _narrationToken++;
    setState(() {
      _quizIndex = 0;
      _quizUnlocked = 0;
      _quizReadingOption = null;
      _quizScore = 0;
      _quizPicked = null;
      _quizShowingExplanation = false;
      _view = _View.quiz;
    });
    _beginGame('cyber.intro_quiz', _announceQuizQuestion);
  }

  /// Прво се отклучува и чита прашањето, па опциите една по една - секоја
  /// станува допирлива откако ќе се прочита (исто како кај „Приказна - твој
  /// избор“).
  Future<void> _announceQuizQuestion() async {
    final myToken = ++_narrationToken;
    setState(() {
      _quizUnlocked = 1;
      _quizReadingOption = null;
    });
    await _speak('question${_quizIndex + 1}');
    if (myToken != _narrationToken || !mounted) return;
    const letters = ['a', 'b', 'c'];
    for (var i = 0; i < letters.length; i++) {
      if (myToken != _narrationToken || !mounted) return;
      setState(() => _quizReadingOption = i);
      await _speak('option${_quizIndex + 1}${letters[i]}');
      if (myToken != _narrationToken || !mounted) return;
      setState(() {
        _quizUnlocked = i + 2;
        _quizReadingOption = null;
      });
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Ако детето сака да го слушне прашањето уште еднаш.
  void _repeatQuizQuestion() {
    if (_quizPicked != null) return;
    _voicePlayer.stop();
    _announceQuizQuestion();
  }

  Future<void> _selectQuizAnswer(int index, {bool fromVoice = false}) async {
    if (_quizPicked != null || (!fromVoice && index + 2 > _quizUnlocked)) return;
    // Прекини го читањето штом е избран одговор.
    _narrationToken++;
    _voicePlayer.stop();
    final q = _questions[_quizIndex];
    final correct = index == q.correctAnswer;
    setState(() => _quizPicked = index);

    if (await VibrationUtils.hasVibrator()) {
      if (correct) {
        await VibrationUtils.vibrate(duration: 200);
      } else {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
    }
    if (!mounted || _view != _View.quiz) return;
    if (correct) {
      setState(() => _quizScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || _view != _View.quiz) return;
    setState(() => _quizShowingExplanation = true);
    // Објаснувањето што се прикажува се и изговара (explanationN.mp3).
    _narrationToken++;
    await _speak('explanation${_quizIndex + 1}');
  }

  void _quizContinue() {
    _narrationToken++;
    _voicePlayer.stop();
    final next = _quizIndex + 1;
    if (next >= _questions.length) {
      setState(() => _view = _View.quizResult);
      _speak(_audioKey('cyber.quiz_done'));
    } else {
      setState(() {
        _quizIndex = next;
        _quizUnlocked = 0;
        _quizReadingOption = null;
        _quizPicked = null;
        _quizShowingExplanation = false;
      });
      _announceQuizQuestion();
    }
  }

  // =====================================================================
  // Build.
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.cyber_safety'.tr(),
      titleFontSize: 26,
      // Секој поглед има свое (жолто) копче за глас - со одговорите на
      // играта, имињата на другите режими и „назад“.
      voiceCommand: false,
      // Ноќна позадина со штитови, катанци и клучеви што лебдат.
      bodyBackground: const EmojiBackdrop(
        emojis: ['🛡️', '🔒', '🔑', '✉️', '🏰', '🕵️'],
        tint: Color(0xFF0891B2),
      ),
      child: SafeArea(
        child: Builder(
          builder: (context) {
            switch (_view) {
              case _View.modeSelect:
                return _buildModeSelect(context);
              case _View.phishing:
                return _buildPhishing(context);
              case _View.phishingResult:
                return _buildPhishingResult(context);
              case _View.quiz:
                return _buildQuiz(context);
              case _View.quizResult:
                return _buildQuizResult(context);
              case _View.password:
                return _buildCastle(context);
              case _View.agent:
                return _buildAgent(context);
              case _View.agentResult:
                return _buildAgentResult(context);
            }
          },
        ),
      ),
    );
  }

  // --- Избор на режим ---
  //
  // Изглед: ноќната позадина на апликацијата + неонски „терминален“ белег
  // на кибер-играта (моноспејс наслови, тиркизен сјај). Картичките се во
  // бојата на играта, со реден број (може да се каже „прва“, „втора“...) и
  // кусото објаснување на играта.

  static const Color _neon = Color(0xFF22D3EE);
  static const Color _gold = Color(0xFFFFC93C);

  Color _fg(bool hc, Color contrast) => hc ? contrast : Colors.white;

  /// Целата ширина (лизгачот скроз десно), содржината во средина до 860.
  Widget _page(List<Widget> Function(double side) children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 860) / 2).clamp(20.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 12, side, 32),
          children: children(side),
        );
      },
    );
  }

  /// Неонски „терминален“ наслов.
  Widget _terminalTitle(String text, IconData icon, bool hc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: hc ? Colors.black : const Color(0xFF0B0F19).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hc ? Colors.white : _neon, width: 2),
        boxShadow: hc ? null : [BoxShadow(color: _neon.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 1)],
      ),
      child: Row(
        children: [
          Icon(icon, color: hc ? Colors.white : _neon, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '> $text',
              style: TextStyle(fontFamily: 'monospace', fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: hc ? Colors.white : _neon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelect(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final modes = [
      (Icons.mail_lock_rounded, 'cyber.mode_phishing', 'cyber.intro_phishing', _startPhishing, const Color(0xFFC2410C)),
      (Icons.quiz_rounded, 'cyber.mode_quiz', 'cyber.intro_quiz', _startQuiz, const Color(0xFF6D28D9)),
      (Icons.castle_rounded, 'cyber.mode_password', 'cyber.intro_castle', _startCastle, const Color(0xFF047857)),
      (Icons.theater_comedy_rounded, 'cyber.mode_agent', 'cyber.intro_agent', _startAgent, const Color(0xFFBE185D)),
    ];
    return _page((side) => [
          PopIn(index: 0, child: _terminalTitle('cyber.choose_mode'.tr(), Icons.security_rounded, hc)),
          const SizedBox(height: 18),
          Center(
            child: CategoryVoiceCommandButton(
              options: _modeVoiceOptions(),
              onBack: () => Navigator.of(context).pop(),
              background: hc ? null : _gold,
              foreground: hc ? null : Playful.ink,
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < modes.length; i++) ...[
            PopIn(
              index: 1 + i,
              child: _modeCard(
                context,
                number: i + 1,
                icon: modes[i].$1,
                label: modes[i].$2.tr(),
                desc: modes[i].$3.tr(),
                onTap: modes[i].$4,
                accent: modes[i].$5,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ]);
  }

  /// Редни броеви (mk/en/sq) за картичките во менито - се бара цел збор, за
  /// „два“ да не се фати во друг збор.
  static const List<List<String>> _ordinalWords = [
    ['прва', 'прво', 'први', 'прв', 'првата', 'првиот', 'pari', 'para', '1', 'еден', 'една', 'first', 'one', 'parë', 'pare', 'një', 'nje'],
    ['втора', 'второ', 'втори', 'втор', 'втората', 'вториот', 'dyti', 'dyta', '2', 'два', 'две', 'second', 'two', 'dytë', 'dyte', 'dy'],
    ['трета', 'трето', 'трети', 'трет', 'третата', 'третиот', 'treti', 'treta', '3', 'три', 'third', 'three', 'tretë', 'trete', 'tre'],
    ['четврта', 'четврто', 'четврти', 'четвртата', '4', 'четири', 'fourth', 'four', 'katërt', 'katert', 'katër', 'kater'],
  ];

  /// Гласовни опции за режимите. Во менито се препознава и редниот број
  /// („прва“, „2“...); од внатре во некој режим (копчето горе десно) - само
  /// имињата, за директно префрлање од режим во режим.
  List<VoiceCategoryOption> _modeVoiceOptions({bool ordinals = true}) => [
      if (ordinals) ...[
        // По реден број на картичката: „прва/1“ ... „четврта/4“.
        VoiceCategoryOption(keywords: const [], matches: (t) => _saysOrdinal(t, 0), onSelected: _startPhishing),
        VoiceCategoryOption(keywords: const [], matches: (t) => _saysOrdinal(t, 1), onSelected: _startQuiz),
        VoiceCategoryOption(keywords: const [], matches: (t) => _saysOrdinal(t, 2), onSelected: _startCastle),
        VoiceCategoryOption(keywords: const [], matches: (t) => _saysOrdinal(t, 3), onSelected: _startAgent),
      ],
      // Секоја категорија се препознава по кој било збор од нејзиното
      // име (и со/без член), на трите јазици.
      VoiceCategoryOption(
        keywords: const [
          'волк во овча кожа', 'волк', 'волкот', 'овча', 'кожа', 'фишинг', 'пораки', 'порака',
          "wolf in sheep", 'wolf', 'sheep', 'phishing', 'messages',
          'ujku me lëkurë', 'ujku', 'ujk', 'delje', 'lëkurë', 'lekure', 'mesazh',
        ],
        onSelected: _startPhishing,
      ),
      VoiceCategoryOption(
        keywords: const [
          'квиз', 'квизот', 'квис', 'кфиз', 'квиц', 'квез', 'кваз', 'тест', 'прашања',
          'quiz', 'quizz', 'quis', 'kwiz', 'kvis', 'quest', 'test',
          'kuiz', 'kuizi', 'kviz', 'kuis', 'pyetje',
        ],
        onSelected: _startQuiz,
      ),
      VoiceCategoryOption(
        keywords: const [
          'изгради го замокот', 'изгради', 'замок', 'замокот', 'лозинк',
          'build the castle', 'castle', 'build', 'password',
          'ndërto kështjellën', 'ndërto', 'nderto', 'kështjell', 'keshtjell', 'kshtjell', 'fjalëkalim', 'fjalekalim',
        ],
        onSelected: _startCastle,
      ),
      VoiceCategoryOption(
        keywords: const [
          'таен агент', 'тајниот агент', 'тајен агент', 'таен', 'агент', 'агентот',
          'secret agent', 'secret', 'agent',
          'agjenti sekret', 'agjent', 'sekret',
        ],
        onSelected: _startAgent,
      ),
    ];

  // --- Гласовни одговори во играта ---

  /// Дали транскриптот содржи некој од зборовите (цел збор или почеток на
  /// збор, за облици како „безбедна“, „одбивам“).
  static bool _saysAny(String t, List<String> words) {
    final clean = t.toLowerCase().replaceAll(RegExp(r'[.,!?„“"]'), ' ');
    for (final w in words) {
      if (w.contains(' ')) {
        if (clean.contains(w)) return true;
      } else if (clean.split(RegExp(r'\s+')).any((x) => x.startsWith(w))) {
        return true;
      }
    }
    return false;
  }

  static const List<String> _kwUnsafe = [
    'небезбед', 'не е безбед', 'не безбед', 'опасн', 'unsafe', 'not safe', "isn't safe", 'danger',
    'pasigurt', 'nuk është i sigurt', 'nuk eshte i sigurt', 'jo i sigurt', 'rrezik',
  ];
  static const List<String> _kwSafe = ['безбед', 'сигурн', 'safe', 'sigurt'];
  static const List<String> _kwRefuse = [
    'одбиј', 'одбив', 'одбие', 'не одговар', 'нема да одговор', 'не одговор',
    'refuse', 'decline', 'reject', "don't answer", 'not answer', "won't answer", 'no answer',
    'refuzo', 'refuzoj', 'nuk përgjigj', 'nuk pergjigj', 'mos përgjigj',
  ];
  static const List<String> _kwAnswer = ['одговор', 'одговар', 'answer', 'reply', 'përgjigj', 'pergjigj'];
  static const List<String> _kwRepeat = ['повтори', 'пак', 'слушни', 'repeat', 'again', 'listen', 'përsërit', 'perserit', 'dëgjo', 'degjo'];

  /// Опциите за копчето за глас во тековниот поглед: одговорите на играта,
  /// па имињата на другите режими.
  List<VoiceCategoryOption> _gameVoiceOptions() {
    final opts = <VoiceCategoryOption>[];
    switch (_view) {
      case _View.phishing:
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwRepeat), onSelected: () {
          if (!_phishingLocked) _announcePhishingMessage();
        }));
        // „Небезбедно“ го содржи „безбедно“ - затоа прво се проверува опасно.
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwUnsafe), onSelected: () => _answerPhishing(false)));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwSafe), onSelected: () => _answerPhishing(true)));
        break;
      case _View.agent:
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwRepeat), onSelected: () {
          if (!_agentLocked) _announceAgentQuestion();
        }));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwRefuse), onSelected: () => _answerAgent(true)));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, _kwAnswer), onSelected: () => _answerAgent(false)));
        break;
      case _View.quiz:
        opts.add(VoiceCategoryOption(
          keywords: const [],
          matches: (t) => _quizShowingExplanation && _saysAny(t, const ['продолж', 'следн', 'continue', 'next', 'vazhdo', 'tjetr']),
          onSelected: _quizContinue,
        ));
        opts.add(VoiceCategoryOption(
          keywords: const [],
          matches: (t) => _saysAny(t, const ['повтори', 'пак', 'repeat', 'again', 'përsërit', 'perserit']),
          onSelected: _repeatQuizQuestion,
        ));
        // Прво редните броеви за сите три (за „a third one“ да не се фати
        // како „a“), па буквите.
        for (var i = 0; i < 3; i++) {
          final index = i;
          opts.add(VoiceCategoryOption(
            keywords: const [],
            matches: (t) => _saysOrdinal(t, index),
            onSelected: () => _selectQuizAnswer(index, fromVoice: true),
          ));
        }
        for (var i = 0; i < 3; i++) {
          final index = i;
          opts.add(VoiceCategoryOption(
            keywords: const [],
            matches: (t) => _saysWord(t, _quizLetterWords[index]),
            onSelected: () => _selectQuizAnswer(index, fromVoice: true),
          ));
        }
        break;
      case _View.password:
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, const ['почни', 'одново', 'start over', 'reset', 'fillo']), onSelected: _resetCastle));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, const ['мали', 'lowercase', 'lower', 'small', 'vogla']), onSelected: () => _addIngredient('lower')));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, const ['големи', 'uppercase', 'upper', 'capital', 'big', 'mëdha', 'medha']), onSelected: () => _addIngredient('upper')));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, const ['брое', 'бројк', 'цифр', 'number', 'digit', 'numra', 'shifra']), onSelected: () => _addIngredient('digit')));
        opts.add(VoiceCategoryOption(keywords: const [], matches: (t) => _saysAny(t, const ['симбол', 'знац', 'знак', 'symbol', 'simbol', 'shenj']), onSelected: () => _addIngredient('symbol')));
        break;
      case _View.phishingResult:
      case _View.quizResult:
      case _View.agentResult:
        opts.add(VoiceCategoryOption(
          keywords: const [],
          matches: (t) => _saysAny(t, const ['повторно', 'играј пак', 'play again', 'again', 'përsëri', 'perseri']),
          onSelected: _view == _View.phishingResult ? _startPhishing : (_view == _View.quizResult ? _startQuiz : _startAgent),
        ));
        break;
      case _View.modeSelect:
        break;
    }
    return [...opts, ..._modeVoiceOptions(ordinals: false)];
  }

  /// „а / б / в“ и „a / b / c“ за одговорите во квизот - само како
  /// посебен збор (не почеток на друг збор).
  static const List<List<String>> _quizLetterWords = [
    ['а', 'a'],
    ['б', 'b'],
    ['в', 'c'],
  ];

  static bool _saysWord(String t, List<String> words) {
    final parts = t.toLowerCase().replaceAll(RegExp(r'[.,!?„“"]'), ' ').split(RegExp(r'\s+'));
    return words.any(parts.contains);
  }

  /// Штом почне гласовната команда: запри го говорот; во квизот отклучи ги
  /// сите одговори (детето сака да одговори со глас).
  void _onGameVoiceStart() {
    _stopNarration();
    if (_view == _View.quiz && _quizPicked == null && mounted) {
      setState(() {
        _quizUnlocked = 4;
        _quizReadingOption = null;
      });
    }
  }

  static bool _saysOrdinal(String t, int index) {
    final words = t.replaceAll(RegExp(r'[.,!?]'), ' ').split(RegExp(r'\s+'));
    return _ordinalWords[index].any(words.contains);
  }

  /// Картичка за игра: градиент во бојата на играта, бел раб, сјај, реден
  /// број во златно копче, име и кусо објаснување.
  Widget _modeCard(
    BuildContext context, {
    required int number,
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
    required Color accent,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final deep = Color.lerp(accent, Colors.black, 0.35)!;
    final fg = hc ? Colors.white : Colors.white;
    return Semantics(
      label: '$number. $label. $desc',
      button: true,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: hc ? null : LinearGradient(colors: [accent, deep], begin: Alignment.topLeft, end: Alignment.bottomRight),
                color: hc ? Colors.black : null,
                border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.85), width: 3),
                boxShadow: hc ? null : [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    if (!hc)
                      Positioned(
                        right: -18,
                        bottom: -26,
                        child: ExcludeSemantics(child: Icon(icon, size: 140, color: Colors.white.withValues(alpha: 0.10))),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ExcludeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? Colors.black : Colors.white, border: hc ? Border.all(color: Colors.white, width: 2) : null),
                                  child: Icon(icon, color: hc ? const Color(0xFFFFFF00) : deep, size: 42),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? const Color(0xFFFFFF00) : _gold, border: Border.all(color: Colors.white, width: 2)),
                                  child: Text('$number', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Playful.ink)),
                                ),
                              ],
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: Playful.display(26, color: fg)),
                                  const SizedBox(height: 8),
                                  Text(desc, style: Playful.body(16.5, color: fg.withValues(alpha: 0.95))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: hc ? 0.1 : 0.22), border: Border.all(color: Colors.white, width: 2)),
                              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Заеднички елементи за игрите ---

  /// Златна пилула со бројот на пораката / прашањето.
  Widget _buildLevelBadge(String text, Color contrast, bool hc) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: hc ? Colors.black : _gold,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white, width: hc ? 1.5 : 2),
        ),
        child: Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: hc ? Colors.white : Playful.ink)),
      ),
    );
  }

  /// „Како се игра“ - кусото објаснување за играта (само текст).
  Widget _briefing(bool hc) {
    final key = _introKey;
    if (key == null) return const SizedBox.shrink();
    return Semantics(
      label: '${'cyber.how_to_play'.tr()}. ${key.tr()}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: BoxDecoration(
          color: hc ? Colors.black : const Color(0xFF0B0F19).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hc ? Colors.white : _neon.withValues(alpha: 0.7), width: 2),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.terminal_rounded, color: hc ? Colors.white : _neon, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '> ${'cyber.how_to_play'.tr()}',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w900, color: hc ? Colors.white : _neon),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(key.tr(), style: Playful.body(17, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// Жолто копче за глас (одговорите на играта + режими + „назад“) и кус
  /// потсетник што може да се каже.
  Widget _voiceRow(String? hintKey, bool hc) {
    return Column(
      children: [
        Center(
          child: CategoryVoiceCommandButton(
            options: _gameVoiceOptions(),
            onBack: _backToModeSelect,
            onListenStart: _onGameVoiceStart,
            respondToHotkey: true,
            compact: true,
            background: hc ? null : _gold,
            foreground: hc ? null : Playful.ink,
          ),
        ),
        if (hintKey != null) ...[
          const SizedBox(height: 8),
          Text(hintKey.tr(), textAlign: TextAlign.center, style: Playful.body(15, color: hc ? Colors.white : Colors.white.withValues(alpha: 0.85))),
        ],
      ],
    );
  }

  /// Порака во стил на инбокс: бела (темен текст) со златен раб; по
  /// одговорот - зелена / црвена.
  Widget _buildMessageCard(
    BuildContext context, {
    required IconData headerIcon,
    required Color headerIconColor,
    required String senderText,
    required String bodyText,
    Color? cardColor,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final answered = cardColor != null;
    final ink = answered ? Colors.white : (hc ? Colors.white : Playful.ink);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: answered ? cardColor : (hc ? Colors.black : Colors.white),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: answered ? Colors.white : (hc ? Colors.white : _gold), width: 3),
        boxShadow: hc ? const [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: answered ? Colors.white.withValues(alpha: 0.25) : (hc ? Colors.white : headerIconColor),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(headerIcon, size: 32, color: answered ? Colors.white : (hc ? Colors.black : Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(senderText, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 2),
                    Text('cyber.new_message_label'.tr(), style: TextStyle(fontSize: 14, color: ink.withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: ink.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 16),
          Text(bodyText, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.4, color: ink)),
        ],
      ),
    );
  }

  /// Големо копче за одговор во полна боја (бел текст), со бел раб.
  Widget _phishingChoiceButton(BuildContext context, {required String label, required IconData icon, required Color color, required VoidCallback onTap, required bool locked, bool picked = false}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      button: !locked,
      label: label,
      child: AbsorbPointer(
        absorbing: locked,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          scale: picked ? 1.06 : 1.0,
          child: PressableScale(
            child: Material(
              color: hc ? Colors.black : color,
              borderRadius: BorderRadius.circular(24),
              elevation: hc ? 0 : 8,
              shadowColor: color.withValues(alpha: 0.6),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onTap,
                child: Container(
                  height: 134,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: hc ? color : Colors.white, width: picked ? 5 : 3),
                  ),
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 48),
                        const SizedBox(height: 8),
                        Text(label, textAlign: TextAlign.center, style: Playful.title(21)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Трофеј, резултат, „Играј повторно“ и „Смени игра“.
  Widget _resultView({required String titleKey, required int score, required int total, required VoidCallback onAgain}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _fg(hc, AccessibilityUtils.getContrastColor(context));
    return _page((side) => [
          const SizedBox(height: 24),
          PopIn(
            child: Center(
              child: RippleRings(
                color: hc ? Colors.white : _gold,
                spread: 24,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: hc ? Colors.black : Playful.night,
                    shape: BoxShape.circle,
                    border: Border.all(color: hc ? Colors.white : _gold, width: 5),
                  ),
                  child: Icon(Icons.emoji_events_rounded, size: 76, color: hc ? const Color(0xFFFFFF00) : _gold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          PopIn(index: 1, child: Text(titleKey.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 26))),
          const SizedBox(height: 14),
          // По еден штит за секој точен одговор.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < total; i++)
                PopIn(
                  index: 2 + i,
                  stepMs: 90,
                  child: Icon(
                    i < score ? Icons.shield_rounded : Icons.shield_outlined,
                    size: 42,
                    color: i < score ? (hc ? const Color(0xFFFFFF00) : _gold) : contrast.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('cyber.score'.tr(args: [score.toString(), total.toString()]), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 20)),
          const SizedBox(height: 28),
          _bigButton(icon: Icons.refresh_rounded, label: 'cyber.play_again'.tr(), onTap: onAgain, primary: true),
          const SizedBox(height: 12),
          _bigButton(icon: Icons.grid_view_rounded, label: 'cyber.change_mode'.tr(), onTap: _backToModeSelect, primary: false),
          const SizedBox(height: 22),
          _voiceRow(null, hc),
        ]);
  }

  Widget _bigButton({required IconData icon, required String label, required VoidCallback onTap, required bool primary}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final bg = hc ? Colors.black : (primary ? _gold : Colors.white.withValues(alpha: 0.1));
    final fg = hc ? Colors.white : (primary ? Playful.ink : Colors.white);
    return PressableScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: primary && !hc ? 0 : 0.8), width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 28),
                const SizedBox(width: 10),
                Flexible(child: Text(label, style: Playful.title(20, color: fg))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Волк во овча кожа ---

  Widget _buildPhishing(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _fg(hc, AccessibilityUtils.getContrastColor(context));
    final msg = _phishingRoundList[_phishingIndex];

    Color? cardColor;
    if (_phishingPickedCorrect != null) {
      cardColor = _phishingPickedCorrect!
          ? (hc ? const Color(0xFF14532D) : const Color(0xFF16A34A))
          : (hc ? const Color(0xFF3A3A3A) : const Color(0xFFDC2626));
    }

    return _page((side) => [
          _buildBackRow(contrast, onBack: _backToModeSelect),
          const SizedBox(height: 6),
          _buildLevelBadge('cyber.phishing_progress'.tr(args: [(_phishingIndex + 1).toString(), _phishingRoundList.length.toString()]), contrast, hc),
          const SizedBox(height: 14),
          _briefing(hc),
          const SizedBox(height: 16),
          Text('cyber.phishing_prompt'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 26)),
          const SizedBox(height: 16),
          _buildMessageCard(
            context,
            headerIcon: Icons.mail_rounded,
            headerIconColor: const Color(0xFFC2410C),
            senderText: msg.senderKey.tr(),
            bodyText: msg.textKey.tr(),
            cardColor: cardColor,
          ),
          const SizedBox(height: 18),
          Text('cyber.choose_feeling'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 19)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.danger'.tr(), icon: Icons.warning_rounded, color: const Color(0xFFDC2626), onTap: () => _answerPhishing(false), locked: _phishingLocked, picked: _phishingPickedSafe == false)),
              const SizedBox(width: 16),
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.safe'.tr(), icon: Icons.verified_user_rounded, color: const Color(0xFF15803D), onTap: () => _answerPhishing(true), locked: _phishingLocked, picked: _phishingPickedSafe == true)),
            ],
          ),
          const SizedBox(height: 18),
          _voiceRow('cyber.voice_hint_phishing', hc),
        ]);
  }

  Widget _buildPhishingResult(BuildContext context) => _resultView(
        titleKey: 'cyber.phishing_done',
        score: _phishingScore,
        total: _phishingRoundList.length,
        onAgain: _startPhishing,
      );

  // --- Квиз ---

  Widget _buildQuiz(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _fg(hc, AccessibilityUtils.getContrastColor(context));
    final q = _questions[_quizIndex];

    return _page((side) => [
          _buildBackRow(contrast, onBack: _backToModeSelect),
          const SizedBox(height: 6),
          _buildLevelBadge('cyber.progress'.tr(args: [(_quizIndex + 1).toString(), _questions.length.toString()]), contrast, hc),
          const SizedBox(height: 14),
          _briefing(hc),
          const SizedBox(height: 16),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _quizUnlocked >= 1 ? 1.0 : 0.35,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: hc ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: hc ? Colors.white : _gold, width: 3),
                boxShadow: hc ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.help_rounded, color: hc ? Colors.white : const Color(0xFF6D28D9), size: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q.question, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.35, color: hc ? Colors.white : Playful.ink))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_quizPicked == null)
            Center(
              child: OutlinedButton.icon(
                onPressed: _repeatQuizQuestion,
                icon: Icon(Icons.replay_rounded, color: hc ? null : _gold),
                label: Text('cyber.repeat_question'.tr(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.75), width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          const SizedBox(height: 14),
          for (var index = 0; index < q.options.length; index++) ...[
            _quizOptionRow(q, index, hc),
            const SizedBox(height: 14),
          ],
          if (_quizShowingExplanation) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: hc ? Colors.black : const Color(0xFF0B0F19).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hc ? Colors.white : _neon, width: 2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_rounded, color: hc ? Colors.white : _gold, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q.explanation, style: Playful.body(18))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _bigButton(icon: Icons.arrow_forward_rounded, label: 'cyber.continue_button'.tr(), onTap: _quizContinue, primary: true),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          _voiceRow('cyber.voice_hint_quiz', hc),
        ]);
  }

  /// Одговор во квизот: бел ред со бројот; се чита - злато; точно -
  /// зелено; погрешно - сиво. Додека не се прочита - бледо.
  Widget _quizOptionRow(CyberSafetyQuestion q, int index, bool hc) {
    final option = q.options[index];
    final picked = _quizPicked == index;
    final unlocked = index + 2 <= _quizUnlocked;
    final reading = _quizReadingOption == index;
    final showCorrect = (picked || _quizShowingExplanation) && index == q.correctAnswer;
    Color bg = hc ? AccessibilityUtils.getPrimaryButtonBackground(context) : Colors.white;
    Color fg = hc ? Colors.white : Playful.ink;
    if (showCorrect) {
      bg = hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A);
      fg = hc ? Colors.black : Colors.white;
    } else if (picked) {
      bg = hc ? const Color(0xFF3A3A3A) : const Color(0xFFDC2626);
      fg = Colors.white;
    } else if (reading && !hc) {
      bg = _gold;
    }
    return AbsorbPointer(
      absorbing: _quizPicked != null || !unlocked,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: (unlocked || reading || _quizPicked != null) ? 1.0 : 0.35,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          scale: reading || picked ? 1.03 : 1.0,
          child: Semantics(
            label: '${index + 1}. $option',
            button: unlocked,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              elevation: hc ? 0 : (reading ? 14 : 6),
              shadowColor: reading ? _gold : Colors.black.withValues(alpha: 0.5),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _selectQuizAnswer(index),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: reading || hc ? Border.all(color: hc ? Colors.white : Colors.white, width: reading ? 4 : 2) : null,
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? Colors.black : const Color(0xFF6D28D9), border: Border.all(color: Colors.white, width: 2)),
                          child: showCorrect
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 28)
                              : (picked
                                  ? const Icon(Icons.close_rounded, color: Colors.white, size: 28)
                                  : Text('${index + 1}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(option, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.3, color: fg))),
                        if (reading && !hc) const SoundWave(color: Playful.ink, bars: 5, height: 26, barWidth: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizResult(BuildContext context) => _resultView(
        titleKey: 'cyber.quiz_done',
        score: _quizScore,
        total: _questions.length,
        onAgain: _startQuiz,
      );

  // --- Изгради го замокот ---

  Widget _buildCastle(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _fg(hc, AccessibilityUtils.getContrastColor(context));
    final level = _castleLevel < 0 ? 0 : _castleLevel;
    const emojis = ['🏚️', '🏠', '🏰'];
    const levelColors = [Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF16A34A)];
    final levelLabels = ['cyber.castle_weak'.tr(), 'cyber.castle_medium'.tr(), 'cyber.castle_strong'.tr()];
    final color = levelColors[level];

    return _page((side) => [
          _buildBackRow(contrast, onBack: _backToModeSelect),
          const SizedBox(height: 6),
          _briefing(hc),
          const SizedBox(height: 16),
          // Замокот: расте со лозинката; под него „тули“ - по една за
          // секој додаден знак, во бојата на неговиот вид.
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: hc ? Colors.black : null,
              gradient: hc ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, Playful.night, 0.35)!, Color.lerp(color, Playful.night, 0.7)!]),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: hc ? 1 : 0.85), width: 3),
              boxShadow: hc ? null : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
            ),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack), child: child),
                  child: Text(emojis[level], key: ValueKey(level), style: const TextStyle(fontSize: 96)),
                ),
                const SizedBox(height: 8),
                Text(levelLabels[level], style: Playful.display(28, color: Colors.white)),
                const SizedBox(height: 14),
                // Метар на сила: три дела.
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          height: 14,
                          margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: _castleLevel >= i ? levelColors[i] : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // Тулите (знаците во лозинката).
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _castleLength.clamp(0, 24); i++)
                      PopIn(
                        startMs: 0,
                        stepMs: 0,
                        child: Container(
                          width: 26,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Playful.ink.withValues(alpha: 0.5), width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_castleMessageKey != null) ...[
                  const SizedBox(height: 12),
                  Text(_castleMessageKey!.tr(), textAlign: TextAlign.center, style: Playful.body(18)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('cyber.castle_add_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 18)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 640 ? 4 : 2;
              const gap = 14.0;
              final w = (constraints.maxWidth - gap * (cols - 1)) / cols - 0.5;
              final tiles = [
                ('cyber.ingredient_lower', Icons.text_fields_rounded, const Color(0xFF1D4ED8), 'lower', 'abc'),
                ('cyber.ingredient_upper', Icons.font_download_rounded, const Color(0xFF7E22CE), 'upper', 'ABC'),
                ('cyber.ingredient_digit', Icons.pin_rounded, const Color(0xFF0F766E), 'digit', '123'),
                ('cyber.ingredient_symbol', Icons.tag_rounded, const Color(0xFFB45309), 'symbol', '#@!'),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in tiles)
                    SizedBox(
                      width: w,
                      height: 150,
                      child: _ingredientButton(context, label: t.$1.tr(), icon: t.$2, color: t.$3, sample: t.$5, onTap: () => _addIngredient(t.$4)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _bigButton(icon: Icons.refresh_rounded, label: 'cyber.castle_reset'.tr(), onTap: _resetCastle, primary: false),
          const SizedBox(height: 18),
          _voiceRow('cyber.voice_hint_castle', hc),
        ]);
  }

  /// Копче-состојка за замокот: во полна боја, со бел раб, примерок од
  /// знаците (abc / ABC / 123 / #@!) и иконата.
  Widget _ingredientButton(BuildContext context, {required String label, required IconData icon, required Color color, required String sample, required VoidCallback onTap}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: true,
      child: PressableScale(
        child: Material(
          color: hc ? Colors.black : color,
          borderRadius: BorderRadius.circular(24),
          elevation: hc ? 0 : 8,
          shadowColor: color.withValues(alpha: 0.6),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: hc ? color : Colors.white, width: 3),
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 40),
                        const SizedBox(width: 8),
                        Text(sample, style: const TextStyle(fontFamily: 'monospace', fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: Playful.title(19))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Таен агент ---

  Widget _buildAgent(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _fg(hc, AccessibilityUtils.getContrastColor(context));
    final questionText = _agentRoundList[_agentIndex].tr();

    Color? cardColor;
    if (_agentPickedRefuse != null) {
      final correct = _agentPickedRefuse!;
      cardColor = correct ? (hc ? const Color(0xFF14532D) : const Color(0xFF16A34A)) : (hc ? const Color(0xFF3A3A3A) : const Color(0xFFDC2626));
    }

    return _page((side) => [
          _buildBackRow(contrast, onBack: _backToModeSelect),
          const SizedBox(height: 6),
          _buildLevelBadge('cyber.phishing_progress'.tr(args: [(_agentIndex + 1).toString(), _agentRoundList.length.toString()]), contrast, hc),
          const SizedBox(height: 14),
          _briefing(hc),
          const SizedBox(height: 16),
          Text('cyber.agent_prompt'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 26)),
          const SizedBox(height: 16),
          _buildMessageCard(
            context,
            headerIcon: Icons.person_search_rounded,
            headerIconColor: const Color(0xFFBE185D),
            senderText: 'cyber.agent_sender_label'.tr(),
            bodyText: questionText,
            cardColor: cardColor,
          ),
          const SizedBox(height: 18),
          Text('cyber.agent_choose_label'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 19)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.agent_answer'.tr(), icon: Icons.chat_bubble_rounded, color: const Color(0xFFDC2626), onTap: () => _answerAgent(false), locked: _agentLocked, picked: _agentPickedRefuse == false)),
              const SizedBox(width: 16),
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.agent_refuse'.tr(), icon: Icons.shield_rounded, color: const Color(0xFF15803D), onTap: () => _answerAgent(true), locked: _agentLocked, picked: _agentPickedRefuse == true)),
            ],
          ),
          const SizedBox(height: 18),
          _voiceRow('cyber.voice_hint_agent', hc),
        ]);
  }

  Widget _buildAgentResult(BuildContext context) => _resultView(
        titleKey: 'cyber.agent_done',
        score: _agentScore,
        total: _agentRoundList.length,
        onAgain: _startAgent,
      );

  Widget _buildBackRow(Color contrast, {required VoidCallback onBack}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Row(
      children: [
        Semantics(
          label: 'cyber.change_mode'.tr(),
          button: true,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: contrast, size: 30),
            style: IconButton.styleFrom(
              backgroundColor: hc ? null : Colors.white.withValues(alpha: 0.15),
              side: hc ? null : BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
            ),
            onPressed: onBack,
          ),
        ),
      ],
    );
  }
}