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

/// Приказна – твој избор: слушаш/читаш кратка приказна, избираш што ќе се
/// случи понатаму, слушаш/читаш го исходот. И приказната И исходот се
/// секогаш прикажани и на екран (не само изговорени) - клучно за деца со
/// оштетен слух. Целиот говор оди преку системскиот text-to-speech (без
/// однапред снимени mp3 датотеки). Напредувањето кон следната приказна е
/// рачно (копче „Продолжи"), без присилно темпирање.
class StoryChoicesScreen extends StatefulWidget {
  const StoryChoicesScreen({super.key});

  @override
  State<StoryChoicesScreen> createState() => _StoryChoicesScreenState();
}

class _StoryChoicesScreenState extends State<StoryChoicesScreen> {
  static const Color _moduleAccent = Color(0xFF0F766E);
  static const int _storyCount = 3;

  /// Еден елемент во сцената на приказната: икона, големина, боја, и
  /// позиција во сцената (Alignment: -1..1 по X и Y). Режимот со висок
  /// контраст секогаш презема свои бои, без разлика на ова.
  static const List<_SceneItem> _story1Scene = [
    _SceneItem(icon: Icons.park_rounded, size: 140, color: Color(0xFF15803D), align: Alignment(-0.6, -0.35)), // дрво - најголемо
    _SceneItem(icon: Icons.attractions_rounded, size: 130, color: Color(0xFFB45309), align: Alignment(0.55, -0.25)), // лулашка - најголема
    _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(-0.05, 0.55)), // силуета - средна
    _SceneItem(icon: Icons.local_florist_rounded, size: 55, color: Color(0xFFDB2777), align: Alignment(0.8, 0.85)), // цвеќе - најмало
  ];
  static const List<_SceneItem> _story2Scene = [
    _SceneItem(icon: Icons.opacity_rounded, size: 125, color: Color(0xFF0284C7), align: Alignment(-0.55, -0.3)), // вода - големо
    _SceneItem(icon: Icons.local_drink_rounded, size: 125, color: Color(0xFFEA580C), align: Alignment(0.55, -0.3)), // сок - големо
    _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(0.0, 0.55)), // силуета - средно
    _SceneItem(icon: Icons.wb_sunny_rounded, size: 50, color: Color(0xFFD97706), align: Alignment(0.85, -0.8)), // сонце - најмало
  ];
  static const List<_SceneItem> _story3Scene = [
    _SceneItem(icon: Icons.menu_book_rounded, size: 125, color: Color(0xFF4338CA), align: Alignment(-0.55, -0.25)), // книга - големо
    _SceneItem(icon: Icons.pets_rounded, size: 120, color: Color(0xFFB45309), align: Alignment(0.55, -0.3)), // животно - големо
    _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(0.0, 0.55)), // силуета - средно
    _SceneItem(icon: Icons.star_rounded, size: 50, color: Color(0xFFCA8A04), align: Alignment(0.85, -0.8)), // ѕвезда - најмало
  ];
  static const Map<int, List<_SceneItem>> _storyScenes = {
    0: _story1Scene,
    1: _story2Scene,
    2: _story3Scene,
  };
  static const Map<int, List<Color>> _sceneBackgrounds = {
    0: [Color(0xFFECFDF5), Color(0xFFBBF7D0)], // парк - зеленило
    1: [Color(0xFFF0F9FF), Color(0xFFBAE6FD)], // вода/жед - сино
    2: [Color(0xFFEEF2FF), Color(0xFFC7D2FE)], // читање/вселена - виолетово
  };

  /// Икона на секоја опција - одговара на содржината на одговорот.
  static const Map<String, IconData> _optionIcons = {
    's1_o1': Icons.attractions_rounded, // лулашка
    's1_o2': Icons.local_florist_rounded, // цвеќиња
    's2_o1': Icons.water_drop_rounded, // вода
    's2_o2': Icons.local_drink_rounded, // сок
    's3_o1': Icons.pets_rounded, // книга за животни
    's3_o2': Icons.rocket_launch_rounded, // книга за вселена
  };

  late VoiceAssistantService _voiceAssistant;
  /// Само за mk - за en/sq никогаш не се обидуваме со mp3.
  final AudioPlayer _voicePlayer = AudioPlayer();

  int _currentStory = 0;
  /// Се зголемува секогаш кога почнува нова секвенца на читање/избор -
  /// секоја веќе-стартувана асинхрона секвенца проверува дали токенот сè
  /// уште е ист, и ако не е (значи е застарена), веднаш прекинува - спречува
  /// преклопување на говор ако детето избере опција додека сè уште трае
  /// претходното читање.
  int _narrationToken = 0;
  bool _showingOutcome = false;
  bool _allDone = false;
  String? _lastOutcomeKey;
  bool _explanationOpen = false;
  /// Копчињата за избор се отклучуваат дури откако ЦЕЛОТО читање (текст +
  /// "што ќе се случи" + двете опции) целосно ќе заврши - спречува
  /// преклопување на говор ако детето допре пребрзо.
  bool _buttonsUnlocked = false;

  /// "Порта" на почетокот: 5 секунди во кои детето може да го притисне
  /// објаснувањето (или тоа автоматски ќе се отвори по истек на времето).
  /// Штом објаснувањето еднаш ќе се искористи, останува трајно заклучено.
  Timer? _gateTimer;
  bool _explanationEverUsed = false;
  /// За краток визуелен "светкање" ефект на избраната опција пред премин
  /// кон екранот со исход.
  int? _selectedOption;

  String get _langCode => context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGate());
  }

  @override
  void dispose() {
    // Го запира говорот веднаш штом се напушта екранот - без разлика дали
    // објаснувањето било отворено или не.
    _gateTimer?.cancel();
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    super.dispose();
  }

  String _storyKey(int i) => 's${i + 1}_text';
  String _opt1Key(int i) => 's${i + 1}_o1';
  String _opt2Key(int i) => 's${i + 1}_o2';
  String _out1Key(int i) => 's${i + 1}_out1';
  String _out2Key(int i) => 's${i + 1}_out2';

  /// Превод-клуч (со префикс "story.") - за текст на екран И за говор.
  String _t(String key) => 'story.$key'.tr();

  /// За mk: пробува однапред снимена mp3 датотека (веќе ги имаш генерирани
  /// за mk), TTS како резерва ако таа конкретна датотека недостасува. За
  /// en/sq: секогаш само системски TTS (за да не треба да генерираш толку
  /// многу дополнителни датотеки). Во двата случаи го чека говорот целосно
  /// да заврши пред да продолжи понатамошниот тек.
  /// Исклучиво снимка (mp3), за СИТЕ јазици - без TTS-резерва. Ако клипот
  /// недостасува/не успее, тишина - намерно, по барање (го отстранува и
  /// стариот бag каде само mk воопшто се обидуваше со mp3, и race-condition-от
  /// каде "портата" од 5 секунди можеше да пресече говор во тек).
  Future<void> _speak(String key, [String? fallbackText]) async {
    if (!mounted) return;

    // Секогаш прво прекини сè што можеби сè уште свири - за да не се
    // преклопат два клипа ако претходниот повик сè уште трае.
    try {
      await _voicePlayer.stop();
    } catch (_) {}
    _voiceAssistant.stop();

    final relativePath = 'audio/story_choices/$_langCode/$key.mp3';

    // Некои платформи (веб) тивко "голтаат" формат-грешка без да фрлат
    // исклучок од .play() - плеерот никогаш не влегува во состојба
    // "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
    // почнал, а не само дека .play() не фрлил грешка.
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
    // Намерно нема TTS-резерва - тишина ако клипот недостасува.
  }

  /// "Порта" на почетокот: 5 секунди во кои се изговара името на играта, а
  /// детето може со клик на објаснувањето да одлучи тоа да се пушти прво.
  /// Ако не притисне ништо, по истек на времето автоматски се отвора
  /// објаснувањето. Приказната НЕ почнува додека објаснувањето не заврши
  /// (природно или со рачно затворање) - двете никогаш не звучат заедно.
  Future<void> _startGate() async {
    final myToken = ++_narrationToken;
    _gateTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || myToken != _narrationToken) return;
      if (!_explanationEverUsed && !_explanationOpen) {
        _openExplanation();
      }
    });
    _voiceAssistant.stop();
    await _speak('game_name', 'features.story_choices'.tr());
  }

  void _openExplanation() {
    _gateTimer?.cancel();
    _narrationToken++;
    setState(() => _explanationOpen = true);
    _speak('explanation', _t('explanation_text')).then((_) {
      if (!mounted || !_explanationOpen) return;
      // Мп3-то/говорот заврши природно - автоматски затвори и продолжи.
      _closeExplanationAndProceed();
    });
  }

  void _closeExplanationAndProceed() {
    _voiceAssistant.stop();
    _voicePlayer.stop();
    setState(() {
      _explanationOpen = false;
      _explanationEverUsed = true;
    });
    // Штом објаснувањето е веќе искористено, приказната конечно може да
    // почне (само ако не е веќе во тек/завршена).
    if (!_showingOutcome && !_allDone && !_buttonsUnlocked) {
      _readStory();
    }
  }

  void _toggleExplanation() {
    if (_explanationEverUsed) return; // трајно заклучено по едно користење
    if (_explanationOpen) {
      _closeExplanationAndProceed();
    } else {
      _openExplanation();
    }
  }

  Future<void> _readStory() async {
    final myToken = ++_narrationToken;
    setState(() {
      _showingOutcome = false;
      _allDone = false;
      _lastOutcomeKey = null;
      _buttonsUnlocked = false;
    });

    await _speak(_storyKey(_currentStory), _t(_storyKey(_currentStory)));
    if (!mounted || myToken != _narrationToken) return;

    await _speak('what_next', _t('what_next'));
    if (!mounted || myToken != _narrationToken) return;

    await _speak(_opt1Key(_currentStory), _t(_opt1Key(_currentStory)));
    if (!mounted || myToken != _narrationToken) return;

    await _speak(_opt2Key(_currentStory), _t(_opt2Key(_currentStory)));
    if (!mounted || myToken != _narrationToken) return;

    // Дури сега, откако СЀ е прочитано, копчињата стануваат допирливи.
    setState(() => _buttonsUnlocked = true);
  }

  Future<void> _choose(int option) async {
    if (_showingOutcome || !_buttonsUnlocked) return;
    // Веднаш поништи ја секоја сè уште активна секвенца на читање (пр. ако
    // детето избрало опција додека сè уште траеше читањето на насловот/
    // прашањето/опциите).
    final myToken = ++_narrationToken;

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 80);
    }

    // Краток визуелен "светкање" ефект на избраната опција пред премин.
    setState(() => _selectedOption = option);
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted || myToken != _narrationToken) return;

    final outcomeKey = option == 1 ? _out1Key(_currentStory) : _out2Key(_currentStory);
    setState(() {
      _showingOutcome = true;
      _lastOutcomeKey = outcomeKey;
      _selectedOption = null;
    });

    await _speak(outcomeKey, _t(outcomeKey));
    if (!mounted || myToken != _narrationToken) return;

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 250);
    }

    final isLastStory = _currentStory + 1 >= _storyCount;
    if (isLastStory) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || myToken != _narrationToken) return;
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150, 100, 250]);
      }
      await _speak('all_done', _t('all_done'));
      if (!mounted || myToken != _narrationToken) return;
      setState(() => _allDone = true);
    }
  }

  /// "Продолжи" - го притиска детето само кога е спремно (нема присилно
  /// темпирање), за да не се брза читателот на титловите.
  Future<void> _continue() async {
    final isLastStory = _currentStory + 1 >= _storyCount;
    if (isLastStory) {
      _restart();
      return;
    }
    final myToken = ++_narrationToken;
    setState(() {
      _currentStory++;
      _showingOutcome = false;
      _lastOutcomeKey = null;
    });
    if (!mounted || myToken != _narrationToken) return;
    _readStory();
  }

  void _restart() {
    _narrationToken++;
    setState(() {
      _currentStory = 0;
      _showingOutcome = false;
      _allDone = false;
      _lastOutcomeKey = null;
    });
    // Без порта/објаснување повторно - веќе е искористено еднаш засекогаш.
    _readStory();
  }

  @override
  Widget build(BuildContext context) {
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.story_choices'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            _buildExplanationButton(contrastColor),
            if (_explanationOpen) _buildExplanationPanel(contrastColor),
            Expanded(
              child: _showingOutcome
                  ? _buildOutcomeView(contrastColor, hc)
                  : _buildStoryView(contrastColor, hc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final label = _explanationEverUsed
        ? 'story.explanation_used'.tr()
        : (_explanationOpen ? 'story.explanation_toggle_close'.tr() : 'story.explanation_toggle_open'.tr());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Opacity(
        opacity: _explanationEverUsed ? 0.5 : 1.0,
        child: Semantics(
          label: label,
          button: !_explanationEverUsed,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _explanationEverUsed ? null : _toggleExplanation,
              icon: Icon(
                _explanationEverUsed
                    ? Icons.lock_rounded
                    : (_explanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded),
                size: 26,
              ),
              label: Text(
                label,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _explanationEverUsed
                    ? AccessibilityUtils.getDisabledColor(context)
                    : (_explanationOpen ? AccessibilityUtils.getDisabledColor(context) : _moduleAccent),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 3,
              ),
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
              Icon(Icons.auto_stories_rounded, color: _moduleAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'story.explanation_title'.tr(),
                  style: GameTypography.heading(context, contrast, 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'story.explanation_text'.tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
        ],
      ),
    );
  }

  /// Сцена на тековната приказна: позадина прилагодена на бои (или чисто
  /// црна во режим висок контраст), со позиционирани икони во различни
  /// големини според важноста во приказната. Чисто визуелно (исклучено од
  /// читачот на екран, за да не се дуплира со гласовниот опис).
  Widget _storyScene(BuildContext context, bool hc, double height) {
    final items = _storyScenes[_currentStory] ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final bg = _sceneBackgrounds[_currentStory] ?? const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

    return ExcludeSemantics(
      child: Container(
        height: height,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: hc
              ? null
              : LinearGradient(colors: bg, begin: Alignment.topCenter, end: Alignment.bottomCenter),
          color: hc ? Colors.black : null,
          border: Border.all(
            color: hc ? Colors.white : _moduleAccent.withOpacity(0.3),
            width: hc ? 2 : 1.5,
          ),
        ),
        child: Stack(
          children: items.map((item) {
            // Во режим висок контраст: секоја икона станува светло жолта на
            // црна позадина, со бел раб околу неа за максимална видливост.
            final iconColor = hc ? const Color(0xFFFFFF00) : item.color;
            return Align(
              alignment: item.align,
              child: Container(
                padding: EdgeInsets.all(hc ? 4 : 0),
                decoration: hc
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      )
                    : null,
                child: Icon(item.icon, size: item.size, color: iconColor),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Секогаш видлив текст-облак - и приказната, и исходот, се прикажуваат
  /// тука (никогаш само изговорени) - клучно за деца со оштетен слух.
  Widget _captionBox(Color contrast, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _moduleAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _moduleAccent.withOpacity(0.3), width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GameTypography.body(context, contrast, 21),
      ),
    );
  }

  Widget _buildStoryView(Color contrast, bool hc) {
    final screenH = MediaQuery.of(context).size.height;
    final sceneHeight = (screenH * 0.34).clamp(240.0, 420.0);
    final opt1Key = _opt1Key(_currentStory);
    final opt2Key = _opt2Key(_currentStory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          // Сцена + текст на приказната - зафаќаат поголем дел од екранот.
          Expanded(
            flex: 11,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  _storyScene(context, hc, sceneHeight),
                  _captionBox(contrast, _t(_storyKey(_currentStory))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'story.what_next'.tr(),
            textAlign: TextAlign.center,
            style: GameTypography.heading(context, contrast, 20),
          ),
          const SizedBox(height: 10),
          // Опциите го пополнуваат преостанатиот простор.
          Expanded(
            flex: 9,
            child: Column(
              children: [
                Expanded(
                  child: _optionButton(
                    contrast,
                    number: 1,
                    text: _t(opt1Key),
                    icon: _optionIcons[opt1Key] ?? Icons.touch_app_rounded,
                    selected: _selectedOption == 1,
                    onTap: () => _choose(1),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _optionButton(
                    contrast,
                    number: 2,
                    text: _t(opt2Key),
                    icon: _optionIcons[opt2Key] ?? Icons.touch_app_rounded,
                    selected: _selectedOption == 2,
                    onTap: () => _choose(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 3Д копче за опција - со сопствена икона, а при избор кратко "светнува"
  /// (посветла боја + поголема сенка) пред премин кон исходот.
  Widget _optionButton(
    Color contrast, {
    required int number,
    required String text,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final baseColor = AccessibilityUtils.getPrimaryButtonBackground(context);
    final glowColor = hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A);
    return Semantics(
      label: '${'story.option_$number'.tr()}: $text. ${'features.tap_to_open'.tr()}',
      button: _buttonsUnlocked,
      child: AbsorbPointer(
        absorbing: !_buttonsUnlocked,
        child: Opacity(
          opacity: _buttonsUnlocked ? 1.0 : 0.4,
          child: AnimatedScale(
            scale: selected ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: (selected ? glowColor : Colors.black).withOpacity(selected ? 0.55 : 0.25),
                    blurRadius: selected ? 26 : 10,
                    spreadRadius: selected ? 2 : 0,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: selected ? glowColor : baseColor,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onTap,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(hc ? 0.9 : 0.35), width: hc ? 2 : 1),
                      gradient: hc
                          ? null
                          : LinearGradient(
                              colors: [
                                Color.lerp(selected ? glowColor : baseColor, Colors.white, 0.22)!,
                                selected ? glowColor : baseColor,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 46, color: Colors.white),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
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
      ),
    );
  }

  Widget _buildOutcomeView(Color contrast, bool hc) {
    final screenH = MediaQuery.of(context).size.height;
    final sceneHeight = (screenH * 0.34).clamp(240.0, 420.0);
    final isLastStory = _currentStory + 1 >= _storyCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _storyScene(context, hc, sceneHeight),
                  if (_lastOutcomeKey != null) _captionBox(contrast, _t(_lastOutcomeKey!)),
                  const SizedBox(height: 18),
                  Text(
                    'story.the_end'.tr(),
                    style: GameTypography.heading(context, contrast, 22),
                  ),
                  if (_allDone) ...[
                    const SizedBox(height: 8),
                    Text(
                      'story.all_done'.tr(),
                      textAlign: TextAlign.center,
                      style: GameTypography.body(context, contrast, 16),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_allDone)
            // Последната приказна целосно заврши (вклучувајќи го all_done.mp3) -
            // сега се појавуваат излез и обиди повторно.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _bigCircleButton(icon: Icons.home_rounded, label: 'story.exit_to_menu'.tr(), color: AccessibilityUtils.getDisabledColor(context), onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 28),
                _bigCircleButton(icon: Icons.replay_rounded, label: 'story.play_again'.tr(), color: _moduleAccent, onTap: _restart),
              ],
            )
          else if (!isLastStory)
            // Не е последната приказна - копче за продолжување кон следната.
            _bigCircleButton(icon: Icons.arrow_forward_rounded, label: 'story.next_story'.tr(), color: _moduleAccent, onTap: _continue)
          else
            // Последна приказна, но all_done.mp3 сè уште не завршило - нема
            // копче "следна приказна" (нема потреба), а излез/рестарт сè
            // уште не се појавуваат.
            const SizedBox(height: 74),
        ],
      ),
    );
  }

  /// Големо кружно 3Д копче (само икона) - продолжи / излез / обиди повторно.
  Widget _bigCircleButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: true,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(hc ? 0 : 0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          color: hc ? Colors.black : color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hc
                    ? null
                    : LinearGradient(
                        colors: [Color.lerp(color, Colors.white, 0.3)!, color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                border: hc ? Border.all(color: Colors.white, width: 2) : null,
              ),
              padding: const EdgeInsets.all(30),
              child: Icon(icon, size: 52, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Опис на еден елемент во сцената на приказна: икона, големина, боја,
/// и позиција (Alignment, -1..1 по X и Y).
class _SceneItem {
  final IconData icon;
  final double size;
  final Color color;
  final Alignment align;

  const _SceneItem({
    required this.icon,
    required this.size,
    required this.color,
    required this.align,
  });
}