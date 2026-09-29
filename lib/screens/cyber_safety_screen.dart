import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

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
  int _quizScore = 0;
  int? _quizPicked;
  bool _quizShowingExplanation = false;

  // --- Изгради го замокот (сила на лозинка) ---
  int _castleLength = 0;
  final Set<String> _castleCategories = {};
  int _castleLevel = -1; // -1 = ништо сè уште, 0=слаб, 1=среден, 2=силен

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

  @override
  void dispose() {
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    super.dispose();
  }

  /// Ги отстранува 'cyber.' на почетокот на клучот за превод, за да се добие
  /// името на mp3-датотеката (пр. 'cyber.msg_danger1' -> 'msg_danger1'). Ова
  /// е намерна конвенција - секоја снимка се вика исто како клучот за превод
  /// на содржината што ја чита, само без префиксот.
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
    _narrationToken++;
    _voicePlayer.stop();
    setState(() => _view = _View.modeSelect);
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
    _announcePhishingMessage();
  }

  Future<void> _announcePhishingMessage() async {
    final myToken = ++_narrationToken;
    final msg = _phishingRoundList[_phishingIndex];
    await _speak('phishing_prompt');
    if (myToken != _narrationToken || !mounted) return;
    await _speak(_audioKey(msg.textKey));
  }

  Future<void> _answerPhishing(bool pickedSafe) async {
    if (_phishingLocked) return;
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
    if (correct) {
      setState(() => _phishingScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    final next = _phishingIndex + 1;
    if (next >= _phishingRoundList.length) {
      setState(() => _view = _View.phishingResult);
      await _speak('phishing_done');
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
      _view = _View.password;
    });
    _speak('castle_intro');
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
        await _speak('castle_strong');
      } else if (newLevel == 1) {
        await _speak('castle_medium');
      }
    }
  }

  void _resetCastle() {
    setState(() {
      _castleLength = 0;
      _castleCategories.clear();
      _castleLevel = -1;
    });
    _speak('castle_intro');
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
    _announceAgentQuestion();
  }

  Future<void> _announceAgentQuestion() async {
    final myToken = ++_narrationToken;
    await _speak('agent_prompt');
    if (myToken != _narrationToken || !mounted) return;
    await _speak(_audioKey(_agentRoundList[_agentIndex]));
  }

  Future<void> _answerAgent(bool refused) async {
    if (_agentLocked) return;
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
    if (correct) {
      setState(() => _agentScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    final next = _agentIndex + 1;
    if (next >= _agentRoundList.length) {
      setState(() => _view = _View.agentResult);
      await _speak('agent_done');
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
      _quizScore = 0;
      _quizPicked = null;
      _quizShowingExplanation = false;
      _view = _View.quiz;
    });
    _announceQuizQuestion();
  }

  Future<void> _announceQuizQuestion() async {
    final myToken = ++_narrationToken;
    await _speak('question${_quizIndex + 1}');
    if (myToken != _narrationToken || !mounted) return;
    const letters = ['a', 'b', 'c'];
    for (final letter in letters) {
      if (myToken != _narrationToken || !mounted) return;
      await _speak('option${_quizIndex + 1}$letter');
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _selectQuizAnswer(int index) async {
    if (_quizPicked != null) return;
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
    if (correct) {
      setState(() => _quizScore++);
      await _playPongEffect('hit.mp3');
    } else {
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _quizShowingExplanation = true);
  }

  void _quizContinue() {
    final next = _quizIndex + 1;
    if (next >= _questions.length) {
      setState(() => _view = _View.quizResult);
      _speak('quiz_done');
    } else {
      setState(() {
        _quizIndex = next;
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

  Widget _buildModeSelect(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // "Терминален" наслов - асоцира на cyber/хакерска естетика.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: hc ? Colors.black : const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: hc ? Colors.white : const Color(0xFF22D3EE), width: hc ? 2 : 1.5),
            boxShadow: hc
                ? null
                : [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.35), blurRadius: 18, spreadRadius: 1)],
          ),
          child: Row(
            children: [
              Icon(Icons.security_rounded, color: hc ? Colors.white : const Color(0xFF22D3EE), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'cyber.choose_mode'.tr(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: hc ? Colors.white : const Color(0xFF22D3EE),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _modeCard(
          context,
          icon: Icons.mail_lock_rounded,
          label: 'cyber.mode_phishing'.tr(),
          onTap: _startPhishing,
          accent: const Color(0xFFF97316),
        ),
        const SizedBox(height: 16),
        _modeCard(
          context,
          icon: Icons.quiz_rounded,
          label: 'cyber.mode_quiz'.tr(),
          onTap: _startQuiz,
          accent: const Color(0xFF8B5CF6),
        ),
        const SizedBox(height: 16),
        _modeCard(
          context,
          icon: Icons.castle_rounded,
          label: 'cyber.mode_password'.tr(),
          onTap: _startCastle,
          accent: const Color(0xFF10B981),
        ),
        const SizedBox(height: 16),
        _modeCard(
          context,
          icon: Icons.theater_comedy_rounded,
          label: 'cyber.mode_agent'.tr(),
          onTap: _startAgent,
          accent: const Color(0xFFEC4899),
        ),
      ],
    );
  }

  /// Категорија на почетниот екран - поголема, со "cyber"/хакерска естетика
  /// (темна "терминална" картичка, неонски акцент-раб со блесок, поголема
  /// моноспејс буква).
  Widget _modeCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color accent = _moduleAccent,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Semantics(
        label: enabled ? label : '$label. ${'cyber.coming_soon'.tr()}',
        button: enabled,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: hc
                    ? null
                    : LinearGradient(
                        colors: [const Color(0xFF0B0F19), Color.lerp(const Color(0xFF0B0F19), accent, 0.16)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: hc ? Colors.black : null,
                border: Border.all(color: hc ? Colors.white : accent, width: hc ? 2 : 1.8),
                boxShadow: hc
                    ? null
                    : [
                        BoxShadow(color: accent.withOpacity(0.4), blurRadius: 16, spreadRadius: 0.5),
                        BoxShadow(color: Colors.black.withOpacity(0.35), offset: const Offset(0, 6), blurRadius: 12),
                      ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? const Color(0xFFFFFF00) : accent,
                      boxShadow: hc ? null : [BoxShadow(color: accent.withOpacity(0.6), blurRadius: 14, spreadRadius: 1)],
                    ),
                    child: Icon(icon, color: hc ? Colors.black : Colors.white, size: 38),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            height: 1.15,
                            color: hc ? Colors.white : Colors.white.withOpacity(0.96),
                          ),
                        ),
                        if (!enabled) ...[
                          const SizedBox(height: 4),
                          Text(
                            'cyber.coming_soon'.tr(),
                            style: TextStyle(fontSize: 14, color: hc ? Colors.white70 : Colors.white60),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (enabled) Icon(Icons.chevron_right_rounded, color: hc ? Colors.white : accent, size: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Заеднички елементи за екраните "порака + два одговора"
  //     (Волк во овча кожа / Таен агент) - редизајнирано по мокап: пилула
  //     со ниво/прогрес, крупен наслов-прашање, картичка-порака во стил на
  //     инбокс (икона + подател + линија + текст), па два големи копчиња
  //     со контура наместо целосно обоени.

  Widget _buildLevelBadge(String text, Color contrast, bool hc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: hc ? Colors.black : AccessibilityUtils.getDisabledColor(context),
            borderRadius: BorderRadius.circular(24),
            border: hc ? Border.all(color: Colors.white, width: 1.5) : null,
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: hc ? Colors.white : contrast.withOpacity(0.8)),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard(
    BuildContext context, {
    required IconData headerIcon,
    required Color headerIconColor,
    required String senderText,
    required String bodyText,
    Color? cardColor,
  }) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final answered = cardColor != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: answered ? cardColor : (hc ? Colors.black : Colors.white),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: answered
              ? (hc ? Colors.white : Colors.white.withOpacity(0.55))
              : (hc ? Colors.white : const Color(0xFFF59E0B)),
          width: hc ? 2.5 : 2.2,
        ),
        boxShadow: hc
            ? const []
            : [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: answered
                      ? Colors.white.withOpacity(0.25)
                      : (hc ? Colors.white : headerIconColor.withOpacity(0.15)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  headerIcon,
                  size: 30,
                  color: answered ? Colors.white : (hc ? Colors.black : headerIconColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: answered ? Colors.white : (hc ? Colors.white : contrast),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'cyber.new_message_label'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: answered ? Colors.white70 : (hc ? Colors.white70 : contrast.withOpacity(0.55)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            color: answered ? Colors.white.withOpacity(0.4) : (hc ? Colors.white24 : contrast.withOpacity(0.12)),
            height: 1,
          ),
          const SizedBox(height: 16),
          Text(
            bodyText,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: answered ? Colors.white : (hc ? Colors.white : contrast),
            ),
          ),
        ],
      ),
    );
  }

  // --- Волк во овча кожа ---

  Widget _buildPhishing(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final msg = _phishingRoundList[_phishingIndex];

    Color? cardColor;
    if (_phishingPickedCorrect != null) {
      cardColor = _phishingPickedCorrect!
          ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A))
          : (hc ? const Color(0xFF3A3A3A) : const Color(0xFFDC2626));
    }

    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToModeSelect),
        _buildLevelBadge(
          'cyber.phishing_progress'.tr(args: [(_phishingIndex + 1).toString(), _phishingRoundList.length.toString()]),
          contrast,
          hc,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.phishing_prompt'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 23)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: _buildMessageCard(
                context,
                headerIcon: Icons.mail_rounded,
                headerIconColor: const Color(0xFFF59E0B),
                senderText: msg.senderKey.tr(),
                bodyText: msg.textKey.tr(),
                cardColor: cardColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.choose_feeling'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 17)),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.danger'.tr(), icon: Icons.warning_rounded, color: const Color(0xFFDC2626), onTap: () => _answerPhishing(false), locked: _phishingLocked)),
              const SizedBox(width: 16),
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.safe'.tr(), icon: Icons.verified_user_rounded, color: const Color(0xFF16A34A), onTap: () => _answerPhishing(true), locked: _phishingLocked)),
            ],
          ),
        ),
      ],
    );
  }

  /// Копче за одговор - контура во боја на позадина бела/црна (наместо
  /// целосно обоена позадина), со голема икона над текстот, по мокапот.
  Widget _phishingChoiceButton(BuildContext context, {required String label, required IconData icon, required Color color, required VoidCallback onTap, required bool locked}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return AbsorbPointer(
      absorbing: locked,
      child: Material(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: hc ? 0 : 5,
        shadowColor: Colors.black.withOpacity(0.25),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 122,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color, width: hc ? 2.5 : 2.4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: hc ? Colors.white : color, size: 42),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: hc ? Colors.white : color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhishingResult(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text(
              'cyber.score'.tr(args: [_phishingScore.toString(), _phishingRoundList.length.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _startPhishing,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('cyber.play_again'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _moduleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _backToModeSelect,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text('cyber.change_mode'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccessibilityUtils.getDisabledColor(context),
                foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Квиз ---

  Widget _buildQuiz(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final q = _questions[_quizIndex];

    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToModeSelect),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'cyber.progress'.tr(args: [(_quizIndex + 1).toString(), _questions.length.toString()]),
            style: GameTypography.heading(context, contrast, 20),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _moduleAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _moduleAccent.withOpacity(0.3), width: 1.5),
                  ),
                  child: Text(q.question, textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 19)),
                ),
                const SizedBox(height: 20),
                ...q.options.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final picked = _quizPicked == index;
                  Color bg = AccessibilityUtils.getPrimaryButtonBackground(context);
                  Color fg = AccessibilityUtils.getPrimaryButtonForeground(context);
                  if (picked) {
                    final correct = index == q.correctAnswer;
                    bg = correct ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A)) : (hc ? const Color(0xFF3A3A3A) : const Color(0xFF6B7280));
                    fg = correct && hc ? Colors.black : Colors.white;
                  } else if (_quizShowingExplanation && index == q.correctAnswer) {
                    bg = hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A);
                    fg = hc ? Colors.black : Colors.white;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AbsorbPointer(
                      absorbing: _quizPicked != null,
                      child: Semantics(
                        label: '${index + 1}. $option',
                        button: true,
                        child: SizedBox(
                          width: double.infinity,
                          height: 76,
                          child: ElevatedButton(
                            onPressed: () => _selectQuizAnswer(index),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: bg,
                              foregroundColor: fg,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              elevation: hc ? 0 : 4,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(option, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (_quizShowingExplanation) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AccessibilityUtils.getCardBackgroundColor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: hc ? Colors.white : contrast.withOpacity(0.2), width: hc ? 2 : 1),
                    ),
                    child: Text(q.explanation, style: GameTypography.body(context, contrast, 16)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _quizContinue,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text('cyber.continue_button'.tr(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _moduleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuizResult(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text('cyber.results_title'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 22)),
            const SizedBox(height: 12),
            Text(
              'cyber.score'.tr(args: [_quizScore.toString(), _questions.length.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _startQuiz,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('cyber.play_again'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _moduleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _backToModeSelect,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text('cyber.change_mode'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccessibilityUtils.getDisabledColor(context),
                foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Изгради го замокот ---

  Widget _buildCastle(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final level = _castleLevel < 0 ? 0 : _castleLevel;
    const emojis = ['🏚️', '🏠', '🏰'];
    const levelColors = [Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF16A34A)];
    final levelLabels = ['cyber.castle_weak'.tr(), 'cyber.castle_medium'.tr(), 'cyber.castle_strong'.tr()];

    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToModeSelect),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.castle_intro_tts'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 16)),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: levelColors[level].withOpacity(0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: hc ? Colors.white : levelColors[level], width: hc ? 2 : 2),
          ),
          child: Column(
            children: [
              Text(emojis[level], style: const TextStyle(fontSize: 88)),
              const SizedBox(height: 10),
              Text(levelLabels[level], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: hc ? Colors.white : levelColors[level])),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.castle_add_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 15)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: [
                _ingredientButton(context, label: 'cyber.ingredient_lower'.tr(), icon: Icons.text_fields_rounded, color: const Color(0xFF2563EB), onTap: () => _addIngredient('lower')),
                _ingredientButton(context, label: 'cyber.ingredient_upper'.tr(), icon: Icons.font_download_rounded, color: const Color(0xFF9333EA), onTap: () => _addIngredient('upper')),
                _ingredientButton(context, label: 'cyber.ingredient_digit'.tr(), icon: Icons.pin_rounded, color: const Color(0xFF0D9488), onTap: () => _addIngredient('digit')),
                _ingredientButton(context, label: 'cyber.ingredient_symbol'.tr(), icon: Icons.tag_rounded, color: const Color(0xFFD97706), onTap: () => _addIngredient('symbol')),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ElevatedButton.icon(
            onPressed: _resetCastle,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('cyber.castle_reset'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccessibilityUtils.getDisabledColor(context),
              foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  /// Копче-состојка за замокот - иконата сега е МНОГУ поголема (сразмерна
  /// на висината на копчето, не фиксна мала големина), за подобра видливост.
  Widget _ingredientButton(BuildContext context, {required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: hc ? Colors.black : color,
        borderRadius: BorderRadius.circular(20),
        elevation: hc ? 0 : 6,
        shadowColor: Colors.black.withOpacity(0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: hc ? color : Colors.white.withOpacity(0.35), width: hc ? 2 : 1),
              gradient: hc ? null : LinearGradient(colors: [Color.lerp(color, Colors.white, 0.2)!, color], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Иконата зафаќа над половина од висината на копчето -
                // многу поголема отколку претходната фиксна големина 34.
                final iconSize = (constraints.maxHeight * 0.5).clamp(48.0, 96.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: iconSize),
                    const SizedBox(height: 8),
                    Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // --- Таен агент ---

  Widget _buildAgent(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final questionText = _agentRoundList[_agentIndex].tr();

    Color? cardColor;
    if (_agentPickedRefuse != null) {
      final correct = _agentPickedRefuse!;
      cardColor = correct ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A)) : (hc ? const Color(0xFF3A3A3A) : const Color(0xFFDC2626));
    }

    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToModeSelect),
        _buildLevelBadge(
          'cyber.phishing_progress'.tr(args: [(_agentIndex + 1).toString(), _agentRoundList.length.toString()]),
          contrast,
          hc,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.agent_prompt_tts'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 23)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: _buildMessageCard(
                context,
                headerIcon: Icons.person_rounded,
                headerIconColor: const Color(0xFFEC4899),
                senderText: 'cyber.agent_sender_label'.tr(),
                bodyText: questionText,
                cardColor: cardColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('cyber.agent_choose_label'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 17)),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.agent_answer'.tr(), icon: Icons.chat_bubble_rounded, color: const Color(0xFFDC2626), onTap: () => _answerAgent(false), locked: _agentLocked)),
              const SizedBox(width: 16),
              Expanded(child: _phishingChoiceButton(context, label: 'cyber.agent_refuse'.tr(), icon: Icons.shield_rounded, color: const Color(0xFF16A34A), onTap: () => _answerAgent(true), locked: _agentLocked)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgentResult(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text(
              'cyber.score'.tr(args: [_agentScore.toString(), _agentRoundList.length.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _startAgent,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('cyber.play_again'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _moduleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _backToModeSelect,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text('cyber.change_mode'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccessibilityUtils.getDisabledColor(context),
                foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackRow(Color contrast, {required VoidCallback onBack}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Semantics(
            label: 'cyber.change_mode'.tr(),
            button: true,
            child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: contrast), onPressed: onBack),
          ),
        ],
      ),
    );
  }
}