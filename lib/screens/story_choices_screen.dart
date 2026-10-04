import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

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

  /// Боја на секоја од двете опции.
  static const List<Color> _optionColors = [Color(0xFF2563EB), Color(0xFFDB2777)];

  bool get _hc => AccessibilityUtils.isHighContrast(context);
  Color get _fg => _hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

  @override
  Widget build(BuildContext context) {
    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'features.story_choices'.tr(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['📖', '✨', '🌳', '🚀', '🐾', '⭐'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 820) / 2).clamp(16.0, double.infinity);
            final sceneHeight = (constraints.maxHeight * 0.36).clamp(220.0, 400.0);
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 12, side, 28),
              children: [
                _buildExplanationButton(),
                if (_explanationOpen)
                  PlayfulExplainPanel(
                    icon: Icons.auto_stories_rounded,
                    title: 'story.explanation_title'.tr(),
                    text: 'story.explanation_text'.tr(),
                    accent: _moduleAccent,
                  ),
                const SizedBox(height: 16),
                _storyProgress(),
                const SizedBox(height: 16),
                if (_showingOutcome)
                  ..._buildOutcomeView(sceneHeight)
                else
                  ..._buildStoryView(sceneHeight),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Објаснувањето може да се отвори само еднаш - потоа е заклучено.
  Widget _buildExplanationButton() {
    final label = _explanationEverUsed
        ? 'story.explanation_used'.tr()
        : (_explanationOpen ? 'story.explanation_toggle_close'.tr() : 'story.explanation_toggle_open'.tr());
    return AbsorbPointer(
      absorbing: _explanationEverUsed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _explanationEverUsed ? 0.5 : 1.0,
        child: PlayfulExplainButton(
          open: _explanationOpen,
          label: label,
          onTap: _toggleExplanation,
        ),
      ),
    );
  }

  /// Три книги - поминатите и тековната приказна светат златно.
  Widget _storyProgress() {
    final hc = _hc;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _storyCount; i++) ...[
            if (i > 0)
              Container(
                width: 28,
                height: 3,
                color: i <= _currentStory
                    ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
                    : Colors.white.withValues(alpha: 0.25),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: i == _currentStory ? 50 : 40,
              height: i == _currentStory ? 50 : 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= _currentStory
                    ? (hc ? Colors.black : Playful.sun)
                    : (hc ? Colors.black : Colors.white.withValues(alpha: 0.1)),
                border: Border.all(
                  color: i <= _currentStory ? Colors.white : Colors.white.withValues(alpha: 0.5),
                  width: i == _currentStory ? 3 : 2,
                ),
                boxShadow: i == _currentStory && !hc
                    ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 16)]
                    : null,
              ),
              child: Icon(
                i < _currentStory ? Icons.check_rounded : Icons.menu_book_rounded,
                size: i == _currentStory ? 26 : 20,
                color: i <= _currentStory
                    ? (hc ? const Color(0xFFFFFF00) : Playful.ink)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Сцена на тековната приказна: осветлена „страница од сликовница“
  /// (пастелна позадина, златен раб, сјај) со позиционирани икони. Во
  /// висок контраст - црна со жолти икони. Чисто визуелно.
  Widget _storyScene(bool hc, double height) {
    final items = _storyScenes[_currentStory] ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final bg = _sceneBackgrounds[_currentStory] ?? const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

    return ExcludeSemantics(
      child: PopIn(
        key: ValueKey('scene_$_currentStory'),
        child: Container(
          height: height,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: hc ? null : LinearGradient(colors: bg, begin: Alignment.topCenter, end: Alignment.bottomCenter),
            color: hc ? Colors.black : null,
            border: Border.all(color: hc ? Colors.white : Playful.sun, width: hc ? 2 : 4),
            boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.35), blurRadius: 26)],
          ),
          // Иконите се смалуваат на тесни екрани (пр. 360px) за да не се
          // преклопуваат; на широки екрани остануваат во полна големина.
          child: LayoutBuilder(
            builder: (context, c) {
              final s = math.min(c.maxWidth / 480, c.maxHeight / 260).clamp(0.55, 1.0);
              return Stack(
            children: [
              for (final item in items)
                Align(
                  alignment: item.align,
                  child: Container(
                    padding: EdgeInsets.all(hc ? 4 : 0),
                    decoration: hc
                        ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))
                        : null,
                    child: Icon(
                      item.icon,
                      size: item.size * s,
                      color: hc ? const Color(0xFFFFFF00) : item.color,
                      shadows: hc ? null : [Shadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 12)],
                    ),
                  ),
                ),
            ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Секогаш видлив текст - приказната и исходот се и прикажани, не само
  /// изговорени (клучно за деца со оштетен слух). Бел облак со опашка.
  Widget _captionBox(String text) {
    final hc = _hc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: ShapeDecoration(
        color: hc ? Colors.black : Colors.white,
        shape: SpeechBubbleBorder(
          radius: 26,
          side: BorderSide(color: hc ? Colors.white : Playful.sun, width: 3),
        ),
        shadows: hc ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Playful.body(21, color: hc ? Colors.white : Playful.ink),
      ),
    );
  }

  List<Widget> _buildStoryView(double sceneHeight) {
    final hc = _hc;
    final opt1Key = _opt1Key(_currentStory);
    final opt2Key = _opt2Key(_currentStory);
    return [
      _storyScene(hc, sceneHeight),
      const SizedBox(height: 16),
      _captionBox(_t(_storyKey(_currentStory))),
      const SizedBox(height: 18),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded, color: hc ? _fg : Playful.sun, size: 26),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'story.what_next'.tr(),
              textAlign: TextAlign.center,
              style: Playful.display(24, color: _fg),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // Додека се чита - мал брановиден знак; копчињата се уште заклучени.
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buttonsUnlocked || hc
            ? const SizedBox(key: ValueKey('ready'), height: 8)
            : const Center(
                key: ValueKey('reading'),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SoundWave(color: Playful.sun, bars: 9, height: 26, barWidth: 5),
                ),
              ),
      ),
      _optionButton(
        number: 1,
        text: _t(opt1Key),
        icon: _optionIcons[opt1Key] ?? Icons.touch_app_rounded,
        selected: _selectedOption == 1,
        onTap: () => _choose(1),
      ),
      const SizedBox(height: 14),
      _optionButton(
        number: 2,
        text: _t(opt2Key),
        icon: _optionIcons[opt2Key] ?? Icons.touch_app_rounded,
        selected: _selectedOption == 2,
        onTap: () => _choose(2),
      ),
    ];
  }

  /// Шарена картичка за опција: златен број, икона во бел круг, текст.
  /// При избор кратко светнува зелено пред премин кон исходот.
  Widget _optionButton({
    required int number,
    required String text,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final hc = _hc;
    final base = selected ? const Color(0xFF16A34A) : _optionColors[(number - 1) % _optionColors.length];
    return Semantics(
      label: '${'story.option_$number'.tr()}: $text. ${'features.tap_to_open'.tr()}',
      button: _buttonsUnlocked,
      child: ExcludeSemantics(
        child: AbsorbPointer(
          absorbing: !_buttonsUnlocked,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _buttonsUnlocked ? 1.0 : 0.4,
            child: AnimatedScale(
              scale: selected ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: PressableScale(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      constraints: const BoxConstraints(minHeight: 110),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: hc ? (selected ? const Color(0xFF333300) : Colors.black) : null,
                        gradient: hc
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color.lerp(base, Colors.white, 0.08)!, Color.lerp(base, Colors.black, 0.35)!],
                              ),
                        border: Border.all(
                          color: hc ? (selected ? const Color(0xFFFFFF00) : Colors.white) : (selected ? Playful.sun : Colors.white),
                          width: selected ? 4 : 3,
                        ),
                        boxShadow: hc
                            ? null
                            : [BoxShadow(color: (selected ? Playful.sun : base).withValues(alpha: selected ? 0.7 : 0.45), blurRadius: selected ? 28 : 16)],
                      ),
                      child: Row(
                        children: [
                          // Број на опцијата.
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hc ? Colors.black : Playful.sun,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text('$number', style: Playful.display(20, color: hc ? Colors.white : Playful.ink)),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hc ? Colors.black : Colors.white.withValues(alpha: 0.18),
                              border: Border.all(color: Colors.white.withValues(alpha: hc ? 1 : 0.8), width: 2),
                            ),
                            child: Icon(icon, size: 42, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              text,
                              style: Playful.title(23, color: Colors.white),
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
      ),
    );
  }

  List<Widget> _buildOutcomeView(double sceneHeight) {
    final hc = _hc;
    final isLastStory = _currentStory + 1 >= _storyCount;
    return [
      _storyScene(hc, sceneHeight),
      const SizedBox(height: 16),
      if (_lastOutcomeKey != null) _captionBox(_t(_lastOutcomeKey!)),
      const SizedBox(height: 20),
      PopIn(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_rounded, color: hc ? _fg : Playful.sun, size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'story.the_end'.tr(),
                textAlign: TextAlign.center,
                style: Playful.display(26, color: _fg),
              ),
            ),
          ],
        ),
      ),
      if (_allDone) ...[
        const SizedBox(height: 8),
        Text(
          'story.all_done'.tr(),
          textAlign: TextAlign.center,
          style: Playful.body(18, color: _fg),
        ),
      ],
      const SizedBox(height: 24),
      if (_allDone)
        // Последната приказна целосно заврши - излез и обиди повторно.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 32,
          runSpacing: 20,
          children: [
            _bigCircleButton(
              icon: Icons.home_rounded,
              label: 'story.exit_to_menu'.tr(),
              gold: false,
              onTap: () => Navigator.of(context).pop(),
            ),
            _bigCircleButton(
              icon: Icons.replay_rounded,
              label: 'story.play_again'.tr(),
              gold: true,
              onTap: _restart,
            ),
          ],
        )
      else if (!isLastStory)
        Center(
          child: _bigCircleButton(
            icon: Icons.arrow_forward_rounded,
            label: 'story.next_story'.tr(),
            gold: true,
            onTap: _continue,
          ),
        )
      else
        // Последна приказна, но завршната порака сè уште трае.
        const SizedBox(height: 74),
    ];
  }

  /// Голем круг со икона и натпис под него - продолжи / излез / одново.
  Widget _bigCircleButton({required IconData icon, required String label, required bool gold, required VoidCallback onTap}) {
    final hc = _hc;
    final shown = label.replaceAll(RegExp(r'\.\s*$'), '');
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RippleRings(
                color: hc ? Colors.white : Playful.sun,
                active: gold && !hc,
                spread: 18,
                child: PressableScale(
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : (gold ? Playful.sun : Colors.white.withValues(alpha: 0.12)),
                      border: Border.all(color: Colors.white, width: hc ? 2 : 4),
                      boxShadow: hc || !gold ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 22)],
                    ),
                    child: Icon(icon, size: 52, color: hc ? Colors.white : (gold ? Playful.ink : Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(shown, textAlign: TextAlign.center, style: Playful.title(18, color: _fg)),
            ],
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