// import 'dart:async';
// import 'dart:math' as math;
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:easy_localization/easy_localization.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
// import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
// import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
// import 'package:hear_and_see_safe/utils/vibration_utils.dart';
// import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
// import 'package:hear_and_see_safe/widgets/playful_ui.dart';

// /// Множител за големината на текстот на овој екран (поголеми букви).
// const double _kStoryText = 1.6;

// /// Приказна – твој избор: слушаш/читаш кратка приказна, избираш што ќе се
// /// случи понатаму, слушаш/читаш го исходот. И приказната И исходот се
// /// секогаш прикажани и на екран (не само изговорени) - клучно за деца со
// /// оштетен слух. Целиот говор оди преку системскиот text-to-speech (без
// /// однапред снимени mp3 датотеки). Напредувањето кон следната приказна е
// /// рачно (копче „Продолжи"), без присилно темпирање.
// class StoryChoicesScreen extends StatefulWidget {
//   const StoryChoicesScreen({super.key});

//   @override
//   State<StoryChoicesScreen> createState() => _StoryChoicesScreenState();
// }

// class _StoryChoicesScreenState extends State<StoryChoicesScreen> {
//   static const Color _moduleAccent = Color(0xFF0F766E);
//   static const int _storyCount = 3;

//   /// Еден елемент во сцената на приказната: икона, големина, боја, и
//   /// позиција во сцената (Alignment: -1..1 по X и Y). Режимот со висок
//   /// контраст секогаш презема свои бои, без разлика на ова.
//   static const List<_SceneItem> _story1Scene = [
//     _SceneItem(icon: Icons.park_rounded, size: 140, color: Color(0xFF15803D), align: Alignment(-0.6, -0.35)), // дрво - најголемо
//     _SceneItem(icon: Icons.attractions_rounded, size: 130, color: Color(0xFFB45309), align: Alignment(0.55, -0.25)), // лулашка - најголема
//     _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(-0.05, 0.55)), // силуета - средна
//     _SceneItem(icon: Icons.local_florist_rounded, size: 55, color: Color(0xFFDB2777), align: Alignment(0.8, 0.85)), // цвеќе - најмало
//   ];
//   static const List<_SceneItem> _story2Scene = [
//     _SceneItem(icon: Icons.opacity_rounded, size: 125, color: Color(0xFF0284C7), align: Alignment(-0.55, -0.3)), // вода - големо
//     _SceneItem(icon: Icons.local_drink_rounded, size: 125, color: Color(0xFFEA580C), align: Alignment(0.55, -0.3)), // сок - големо
//     _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(0.0, 0.55)), // силуета - средно
//     _SceneItem(icon: Icons.wb_sunny_rounded, size: 50, color: Color(0xFFD97706), align: Alignment(0.85, -0.8)), // сонце - најмало
//   ];
//   static const List<_SceneItem> _story3Scene = [
//     _SceneItem(icon: Icons.menu_book_rounded, size: 125, color: Color(0xFF4338CA), align: Alignment(-0.55, -0.25)), // книга - големо
//     _SceneItem(icon: Icons.pets_rounded, size: 120, color: Color(0xFFB45309), align: Alignment(0.55, -0.3)), // животно - големо
//     _SceneItem(icon: Icons.person_rounded, size: 88, color: Color(0xFF1E293B), align: Alignment(0.0, 0.55)), // силуета - средно
//     _SceneItem(icon: Icons.star_rounded, size: 50, color: Color(0xFFCA8A04), align: Alignment(0.85, -0.8)), // ѕвезда - најмало
//   ];
//   static const Map<int, List<_SceneItem>> _storyScenes = {
//     0: _story1Scene,
//     1: _story2Scene,
//     2: _story3Scene,
//   };
//   static const Map<int, List<Color>> _sceneBackgrounds = {
//     0: [Color(0xFFECFDF5), Color(0xFFBBF7D0)], // парк - зеленило
//     1: [Color(0xFFF0F9FF), Color(0xFFBAE6FD)], // вода/жед - сино
//     2: [Color(0xFFEEF2FF), Color(0xFFC7D2FE)], // читање/вселена - виолетово
//   };

//   /// Икона на секоја опција - одговара на содржината на одговорот.
//   static const Map<String, IconData> _optionIcons = {
//     's1_o1': Icons.attractions_rounded, // лулашка
//     's1_o2': Icons.local_florist_rounded, // цвеќиња
//     's2_o1': Icons.water_drop_rounded, // вода
//     's2_o2': Icons.local_drink_rounded, // сок
//     's3_o1': Icons.pets_rounded, // книга за животни
//     's3_o2': Icons.rocket_launch_rounded, // книга за вселена
//   };

//   late VoiceAssistantService _voiceAssistant;
//   /// Само за mk - за en/sq никогаш не се обидуваме со mp3.
//   final AudioPlayer _voicePlayer = AudioPlayer();

//   int _currentStory = 0;
//   /// Се зголемува секогаш кога почнува нова секвенца на читање/избор -
//   /// секоја веќе-стартувана асинхрона секвенца проверува дали токенот сè
//   /// уште е ист, и ако не е (значи е застарена), веднаш прекинува - спречува
//   /// преклопување на говор ако детето избере опција додека сè уште трае
//   /// претходното читање.
//   int _narrationToken = 0;
//   bool _showingOutcome = false;
//   bool _allDone = false;
//   String? _lastOutcomeKey;
//   bool _explanationOpen = false;
//   /// Копчињата за избор се отклучуваат дури откако ЦЕЛОТО читање (текст +
//   /// "што ќе се случи" + двете опции) целосно ќе заврши - спречува
//   /// преклопување на говор ако детето допре пребрзо.
//   bool _buttonsUnlocked = false;

//   /// "Порта" на почетокот: 5 секунди во кои детето може да го притисне
//   /// објаснувањето (или тоа автоматски ќе се отвори по истек на времето).
//   /// Штом објаснувањето еднаш ќе се искористи, останува трајно заклучено.
//   Timer? _gateTimer;
//   bool _explanationEverUsed = false;
//   /// За краток визуелен "светкање" ефект на избраната опција пред премин
//   /// кон екранот со исход.
//   int? _selectedOption;

//   String get _langCode => context.locale.languageCode;

//   @override
//   void initState() {
//     super.initState();
//     _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
//     _voiceAssistant.initialize();
//     WidgetsBinding.instance.addPostFrameCallback((_) => _startGate());
//   }

//   @override
//   void dispose() {
//     // Го запира говорот веднаш штом се напушта екранот - без разлика дали
//     // објаснувањето било отворено или не.
//     _gateTimer?.cancel();
//     _voiceAssistant.stop();
//     _voicePlayer.dispose();
//     super.dispose();
//   }

//   String _storyKey(int i) => 's${i + 1}_text';
//   String _opt1Key(int i) => 's${i + 1}_o1';
//   String _opt2Key(int i) => 's${i + 1}_o2';
//   String _out1Key(int i) => 's${i + 1}_out1';
//   String _out2Key(int i) => 's${i + 1}_out2';

//   /// Превод-клуч (со префикс "story.") - за текст на екран И за говор.
//   String _t(String key) => 'story.$key'.tr();

//   /// За mk: пробува однапред снимена mp3 датотека (веќе ги имаш генерирани
//   /// за mk), TTS како резерва ако таа конкретна датотека недостасува. За
//   /// en/sq: секогаш само системски TTS (за да не треба да генерираш толку
//   /// многу дополнителни датотеки). Во двата случаи го чека говорот целосно
//   /// да заврши пред да продолжи понатамошниот тек.
//   /// Исклучиво снимка (mp3), за СИТЕ јазици - без TTS-резерва. Ако клипот
//   /// недостасува/не успее, тишина - намерно, по барање (го отстранува и
//   /// стариот бag каде само mk воопшто се обидуваше со mp3, и race-condition-от
//   /// каде "портата" од 5 секунди можеше да пресече говор во тек).
//   Future<void> _speak(String key, [String? fallbackText]) async {
//     if (!mounted) return;

//     // Секогаш прво прекини сè што можеби сè уште свири - за да не се
//     // преклопат два клипа ако претходниот повик сè уште трае.
//     try {
//       await _voicePlayer.stop();
//     } catch (_) {}
//     _voiceAssistant.stop();

//     final relativePath = 'audio/story_choices/$_langCode/$key.mp3';

//     // Некои платформи (веб) тивко "голтаат" формат-грешка без да фрлат
//     // исклучок од .play() - плеерот никогаш не влегува во состојба
//     // "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
//     // почнал, а не само дека .play() не фрлил грешка.
//     bool reachedPlaying = false;
//     final startedCompleter = Completer<void>();
//     final finishedCompleter = Completer<void>();
//     late final StreamSubscription<PlayerState> stateSub;
//     stateSub = _voicePlayer.onPlayerStateChanged.listen((state) {
//       if (state == PlayerState.playing) {
//         reachedPlaying = true;
//         if (!startedCompleter.isCompleted) startedCompleter.complete();
//       }
//       if (state == PlayerState.completed || state == PlayerState.stopped) {
//         if (!startedCompleter.isCompleted) startedCompleter.complete();
//         if (!finishedCompleter.isCompleted) finishedCompleter.complete();
//       }
//     });

//     bool playCallSucceeded = false;
//     try {
//       await _voicePlayer.play(AssetSource(relativePath));
//       playCallSucceeded = true;
//     } catch (_) {
//       playCallSucceeded = false;
//     }

//     if (playCallSucceeded) {
//       await startedCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
//       if (reachedPlaying) {
//         await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
//       }
//     }
//     await stateSub.cancel();
//     // Намерно нема TTS-резерва - тишина ако клипот недостасува.
//   }

//   /// "Порта" на почетокот: 5 секунди во кои се изговара името на играта, а
//   /// детето може со клик на објаснувањето да одлучи тоа да се пушти прво.
//   /// Ако не притисне ништо, по истек на времето автоматски се отвора
//   /// објаснувањето. Приказната НЕ почнува додека објаснувањето не заврши
//   /// (природно или со рачно затворање) - двете никогаш не звучат заедно.
//   Future<void> _startGate() async {
//     final myToken = ++_narrationToken;
//     _gateTimer = Timer(const Duration(seconds: 5), () {
//       if (!mounted || myToken != _narrationToken) return;
//       if (!_explanationEverUsed && !_explanationOpen) {
//         _openExplanation();
//       }
//     });
//     _voiceAssistant.stop();
//     await _speak('game_name', 'features.story_choices'.tr());
//   }

//   void _openExplanation() {
//     _gateTimer?.cancel();
//     _narrationToken++;
//     setState(() => _explanationOpen = true);
//     _speak('explanation', _t('explanation_text')).then((_) {
//       if (!mounted || !_explanationOpen) return;
//       // Мп3-то/говорот заврши природно - автоматски затвори и продолжи.
//       _closeExplanationAndProceed();
//     });
//   }

//   void _closeExplanationAndProceed() {
//     _voiceAssistant.stop();
//     _voicePlayer.stop();
//     setState(() {
//       _explanationOpen = false;
//       _explanationEverUsed = true;
//     });
//     // Штом објаснувањето е веќе искористено, приказната конечно може да
//     // почне (само ако не е веќе во тек/завршена).
//     if (!_showingOutcome && !_allDone && !_buttonsUnlocked) {
//       _readStory();
//     }
//   }

//   void _toggleExplanation() {
//     if (_explanationEverUsed) return; // трајно заклучено по едно користење
//     if (_explanationOpen) {
//       _closeExplanationAndProceed();
//     } else {
//       _openExplanation();
//     }
//   }

//   Future<void> _readStory() async {
//     final myToken = ++_narrationToken;
//     setState(() {
//       _showingOutcome = false;
//       _allDone = false;
//       _lastOutcomeKey = null;
//       _buttonsUnlocked = false;
//     });

//     await _speak(_storyKey(_currentStory), _t(_storyKey(_currentStory)));
//     if (!mounted || myToken != _narrationToken) return;

//     await _speak('what_next', _t('what_next'));
//     if (!mounted || myToken != _narrationToken) return;

//     await _speak(_opt1Key(_currentStory), _t(_opt1Key(_currentStory)));
//     if (!mounted || myToken != _narrationToken) return;

//     await _speak(_opt2Key(_currentStory), _t(_opt2Key(_currentStory)));
//     if (!mounted || myToken != _narrationToken) return;

//     // Дури сега, откако СЀ е прочитано, копчињата стануваат допирливи.
//     setState(() => _buttonsUnlocked = true);
//   }

//   Future<void> _choose(int option) async {
//     if (_showingOutcome || !_buttonsUnlocked) return;
//     // Веднаш поништи ја секоја сè уште активна секвенца на читање (пр. ако
//     // детето избрало опција додека сè уште траеше читањето на насловот/
//     // прашањето/опциите).
//     final myToken = ++_narrationToken;

//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 80);
//     }

//     // Краток визуелен "светкање" ефект на избраната опција пред премин.
//     setState(() => _selectedOption = option);
//     await Future.delayed(const Duration(milliseconds: 220));
//     if (!mounted || myToken != _narrationToken) return;

//     final outcomeKey = option == 1 ? _out1Key(_currentStory) : _out2Key(_currentStory);
//     setState(() {
//       _showingOutcome = true;
//       _lastOutcomeKey = outcomeKey;
//       _selectedOption = null;
//     });

//     await _speak(outcomeKey, _t(outcomeKey));
//     if (!mounted || myToken != _narrationToken) return;

//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 250);
//     }

//     final isLastStory = _currentStory + 1 >= _storyCount;
//     if (isLastStory) {
//       await Future.delayed(const Duration(milliseconds: 300));
//       if (!mounted || myToken != _narrationToken) return;
//       if (await VibrationUtils.hasVibrator()) {
//         await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150, 100, 250]);
//       }
//       await _speak('all_done', _t('all_done'));
//       if (!mounted || myToken != _narrationToken) return;
//       setState(() => _allDone = true);
//     }
//   }

//   /// "Продолжи" - го притиска детето само кога е спремно (нема присилно
//   /// темпирање), за да не се брза читателот на титловите.
//   Future<void> _continue() async {
//     final isLastStory = _currentStory + 1 >= _storyCount;
//     if (isLastStory) {
//       _restart();
//       return;
//     }
//     final myToken = ++_narrationToken;
//     setState(() {
//       _currentStory++;
//       _showingOutcome = false;
//       _lastOutcomeKey = null;
//     });
//     if (!mounted || myToken != _narrationToken) return;
//     _readStory();
//   }

//   void _restart() {
//     _narrationToken++;
//     setState(() {
//       _currentStory = 0;
//       _showingOutcome = false;
//       _allDone = false;
//       _lastOutcomeKey = null;
//     });
//     // Без порта/објаснување повторно - веќе е искористено еднаш засекогаш.
//     _readStory();
//   }

//   /// Боја на секоја од двете опции.
//   static const List<Color> _optionColors = [Color(0xFF2563EB), Color(0xFFDB2777)];

//   bool get _hc => AccessibilityUtils.isHighContrast(context);
//   Color get _fg => _hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

//   @override
//   Widget build(BuildContext context) {
//     return GameScreenChrome(
//       accent: _moduleAccent,
//       title: 'features.story_choices'.tr(),
//       bodyBackground: const EmojiBackdrop(
//         emojis: ['📖', '✨', '🌳', '🚀', '🐾', '⭐'],
//         tint: _moduleAccent,
//       ),
//       child: SafeArea(
//         child: LayoutBuilder(
//           builder: (context, constraints) {
//             final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
//             final sceneHeight = (constraints.maxHeight * 0.36).clamp(220.0, 400.0);
//             return ListView(
//               padding: EdgeInsets.fromLTRB(side, 12, side, 28),
//               children: [
//                 _buildExplanationButton(),
//                 if (_explanationOpen)
//                   PlayfulExplainPanel(
//                     icon: Icons.auto_stories_rounded,
//                     title: 'story.explanation_title'.tr(),
//                     text: 'story.explanation_text'.tr(),
//                     accent: _moduleAccent,
//                   ),
//                 const SizedBox(height: 16),
//                 _storyProgress(),
//                 const SizedBox(height: 16),
//                 if (_showingOutcome)
//                   ..._buildOutcomeView(sceneHeight)
//                 else
//                   ..._buildStoryView(sceneHeight),
//               ],
//             );
//           },
//         ),
//       ),
//     );
//   }

//   /// Објаснувањето може да се отвори само еднаш - потоа е заклучено.
//   Widget _buildExplanationButton() {
//     final label = _explanationEverUsed
//         ? 'story.explanation_used'.tr()
//         : (_explanationOpen ? 'story.explanation_toggle_close'.tr() : 'story.explanation_toggle_open'.tr());
//     return AbsorbPointer(
//       absorbing: _explanationEverUsed,
//       child: AnimatedOpacity(
//         duration: const Duration(milliseconds: 250),
//         opacity: _explanationEverUsed ? 0.5 : 1.0,
//         child: PlayfulExplainButton(
//           open: _explanationOpen,
//           label: label,
//           onTap: _toggleExplanation,
//         ),
//       ),
//     );
//   }

//   /// Три книги - поминатите и тековната приказна светат златно.
//   Widget _storyProgress() {
//     final hc = _hc;
//     return ExcludeSemantics(
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           for (var i = 0; i < _storyCount; i++) ...[
//             if (i > 0)
//               Container(
//                 width: 28,
//                 height: 3,
//                 color: i <= _currentStory
//                     ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
//                     : Colors.white.withValues(alpha: 0.25),
//               ),
//             AnimatedContainer(
//               duration: const Duration(milliseconds: 300),
//               width: i == _currentStory ? 50 : 40,
//               height: i == _currentStory ? 50 : 40,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: i <= _currentStory
//                     ? (hc ? Colors.black : Playful.sun)
//                     : (hc ? Colors.black : Colors.white.withValues(alpha: 0.1)),
//                 border: Border.all(
//                   color: i <= _currentStory ? Colors.white : Colors.white.withValues(alpha: 0.5),
//                   width: i == _currentStory ? 3 : 2,
//                 ),
//                 boxShadow: i == _currentStory && !hc
//                     ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 16)]
//                     : null,
//               ),
//               child: Icon(
//                 i < _currentStory ? Icons.check_rounded : Icons.menu_book_rounded,
//                 size: i == _currentStory ? 26 : 20,
//                 color: i <= _currentStory
//                     ? (hc ? const Color(0xFFFFFF00) : Playful.ink)
//                     : Colors.white.withValues(alpha: 0.7),
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }

//   /// Сцена на тековната приказна: осветлена „страница од сликовница“
//   /// (пастелна позадина, златен раб, сјај) со позиционирани икони. Во
//   /// висок контраст - црна со жолти икони. Чисто визуелно.
//   Widget _storyScene(bool hc, double height) {
//     final items = _storyScenes[_currentStory] ?? const [];
//     if (items.isEmpty) return const SizedBox.shrink();
//     final bg = _sceneBackgrounds[_currentStory] ?? const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

//     return ExcludeSemantics(
//       child: PopIn(
//         key: ValueKey('scene_$_currentStory'),
//         child: Container(
//           height: height,
//           width: double.infinity,
//           clipBehavior: Clip.antiAlias,
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(28),
//             gradient: hc ? null : LinearGradient(colors: bg, begin: Alignment.topCenter, end: Alignment.bottomCenter),
//             color: hc ? Colors.black : null,
//             border: Border.all(color: hc ? Colors.white : Playful.sun, width: hc ? 2 : 4),
//             boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.35), blurRadius: 26)],
//           ),
//           // Иконите се смалуваат на тесни екрани (пр. 360px) за да не се
//           // преклопуваат; на широки екрани остануваат во полна големина.
//           child: LayoutBuilder(
//             builder: (context, c) {
//               final s = math.min(c.maxWidth / 480, c.maxHeight / 260).clamp(0.55, 1.0);
//               return Stack(
//             children: [
//               for (final item in items)
//                 Align(
//                   alignment: item.align,
//                   child: Container(
//                     padding: EdgeInsets.all(hc ? 4 : 0),
//                     decoration: hc
//                         ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))
//                         : null,
//                     child: Icon(
//                       item.icon,
//                       size: item.size * s,
//                       color: hc ? const Color(0xFFFFFF00) : item.color,
//                       shadows: hc ? null : [Shadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 12)],
//                     ),
//                   ),
//                 ),
//             ],
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   /// Секогаш видлив текст - приказната и исходот се и прикажани, не само
//   /// изговорени (клучно за деца со оштетен слух). Бел облак со опашка.
//   Widget _captionBox(String text) {
//     final hc = _hc;
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
//       decoration: ShapeDecoration(
//         color: hc ? Colors.black : Colors.white,
//         shape: SpeechBubbleBorder(
//           radius: 26,
//           side: BorderSide(color: hc ? Colors.white : Playful.sun, width: 3),
//         ),
//         shadows: hc ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
//       ),
//       child: Text(
//         text,
//         textAlign: TextAlign.center,
//         style: Playful.body(21 * _kStoryText, color: hc ? Colors.white : Playful.ink),
//       ),
//     );
//   }

//   List<Widget> _buildStoryView(double sceneHeight) {
//     final hc = _hc;
//     final opt1Key = _opt1Key(_currentStory);
//     final opt2Key = _opt2Key(_currentStory);
//     return [
//       _storyScene(hc, sceneHeight),
//       const SizedBox(height: 16),
//       _captionBox(_t(_storyKey(_currentStory))),
//       const SizedBox(height: 18),
//       Row(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.auto_awesome_rounded, color: hc ? _fg : Playful.sun, size: 34),
//           const SizedBox(width: 10),
//           Flexible(
//             child: Text(
//               'story.what_next'.tr(),
//               textAlign: TextAlign.center,
//               style: Playful.display(24 * _kStoryText, color: _fg),
//             ),
//           ),
//         ],
//       ),
//       const SizedBox(height: 10),
//       // Додека се чита - мал брановиден знак; копчињата се уште заклучени.
//       AnimatedSwitcher(
//         duration: const Duration(milliseconds: 250),
//         child: _buttonsUnlocked || hc
//             ? const SizedBox(key: ValueKey('ready'), height: 8)
//             : const Center(
//                 key: ValueKey('reading'),
//                 child: Padding(
//                   padding: EdgeInsets.only(bottom: 8),
//                   child: SoundWave(color: Playful.sun, bars: 9, height: 26, barWidth: 5),
//                 ),
//               ),
//       ),
//       _optionButton(
//         number: 1,
//         text: _t(opt1Key),
//         icon: _optionIcons[opt1Key] ?? Icons.touch_app_rounded,
//         selected: _selectedOption == 1,
//         onTap: () => _choose(1),
//       ),
//       const SizedBox(height: 14),
//       _optionButton(
//         number: 2,
//         text: _t(opt2Key),
//         icon: _optionIcons[opt2Key] ?? Icons.touch_app_rounded,
//         selected: _selectedOption == 2,
//         onTap: () => _choose(2),
//       ),
//     ];
//   }

//   /// Шарена картичка за опција: златен број, икона во бел круг, текст.
//   /// При избор кратко светнува зелено пред премин кон исходот.
//   Widget _optionButton({
//     required int number,
//     required String text,
//     required IconData icon,
//     required bool selected,
//     required VoidCallback onTap,
//   }) {
//     final hc = _hc;
//     final base = selected ? const Color(0xFF16A34A) : _optionColors[(number - 1) % _optionColors.length];
//     return Semantics(
//       label: '${'story.option_$number'.tr()}: $text. ${'features.tap_to_open'.tr()}',
//       button: _buttonsUnlocked,
//       child: ExcludeSemantics(
//         child: AbsorbPointer(
//           absorbing: !_buttonsUnlocked,
//           child: AnimatedOpacity(
//             duration: const Duration(milliseconds: 250),
//             opacity: _buttonsUnlocked ? 1.0 : 0.4,
//             child: AnimatedScale(
//               scale: selected ? 1.04 : 1.0,
//               duration: const Duration(milliseconds: 180),
//               curve: Curves.easeOut,
//               child: PressableScale(
//                 child: Material(
//                   color: Colors.transparent,
//                   borderRadius: BorderRadius.circular(26),
//                   child: InkWell(
//                     borderRadius: BorderRadius.circular(26),
//                     onTap: onTap,
//                     child: AnimatedContainer(
//                       duration: const Duration(milliseconds: 180),
//                       constraints: const BoxConstraints(minHeight: 110),
//                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(26),
//                         color: hc ? (selected ? const Color(0xFF333300) : Colors.black) : null,
//                         gradient: hc
//                             ? null
//                             : LinearGradient(
//                                 begin: Alignment.topLeft,
//                                 end: Alignment.bottomRight,
//                                 colors: [Color.lerp(base, Colors.white, 0.08)!, Color.lerp(base, Colors.black, 0.35)!],
//                               ),
//                         border: Border.all(
//                           color: hc ? (selected ? const Color(0xFFFFFF00) : Colors.white) : (selected ? Playful.sun : Colors.white),
//                           width: selected ? 4 : 3,
//                         ),
//                         boxShadow: hc
//                             ? null
//                             : [BoxShadow(color: (selected ? Playful.sun : base).withValues(alpha: selected ? 0.7 : 0.45), blurRadius: selected ? 28 : 16)],
//                       ),
//                       child: LayoutBuilder(
//                         builder: (context, c) {
//                           final badges = <Widget>[
//                           // Број на опцијата.
//                           Container(
//                             width: 52,
//                             height: 52,
//                             alignment: Alignment.center,
//                             decoration: BoxDecoration(
//                               shape: BoxShape.circle,
//                               color: hc ? Colors.black : Playful.sun,
//                               border: Border.all(color: Colors.white, width: 2),
//                             ),
//                             child: FittedBox(
//                               fit: BoxFit.scaleDown,
//                               child: Text('$number', style: Playful.display(20 * _kStoryText, color: hc ? Colors.white : Playful.ink)),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Container(
//                             width: 84,
//                             height: 84,
//                             decoration: BoxDecoration(
//                               shape: BoxShape.circle,
//                               color: hc ? Colors.black : Colors.white.withValues(alpha: 0.18),
//                               border: Border.all(color: Colors.white.withValues(alpha: hc ? 1 : 0.8), width: 2),
//                             ),
//                             child: Icon(icon, size: 52, color: Colors.white),
//                           ),
//                           ];
//                           final label = Text(
//                             text,
//                             style: Playful.title(23 * _kStoryText, color: Colors.white),
//                           );
//                           // На тесен екран (телефон) текстот оди под бројот и
//                           // иконата, за големите букви да имаат цела ширина.
//                           if (c.maxWidth < 480) {
//                             return Column(
//                               crossAxisAlignment: CrossAxisAlignment.stretch,
//                               children: [
//                                 Row(children: badges),
//                                 const SizedBox(height: 10),
//                                 label,
//                               ],
//                             );
//                           }
//                           return Row(
//                             children: [
//                               ...badges,
//                               const SizedBox(width: 14),
//                               Expanded(child: label),
//                             ],
//                           );
//                         },
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   List<Widget> _buildOutcomeView(double sceneHeight) {
//     final hc = _hc;
//     final isLastStory = _currentStory + 1 >= _storyCount;
//     return [
//       _storyScene(hc, sceneHeight),
//       const SizedBox(height: 16),
//       if (_lastOutcomeKey != null) _captionBox(_t(_lastOutcomeKey!)),
//       const SizedBox(height: 20),
//       PopIn(
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(Icons.auto_stories_rounded, color: hc ? _fg : Playful.sun, size: 40),
//             const SizedBox(width: 10),
//             Flexible(
//               child: Text(
//                 'story.the_end'.tr(),
//                 textAlign: TextAlign.center,
//                 style: Playful.display(26 * _kStoryText, color: _fg),
//               ),
//             ),
//           ],
//         ),
//       ),
//       if (_allDone) ...[
//         const SizedBox(height: 8),
//         Text(
//           'story.all_done'.tr(),
//           textAlign: TextAlign.center,
//           style: Playful.body(18 * _kStoryText, color: _fg),
//         ),
//       ],
//       const SizedBox(height: 24),
//       if (_allDone)
//         // Последната приказна целосно заврши - излез и обиди повторно.
//         Wrap(
//           alignment: WrapAlignment.center,
//           spacing: 32,
//           runSpacing: 20,
//           children: [
//             _bigCircleButton(
//               icon: Icons.home_rounded,
//               label: 'story.exit_to_menu'.tr(),
//               gold: false,
//               onTap: () => Navigator.of(context).pop(),
//             ),
//             StartHotkeyListener(
//               onTrigger: _restart,
//               child: _bigCircleButton(
//                 icon: Icons.replay_rounded,
//                 label: 'story.play_again'.tr(),
//                 gold: true,
//                 onTap: _restart,
//               ),
//             ),
//           ],
//         )
//       else if (!isLastStory)
//         Center(
//           child: StartHotkeyListener(
//             onTrigger: _continue,
//             child: _bigCircleButton(
//               icon: Icons.arrow_forward_rounded,
//               label: 'story.next_story'.tr(),
//               gold: true,
//               onTap: _continue,
//             ),
//           ),
//         )
//       else
//         // Последна приказна, но завршната порака сè уште трае.
//         const SizedBox(height: 90),
//     ];
//   }

//   /// Голем круг со икона и натпис под него - продолжи / излез / одново.
//   Widget _bigCircleButton({required IconData icon, required String label, required bool gold, required VoidCallback onTap}) {
//     final hc = _hc;
//     final shown = label.replaceAll(RegExp(r'\.\s*$'), '');
//     return Semantics(
//       label: label,
//       button: true,
//       child: ExcludeSemantics(
//         child: GestureDetector(
//           onTap: onTap,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               RippleRings(
//                 color: hc ? Colors.white : Playful.sun,
//                 active: gold && !hc,
//                 spread: 18,
//                 child: PressableScale(
//                   child: Container(
//                     width: 124,
//                     height: 124,
//                     decoration: BoxDecoration(
//                       shape: BoxShape.circle,
//                       color: hc ? Colors.black : (gold ? Playful.sun : Colors.white.withValues(alpha: 0.12)),
//                       border: Border.all(color: Colors.white, width: hc ? 2 : 4),
//                       boxShadow: hc || !gold ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 22)],
//                     ),
//                     child: Icon(icon, size: 62, color: hc ? Colors.white : (gold ? Playful.ink : Colors.white)),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               ConstrainedBox(
//                 constraints: const BoxConstraints(maxWidth: 320),
//                 child: Text(shown, textAlign: TextAlign.center, style: Playful.title(18 * _kStoryText, color: _fg)),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// Опис на еден елемент во сцената на приказна: икона, големина, боја,
// /// и позиција (Alignment, -1..1 по X и Y).
// class _SceneItem {
//   final IconData icon;
//   final double size;
//   final Color color;
//   final Alignment align;

//   const _SceneItem({
//     required this.icon,
//     required this.size,
//     required this.color,
//     required this.align,
//   });
// }
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

/// Множител за големината на текстот на овој екран (поголеми букви).
const double _kStoryText = 1.6;

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

  /// Позадините се користат само како резервни бои; самата сцена е
  /// нацртана како една цела илустрација со CustomPainter.
  static const Map<int, List<Color>> _sceneBackgrounds = {
    0: [Color(0xFF8FD3F4), Color(0xFFEAF8FF)], // парк
    1: [Color(0xFF9DDCF7), Color(0xFFF2FBFF)], // двор / бунар
    2: [Color(0xFFE9D8FF), Color(0xFFFFF4DE)], // библиотека
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
            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
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

  /// Реалистична илустрирана сцена.
  ///
  /// Наместо одделни Material Icons, секоја приказна се црта како една
  /// целина: простор, лик, предмети и детали се визуелно поврзани.
  Widget _storyScene(bool hc, double height) {
    return ExcludeSemantics(
      child: PopIn(
        key: ValueKey('scene_$_currentStory'),
        child: Container(
          height: height,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: hc ? Colors.white : Playful.sun,
              width: hc ? 2 : 4,
            ),
            boxShadow: hc
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: CustomPaint(
            painter: _RealisticStoryScenePainter(
              story: _currentStory,
              highContrast: hc,
            ),
            child: const SizedBox.expand(),
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
        style: Playful.body(21 * _kStoryText, color: hc ? Colors.white : Playful.ink),
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
          Icon(Icons.auto_awesome_rounded, color: hc ? _fg : Playful.sun, size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'story.what_next'.tr(),
              textAlign: TextAlign.center,
              style: Playful.display(24 * _kStoryText, color: _fg),
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
    final accent = selected
        ? const Color(0xFF16A34A)
        : _optionColors[(number - 1) % _optionColors.length];
    final deep = Color.lerp(accent, Colors.black, 0.28)!;

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
              scale: selected ? 1.035 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: PressableScale(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(26),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: hc ? Colors.black : null,
                        gradient: hc
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [accent, deep],
                              ),
                        border: Border.all(
                          color: hc
                              ? (selected
                                  ? const Color(0xFFFFFF00)
                                  : Colors.white)
                              : Colors.white.withValues(alpha: selected ? 0.95 : 0.22),
                          width: selected ? 3.5 : 1.5,
                        ),
                        boxShadow: hc
                            ? null
                            : [
                                BoxShadow(
                                  color: deep.withValues(alpha: 0.55),
                                  blurRadius: selected ? 24 : 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Stack(
                          children: [
                            // Голема бледа икона во долниот десен агол,
                            // исто како на картичките на Home Screen.
                            Positioned(
                              right: -14,
                              bottom: -18,
                              child: ExcludeSemantics(
                                child: Icon(
                                  icon,
                                  size: 160 * _kStoryText / 1.6,
                                  color: Colors.white.withValues(alpha: hc ? 0.06 : 0.10),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(22),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final narrow = box.maxWidth < 600;

                                  final iconBox = Container(
                                    width: 92,
                                    height: 92,
                                    decoration: BoxDecoration(
                                      color: hc
                                          ? Colors.black
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: hc
                                          ? Border.all(color: Colors.white, width: 2)
                                          : null,
                                    ),
                                    child: Icon(
                                      icon,
                                      size: 54,
                                      color: hc ? Colors.white : deep,
                                    ),
                                  );

                                  final numberBadge = Container(
                                    width: 46,
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hc
                                          ? Colors.black
                                          : Colors.white.withValues(alpha: 0.96),
                                      border: Border.all(
                                        color: hc ? Colors.white : deep,
                                        width: 2,
                                      ),
                                      boxShadow: hc
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: deep.withValues(alpha: 0.35),
                                                blurRadius: 8,
                                              ),
                                            ],
                                    ),
                                    child: Text(
                                      '$number',
                                      style: Playful.display(
                                        20 * _kStoryText / 1.6,
                                        color: hc ? Colors.white : deep,
                                      ),
                                    ),
                                  );

                                  final label = Expanded(
                                    child: Text(
                                      text,
                                      style: Playful.display(
                                        (narrow ? 27 : 23) * _kStoryText,
                                        color: hc ? Colors.white : Colors.white,
                                      ),
                                    ),
                                  );

                                  if (narrow) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            iconBox,
                                            const Spacer(),
                                            numberBadge,
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          text,
                                          style: Playful.display(
                                            27 * _kStoryText,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          iconBox,
                                          Positioned(
                                            left: -10,
                                            top: -10,
                                            child: numberBadge,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 22),
                                      label,
                                      const SizedBox(width: 16),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ],
                                  );
                                },
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
            Icon(Icons.auto_stories_rounded, color: hc ? _fg : Playful.sun, size: 40),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'story.the_end'.tr(),
                textAlign: TextAlign.center,
                style: Playful.display(26 * _kStoryText, color: _fg),
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
          style: Playful.body(18 * _kStoryText, color: _fg),
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
            StartHotkeyListener(
              onTrigger: _restart,
              child: _bigCircleButton(
                icon: Icons.replay_rounded,
                label: 'story.play_again'.tr(),
                gold: true,
                onTap: _restart,
              ),
            ),
          ],
        )
      else if (!isLastStory)
        Center(
          child: StartHotkeyListener(
            onTrigger: _continue,
            child: _bigCircleButton(
              icon: Icons.arrow_forward_rounded,
              label: 'story.next_story'.tr(),
              gold: true,
              onTap: _continue,
            ),
          ),
        )
      else
        // Последна приказна, но завршната порака сè уште трае.
        const SizedBox(height: 90),
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
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : (gold ? Playful.sun : Colors.white.withValues(alpha: 0.12)),
                      border: Border.all(color: Colors.white, width: hc ? 2 : 4),
                      boxShadow: hc || !gold ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 22)],
                    ),
                    child: Icon(icon, size: 62, color: hc ? Colors.white : (gold ? Playful.ink : Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(shown, textAlign: TextAlign.center, style: Playful.title(18 * _kStoryText, color: _fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Целата илустрација на трите приказни.
/// Намерно е CustomPainter за да нема зависност од мрежни слики, emoji или
/// Material Icons и сцената да остане остра на различни резолуции.
class _RealisticStoryScenePainter extends CustomPainter {
  _RealisticStoryScenePainter({
    required this.story,
    required this.highContrast,
  });

  final int story;
  final bool highContrast;

  late Canvas _canvas;
  late Size _size;
  late double _sx;
  late double _sy;

  double X(num x) => x.toDouble() * _sx;
  double Y(num y) => y.toDouble() * _sy;
  Offset P(num x, num y) => Offset(X(x), Y(y));

  Paint fill(Color color) => Paint()..color = color;
  Paint stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Path path(List<Offset> points, {bool close = true}) {
    final p = Path();
    if (points.isEmpty) return p;
    p.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      p.lineTo(point.dx, point.dy);
    }
    if (close) p.close();
    return p;
  }

  void ellipse(Offset c, double rx, double ry, Paint paint) {
    _canvas.drawOval(
      Rect.fromCenter(center: c, width: X(rx * 2), height: Y(ry * 2)),
      paint,
    );
  }

  void circle(Offset c, double r, Paint paint) {
    _canvas.drawCircle(c, X(r), paint);
  }

  void line(Offset a, Offset b, Paint paint) {
    _canvas.drawLine(a, b, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _canvas = canvas;
    _size = size;
    _sx = size.width / 1000;
    _sy = size.height / 560;

    if (highContrast) {
      _paintHighContrast();
      return;
    }

    switch (story) {
      case 0:
        _paintPark();
        break;
      case 1:
        _paintWellScene();
        break;
      default:
        _paintLibrary();
        break;
    }
  }

  void _paintHighContrast() {
    _canvas.drawRect(Offset.zero & _size, fill(Colors.black));
    final white = stroke(Colors.white, 4);
    final yellow = const Color(0xFFFFFF00);
    final yellowPaint = stroke(yellow, 5);

    if (story == 0) {
      _canvas.drawPath(path([P(0, 410), P(1000, 410), P(1000, 560), P(0, 560)]), fill(Colors.black));
      _canvas.drawPath(path([P(430, 250), P(510, 250), P(545, 470), P(395, 470)]), yellowPaint);
      circle(P(470, 185), 125, stroke(Colors.white, 6));
      line(P(650, 225), P(650, 455), white);
      line(P(790, 225), P(790, 455), white);
      line(P(650, 225), P(790, 225), yellowPaint);
      line(P(665, 455), P(710, 455), yellowPaint);
      line(P(775, 455), P(735, 455), yellowPaint);
      _drawPerson(P(505, 410), scale: 1.0, outline: yellow, fillColor: Colors.black);
      _drawFlowers(yellowPaint);
    } else if (story == 1) {
      _canvas.drawPath(path([P(0, 420), P(1000, 420), P(1000, 560), P(0, 560)]), fill(Colors.black));
      _drawWell(P(220, 390), yellowPaint, white);
      _drawTable(P(735, 390), yellowPaint, white);
      _drawPerson(P(500, 410), scale: 1.0, outline: yellow, fillColor: Colors.black);
      _drawBottle(P(735, 310), yellowPaint, white);
    } else {
      _drawBookshelves(yellowPaint, white);
      _drawPerson(P(500, 410), scale: 1.05, outline: yellow, fillColor: Colors.black);
      _drawThoughtCloud(P(300, 160), 1.0, yellowPaint);
      _drawThoughtCloud(P(700, 160), 1.0, yellowPaint);
      _drawAnimal(P(300, 160), yellowPaint, true);
      _drawPlanet(P(700, 160), yellowPaint);
    }
  }

  // -------------------------------------------------------------------------
  // SCENE 1 — ANA IN THE PARK
  // -------------------------------------------------------------------------

  void _paintPark() {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF75C9F4),
          Color(0xFFDDF4FF),
          Color(0xFFFFF1CF),
        ],
      ).createShader(Offset.zero & _size);
    _canvas.drawRect(Offset.zero & _size, sky);

    // Soft distant hills.
    _canvas.drawPath(
      path([
        P(0, 390), P(150, 330), P(280, 365), P(420, 315),
        P(590, 355), P(760, 300), P(1000, 350), P(1000, 560), P(0, 560),
      ]),
      fill(const Color(0xFFA8D78A)),
    );

    // Grass foreground.
    _canvas.drawPath(
      path([P(0, 405), P(1000, 405), P(1000, 560), P(0, 560)]),
      fill(const Color(0xFF62A84E)),
    );

    // Grass highlight strips.
    final grass = stroke(const Color(0xFF8CCB67), 3);
    for (var i = 0; i < 34; i++) {
      final x = 10 + (i * 31) % 990;
      final y = 425 + (i * 17) % 110;
      line(P(x, y), P(x - 4, y - 13), grass);
    }

    // Sun.
    circle(P(865, 75), 40, fill(const Color(0xFFFFD75A)));
    circle(P(865, 75), 52, fill(const Color(0xFFFFD75A).withValues(alpha: 0.20)));

    // Clouds.
    _drawCloud(P(180, 90), 1.1, Colors.white.withValues(alpha: 0.86));
    _drawCloud(P(650, 105), 0.75, Colors.white.withValues(alpha: 0.70));

    // Large realistic tree on the left.
    _drawParkTree(P(190, 405), 1.0);

    // Swing on the right, integrated into the park.
    _drawSwing(P(670, 210), 1.05);

    // Anna in the middle, looking between the swing and flowers.
    _drawPerson(
      P(495, 407),
      scale: 1.05,
      outline: const Color(0xFF543A2B),
      fillColor: const Color(0xFFFFC9A8),
      hairColor: const Color(0xFF5A321F),
      shirtColor: const Color(0xFFFF78A8),
      pantsColor: const Color(0xFF4E78C4),
      female: true,
    );

    // Flowers are clearly on the ground, not floating icons.
    _drawFlowers(stroke(const Color(0xFF356D2B), 3));
    _drawFlower(P(390, 468), 0.9, const Color(0xFFFF5C8A));
    _drawFlower(P(355, 495), 0.65, const Color(0xFFFFD45C));
    _drawFlower(P(420, 505), 0.72, const Color(0xFF9B6DFF));
  }

  void _drawParkTree(Offset base, double s) {
    // Shadow.
    ellipse(P(base.dx / _sx + 10, base.dy / _sy + 6), 125 * s, 28 * s,
        fill(Colors.black.withValues(alpha: 0.13)));

    final trunk = path([
      P(base.dx / _sx - 38 * s, base.dy / _sy),
      P(base.dx / _sx - 30 * s, base.dy / _sy - 230 * s),
      P(base.dx / _sx - 13 * s, base.dy / _sy - 250 * s),
      P(base.dx / _sx + 20 * s, base.dy / _sy - 220 * s),
      P(base.dx / _sx + 38 * s, base.dy / _sy),
    ]);
    _canvas.drawPath(
      trunk,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF6A3E22), Color(0xFFA86638), Color(0xFF59321C)],
        ).createShader(Rect.fromLTWH(X(150), Y(150), X(100), Y(260))),
    );

    // Branches.
    final branch = stroke(const Color(0xFF6A3E22), 15 * s);
    line(P(190, 200), P(105, 135), branch);
    line(P(205, 190), P(275, 125), branch);
    line(P(195, 235), P(130, 185), branch);

    // Layered canopy gives depth instead of a flat circle.
    final dark = fill(const Color(0xFF286B35));
    final mid = fill(const Color(0xFF3F8E43));
    final light = fill(const Color(0xFF65A94F));
    circle(P(105, 135), 66 * s, dark);
    circle(P(180, 105), 82 * s, mid);
    circle(P(270, 135), 70 * s, dark);
    circle(P(135, 195), 75 * s, mid);
    circle(P(225, 185), 92 * s, light);
    circle(P(305, 195), 64 * s, mid);
    circle(P(205, 78), 55 * s, light);

    // Individual leaf clusters.
    final leaf = fill(const Color(0xFF82BD5C).withValues(alpha: 0.85));
    for (final pt in [
      P(125, 112), P(158, 77), P(205, 116), P(244, 82),
      P(275, 151), P(168, 171), P(236, 180), P(110, 170),
    ]) {
      circle(pt, 16 * s, leaf);
    }
  }

  void _drawSwing(Offset top, double s) {
    final metal = stroke(const Color(0xFF6E513C), 10 * s);
    line(P(650, 210), P(620, 455), metal);
    line(P(790, 210), P(820, 455), metal);
    line(P(650, 210), P(790, 210), stroke(const Color(0xFF4C392E), 13 * s));

    // Swing seat.
    final rope = stroke(const Color(0xFFE8D1A0), 4 * s);
    line(P(675, 212), P(675, 385), rope);
    line(P(765, 212), P(765, 385), rope);
    final seat = path([
      P(658, 383), P(782, 383), P(770, 405), P(670, 405),
    ]);
    _canvas.drawPath(seat, fill(const Color(0xFFB66B3D)));
    _canvas.drawPath(seat, stroke(const Color(0xFF754125), 3));
    // Small highlight.
    line(P(680, 388), P(760, 388), stroke(const Color(0xFFD9915A), 3));
  }

  // -------------------------------------------------------------------------
  // SCENE 2 — MARKO: WELL + TABLE + WATER / JUICE
  // -------------------------------------------------------------------------

  void _paintWellScene() {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7DC9F2), Color(0xFFE5F7FF)],
      ).createShader(Offset.zero & _size);
    _canvas.drawRect(Offset.zero & _size, sky);

    // Clouds and warm sun.
    circle(P(850, 75), 38, fill(const Color(0xFFFFD35C)));
    _drawCloud(P(160, 95), 1.0, Colors.white.withValues(alpha: 0.8));

    // Yard.
    _canvas.drawPath(
      path([P(0, 390), P(1000, 390), P(1000, 560), P(0, 560)]),
      fill(const Color(0xFF73A953)),
    );

    // Stone path.
    final stone = fill(const Color(0xFFD5D1C4));
    for (var i = 0; i < 7; i++) {
      ellipse(P(420 + i * 75, 490 + (i.isEven ? 8 : -5)), 35, 13, stone);
    }

    // Well to the left.
    _drawWell(P(205, 395), stroke(const Color(0xFF624733), 4),
        stroke(const Color(0xFF4B3525), 5));

    // Table on the right.
    _drawTable(P(750, 405), stroke(const Color(0xFF65452E), 5),
        stroke(const Color(0xFF4A3425), 4));

    // Bottle is physically on the table.
    _drawBottle(P(745, 316), stroke(const Color(0xFF284F71), 4),
        stroke(const Color(0xFF173A58), 3));

    // Glass of water next to it.
    _drawGlass(P(830, 350), const Color(0xFFBDEBFF));

    // Marko stands between the choices.
    _drawPerson(
      P(505, 410),
      scale: 1.08,
      outline: const Color(0xFF4D3527),
      fillColor: const Color(0xFFE7B28F),
      hairColor: const Color(0xFF3B281F),
      shirtColor: const Color(0xFF4E87D1),
      pantsColor: const Color(0xFF33465F),
      female: false,
    );

    // Subtle arrows of attention, not icons: visual eye-lines toward objects.
    final attention = stroke(const Color(0xFFFFFFFF).withValues(alpha: 0.55), 3);
    line(P(450, 285), P(310, 300), attention);
    line(P(555, 285), P(705, 305), attention);
  }

  void _drawWell(Offset base, Paint outline, Paint darkOutline) {
    // Roof supports.
    line(P(150, 210), P(150, 395), darkOutline);
    line(P(285, 210), P(285, 395), darkOutline);
    line(P(150, 210), P(285, 210), darkOutline);

    // Roof.
    _canvas.drawPath(
      path([P(135, 215), P(218, 150), P(300, 215), P(285, 225), P(218, 175), P(150, 225)]),
      fill(const Color(0xFF9C5D35)),
    );
    _canvas.drawPath(
      path([P(135, 215), P(218, 150), P(300, 215)]),
      outline,
    );

    // Stone well body.
    final body = path([
      P(130, 325), P(305, 325), P(285, 430), P(150, 430),
    ]);
    _canvas.drawPath(body, fill(const Color(0xFF9B9A8F)));
    _canvas.drawPath(body, outline);

    // Individual stones.
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        final x = 145 + col * 40 + (row.isOdd ? 18 : 0);
        final y = 340 + row * 29;
        _canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(X(x), Y(y), X(54), Y(25)),
            Radius.circular(X(8)),
          ),
          fill(row.isEven ? const Color(0xFFB7B5A8) : const Color(0xFF8F8D83)),
        );
      }
    }

    // Dark opening + water.
    ellipse(P(218, 329), 82, 24, fill(const Color(0xFF41392F)));
    ellipse(P(218, 330), 63, 15, fill(const Color(0xFF5CB9D9)));
    ellipse(P(218, 326), 52, 9, fill(const Color(0xFF91DDF0)));
    line(P(150, 315), P(285, 315), outline);
  }

  void _drawTable(Offset base, Paint outline, Paint darkOutline) {
    // Tabletop.
    final top = path([
      P(630, 355), P(875, 355), P(905, 380), P(660, 380),
    ]);
    _canvas.drawPath(top, fill(const Color(0xFF9A6037)));
    _canvas.drawPath(top, outline);

    // Table legs.
    line(P(665, 378), P(650, 510), darkOutline);
    line(P(860, 378), P(880, 510), darkOutline);
    line(P(690, 378), P(700, 500), darkOutline);
    line(P(835, 378), P(825, 500), darkOutline);

    // Wood grain.
    line(P(665, 365), P(820, 365), stroke(const Color(0xFFD28A50), 3));
    line(P(700, 373), P(875, 373), stroke(const Color(0xFF704226), 2));
  }

  void _drawBottle(Offset c, Paint outline, Paint darkOutline) {
    final bottle = path([
      P(715, 355), P(715, 315), P(727, 305), P(727, 278),
      P(765, 278), P(765, 305), P(777, 315), P(777, 355),
    ]);
    _canvas.drawPath(
      bottle,
      fill(const Color(0xFF72C5E8).withValues(alpha: 0.88)),
    );
    _canvas.drawPath(bottle, outline);
    _canvas.drawRect(Rect.fromLTWH(X(727), Y(270), X(38), Y(14)), fill(const Color(0xFF5D4635)));
    _canvas.drawRect(Rect.fromLTWH(X(731), Y(271), X(30), Y(8)), fill(const Color(0xFFD4AA64)));
    // Label.
    _canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(X(718), Y(326), X(56), Y(20)),
        Radius.circular(X(6)),
      ),
      fill(Colors.white.withValues(alpha: 0.78)),
    );
  }

  void _drawGlass(Offset c, Color water) {
    final glass = Path()
      ..moveTo(X(810), Y(355))
      ..lineTo(X(850), Y(355))
      ..lineTo(X(845), Y(395))
      ..lineTo(X(815), Y(395))
      ..close();
    _canvas.drawPath(glass, fill(Colors.white.withValues(alpha: 0.45)));
    _canvas.drawPath(glass, stroke(Colors.white, 3));
    _canvas.drawRect(Rect.fromLTWH(X(814), Y(372), X(32), Y(22)), fill(water));
  }

  // -------------------------------------------------------------------------
  // SCENE 3 — SONJA IN A LIBRARY + THOUGHT CLOUDS
  // -------------------------------------------------------------------------

  void _paintLibrary() {
    // Warm library wall.
    final wall = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8E8D1), Color(0xFFE5C7A4)],
      ).createShader(Offset.zero & _size);
    _canvas.drawRect(Offset.zero & _size, wall);

    _drawBookshelves(
      stroke(const Color(0xFF6E4227), 4),
      stroke(const Color(0xFF4C2D1C), 4),
    );

    // Reading table and books behind Sonja.
    _canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(X(330), Y(410), X(340), Y(42)),
        Radius.circular(X(10)),
      ),
      fill(const Color(0xFF8B5736)),
    );
    _canvas.drawRect(Rect.fromLTWH(X(350), Y(445), X(20), Y(80)), fill(const Color(0xFF68412A)));
    _canvas.drawRect(Rect.fromLTWH(X(630), Y(445), X(20), Y(80)), fill(const Color(0xFF68412A)));

    // Open book on table.
    _canvas.drawPath(
      path([P(450, 408), P(500, 395), P(550, 408), P(500, 430)]),
      fill(const Color(0xFFFFF8E8)),
    );
    _canvas.drawPath(path([P(450, 408), P(500, 395), P(550, 408)]), stroke(const Color(0xFF7E6654), 2));

    // Sonja.
    _drawPerson(
      P(500, 420),
      scale: 1.12,
      outline: const Color(0xFF53352B),
      fillColor: const Color(0xFFE8B899),
      hairColor: const Color(0xFF3C241B),
      shirtColor: const Color(0xFF9D67C7),
      pantsColor: const Color(0xFF526CA8),
      female: true,
    );

    // Thought clouds rise from Sonja's head.
    _drawThoughtCloud(P(325, 150), 1.0, stroke(const Color(0xFF826A95), 3));
    _drawThoughtCloud(P(705, 150), 1.0, stroke(const Color(0xFF826A95), 3));

    // Animal thought.
    _drawAnimal(P(325, 150), stroke(const Color(0xFF6A4A36), 3), false);

    // Planet thought.
    _drawPlanet(P(705, 150), stroke(const Color(0xFF4D5C91), 3));

    // Little connecting bubbles.
    circle(P(425, 245), 13, fill(Colors.white.withValues(alpha: 0.95)));
    circle(P(405, 270), 8, fill(Colors.white.withValues(alpha: 0.95)));
    circle(P(575, 270), 8, fill(Colors.white.withValues(alpha: 0.95)));
    circle(P(595, 245), 13, fill(Colors.white.withValues(alpha: 0.95)));
  }

  void _drawBookshelves(Paint outline, Paint darkOutline) {
    // Back wall shelves.
    for (final y in [105.0, 225.0, 345.0]) {
      _canvas.drawRect(
        Rect.fromLTWH(X(55), Y(y), X(890), Y(22)),
        fill(const Color(0xFF754729)),
      );
      _canvas.drawRect(
        Rect.fromLTWH(X(55), Y(y), X(890), Y(22)),
        outline,
      );
    }

    // Uprights.
    for (final x in [55.0, 270.0, 485.0, 700.0, 945.0]) {
      _canvas.drawRect(
        Rect.fromLTWH(X(x), Y(85), X(22), Y(300)),
        fill(const Color(0xFF6A4028)),
      );
      line(P(x + 3, 95), P(x + 3, 370), darkOutline);
    }

    final bookColors = [
      const Color(0xFFB85C50),
      const Color(0xFF4E78A6),
      const Color(0xFFD19A4A),
      const Color(0xFF6C9B66),
      const Color(0xFF875F9E),
      const Color(0xFFC56B8D),
    ];

    var colorIndex = 0;
    for (final shelfY in [82.0, 202.0, 322.0]) {
      for (var col = 0; col < 4; col++) {
        var x = 78.0 + col * 215;
        for (var b = 0; b < 7; b++) {
          final width = 18.0 + (b % 3) * 5;
          final height = 55.0 + (b % 4) * 8;
          final bottom = shelfY + 20;
          _canvas.drawRect(
            Rect.fromLTWH(X(x), Y(bottom - height), X(width), Y(height)),
            fill(bookColors[colorIndex++ % bookColors.length]),
          );
          x += width + 5;
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // PEOPLE / THOUGHTS / SMALL DETAILS
  // -------------------------------------------------------------------------

  void _drawPerson(
    Offset feet, {
    required double scale,
    required Color outline,
    required Color fillColor,
    Color hairColor = const Color(0xFF4A2D20),
    Color shirtColor = const Color(0xFF4D83C6),
    Color pantsColor = const Color(0xFF40506D),
    bool female = false,
  }) {
    final cx = feet.dx / _sx;
    final fy = feet.dy / _sy;

    // Shadow.
    ellipse(P(cx, fy + 3), 58 * scale, 13 * scale,
        fill(Colors.black.withValues(alpha: 0.16)));

    // Legs.
    final legPaint = fill(pantsColor);
    _canvas.drawPath(
      path([
        P(cx - 22 * scale, fy - 105 * scale),
        P(cx - 3 * scale, fy - 105 * scale),
        P(cx - 8 * scale, fy - 12 * scale),
        P(cx - 37 * scale, fy - 12 * scale),
      ]),
      legPaint,
    );
    _canvas.drawPath(
      path([
        P(cx + 3 * scale, fy - 105 * scale),
        P(cx + 22 * scale, fy - 105 * scale),
        P(cx + 37 * scale, fy - 12 * scale),
        P(cx + 8 * scale, fy - 12 * scale),
      ]),
      legPaint,
    );

    // Shoes.
    ellipse(P(cx - 25 * scale, fy - 5 * scale), 27 * scale, 10 * scale,
        fill(const Color(0xFF2E3038)));
    ellipse(P(cx + 25 * scale, fy - 5 * scale), 27 * scale, 10 * scale,
        fill(const Color(0xFF2E3038)));

    // Torso with slight shoulder taper.
    _canvas.drawPath(
      path([
        P(cx - 48 * scale, fy - 205 * scale),
        P(cx - 23 * scale, fy - 228 * scale),
        P(cx + 23 * scale, fy - 228 * scale),
        P(cx + 48 * scale, fy - 205 * scale),
        P(cx + 36 * scale, fy - 100 * scale),
        P(cx - 36 * scale, fy - 100 * scale),
      ]),
      fill(shirtColor),
    );

    // Arms.
    final arm = stroke(fillColor, 18 * scale);
    line(P(cx - 37 * scale, fy - 195 * scale), P(cx - 68 * scale, fy - 115 * scale), arm);
    line(P(cx + 37 * scale, fy - 195 * scale), P(cx + 68 * scale, fy - 115 * scale), arm);

    // Neck.
    _canvas.drawRect(
      Rect.fromLTWH(X(cx - 14 * scale), Y(fy - 246 * scale), X(28 * scale), Y(35 * scale)),
      fill(fillColor),
    );

    // Hair behind head.
    circle(P(cx, fy - 288 * scale), 58 * scale, fill(hairColor));

    // Face.
    circle(P(cx, fy - 285 * scale), 48 * scale, fill(fillColor));
    _canvas.drawArc(
      Rect.fromCircle(center: P(cx, fy - 285 * scale), radius: X(48 * scale)),
      math.pi + 0.12,
      math.pi - 0.24,
      false,
      stroke(outline, 2.2 * scale),
    );

    // Hair fringe.
    if (female) {
      _canvas.drawPath(
        path([
          P(cx - 48 * scale, fy - 302 * scale),
          P(cx - 25 * scale, fy - 345 * scale),
          P(cx + 18 * scale, fy - 338 * scale),
          P(cx + 49 * scale, fy - 302 * scale),
          P(cx + 29 * scale, fy - 314 * scale),
          P(cx + 8 * scale, fy - 297 * scale),
          P(cx - 10 * scale, fy - 315 * scale),
          P(cx - 30 * scale, fy - 300 * scale),
        ]),
        fill(hairColor),
      );
      // ponytail / side hair.
      circle(P(cx - 50 * scale, fy - 265 * scale), 25 * scale, fill(hairColor));
      circle(P(cx + 50 * scale, fy - 265 * scale), 25 * scale, fill(hairColor));
    }

    // Eyes.
    circle(P(cx - 17 * scale, fy - 287 * scale), 4.5 * scale, fill(outline));
    circle(P(cx + 17 * scale, fy - 287 * scale), 4.5 * scale, fill(outline));

    // Nose and gentle smile.
    line(P(cx, fy - 280 * scale), P(cx - 2 * scale, fy - 270 * scale), stroke(outline, 2));
    _canvas.drawArc(
      Rect.fromCenter(center: P(cx, fy - 268 * scale), width: X(25 * scale), height: Y(18 * scale)),
      0.2,
      math.pi - 0.4,
      false,
      stroke(outline, 2.2 * scale),
    );

    // Clothing outline / buttons.
    line(P(cx, fy - 218 * scale), P(cx, fy - 112 * scale), stroke(outline.withValues(alpha: 0.45), 2));
    circle(P(cx, fy - 190 * scale), 3.5 * scale, fill(Colors.white.withValues(alpha: 0.85)));
    circle(P(cx, fy - 165 * scale), 3.5 * scale, fill(Colors.white.withValues(alpha: 0.85)));
  }

  void _drawFlowers(Paint stemPaint) {
    line(P(390, 505), P(390, 455), stemPaint);
    line(P(355, 520), P(355, 478), stemPaint);
    line(P(420, 525), P(420, 480), stemPaint);
  }

  void _drawFlower(Offset c, double s, Color petalColor) {
    final stem = stroke(const Color(0xFF3C7B37), 4 * s);
    line(P(c.dx / _sx, c.dy / _sy + 10), P(c.dx / _sx, c.dy / _sy + 40), stem);
    final pc = fill(petalColor);
    for (var i = 0; i < 5; i++) {
      final a = i * math.pi * 2 / 5;
      circle(
        P(c.dx / _sx + math.cos(a) * 10 * s, c.dy / _sy + math.sin(a) * 10 * s),
        8 * s,
        pc,
      );
    }
    circle(c, 5 * s, fill(const Color(0xFFFFD34E)));
  }

  void _drawCloud(Offset c, double s, Color color) {
    circle(c + Offset(X(-35 * s), Y(6 * s)), 28 * s, fill(color));
    circle(c + Offset(X(0), Y(-8 * s)), 38 * s, fill(color));
    circle(c + Offset(X(38 * s), Y(8 * s)), 25 * s, fill(color));
    _canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx - X(60 * s), c.dy, X(120 * s), Y(36 * s)),
        Radius.circular(X(18 * s)),
      ),
      fill(color),
    );
  }

  void _drawThoughtCloud(Offset center, double scale, Paint outline) {
    final c = center;
    final cloudFill = fill(Colors.white.withValues(alpha: 0.97));

    circle(c + Offset(X(-60 * scale), Y(5 * scale)), 52 * scale, cloudFill);
    circle(c + Offset(X(-8 * scale), Y(-15 * scale)), 68 * scale, cloudFill);
    circle(c + Offset(X(55 * scale), Y(8 * scale)), 48 * scale, cloudFill);
    _canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c.dx - X(92 * scale),
          c.dy - Y(5 * scale),
          X(184 * scale),
          Y(72 * scale),
        ),
        Radius.circular(X(32 * scale)),
      ),
      cloudFill,
    );

    _canvas.drawCircle(c + Offset(X(-60 * scale), Y(5 * scale)), X(52 * scale), outline);
    _canvas.drawCircle(c + Offset(X(-8 * scale), Y(-15 * scale)), X(68 * scale), outline);
    _canvas.drawCircle(c + Offset(X(55 * scale), Y(8 * scale)), X(48 * scale), outline);
  }

  void _drawAnimal(Offset center, Paint outline, bool hc) {
    final c = center;
    final body = hc ? Colors.black : const Color(0xFFD59A62);
    final dark = hc ? Colors.white : const Color(0xFF6A4632);

    // A friendly cat/dog-like animal silhouette.
    ellipse(c + Offset(X(0), Y(35)), 58, 38, fill(body));
    circle(c + Offset(X(0), Y(-8)), 40, fill(body));

    _canvas.drawPath(
      path([
        P(c.dx / _sx - 34, c.dy / _sy - 28),
        P(c.dx / _sx - 42, c.dy / _sy - 65),
        P(c.dx / _sx - 8, c.dy / _sy - 42),
      ]),
      fill(body),
    );
    _canvas.drawPath(
      path([
        P(c.dx / _sx + 34, c.dy / _sy - 28),
        P(c.dx / _sx + 42, c.dy / _sy - 65),
        P(c.dx / _sx + 8, c.dy / _sy - 42),
      ]),
      fill(body),
    );

    circle(c + Offset(X(-15), Y(-12)), 5, fill(dark));
    circle(c + Offset(X(15), Y(-12)), 5, fill(dark));
    ellipse(c + Offset(X(0), Y(7)), 10, 7, fill(dark));
    _canvas.drawArc(
      Rect.fromCenter(center: c + Offset(X(0), Y(14)), width: X(24), height: Y(15)),
      0,
      math.pi,
      false,
      stroke(dark, 2),
    );
    _canvas.drawPath(
      path([
        P(c.dx / _sx + 45, c.dy / _sy + 35),
        P(c.dx / _sx + 80, c.dy / _sy + 5),
        P(c.dx / _sx + 86, c.dy / _sy + 23),
        P(c.dx / _sx + 55, c.dy / _sy + 54),
      ]),
      stroke(dark, 8),
    );
  }

  void _drawPlanet(Offset center, Paint outline) {
    final c = center;
    circle(c, 52, fill(const Color(0xFF6A8FD1)));
    circle(c + Offset(X(-15), Y(-12)), 30, fill(const Color(0xFF83B45E).withValues(alpha: 0.9)));
    ellipse(c + Offset(X(18), Y(10)), 18, 12, fill(const Color(0xFF83B45E)));
    ellipse(c + Offset(X(0), Y(15)), 12, 8, fill(const Color(0xFF83B45E)));

    _canvas.drawOval(
      Rect.fromCenter(center: c, width: X(145), height: Y(38)),
      stroke(const Color(0xFFB77CE2), 7),
    );
    _canvas.drawCircle(c, X(52), outline);
  }

  @override
  bool shouldRepaint(covariant _RealisticStoryScenePainter oldDelegate) {
    return oldDelegate.story != story ||
        oldDelegate.highContrast != highContrast;
  }
}