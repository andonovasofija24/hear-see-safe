// import 'dart:async';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:provider/provider.dart';
// import 'package:easy_localization/easy_localization.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:flutter_compass/flutter_compass.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
// import 'package:hear_and_see_safe/theme/app_style.dart';
// import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
// import 'package:hear_and_see_safe/utils/vibration_utils.dart';
// import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

// /// Модул за просторна ориентација со 4 режими (табови горе):
// /// - Симон - насоки: вибрациска низа од 4 насоки, детето ја повторува со допир.
// /// - Лавиринт: следење невидлива патека со прст, вибрација при излегување.
// /// - Радар: пронаоѓање скриен предмет преку "жешко-студено" вибрации, потоа
// ///   влечење на пронајдениот предмет до означена цел.
// /// - Компас: физичко вртење на телефонот за да се погоди бараната насока
// ///   (север/југ/исток/запад), користејќи го компасот на уредот.
// class SpatialOrientationScreen extends StatefulWidget {
//   const SpatialOrientationScreen({super.key});

//   @override
//   State<SpatialOrientationScreen> createState() => _SpatialOrientationScreenState();
// }

// enum _SpatialTab { simon, maze, radar, compass }

// class _SpatialOrientationScreenState extends State<SpatialOrientationScreen> {
//   static const Color _moduleAccent = Color(0xFF7C3AED);

//   late VoiceAssistantService _voiceAssistant;
//   final AudioPlayer _voicePlayer = AudioPlayer();
//   /// Одделен плеер за кратки звучни ефекти (hit/miss од Гласовен Понг),
//   /// за да не го прекинуваат говорниот клип и обратно.
//   final AudioPlayer _effectsPlayer = AudioPlayer();
//   final Random _random = Random();

//   _SpatialTab _tab = _SpatialTab.simon;
//   bool _explanationOpen = false;

//   String get _langCode => context.locale.languageCode;

//   // =====================================================================
//   // "Симон - насоки"
//   // =====================================================================
//   static const int _simonTotalRounds = 10;
//   static const List<String> _directions = ['up', 'down', 'left', 'right'];
//   static const Map<String, String> _directionLabelKeys = {
//     'up': 'spatial.dir_up',
//     'down': 'spatial.dir_down',
//     'left': 'spatial.dir_left',
//     'right': 'spatial.dir_right',
//   };
//   static const Map<String, IconData> _directionIcons = {
//     'up': Icons.keyboard_arrow_up_rounded,
//     'down': Icons.keyboard_arrow_down_rounded,
//     'left': Icons.keyboard_arrow_left_rounded,
//     'right': Icons.keyboard_arrow_right_rounded,
//   };
//   static const Map<String, List<int>> _directionVibrationPatterns = {
//     'up': [0, 400],
//     'down': [0, 120, 100, 120],
//     'left': [0, 80, 80, 80, 80, 80],
//     'right': [0, 80, 120, 300],
//   };

//   late final List<int> _simonLengthPerRound =
//       List.generate(_simonTotalRounds, (i) => 2 + (i % 6));

//   List<String> _simonSequence = [];
//   int _simonUserIndex = 0;
//   bool _simonRevealed = false;
//   bool _simonIsPlaying = false;
//   String? _simonFlashingDir;
//   int _simonRound = 0;
//   int _simonHits = 0;
//   bool _simonGameOver = false;

//   // =====================================================================
//   // "Лавиринт"
//   // =====================================================================
//   static const int _mazeRows = 7;
//   static const int _mazeCols = 5;
//   static const int _mazeTotalRounds = 5;

//   bool _mazeStarted = false;
//   bool _mazeGameOver = false;
//   List<Point<int>> _mazePath = [];
//   Set<Point<int>> _mazePathSet = {};
//   Point<int>? _mazeCurrentCell;
//   int _mazeProgressIndex = -1;
//   bool _mazeErrorFlash = false;
//   int _mazeRound = 0;
//   int _mazeMistakesThisMaze = 0;
//   int _mazeTotalMistakes = 0;

//   // =====================================================================
//   // "Радар"
//   // =====================================================================
//   static const int _radarTotalRounds = 10;

//   bool _radarStarted = false;
//   bool _radarGameOver = false;
//   bool _radarFound = false;
//   Offset _radarTarget = const Offset(0.5, 0.5);
//   Offset? _radarLastNormPos;
//   Timer? _radarLoopTimer;
//   int _radarMsSinceLastPulse = 0;
//   int _radarRound = 0;
//   int _radarHits = 0;
//   /// Позиција на прстот (во пиксели) + блискост до целта (0..1) - за
//   /// визуелен "пулс" кој ги следи вибрациите (на веб нема вистинска вибрација).
//   Offset? _radarLastLocalPos;
//   bool _radarPulseFlash = false;
//   double _radarProximity = 0;

//   /// Видливост на помошниот круг - 1.0 во првата рунда, линеарно опаѓа до
//   /// 0.0 (целосно невидливо) до последната рунда.
//   double get _radarHintOpacity {
//     if (_radarTotalRounds <= 1) return 0;
//     final t = _radarRound / (_radarTotalRounds - 1);
//     return (0.8 * (1 - t)).clamp(0.0, 0.8);
//   }

//   // =====================================================================
//   // "Компас"
//   // =====================================================================
//   static const int _compassTotalRounds = 4;
//   static const List<double> _compassDirs = [0, 90, 180, 270];
//   static const Map<double, String> _compassDirLabelKeys = {
//     0: 'spatial.compass_north',
//     90: 'spatial.compass_east',
//     180: 'spatial.compass_south',
//     270: 'spatial.compass_west',
//   };

//   StreamSubscription<CompassEvent>? _compassSub;
//   double? _compassHeading;
//   double _compassTargetHeading = 0;
//   bool _compassStarted = false;
//   bool _compassGameOver = false;
//   bool _compassPermissionDenied = false;
//   int _compassRound = 0;
//   int _compassHits = 0;
//   Timer? _compassLockTimer;
//   double _compassLockProgress = 0;

//   /// Дали да се користи верзијата со копчиња (движење + ротација) наместо
//   /// физичкиот сензор - секогаш true на веб/десктоп каде нема компас.
//   bool get _useCompassAlt => kIsWeb;

//   static const int _compassAltTotalRounds = 8;
//   static const List<String> _compassMoves = [
//     'up', 'down', 'left', 'right', 'rotate_left', 'rotate_right', 'stay',
//   ];
//   static const Map<String, String> _compassMoveLabelKeys = {
//     'up': 'spatial.dir_up',
//     'down': 'spatial.dir_down',
//     'left': 'spatial.dir_left',
//     'right': 'spatial.dir_right',
//     'rotate_left': 'spatial.compass_rotate_left',
//     'rotate_right': 'spatial.compass_rotate_right',
//     'stay': 'spatial.compass_stay',
//   };
//   static const Map<String, IconData> _compassMoveIcons = {
//     'up': Icons.keyboard_arrow_up_rounded,
//     'down': Icons.keyboard_arrow_down_rounded,
//     'left': Icons.keyboard_arrow_left_rounded,
//     'right': Icons.keyboard_arrow_right_rounded,
//     'rotate_left': Icons.rotate_left_rounded,
//     'rotate_right': Icons.rotate_right_rounded,
//     'stay': Icons.pan_tool_rounded,
//   };
//   static const Map<String, List<int>> _compassMoveVibrationPatterns = {
//     'up': [0, 400],
//     'down': [0, 120, 100, 120],
//     'left': [0, 80, 80, 80, 80, 80],
//     'right': [0, 80, 120, 300],
//     'rotate_left': [0, 60, 60, 60, 60, 60, 60, 60],
//     'rotate_right': [0, 300, 100, 300],
//     'stay': [0, 600],
//   };
//   static const double _compassAltStep = 34;
//   static const double _compassAltRotateStep = 45;

//   late final List<int> _compassAltLengthPerRound =
//       List.generate(_compassAltTotalRounds, (i) => 2 + (i % 6));

//   List<String> _compassAltSequence = [];
//   bool _compassAltDemoPlaying = false;
//   bool _compassAltRevealed = false;
//   bool _compassAltProcessing = false;
//   int _compassAltUserIndex = 0;
//   int _compassAltRound = 0;
//   int _compassAltHits = 0;
//   bool _compassAltGameOver = false;

//   double _compassAltX = 0;
//   double _compassAltY = 0;
//   double _compassAltRotation = 0;
//   double _compassAltTargetX = 0;
//   double _compassAltTargetY = 0;
//   double _compassAltTargetRotation = 0;
//   /// Дали е побарано хинт за тековниот потег (го покажува само СЛЕДНИОТ
//   /// очекуван потег на барање - НЕ целата низа).
//   bool _compassAltHintRevealed = false;
//   /// Се зголемува при секое движење - визуелно ја "тресе" стрелката.
//   int _compassAltShakeTick = 0;

//   @override
//   void initState() {
//     super.initState();
//     _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
//     _voiceAssistant.initialize();
//     _prepareSimonRound();
//     _prepareCompassAltRound();
//     // Лавиринтот се прикажува (засенчен) уште на почеток - со означен старт и крај.
//     _generateMaze(start: false);
//   }

//   @override
//   void dispose() {
//     // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
//     // дали објаснувањето било отворено или не.
//     _voiceAssistant.stop();
//     _voicePlayer.dispose();
//     _effectsPlayer.dispose();
//     _radarLoopTimer?.cancel();
//     _compassLockTimer?.cancel();
//     _compassSub?.cancel();
//     super.dispose();
//   }

//   /// Пробува однапред снимена звучна датотека (твоја снимка, по јазик), а
//   /// само ако не постои паѓа назад на системскиот text-to-speech.
//   /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
//   /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
//   /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
//   /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
//   Future<void> _playClip(String key, String fallbackText) async {
//     if (!mounted) return;
//     final relativePath = 'audio/spatial_orientation/$_langCode/$key.mp3';
//     try {
//       await _voicePlayer.stop();
//     } catch (_) {}

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

//     if (!mounted) return;
//     if (!(playCallSucceeded && reachedPlaying)) {
//       await _voiceAssistant.speakWithLanguage(fallbackText, _langCode, vibrate: false);
//     }
//   }

//   /// hit.mp3 / miss.mp3 од Гласовен Понг (assets/sounds/pong/) - истите
//   /// датотеки, без потреба од нови снимки. Не е говор, нема TTS-резерва.
//   Future<void> _playPongEffect(String fileName) async {
//     try {
//       await _effectsPlayer.stop();
//     } catch (_) {}
//     try {
//       await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
//     } catch (_) {}
//   }

//   void _toggleExplanation() {
//     final opening = !_explanationOpen;
//     setState(() => _explanationOpen = opening);
//     if (opening) {
//       _playClip('explanation_$_explanationKeySuffix', 'spatial.explanation_${_explanationKeySuffix}_text'.tr());
//     } else {
//       _voiceAssistant.stop();
//       _voicePlayer.stop();
//     }
//   }

//   void _switchTab(_SpatialTab tab) {
//     setState(() => _tab = tab);
//     AccessibilityUtils.provideFeedback(context: context);
//     if (_explanationOpen) {
//       // Панелот е веќе отворен - пушти го говорот за НОВИОТ таб веднаш,
//       // наместо да остане говорот на претходниот таб.
//       _playClip('explanation_$_explanationKeySuffix', 'spatial.explanation_${_explanationKeySuffix}_text'.tr());
//     }
//   }

//   String get _explanationKeySuffix {
//     switch (_tab) {
//       case _SpatialTab.simon:
//         return 'simon';
//       case _SpatialTab.maze:
//         return 'maze';
//       case _SpatialTab.radar:
//         return 'radar';
//       case _SpatialTab.compass:
//         return 'compass';
//     }
//   }

//   // =====================================================================
//   // "Симон - насоки" - логика
//   // =====================================================================

//   void _prepareSimonRound() {
//     final length = _simonLengthPerRound[_simonRound];
//     setState(() {
//       _simonSequence = List.generate(length, (_) => _directions[_random.nextInt(_directions.length)]);
//       _simonUserIndex = 0;
//       _simonRevealed = false;
//       _simonIsPlaying = false;
//     });
//   }

//   Future<void> _vibrateDirection(String dir) async {
//     if (await VibrationUtils.hasVibrator()) {
//       final pattern = _directionVibrationPatterns[dir]!;
//       await VibrationUtils.vibrate(pattern: pattern);
//     }
//   }

//   Future<void> _playSimonSequence() async {
//     setState(() {
//       _simonIsPlaying = true;
//       _simonRevealed = true;
//       _simonUserIndex = 0;
//     });

//     for (final dir in _simonSequence) {
//       if (!mounted) return;
//       setState(() => _simonFlashingDir = dir);
//       await _vibrateDirection(dir);
//       await Future.delayed(const Duration(milliseconds: 650));
//       if (!mounted) return;
//       setState(() => _simonFlashingDir = null);
//       await Future.delayed(const Duration(milliseconds: 250));
//     }

//     if (mounted) setState(() => _simonIsPlaying = false);
//   }

//   Future<void> _onTapDirection(String dir) async {
//     if (_simonIsPlaying || !_simonRevealed || _simonGameOver) return;

//     setState(() => _simonFlashingDir = dir);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 40);
//     }
//     await Future.delayed(const Duration(milliseconds: 130));
//     if (mounted) setState(() => _simonFlashingDir = null);

//     final isCorrectStep = dir == _simonSequence[_simonUserIndex];

//     if (!isCorrectStep) {
//       await _playClip('incorrect', 'spatial.incorrect'.tr());
//       await Future.delayed(const Duration(milliseconds: 900));
//       if (!mounted) return;
//       _nextSimonRound();
//       return;
//     }

//     setState(() => _simonUserIndex++);

//     if (_simonUserIndex >= _simonSequence.length) {
//       setState(() => _simonHits++);
//       await _playClip('correct', 'spatial.correct'.tr());
//       await Future.delayed(const Duration(milliseconds: 900));
//       if (!mounted) return;
//       _nextSimonRound();
//     }
//   }

//   void _nextSimonRound() {
//     final newRound = _simonRound + 1;
//     if (newRound >= _simonTotalRounds) {
//       setState(() {
//         _simonRound = newRound;
//         _simonGameOver = true;
//       });
//     } else {
//       setState(() => _simonRound = newRound);
//       _prepareSimonRound();
//     }
//   }

//   void _restartSimon() {
//     setState(() {
//       _simonRound = 0;
//       _simonHits = 0;
//       _simonGameOver = false;
//     });
//     _prepareSimonRound();
//   }

//   // =====================================================================
//   // "Лавиринт" - логика
//   // =====================================================================

//   void _startMaze() {
//     setState(() {
//       _mazeRound = 0;
//       _mazeTotalMistakes = 0;
//       _mazeGameOver = false;
//     });
//     _generateMaze();
//   }

//   void _generateMaze({bool start = true}) {
//     final path = <Point<int>>[];
//     var cur = Point(0, _random.nextInt(_mazeCols));
//     path.add(cur);
//     final visited = <Point<int>>{cur};
//     while (cur.x < _mazeRows - 1) {
//       final down = Point(cur.x + 1, cur.y);
//       final options = <Point<int>>[down];
//       if (cur.y > 0) {
//         final left = Point(cur.x, cur.y - 1);
//         if (!visited.contains(left)) options.add(left);
//       }
//       if (cur.y < _mazeCols - 1) {
//         final right = Point(cur.x, cur.y + 1);
//         if (!visited.contains(right)) options.add(right);
//       }
//       Point<int> next;
//       if (options.length == 1 || _random.nextDouble() < 0.55) {
//         next = down;
//       } else {
//         final alts = options.where((p) => p != down).toList();
//         next = alts[_random.nextInt(alts.length)];
//       }
//       cur = next;
//       path.add(cur);
//       visited.add(cur);
//     }
//     setState(() {
//       _mazePath = path;
//       _mazePathSet = path.toSet();
//       _mazeCurrentCell = null;
//       _mazeProgressIndex = -1;
//       _mazeMistakesThisMaze = 0;
//       if (start) _mazeStarted = true;
//     });
//   }

//   Future<void> _onMazePointer(Offset localPos, Size areaSize) async {
//     if (!_mazeStarted || _mazeGameOver) return;
//     if (areaSize.width <= 0 || areaSize.height <= 0) return;
//     final cellW = areaSize.width / _mazeCols;
//     final cellH = areaSize.height / _mazeRows;
//     final col = (localPos.dx / cellW).floor().clamp(0, _mazeCols - 1);
//     final row = (localPos.dy / cellH).floor().clamp(0, _mazeRows - 1);
//     final cell = Point(row, col);
//     if (cell == _mazeCurrentCell) return;
//     setState(() => _mazeCurrentCell = cell);

//     // Ако прстот сè уште лебди над квадратчето до кое веќе се стигна - ништо.
//     if (_mazeProgressIndex >= 0 && cell == _mazePath[_mazeProgressIndex]) {
//       return;
//     }

//     final expectedNext =
//         _mazeProgressIndex + 1 < _mazePath.length ? _mazePath[_mazeProgressIndex + 1] : null;

//     if (expectedNext != null && cell == expectedNext) {
//       // Точно - следното квадратче од патеката, по ред.
//       setState(() => _mazeProgressIndex++);
//       if (await VibrationUtils.hasVibrator()) {
//         await VibrationUtils.vibrate(duration: 30);
//       }
//       if (_mazeProgressIndex == _mazePath.length - 1) {
//         await _onMazeComplete();
//       }
//     } else {
//       // Погрешно - или надвор од патеката, или веќе поминато/означено
//       // квадратче допрено повторно (двапати).
//       setState(() => _mazeMistakesThisMaze++);
//       unawaited(_flashMazeError());
//       unawaited(_playPongEffect('miss.mp3'));
//       if (await VibrationUtils.hasVibrator()) {
//         await VibrationUtils.vibrate(pattern: const [0, 250]);
//       }
//     }
//   }

//   Future<void> _flashMazeError() async {
//     setState(() => _mazeErrorFlash = true);
//     await Future.delayed(const Duration(milliseconds: 200));
//     if (mounted) setState(() => _mazeErrorFlash = false);
//   }

//   Future<void> _onMazeComplete() async {
//     setState(() => _mazeTotalMistakes += _mazeMistakesThisMaze);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 500);
//     }
//     unawaited(_playPongEffect('hit.mp3'));
//     await _playClip('correct', 'spatial.correct'.tr());
//     await Future.delayed(const Duration(milliseconds: 900));
//     if (!mounted) return;

//     final newRound = _mazeRound + 1;
//     if (newRound >= _mazeTotalRounds) {
//       setState(() {
//         _mazeRound = newRound;
//         _mazeGameOver = true;
//       });
//     } else {
//       setState(() => _mazeRound = newRound);
//       _generateMaze();
//     }
//   }

//   // =====================================================================
//   // "Радар" - логика
//   // =====================================================================

//   void _startRadar() {
//     setState(() {
//       _radarRound = 0;
//       _radarHits = 0;
//       _radarGameOver = false;
//     });
//     _prepareRadarRound();
//   }

//   void _prepareRadarRound() {
//     _radarLoopTimer?.cancel();
//     setState(() {
//       _radarTarget = Offset(0.15 + _random.nextDouble() * 0.7, 0.15 + _random.nextDouble() * 0.7);
//       _radarFound = false;
//       _radarStarted = true;
//       _radarLastNormPos = null;
//       _radarMsSinceLastPulse = 0;
//     });
//   }

//   void _onRadarPanStart(Offset localPos, Size size) {
//     if (!_radarStarted || _radarGameOver || _radarFound) return;
//     setState(() => _radarLastLocalPos = localPos);
//     _radarLastNormPos = Offset(
//       (localPos.dx / size.width).clamp(0.0, 1.0),
//       (localPos.dy / size.height).clamp(0.0, 1.0),
//     );
//     _radarLoopTimer?.cancel();
//     // Првата пулсација веднаш - да се почувствува штом се допре полето.
//     _radarMsSinceLastPulse = 100000;
//     _radarLoopTimer = Timer.periodic(const Duration(milliseconds: 30), (_) => _radarTick());
//   }

//   void _onRadarPanUpdate(Offset localPos, Size size) {
//     if (!_radarStarted || _radarGameOver || _radarFound) return;
//     setState(() => _radarLastLocalPos = localPos);
//     _radarLastNormPos = Offset(
//       (localPos.dx / size.width).clamp(0.0, 1.0),
//       (localPos.dy / size.height).clamp(0.0, 1.0),
//     );
//   }

//   void _onRadarPanEnd() {
//     _radarLoopTimer?.cancel();
//     if (mounted) {
//       setState(() {
//         _radarLastLocalPos = null;
//         _radarPulseFlash = false;
//         _radarProximity = 0;
//       });
//     }
//   }

//   /// "Жешко-студено": колку си поблизу, толку вибрациите се почести
//   /// (700ms далеку -> 80ms блиску), подолги (30 -> 140ms) - а сосема
//   /// блиску стануваат речиси непрекинати.
//   Future<void> _radarTick() async {
//     if (_radarLastNormPos == null || _radarFound || _radarGameOver || !mounted) return;
//     final dist = (_radarLastNormPos! - _radarTarget).distance;
//     if (dist < 0.06) {
//       _radarLoopTimer?.cancel();
//       await _onRadarFound();
//       return;
//     }
//     final closeness = (1 - (dist / 0.75)).clamp(0.0, 1.0);
//     _radarProximity = closeness;
//     _radarMsSinceLastPulse += 30;
//     final interval = (700 - 620 * closeness).round();
//     if (_radarMsSinceLastPulse >= interval) {
//       _radarMsSinceLastPulse = 0;
//       final duration = (30 + 110 * closeness).round();
//       unawaited(_pulseRadar(duration));
//     }
//   }

//   Future<void> _pulseRadar(int duration) async {
//     if (mounted) setState(() => _radarPulseFlash = true);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: duration);
//     }
//     await Future.delayed(const Duration(milliseconds: 110));
//     if (mounted) setState(() => _radarPulseFlash = false);
//   }

//   Future<void> _onRadarFound() async {
//     setState(() => _radarFound = true);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 400);
//     }
//   }

//   Future<void> _onRadarDropSuccess() async {
//     setState(() => _radarHits++);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 300);
//     }
//     await _playClip('correct', 'spatial.correct'.tr());
//     await Future.delayed(const Duration(milliseconds: 900));
//     if (!mounted) return;

//     final newRound = _radarRound + 1;
//     if (newRound >= _radarTotalRounds) {
//       setState(() {
//         _radarRound = newRound;
//         _radarGameOver = true;
//       });
//     } else {
//       setState(() => _radarRound = newRound);
//       _prepareRadarRound();
//     }
//   }

//   // =====================================================================
//   // "Компас" - логика
//   // =====================================================================

//   Future<void> _startCompass() async {
//     if (_useCompassAlt) {
//       _startCompassAlt();
//       return;
//     }
//     final status = await Permission.locationWhenInUse.request();
//     if (!status.isGranted) {
//       setState(() => _compassPermissionDenied = true);
//       return;
//     }
//     setState(() {
//       _compassPermissionDenied = false;
//       _compassRound = 0;
//       _compassHits = 0;
//       _compassGameOver = false;
//     });
//     _compassSub?.cancel();
//     _compassSub = FlutterCompass.events?.listen(_onCompassEvent);
//     _pickCompassTarget();
//   }

//   void _pickCompassTarget() {
//     _compassLockTimer?.cancel();
//     _compassLockTimer = null;
//     setState(() {
//       _compassTargetHeading = _compassDirs[_random.nextInt(_compassDirs.length)];
//       _compassStarted = true;
//       _compassLockProgress = 0;
//     });
//   }

//   double _angleDiff(double a, double b) {
//     var d = (a - b) % 360;
//     if (d > 180) d -= 360;
//     if (d < -180) d += 360;
//     return d;
//   }

//   void _onCompassEvent(CompassEvent event) {
//     final heading = event.heading;
//     if (heading == null || !mounted || _compassGameOver) return;
//     setState(() => _compassHeading = heading);
//     final diff = _angleDiff(heading, _compassTargetHeading);

//     if (diff.abs() <= 15) {
//       _compassLockTimer ??= Timer.periodic(const Duration(milliseconds: 100), (t) async {
//         if (!mounted) {
//           t.cancel();
//           return;
//         }
//         setState(() => _compassLockProgress = (_compassLockProgress + 0.1).clamp(0.0, 1.0));
//         if (await VibrationUtils.hasVibrator()) {
//           await VibrationUtils.vibrate(duration: 25);
//         }
//         if (_compassLockProgress >= 1.0) {
//           t.cancel();
//           _compassLockTimer = null;
//           _onCompassLocked();
//         }
//       });
//     } else {
//       _compassLockTimer?.cancel();
//       _compassLockTimer = null;
//       if (_compassLockProgress != 0) setState(() => _compassLockProgress = 0);
//     }
//   }

//   Future<void> _onCompassLocked() async {
//     setState(() => _compassHits++);
//     if (await VibrationUtils.hasVibrator()) {
//       await VibrationUtils.vibrate(duration: 500);
//     }
//     await _playClip('correct', 'spatial.correct'.tr());
//     await Future.delayed(const Duration(milliseconds: 900));
//     if (!mounted) return;

//     final newRound = _compassRound + 1;
//     if (newRound >= _compassTotalRounds) {
//       setState(() {
//         _compassRound = newRound;
//         _compassGameOver = true;
//       });
//       _compassSub?.cancel();
//     } else {
//       setState(() => _compassRound = newRound);
//       _pickCompassTarget();
//     }
//   }

//   // =====================================================================
//   // "Компас" (веб/десктоп верзија со копчиња) - логика
//   // =====================================================================

//   void _startCompassAlt() {
//     setState(() {
//       _compassAltRound = 0;
//       _compassAltHits = 0;
//       _compassAltGameOver = false;
//     });
//     _prepareCompassAltRound();
//   }

//   void _prepareCompassAltRound() {
//     final length = _compassAltLengthPerRound[_compassAltRound];
//     setState(() {
//       _compassAltSequence =
//           List.generate(length, (_) => _compassMoves[_random.nextInt(_compassMoves.length)]);
//       _compassAltUserIndex = 0;
//       _compassAltRevealed = false;
//       _compassAltDemoPlaying = false;
//       _compassAltProcessing = false;
//       _compassAltX = 0;
//       _compassAltY = 0;
//       _compassAltRotation = 0;
//       // Дефанзивно - ресетирај ја и „целната" (проѕирна) стрелка, за да
//       // никогаш не покаже застарена вредност од претходната рунда пред
//       // демото за новата рунда да заврши.
//       _compassAltTargetX = 0;
//       _compassAltTargetY = 0;
//       _compassAltTargetRotation = 0;
//       _compassAltHintRevealed = false;
//     });
//   }

//   /// Ја применува една насока врз (x, y, rotation) и ги враќа новите вредности.
//   (double, double, double) _applyMove(String move, double x, double y, double rot) {
//     switch (move) {
//       case 'up':
//         return (x, y - _compassAltStep, rot);
//       case 'down':
//         return (x, y + _compassAltStep, rot);
//       case 'left':
//         return (x - _compassAltStep, y, rot);
//       case 'right':
//         return (x + _compassAltStep, y, rot);
//       case 'rotate_left':
//         return (x, y, rot - _compassAltRotateStep);
//       case 'rotate_right':
//         return (x, y, rot + _compassAltRotateStep);
//       case 'stay':
//       default:
//         return (x, y, rot);
//     }
//   }

//   Future<void> _vibrateCompassMove(String move) async {
//     if (await VibrationUtils.hasVibrator()) {
//       final pattern = _compassMoveVibrationPatterns[move]!;
//       await VibrationUtils.vibrate(pattern: pattern);
//     }
//   }

//   Future<void> _playCompassAltDemo() async {
//     setState(() {
//       _compassAltDemoPlaying = true;
//       _compassAltRevealed = true;
//       _compassAltUserIndex = 0;
//       _compassAltX = 0;
//       _compassAltY = 0;
//       _compassAltRotation = 0;
//     });

//     double x = 0, y = 0, rot = 0;
//     for (final move in _compassAltSequence) {
//       if (!mounted) return;
//       final result = _applyMove(move, x, y, rot);
//       x = result.$1;
//       y = result.$2;
//       rot = result.$3;
//       unawaited(_vibrateCompassMove(move));
//       setState(() {
//         _compassAltX = x;
//         _compassAltY = y;
//         _compassAltRotation = rot;
//         _compassAltShakeTick++;
//       });
//       await Future.delayed(const Duration(milliseconds: 550));
//     }

//     setState(() {
//       _compassAltTargetX = x;
//       _compassAltTargetY = y;
//       _compassAltTargetRotation = rot;
//       // Враќање на иконата на почеток за играчот да почне од таму.
//       _compassAltX = 0;
//       _compassAltY = 0;
//       _compassAltRotation = 0;
//       _compassAltDemoPlaying = false;
//     });
//   }

//   Future<void> _onCompassAltMovePressed(String move) async {
//     if (_compassAltDemoPlaying || !_compassAltRevealed || _compassAltGameOver) return;
//     if (_compassAltProcessing) return;

//     final result = _applyMove(
//       move,
//       _compassAltX,
//       _compassAltY,
//       _compassAltRotation,
//     );
//     final isCorrectStep = move == _compassAltSequence[_compassAltUserIndex];

//     setState(() {
//       _compassAltX = result.$1;
//       _compassAltY = result.$2;
//       _compassAltRotation = result.$3;
//       _compassAltShakeTick++;
//     });
//     unawaited(_vibrateCompassMove(move));

//     if (!isCorrectStep) {
//       _compassAltProcessing = true;
//       await _playClip('incorrect', 'spatial.incorrect'.tr());
//       await Future.delayed(const Duration(milliseconds: 900));
//       _compassAltProcessing = false;
//       if (!mounted) return;
//       _nextCompassAltRound();
//       return;
//     }

//     setState(() {
//       _compassAltUserIndex++;
//       _compassAltHintRevealed = false;
//     });

//     if (_compassAltUserIndex >= _compassAltSequence.length) {
//       _compassAltProcessing = true;
//       setState(() => _compassAltHits++);
//       await _playClip('correct', 'spatial.correct'.tr());
//       await Future.delayed(const Duration(milliseconds: 900));
//       _compassAltProcessing = false;
//       if (!mounted) return;
//       _nextCompassAltRound();
//     }
//   }

//   void _nextCompassAltRound() {
//     final newRound = _compassAltRound + 1;
//     if (newRound >= _compassAltTotalRounds) {
//       setState(() {
//         _compassAltRound = newRound;
//         _compassAltGameOver = true;
//       });
//     } else {
//       setState(() => _compassAltRound = newRound);
//       _prepareCompassAltRound();
//     }
//   }

//   // =====================================================================
//   // Build
//   // =====================================================================

//   @override
//   Widget build(BuildContext context) {
//     final contrast = AccessibilityUtils.getContrastColor(context);
//     final hc = AccessibilityUtils.isHighContrast(context);

//     return GameScreenChrome(
//       accent: _moduleAccent,
//       title: 'spatial.title'.tr(),
//       child: SafeArea(
//         child: Column(
//           children: [
//             _buildExplanationButton(contrast),
//             if (_explanationOpen) _buildExplanationPanel(contrast),
//             _buildTabBar(contrast),
//             Expanded(child: _buildTabContent(contrast, hc)),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildExplanationButton(Color contrast) {
//     final label = _explanationOpen
//         ? 'spatial.explanation_toggle_close'.tr()
//         : 'spatial.explanation_toggle_open'.tr();
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
//       child: Semantics(
//         label: label,
//         button: true,
//         child: SizedBox(
//           width: double.infinity,
//           child: ElevatedButton.icon(
//             onPressed: _toggleExplanation,
//             icon: Icon(
//               _explanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded,
//               size: 26,
//             ),
//             label: Text(
//               label,
//               style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
//             ),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: _explanationOpen
//                   ? AccessibilityUtils.getDisabledColor(context)
//                   : _moduleAccent,
//               foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(vertical: 14),
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//               elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 3,
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildExplanationPanel(Color contrast) {
//     return Container(
//       margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: _moduleAccent.withOpacity(0.08),
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: _moduleAccent.withOpacity(0.35), width: 1.5),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           Row(
//             children: [
//               Icon(Icons.explore_rounded, color: _moduleAccent),
//               const SizedBox(width: 8),
//               Expanded(
//                 child: Text(
//                   'spatial.explanation_title'.tr(),
//                   style: GameTypography.heading(context, contrast, 17),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'spatial.explanation_${_explanationKeySuffix}_text'.tr(),
//             style: GameTypography.body(context, contrast, 15),
//           ),
//         ],
//       ),
//     );
//   }

//   static const Map<_SpatialTab, IconData> _tabIcons = {
//     _SpatialTab.simon: Icons.grid_view_rounded,
//     _SpatialTab.maze: Icons.route_rounded,
//     _SpatialTab.radar: Icons.radar_rounded,
//     _SpatialTab.compass: Icons.explore_rounded,
//   };

//   Widget _buildTabBar(Color contrast) {
//     final tabs = [
//       (_SpatialTab.simon, 'spatial.tab_simon'.tr()),
//       (_SpatialTab.maze, 'spatial.tab_maze'.tr()),
//       (_SpatialTab.radar, 'spatial.tab_radar'.tr()),
//       (_SpatialTab.compass, 'spatial.tab_compass'.tr()),
//     ];
//     final hc = AccessibilityUtils.isHighContrast(context);
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
//       child: IntrinsicHeight(
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             for (var i = 0; i < tabs.length; i++) ...[
//               if (i > 0) const SizedBox(width: 8),
//               Expanded(child: _tabTile(tabs[i].$1, tabs[i].$2, hc)),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   /// Голема плочка за режим: голема икона горе, име долу, јак контраст.
//   Widget _tabTile(_SpatialTab tab, String label, bool hc) {
//     final isActive = _tab == tab;
//     final fg = isActive ? Colors.white : (hc ? Colors.white : _moduleAccent);
//     final bg = isActive
//         ? _moduleAccent
//         : (hc ? Colors.black : _moduleAccent.withOpacity(0.12));
//     return Semantics(
//       label: label,
//       button: true,
//       selected: isActive,
//       child: Material(
//         color: bg,
//         borderRadius: BorderRadius.circular(16),
//         child: InkWell(
//           borderRadius: BorderRadius.circular(16),
//           onTap: () => _switchTab(tab),
//           child: Container(
//             constraints: const BoxConstraints(minHeight: 96),
//             padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(
//                 color: isActive ? Colors.transparent : _moduleAccent,
//                 width: hc ? 2 : 1.5,
//               ),
//             ),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(_tabIcons[tab], size: 44, color: fg),
//                 const SizedBox(height: 6),
//                 Text(
//                   label,
//                   textAlign: TextAlign.center,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   /// Заеднички "заклучен" приказ: играта е видлива (засенчена и недостапна)
//   /// а копчето за започнување стои врз неа - со негово притискање се отклучува.
//   Widget _lockedStage({
//     required bool locked,
//     required Color contrast,
//     required bool hc,
//     required String startLabel,
//     required IconData startIcon,
//     required VoidCallback onStart,
//     required Widget child,
//   }) {
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         Opacity(
//           opacity: locked ? 0.35 : 1.0,
//           child: AbsorbPointer(absorbing: locked, child: child),
//         ),
//         if (locked)
//           Positioned.fill(
//             child: Center(
//               child: Container(
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: hc ? Colors.black : Colors.white.withOpacity(0.92),
//                   borderRadius: BorderRadius.circular(24),
//                   border: Border.all(
//                     color: hc ? Colors.white : _moduleAccent.withOpacity(0.4),
//                     width: hc ? 3 : 1.5,
//                   ),
//                 ),
//                 child: _buildStartCircle(
//                   hc ? contrast : const Color(0xDD000000),
//                   hc,
//                   label: startLabel,
//                   icon: startIcon,
//                   onTap: onStart,
//                 ),
//               ),
//             ),
//           ),
//       ],
//     );
//   }

//   Widget _buildTabContent(Color contrast, bool hc) {
//     switch (_tab) {
//       case _SpatialTab.simon:
//         return _simonGameOver ? _buildSimonEndScreen(contrast) : _buildSimonRound(contrast, hc);
//       case _SpatialTab.maze:
//         return _mazeGameOver ? _buildMazeEndScreen(contrast) : _buildMazeRound(contrast, hc);
//       case _SpatialTab.radar:
//         return _radarGameOver ? _buildRadarEndScreen(contrast) : _buildRadarRound(contrast, hc);
//       case _SpatialTab.compass:
//         return _useCompassAlt
//             ? (_compassAltGameOver ? _buildCompassAltEndScreen(contrast) : _buildCompassAltRound(contrast, hc))
//             : (_compassGameOver ? _buildCompassEndScreen(contrast) : _buildCompassRound(contrast, hc));
//     }
//   }

//   // --- Заеднички мал резиме-екран ---
//   Widget _buildSummaryScreen(Color contrast, String text, VoidCallback onPlayAgain) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
//             const SizedBox(height: 16),
//             Text(text, textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 18)),
//             const SizedBox(height: 28),
//             ElevatedButton.icon(
//               onPressed: onPlayAgain,
//               icon: const Icon(Icons.refresh_rounded),
//               label: Text('spatial.play_again'.tr()),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: _moduleAccent,
//                 foregroundColor: Colors.white,
//                 padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
//                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // =====================================================================
//   // "Симон - насоки" - UI
//   // =====================================================================

//   Widget _buildSimonRound(Color contrast, bool hc) {
//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//           child: Text(
//             'spatial.rounds_progress'.tr(args: [(_simonRound + 1).toString(), _simonTotalRounds.toString()]),
//             style: GameTypography.heading(context, contrast, 18),
//           ),
//         ),
//         Text(
//           'spatial.score'.tr(args: [_simonHits.toString()]),
//           style: GameTypography.body(context, contrast, 15),
//         ),
//         const SizedBox(height: 8),
//         Expanded(
//           child: _lockedStage(
//             locked: !_simonRevealed,
//             contrast: contrast,
//             hc: hc,
//             startLabel: 'spatial.start_sensing'.tr(),
//             startIcon: Icons.vibration_rounded,
//             onStart: _playSimonSequence,
//             child: Column(
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 16),
//                   child: Column(
//                     children: [
//                       Text(
//                         'spatial.choose_prompt'.tr(),
//                         textAlign: TextAlign.center,
//                         style: GameTypography.body(context, contrast, 15),
//                       ),
//                       TextButton.icon(
//                         onPressed: _simonIsPlaying ? null : _playSimonSequence,
//                         icon: const Icon(Icons.replay_rounded),
//                         label: Text('spatial.sense_again'.tr()),
//                       ),
//                     ],
//                   ),
//                 ),
//                 Expanded(child: _buildDPad(contrast, hc)),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildStartCircle(Color contrast, bool hc,
//       {required String label, required IconData icon, required VoidCallback onTap}) {
//     return Semantics(
//       label: label,
//       button: true,
//       child: GestureDetector(
//         onTap: onTap,
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Container(
//               width: 110,
//               height: 110,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 gradient: hc
//                     ? null
//                     : LinearGradient(
//                         colors: [_moduleAccent, Color.lerp(_moduleAccent, const Color(0xFFC4B5FD), 0.5)!],
//                         begin: Alignment.topLeft,
//                         end: Alignment.bottomRight,
//                       ),
//                 color: hc ? _moduleAccent : null,
//                 border: Border.all(color: contrast, width: hc ? 3 : 0),
//                 boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
//               ),
//               child: Icon(icon, size: 48, color: Colors.white),
//             ),
//             const SizedBox(height: 10),
//             Text(label, style: GameTypography.heading(context, contrast, 16), textAlign: TextAlign.center),
//           ],
//         ),
//       ),
//     );
//   }

//   /// Четири ИСТИ копчиња (секое 1/3 од ширината и 1/3 од висината) во
//   /// форма на крст - горе, лево, десно, долу; во средината е декорација.
//   Widget _buildDPad(Color contrast, bool hc) {
//     final interactive = _simonRevealed && !_simonIsPlaying && !_simonGameOver;
//     const empty = SizedBox.shrink();
//     Widget row(Widget a, Widget b, Widget c) => Expanded(
//           child: Row(
//             children: [
//               Expanded(child: a),
//               const SizedBox(width: 8),
//               Expanded(child: b),
//               const SizedBox(width: 8),
//               Expanded(child: c),
//             ],
//           ),
//         );
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//       child: Column(
//         children: [
//           row(empty, _dirZone('up', contrast, hc, interactive), empty),
//           const SizedBox(height: 8),
//           row(
//             _dirZone('left', contrast, hc, interactive),
//             Center(
//               child: Icon(
//                 Icons.vibration_rounded,
//                 size: 56,
//                 color: _moduleAccent.withOpacity(hc ? 0.9 : 0.35),
//               ),
//             ),
//             _dirZone('right', contrast, hc, interactive),
//           ),
//           const SizedBox(height: 8),
//           row(empty, _dirZone('down', contrast, hc, interactive), empty),
//         ],
//       ),
//     );
//   }

//   Widget _dirZone(String dir, Color contrast, bool hc, bool interactive) {
//     final isFlashing = _simonFlashingDir == dir;
//     final label = _directionLabelKeys[dir]!.tr();

//     return Semantics(
//       label: label,
//       button: interactive,
//       child: Material(
//         color: Colors.transparent,
//         borderRadius: BorderRadius.circular(18),
//         child: InkWell(
//           borderRadius: BorderRadius.circular(18),
//           onTap: interactive ? () => _onTapDirection(dir) : null,
//           child: AnimatedContainer(
//             duration: const Duration(milliseconds: 130),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(18),
//               gradient: hc
//                   ? null
//                   : LinearGradient(
//                       colors: isFlashing
//                           ? [Colors.white, Color.lerp(_moduleAccent, Colors.white, 0.5)!]
//                           : [_moduleAccent, Color.lerp(_moduleAccent, Colors.white, 0.25)!],
//                       begin: Alignment.topLeft,
//                       end: Alignment.bottomRight,
//                     ),
//               color: hc ? _moduleAccent.withOpacity(isFlashing ? 0.5 : 0.9) : null,
//               border: Border.all(
//                 color: isFlashing ? Colors.white : (hc ? contrast : Colors.transparent),
//                 width: isFlashing ? 4 : 2,
//               ),
//             ),
//             child: Center(child: Icon(_directionIcons[dir], size: 64, color: Colors.white)),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildSimonEndScreen(Color contrast) {
//     final misses = _simonTotalRounds - _simonHits;
//     return _buildSummaryScreen(
//       contrast,
//       'spatial.final_summary'.tr(args: [_simonHits.toString(), misses.toString(), _simonTotalRounds.toString()]),
//       _restartSimon,
//     );
//   }

//   // =====================================================================
//   // "Лавиринт" - UI
//   // =====================================================================

//   Widget _buildMazeRound(Color contrast, bool hc) {
//     // Сите полиња освен почетокот (зелено) и крајот (портокалово) се
//     // темно сиви - за јак контраст, а патеката останува невидлива.
//     final wallColor = hc ? const Color(0xFF1F1F1F) : const Color(0xFF374151);
//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//           child: Text(
//             'spatial.maze_progress'.tr(args: [(_mazeRound + 1).toString(), _mazeTotalRounds.toString()]),
//             style: GameTypography.heading(context, contrast, 18),
//           ),
//         ),
//         Text(
//           'spatial.maze_mistakes'.tr(args: [_mazeMistakesThisMaze.toString()]),
//           style: GameTypography.body(context, contrast, 14),
//         ),
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
//           child: Text(
//             'spatial.maze_prompt'.tr(),
//             textAlign: TextAlign.center,
//             style: GameTypography.body(context, contrast, 13),
//           ),
//         ),
//         Expanded(
//           child: Padding(
//             padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
//             child: _lockedStage(
//               locked: !_mazeStarted,
//               contrast: contrast,
//               hc: hc,
//               startLabel: 'spatial.maze_start'.tr(),
//               startIcon: Icons.route_rounded,
//               onStart: _startMaze,
//               child: LayoutBuilder(
//                 builder: (context, constraints) {
//                   final size = Size(constraints.maxWidth, constraints.maxHeight);
//                   return GestureDetector(
//                     behavior: HitTestBehavior.opaque,
//                     onPanStart: (d) => _onMazePointer(d.localPosition, size),
//                     onPanUpdate: (d) => _onMazePointer(d.localPosition, size),
//                     child: AnimatedContainer(
//                       duration: const Duration(milliseconds: 100),
//                       decoration: BoxDecoration(
//                         color: hc ? Colors.black : const Color(0xFF111827),
//                         borderRadius: BorderRadius.circular(16),
//                         border: Border.all(
//                           color: _mazeErrorFlash ? const Color(0xFFEF4444) : contrast,
//                           width: _mazeErrorFlash ? 6 : 3,
//                         ),
//                       ),
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(13),
//                         child: Column(
//                           children: List.generate(_mazeRows, (row) {
//                             return Expanded(
//                               child: Row(
//                                 children: List.generate(_mazeCols, (col) {
//                                   final cell = Point(row, col);
//                                   final isStart = _mazePath.isNotEmpty && cell == _mazePath.first;
//                                   final isEnd = _mazePath.isNotEmpty && cell == _mazePath.last;
//                                   final isCurrent = cell == _mazeCurrentCell;
//                                   Color cellColor;
//                                   if (isEnd) {
//                                     cellColor = const Color(0xFFF97316);
//                                   } else if (isStart) {
//                                     cellColor = const Color(0xFF22C55E);
//                                   } else {
//                                     cellColor = wallColor;
//                                   }
//                                   return Expanded(
//                                     child: Container(
//                                       margin: const EdgeInsets.all(1.5),
//                                       decoration: BoxDecoration(
//                                         color: cellColor,
//                                         borderRadius: BorderRadius.circular(4),
//                                         border: isCurrent
//                                             ? Border.all(color: Colors.white, width: 2.5)
//                                             : null,
//                                       ),
//                                     ),
//                                   );
//                                 }),
//                               ),
//                             );
//                           }),
//                         ),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildMazeEndScreen(Color contrast) {
//     return _buildSummaryScreen(
//       contrast,
//       'spatial.maze_final_summary'.tr(args: [_mazeTotalRounds.toString(), _mazeTotalMistakes.toString()]),
//       _startMaze,
//     );
//   }

//   // =====================================================================
//   // "Радар" - UI
//   // =====================================================================

//   Widget _buildRadarRound(Color contrast, bool hc) {
//     const amber = Color(0xFFFFEE58);
//     return Column(
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//           child: Text(
//             'spatial.radar_progress'.tr(args: [(_radarRound + 1).toString(), _radarTotalRounds.toString()]),
//             style: GameTypography.heading(context, contrast, 18),
//           ),
//         ),
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
//           child: Text(
//             _radarFound ? 'spatial.radar_drag_prompt'.tr() : 'spatial.radar_prompt'.tr(),
//             textAlign: TextAlign.center,
//             style: GameTypography.body(context, contrast, 14),
//           ),
//         ),
//         Expanded(
//           child: Padding(
//             padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
//             child: _lockedStage(
//               locked: !_radarStarted,
//               contrast: contrast,
//               hc: hc,
//               startLabel: 'spatial.radar_start'.tr(),
//               startIcon: Icons.radar_rounded,
//               onStart: _startRadar,
//               child: LayoutBuilder(
//                 builder: (context, constraints) {
//                   final size = Size(constraints.maxWidth, constraints.maxHeight);
//                   // Визуелен пулс околу прстот - расте како што се приближуваш
//                   // и светнува на секоја вибрација.
//                   final ringRadius = 22 + 34 * _radarProximity + (_radarPulseFlash ? 8 : 0);
//                   return Container(
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(16),
//                       border: Border.all(color: contrast, width: 3),
//                       color: hc ? Colors.black : const Color(0xFF0B1020),
//                     ),
//                     child: ClipRRect(
//                       borderRadius: BorderRadius.circular(13),
//                       child: Stack(
//                         children: [
//                           // Сцена: концентрични кругови како на радар.
//                           Positioned.fill(
//                             child: IgnorePointer(
//                               child: CustomPaint(
//                                 painter: _RingsScenePainter(
//                                   color: Colors.white.withOpacity(hc ? 0.4 : 0.13),
//                                 ),
//                               ),
//                             ),
//                           ),
//                           Positioned.fill(
//                             child: _radarFound
//                                 ? _buildRadarDragPhase(contrast)
//                                 : Stack(
//                                     children: [
//                                       // Слаб светол круг околу скриениот предмет - за
//                                       // визуелна помош. Видливоста опаѓа секоја рунда.
//                                       Positioned(
//                                         left: _radarTarget.dx * size.width - 40,
//                                         top: _radarTarget.dy * size.height - 40,
//                                         child: IgnorePointer(
//                                           child: Opacity(
//                                             opacity: _radarStarted ? _radarHintOpacity : 0,
//                                             child: Container(
//                                               width: 80,
//                                               height: 80,
//                                               decoration: BoxDecoration(
//                                                 shape: BoxShape.circle,
//                                                 color: amber.withOpacity(0.35),
//                                                 border: Border.all(color: amber, width: 2),
//                                               ),
//                                             ),
//                                           ),
//                                         ),
//                                       ),
//                                       if (_radarLastLocalPos != null)
//                                         Positioned(
//                                           left: _radarLastLocalPos!.dx - ringRadius,
//                                           top: _radarLastLocalPos!.dy - ringRadius,
//                                           child: IgnorePointer(
//                                             child: AnimatedContainer(
//                                               duration: const Duration(milliseconds: 90),
//                                               width: ringRadius * 2,
//                                               height: ringRadius * 2,
//                                               decoration: BoxDecoration(
//                                                 shape: BoxShape.circle,
//                                                 color: amber.withOpacity(_radarPulseFlash ? 0.35 : 0.06),
//                                                 border: Border.all(
//                                                   color: amber.withOpacity(_radarPulseFlash ? 1.0 : 0.5),
//                                                   width: 3,
//                                                 ),
//                                               ),
//                                             ),
//                                           ),
//                                         ),
//                                       GestureDetector(
//                                         behavior: HitTestBehavior.opaque,
//                                         onPanStart: (d) => _onRadarPanStart(d.localPosition, size),
//                                         onPanUpdate: (d) => _onRadarPanUpdate(d.localPosition, size),
//                                         onPanEnd: (_) => _onRadarPanEnd(),
//                                         onPanCancel: _onRadarPanEnd,
//                                         child: const SizedBox.expand(),
//                                       ),
//                                     ],
//                                   ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildRadarDragPhase(Color contrast) {
//     return Stack(
//       children: [
//         Positioned(
//           top: 16,
//           right: 16,
//           child: DragTarget<int>(
//             onAccept: (_) => _onRadarDropSuccess(),
//             builder: (context, candidate, rejected) {
//               final active = candidate.isNotEmpty;
//               return Container(
//                 width: 76,
//                 height: 76,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: active ? const Color(0xFFFBBF24).withOpacity(0.4) : Colors.white.withOpacity(0.1),
//                   border: Border.all(color: const Color(0xFFFBBF24), width: 3),
//                 ),
//                 child: const Icon(Icons.lock_open_rounded, color: Color(0xFFFBBF24), size: 34),
//               );
//             },
//           ),
//         ),
//         Center(
//           child: Draggable<int>(
//             data: 1,
//             feedback: _radarKeyIcon(),
//             childWhenDragging: Opacity(opacity: 0.3, child: _radarKeyIcon()),
//             child: _radarKeyIcon(),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _radarKeyIcon() {
//     return Container(
//       width: 64,
//       height: 64,
//       decoration: const BoxDecoration(
//         shape: BoxShape.circle,
//         color: Color(0xFFFFEE58),
//       ),
//       child: const Icon(Icons.vpn_key_rounded, color: Colors.black87, size: 34),
//     );
//   }

//   Widget _buildRadarEndScreen(Color contrast) {
//     return _buildSummaryScreen(
//       contrast,
//       'spatial.radar_final_summary'.tr(args: [_radarTotalRounds.toString()]),
//       _startRadar,
//     );
//   }

//   // =====================================================================
//   // "Компас" - UI
//   // =====================================================================

//   Widget _buildCompassRound(Color contrast, bool hc) {
//     if (_compassPermissionDenied) {
//       return Center(
//         child: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Text(
//             'spatial.compass_permission_denied'.tr(),
//             textAlign: TextAlign.center,
//             style: GameTypography.body(context, contrast, 16),
//           ),
//         ),
//       );
//     }

//     final targetLabel = _compassDirLabelKeys[_compassTargetHeading]!.tr();
//     final headingText = _compassHeading != null ? _compassHeading!.round().toString() : '--';
//     final arrowColor = hc ? const Color(0xFFFFFF00) : const Color(0xFFFBBF24);

//     return _lockedStage(
//       locked: !_compassStarted,
//       contrast: contrast,
//       hc: hc,
//       startLabel: 'spatial.compass_start'.tr(),
//       startIcon: Icons.explore_rounded,
//       onStart: _startCompass,
//       child: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//             child: Text(
//               'spatial.compass_progress'.tr(args: [(_compassRound + 1).toString(), _compassTotalRounds.toString()]),
//               style: GameTypography.heading(context, contrast, 18),
//             ),
//           ),
//           Text(
//             'spatial.compass_target'.tr(args: [targetLabel]),
//             style: GameTypography.heading(context, contrast, 20),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             'spatial.compass_current'.tr(args: [headingText]),
//             style: GameTypography.body(context, contrast, 14),
//           ),
//           Expanded(
//             child: Container(
//               margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//               decoration: _sceneDecoration(hc),
//               child: Stack(
//                 alignment: Alignment.center,
//                 children: [
//                   Positioned.fill(
//                     child: ClipRRect(
//                       borderRadius: BorderRadius.circular(17),
//                       child: CustomPaint(
//                         painter: _RingsScenePainter(color: Colors.white.withOpacity(hc ? 0.4 : 0.16)),
//                       ),
//                     ),
//                   ),
//                   SizedBox(
//                     width: 180,
//                     height: 180,
//                     child: CircularProgressIndicator(
//                       value: _compassLockProgress,
//                       strokeWidth: 10,
//                       backgroundColor: Colors.white.withOpacity(0.15),
//                       valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
//                     ),
//                   ),
//                   Transform.rotate(
//                     angle: ((_compassHeading ?? 0) * (pi / 180)),
//                     child: Icon(Icons.navigation_rounded, size: 90, color: arrowColor),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   /// Тамна "сцена" (позадина) за компасот.
//   BoxDecoration _sceneDecoration(bool hc) {
//     return BoxDecoration(
//       borderRadius: BorderRadius.circular(20),
//       border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 3),
//       gradient: hc
//           ? null
//           : const LinearGradient(
//               colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//             ),
//       color: hc ? Colors.black : null,
//     );
//   }

//   Widget _buildCompassEndScreen(Color contrast) {
//     return _buildSummaryScreen(
//       contrast,
//       'spatial.compass_final_summary'.tr(args: [_compassTotalRounds.toString()]),
//       _startCompass,
//     );
//   }

//   Widget _buildCompassAltRound(Color contrast, bool hc) {
//     return _lockedStage(
//       locked: !_compassAltRevealed,
//       contrast: contrast,
//       hc: hc,
//       startLabel: 'spatial.compass_alt_start'.tr(),
//       startIcon: Icons.explore_rounded,
//       onStart: _playCompassAltDemo,
//       child: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//             child: Text(
//               'spatial.compass_alt_progress'.tr(args: [(_compassAltRound + 1).toString(), _compassAltTotalRounds.toString()]),
//               style: GameTypography.heading(context, contrast, 18),
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             child: Text(
//               _compassAltDemoPlaying
//                   ? 'spatial.compass_alt_prompt'.tr()
//                   : 'spatial.compass_alt_choose_prompt'.tr(),
//               textAlign: TextAlign.center,
//               style: GameTypography.body(context, contrast, 14),
//             ),
//           ),
//           if (!_compassAltDemoPlaying) ...[
//             Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 TextButton.icon(
//                   onPressed: _playCompassAltDemo,
//                   icon: const Icon(Icons.replay_rounded),
//                   label: Text('spatial.compass_alt_replay'.tr()),
//                 ),
//                 const SizedBox(width: 8),
//                 TextButton.icon(
//                   onPressed: () => setState(() => _compassAltHintRevealed = true),
//                   icon: const Icon(Icons.lightbulb_outline_rounded),
//                   label: Text('spatial.compass_alt_hint'.tr()),
//                 ),
//               ],
//             ),
//             if (_compassAltHintRevealed &&
//                 _compassAltUserIndex < _compassAltSequence.length)
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(_compassMoveIcons[_compassAltSequence[_compassAltUserIndex]], color: _moduleAccent, size: 22),
//                     const SizedBox(width: 6),
//                     Text(
//                       'spatial.compass_alt_hint_label'.tr(args: [
//                         _compassMoveLabelKeys[_compassAltSequence[_compassAltUserIndex]]!.tr(),
//                       ]),
//                       style: GameTypography.body(context, contrast, 15),
//                     ),
//                   ],
//                 ),
//               ),
//           ],
//           Expanded(flex: 3, child: _buildCompassAltScene(contrast, hc)),
//           if (!_compassAltDemoPlaying)
//             Expanded(flex: 2, child: _buildCompassAltPad(contrast, hc)),
//         ],
//       ),
//     );
//   }

//   /// Сцена со мрежа зад стрелката - едно квадратче = еден чекор на движење,
//   /// со означена почетна точка во средината. Се отклучува со "Старт".
//   Widget _buildCompassAltScene(Color contrast, bool hc) {
//     final arrowColor = hc ? const Color(0xFFFFFF00) : const Color(0xFFFBBF24);
//     final ghostColor = Colors.white.withOpacity(hc ? 0.5 : 0.35);
//     return Container(
//       margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
//       decoration: _sceneDecoration(hc),
//       child: Stack(
//         clipBehavior: Clip.none,
//         alignment: Alignment.center,
//         children: [
//           Positioned.fill(
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(17),
//               child: CustomPaint(
//                 painter: _GridScenePainter(
//                   lineColor: Colors.white.withOpacity(hc ? 0.35 : 0.13),
//                   ringColor: Colors.white.withOpacity(hc ? 0.8 : 0.4),
//                   step: _compassAltStep,
//                 ),
//               ),
//             ),
//           ),
//           if (!_compassAltDemoPlaying)
//             Transform.translate(
//               offset: Offset(_compassAltTargetX, _compassAltTargetY),
//               child: Transform.rotate(
//                 angle: _compassAltTargetRotation * (pi / 180),
//                 child: Icon(Icons.navigation_rounded, size: 96, color: ghostColor),
//               ),
//             ),
//           AnimatedContainer(
//             duration: const Duration(milliseconds: 400),
//             transform: Matrix4.translationValues(_compassAltX, _compassAltY, 0),
//             child: AnimatedRotation(
//               turns: _compassAltRotation / 360,
//               duration: const Duration(milliseconds: 400),
//               child: _shakeWrap(Icon(Icons.navigation_rounded, size: 96, color: arrowColor)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   /// Визуелна "вибрација" - стрелката се тресе кратко при секое движење.
//   Widget _shakeWrap(Widget child) {
//     return TweenAnimationBuilder<double>(
//       key: ValueKey(_compassAltShakeTick),
//       tween: Tween<double>(begin: 0.0, end: 1.0),
//       duration: const Duration(milliseconds: 500),
//       builder: (context, t, c) {
//         final amp = _compassAltShakeTick == 0 ? 0.0 : (1 - t) * 8;
//         return Transform.translate(
//           offset: Offset(sin(t * pi * 12) * amp, cos(t * pi * 10) * amp * 0.6),
//           child: c,
//         );
//       },
//       child: child,
//     );
//   }

//   Widget _buildCompassAltPad(Color contrast, bool hc) {
//     Widget cell(String? move) {
//       if (move == null) return const SizedBox.shrink();
//       return _compassMoveButton(move, contrast, hc);
//     }

//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
//       child: Column(
//         children: [
//           Expanded(
//             child: Row(
//               children: [
//                 Expanded(child: cell('rotate_left')),
//                 const SizedBox(width: 8),
//                 Expanded(child: cell('up')),
//                 const SizedBox(width: 8),
//                 Expanded(child: cell('rotate_right')),
//               ],
//             ),
//           ),
//           const SizedBox(height: 8),
//           Expanded(
//             child: Row(
//               children: [
//                 Expanded(child: cell('left')),
//                 const SizedBox(width: 8),
//                 Expanded(child: cell('stay')),
//                 const SizedBox(width: 8),
//                 Expanded(child: cell('right')),
//               ],
//             ),
//           ),
//           const SizedBox(height: 8),
//           Expanded(
//             child: Row(
//               children: [
//                 const Spacer(),
//                 Expanded(child: cell('down')),
//                 const Spacer(),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _compassMoveButton(String move, Color contrast, bool hc) {
//     final label = _compassMoveLabelKeys[move]!.tr();
//     return Semantics(
//       label: label,
//       button: true,
//       child: Material(
//         color: Colors.transparent,
//         borderRadius: BorderRadius.circular(14),
//         child: InkWell(
//           borderRadius: BorderRadius.circular(14),
//           onTap: _compassAltProcessing ? null : () => _onCompassAltMovePressed(move),
//           child: Ink(
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(14),
//               color: hc ? _moduleAccent.withOpacity(0.85) : _moduleAccent.withOpacity(0.16),
//               border: Border.all(color: _moduleAccent, width: 1.5),
//             ),
//             child: Center(
//               child: Icon(_compassMoveIcons[move], size: 42, color: hc ? Colors.white : _moduleAccent),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildCompassAltEndScreen(Color contrast) {
//     final misses = _compassAltTotalRounds - _compassAltHits;
//     return _buildSummaryScreen(
//       contrast,
//       'spatial.compass_alt_final_summary'.tr(args: [
//         _compassAltHits.toString(),
//         misses.toString(),
//         _compassAltTotalRounds.toString(),
//       ]),
//       _startCompassAlt,
//     );
//   }
// }

// /// Сцена со концентрични кругови и крст - за радарот и компасот.
// class _RingsScenePainter extends CustomPainter {
//   final Color color;
//   const _RingsScenePainter({required this.color});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final c = size.center(Offset.zero);
//     final base = min(size.width, size.height) / 2;
//     final paint = Paint()
//       ..color = color
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 1.5;
//     for (final k in const [0.3, 0.6, 0.9, 1.2]) {
//       canvas.drawCircle(c, base * k, paint);
//     }
//     canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), paint);
//     canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), paint);
//   }

//   @override
//   bool shouldRepaint(covariant _RingsScenePainter oldDelegate) => oldDelegate.color != color;
// }

// /// Мрежа (квадратчиња = чекори) со означена почетна точка во центарот.
// class _GridScenePainter extends CustomPainter {
//   final Color lineColor;
//   final Color ringColor;
//   final double step;
//   const _GridScenePainter({required this.lineColor, required this.ringColor, required this.step});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final c = size.center(Offset.zero);
//     final line = Paint()
//       ..color = lineColor
//       ..strokeWidth = 1;
//     for (var x = c.dx; x <= size.width; x += step) {
//       canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
//     }
//     for (var x = c.dx - step; x >= 0; x -= step) {
//       canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
//     }
//     for (var y = c.dy; y <= size.height; y += step) {
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
//     }
//     for (var y = c.dy - step; y >= 0; y -= step) {
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
//     }
//     final ring = Paint()
//       ..color = ringColor
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2;
//     canvas.drawCircle(c, step * 0.7, ring);
//     canvas.drawCircle(c, step * 2.0, ring..color = ringColor.withOpacity(0.5));
//   }

//   @override
//   bool shouldRepaint(covariant _GridScenePainter oldDelegate) =>
//       oldDelegate.lineColor != lineColor ||
//       oldDelegate.ringColor != ringColor ||
//       oldDelegate.step != step;
// }
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

/// Модул за просторна ориентација со 4 режими (табови горе):
/// - Симон - насоки: вибрациска низа од 4 насоки, детето ја повторува со допир.
/// - Лавиринт: следење невидлива патека со прст, вибрација при излегување.
/// - Радар: пронаоѓање скриен предмет преку "жешко-студено" вибрации, потоа
///   влечење на пронајдениот предмет до означена цел.
/// - Компас: физичко вртење на телефонот за да се погоди бараната насока
///   (север/југ/исток/запад), користејќи го компасот на уредот.
class SpatialOrientationScreen extends StatefulWidget {
  const SpatialOrientationScreen({super.key});

  @override
  State<SpatialOrientationScreen> createState() => _SpatialOrientationScreenState();
}

enum _SpatialTab { simon, maze, radar, compass }

class _SpatialOrientationScreenState extends State<SpatialOrientationScreen> {
  static const Color _moduleAccent = Color(0xFF7C3AED);

  late VoiceAssistantService _voiceAssistant;
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Одделен плеер за кратки звучни ефекти (hit/miss од Гласовен Понг),
  /// за да не го прекинуваат говорниот клип и обратно.
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final Random _random = Random();

  _SpatialTab _tab = _SpatialTab.simon;
  bool _explanationOpen = false;

  String get _langCode => context.locale.languageCode;

  // =====================================================================
  // "Симон - насоки"
  // =====================================================================
  static const int _simonTotalRounds = 10;
  static const List<String> _directions = ['up', 'down', 'left', 'right'];
  static const Map<String, String> _directionLabelKeys = {
    'up': 'spatial.dir_up',
    'down': 'spatial.dir_down',
    'left': 'spatial.dir_left',
    'right': 'spatial.dir_right',
  };
  static const Map<String, IconData> _directionIcons = {
    'up': Icons.keyboard_arrow_up_rounded,
    'down': Icons.keyboard_arrow_down_rounded,
    'left': Icons.keyboard_arrow_left_rounded,
    'right': Icons.keyboard_arrow_right_rounded,
  };
  static const Map<String, List<int>> _directionVibrationPatterns = {
    'up': [0, 400],
    'down': [0, 120, 100, 120],
    'left': [0, 80, 80, 80, 80, 80],
    'right': [0, 80, 120, 300],
  };

  late final List<int> _simonLengthPerRound =
      List.generate(_simonTotalRounds, (i) => 2 + (i % 6));

  List<String> _simonSequence = [];
  int _simonUserIndex = 0;
  bool _simonRevealed = false;
  bool _simonIsPlaying = false;
  String? _simonFlashingDir;
  int _simonRound = 0;
  int _simonHits = 0;
  bool _simonGameOver = false;

  // =====================================================================
  // "Лавиринт"
  // =====================================================================
  static const int _mazeRows = 7;
  static const int _mazeCols = 5;
  static const int _mazeTotalRounds = 5;

  bool _mazeStarted = false;
  bool _mazeGameOver = false;
  List<Point<int>> _mazePath = [];
  Set<Point<int>> _mazePathSet = {};
  Point<int>? _mazeCurrentCell;
  int _mazeProgressIndex = -1;
  bool _mazeErrorFlash = false;
  int _mazeRound = 0;
  int _mazeMistakesThisMaze = 0;
  int _mazeTotalMistakes = 0;

  // =====================================================================
  // "Радар"
  // =====================================================================
  static const int _radarTotalRounds = 10;

  bool _radarStarted = false;
  bool _radarGameOver = false;
  bool _radarFound = false;
  Offset _radarTarget = const Offset(0.5, 0.5);
  Offset? _radarLastNormPos;
  Timer? _radarLoopTimer;
  int _radarMsSinceLastPulse = 0;
  int _radarRound = 0;
  int _radarHits = 0;
  /// Позиција на прстот (во пиксели) + блискост до целта (0..1) - за
  /// визуелен "пулс" кој ги следи вибрациите (на веб нема вистинска вибрација).
  Offset? _radarLastLocalPos;
  bool _radarPulseFlash = false;
  double _radarProximity = 0;

  /// Видливост на помошниот круг - 1.0 во првата рунда, линеарно опаѓа до
  /// 0.0 (целосно невидливо) до последната рунда.
  double get _radarHintOpacity {
    if (_radarTotalRounds <= 1) return 0;
    final t = _radarRound / (_radarTotalRounds - 1);
    return (0.8 * (1 - t)).clamp(0.0, 0.8);
  }

  // =====================================================================
  // "Компас"
  // =====================================================================
  static const int _compassTotalRounds = 4;
  static const List<double> _compassDirs = [0, 90, 180, 270];
  static const Map<double, String> _compassDirLabelKeys = {
    0: 'spatial.compass_north',
    90: 'spatial.compass_east',
    180: 'spatial.compass_south',
    270: 'spatial.compass_west',
  };

  StreamSubscription<CompassEvent>? _compassSub;
  double? _compassHeading;
  double _compassTargetHeading = 0;
  bool _compassStarted = false;
  bool _compassGameOver = false;
  bool _compassPermissionDenied = false;
  int _compassRound = 0;
  int _compassHits = 0;
  Timer? _compassLockTimer;
  double _compassLockProgress = 0;

  /// Дали да се користи верзијата со копчиња (движење + ротација) наместо
  /// физичкиот сензор - секогаш true на веб/десктоп каде нема компас.
  bool get _useCompassAlt => kIsWeb;

  static const int _compassAltTotalRounds = 8;
  static const List<String> _compassMoves = [
    'up', 'down', 'left', 'right', 'rotate_left', 'rotate_right', 'stay',
  ];
  static const Map<String, String> _compassMoveLabelKeys = {
    'up': 'spatial.dir_up',
    'down': 'spatial.dir_down',
    'left': 'spatial.dir_left',
    'right': 'spatial.dir_right',
    'rotate_left': 'spatial.compass_rotate_left',
    'rotate_right': 'spatial.compass_rotate_right',
    'stay': 'spatial.compass_stay',
  };
  static const Map<String, IconData> _compassMoveIcons = {
    'up': Icons.keyboard_arrow_up_rounded,
    'down': Icons.keyboard_arrow_down_rounded,
    'left': Icons.keyboard_arrow_left_rounded,
    'right': Icons.keyboard_arrow_right_rounded,
    'rotate_left': Icons.rotate_left_rounded,
    'rotate_right': Icons.rotate_right_rounded,
    'stay': Icons.pan_tool_rounded,
  };
  static const Map<String, List<int>> _compassMoveVibrationPatterns = {
    'up': [0, 400],
    'down': [0, 120, 100, 120],
    'left': [0, 80, 80, 80, 80, 80],
    'right': [0, 80, 120, 300],
    'rotate_left': [0, 60, 60, 60, 60, 60, 60, 60],
    'rotate_right': [0, 300, 100, 300],
    'stay': [0, 600],
  };
  static const double _compassAltStep = 34;
  static const double _compassAltRotateStep = 45;

  late final List<int> _compassAltLengthPerRound =
      List.generate(_compassAltTotalRounds, (i) => 2 + (i % 6));

  List<String> _compassAltSequence = [];
  bool _compassAltDemoPlaying = false;
  bool _compassAltRevealed = false;
  bool _compassAltProcessing = false;
  int _compassAltUserIndex = 0;
  int _compassAltRound = 0;
  int _compassAltHits = 0;
  bool _compassAltGameOver = false;

  double _compassAltX = 0;
  double _compassAltY = 0;
  double _compassAltRotation = 0;
  double _compassAltTargetX = 0;
  double _compassAltTargetY = 0;
  double _compassAltTargetRotation = 0;
  /// Дали е побарано хинт за тековниот потег (го покажува само СЛЕДНИОТ
  /// очекуван потег на барање - НЕ целата низа).
  bool _compassAltHintRevealed = false;
  /// Се зголемува при секое движење - стрелката светнува.
  int _compassAltFlashTick = 0;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _prepareSimonRound();
    _prepareCompassAltRound();
    // Лавиринтот се прикажува (засенчен) уште на почеток - со означен старт и крај.
    _generateMaze(start: false);
  }

  @override
  void dispose() {
    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика
    // дали објаснувањето било отворено или не.
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _radarLoopTimer?.cancel();
    _compassLockTimer?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  /// Пробува однапред снимена звучна датотека (твоја снимка, по јазик), а
  /// само ако не постои паѓа назад на системскиот text-to-speech.
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба
  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА
  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.
  Future<void> _playClip(String key, String fallbackText) async {
    if (!mounted) return;
    final relativePath = 'audio/spatial_orientation/$_langCode/$key.mp3';
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

  /// hit.mp3 / miss.mp3 од Гласовен Понг (assets/sounds/pong/) - истите
  /// датотеки, без потреба од нови снимки. Не е говор, нема TTS-резерва.
  Future<void> _playPongEffect(String fileName) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _playClip('explanation_$_explanationKeySuffix', 'spatial.explanation_${_explanationKeySuffix}_text'.tr());
    } else {
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  void _switchTab(_SpatialTab tab) {
    setState(() => _tab = tab);
    AccessibilityUtils.provideFeedback(context: context);
    if (_explanationOpen) {
      // Панелот е веќе отворен - пушти го говорот за НОВИОТ таб веднаш,
      // наместо да остане говорот на претходниот таб.
      _playClip('explanation_$_explanationKeySuffix', 'spatial.explanation_${_explanationKeySuffix}_text'.tr());
    }
  }

  String get _explanationKeySuffix {
    switch (_tab) {
      case _SpatialTab.simon:
        return 'simon';
      case _SpatialTab.maze:
        return 'maze';
      case _SpatialTab.radar:
        return 'radar';
      case _SpatialTab.compass:
        return 'compass';
    }
  }

  // =====================================================================
  // "Симон - насоки" - логика
  // =====================================================================

  void _prepareSimonRound() {
    final length = _simonLengthPerRound[_simonRound];
    setState(() {
      _simonSequence = List.generate(length, (_) => _directions[_random.nextInt(_directions.length)]);
      _simonUserIndex = 0;
      _simonRevealed = false;
      _simonIsPlaying = false;
    });
  }

  Future<void> _vibrateDirection(String dir) async {
    if (await VibrationUtils.hasVibrator()) {
      final pattern = _directionVibrationPatterns[dir]!;
      await VibrationUtils.vibrate(pattern: pattern);
    }
  }

  Future<void> _playSimonSequence() async {
    setState(() {
      _simonIsPlaying = true;
      _simonRevealed = true;
      _simonUserIndex = 0;
    });

    for (final dir in _simonSequence) {
      if (!mounted) return;
      setState(() => _simonFlashingDir = dir);
      await _vibrateDirection(dir);
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() => _simonFlashingDir = null);
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (mounted) setState(() => _simonIsPlaying = false);
  }

  Future<void> _onTapDirection(String dir) async {
    if (_simonIsPlaying || !_simonRevealed || _simonGameOver) return;

    setState(() => _simonFlashingDir = dir);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 40);
    }
    await Future.delayed(const Duration(milliseconds: 130));
    if (mounted) setState(() => _simonFlashingDir = null);

    final isCorrectStep = dir == _simonSequence[_simonUserIndex];

    if (!isCorrectStep) {
      await _playClip('incorrect', 'spatial.incorrect'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      _nextSimonRound();
      return;
    }

    setState(() => _simonUserIndex++);

    if (_simonUserIndex >= _simonSequence.length) {
      setState(() => _simonHits++);
      await _playClip('correct', 'spatial.correct'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      _nextSimonRound();
    }
  }

  void _nextSimonRound() {
    final newRound = _simonRound + 1;
    if (newRound >= _simonTotalRounds) {
      setState(() {
        _simonRound = newRound;
        _simonGameOver = true;
      });
    } else {
      setState(() => _simonRound = newRound);
      _prepareSimonRound();
    }
  }

  void _restartSimon() {
    setState(() {
      _simonRound = 0;
      _simonHits = 0;
      _simonGameOver = false;
    });
    _prepareSimonRound();
  }

  // =====================================================================
  // "Лавиринт" - логика
  // =====================================================================

  void _startMaze() {
    setState(() {
      _mazeRound = 0;
      _mazeTotalMistakes = 0;
      _mazeGameOver = false;
    });
    _generateMaze();
  }

  void _generateMaze({bool start = true}) {
    final path = <Point<int>>[];
    var cur = Point(0, _random.nextInt(_mazeCols));
    path.add(cur);
    final visited = <Point<int>>{cur};
    while (cur.x < _mazeRows - 1) {
      final down = Point(cur.x + 1, cur.y);
      final options = <Point<int>>[down];
      if (cur.y > 0) {
        final left = Point(cur.x, cur.y - 1);
        if (!visited.contains(left)) options.add(left);
      }
      if (cur.y < _mazeCols - 1) {
        final right = Point(cur.x, cur.y + 1);
        if (!visited.contains(right)) options.add(right);
      }
      Point<int> next;
      if (options.length == 1 || _random.nextDouble() < 0.55) {
        next = down;
      } else {
        final alts = options.where((p) => p != down).toList();
        next = alts[_random.nextInt(alts.length)];
      }
      cur = next;
      path.add(cur);
      visited.add(cur);
    }
    setState(() {
      _mazePath = path;
      _mazePathSet = path.toSet();
      _mazeCurrentCell = null;
      _mazeProgressIndex = -1;
      _mazeMistakesThisMaze = 0;
      if (start) _mazeStarted = true;
    });
  }

  Future<void> _onMazePointer(Offset localPos, Size areaSize) async {
    if (!_mazeStarted || _mazeGameOver) return;
    if (areaSize.width <= 0 || areaSize.height <= 0) return;
    final cellW = areaSize.width / _mazeCols;
    final cellH = areaSize.height / _mazeRows;
    final col = (localPos.dx / cellW).floor().clamp(0, _mazeCols - 1);
    final row = (localPos.dy / cellH).floor().clamp(0, _mazeRows - 1);
    final cell = Point(row, col);
    if (cell == _mazeCurrentCell) return;
    setState(() => _mazeCurrentCell = cell);

    // Ако прстот сè уште лебди над квадратчето до кое веќе се стигна - ништо.
    if (_mazeProgressIndex >= 0 && cell == _mazePath[_mazeProgressIndex]) {
      return;
    }

    final expectedNext =
        _mazeProgressIndex + 1 < _mazePath.length ? _mazePath[_mazeProgressIndex + 1] : null;

    if (expectedNext != null && cell == expectedNext) {
      // Точно - следното квадратче од патеката, по ред.
      setState(() => _mazeProgressIndex++);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 30);
      }
      if (_mazeProgressIndex == _mazePath.length - 1) {
        await _onMazeComplete();
      }
    } else {
      // Погрешно - или надвор од патеката, или веќе поминато/означено
      // квадратче допрено повторно (двапати).
      setState(() => _mazeMistakesThisMaze++);
      unawaited(_flashMazeError());
      unawaited(_playPongEffect('miss.mp3'));
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 250]);
      }
    }
  }

  Future<void> _flashMazeError() async {
    setState(() => _mazeErrorFlash = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _mazeErrorFlash = false);
  }

  Future<void> _onMazeComplete() async {
    setState(() => _mazeTotalMistakes += _mazeMistakesThisMaze);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 500);
    }
    unawaited(_playPongEffect('hit.mp3'));
    await _playClip('correct', 'spatial.correct'.tr());
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final newRound = _mazeRound + 1;
    if (newRound >= _mazeTotalRounds) {
      setState(() {
        _mazeRound = newRound;
        _mazeGameOver = true;
      });
    } else {
      setState(() => _mazeRound = newRound);
      _generateMaze();
    }
  }

  // =====================================================================
  // "Радар" - логика
  // =====================================================================

  void _startRadar() {
    setState(() {
      _radarRound = 0;
      _radarHits = 0;
      _radarGameOver = false;
    });
    _prepareRadarRound();
  }

  void _prepareRadarRound() {
    _radarLoopTimer?.cancel();
    setState(() {
      _radarTarget = Offset(0.15 + _random.nextDouble() * 0.7, 0.15 + _random.nextDouble() * 0.7);
      _radarFound = false;
      _radarStarted = true;
      _radarLastNormPos = null;
      _radarMsSinceLastPulse = 0;
    });
  }

  void _onRadarPanStart(Offset localPos, Size size) {
    if (!_radarStarted || _radarGameOver || _radarFound) return;
    setState(() => _radarLastLocalPos = localPos);
    _radarLastNormPos = Offset(
      (localPos.dx / size.width).clamp(0.0, 1.0),
      (localPos.dy / size.height).clamp(0.0, 1.0),
    );
    _radarLoopTimer?.cancel();
    // Првата пулсација веднаш - да се почувствува штом се допре полето.
    _radarMsSinceLastPulse = 100000;
    _radarLoopTimer = Timer.periodic(const Duration(milliseconds: 30), (_) => _radarTick());
  }

  void _onRadarPanUpdate(Offset localPos, Size size) {
    if (!_radarStarted || _radarGameOver || _radarFound) return;
    setState(() => _radarLastLocalPos = localPos);
    _radarLastNormPos = Offset(
      (localPos.dx / size.width).clamp(0.0, 1.0),
      (localPos.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _onRadarPanEnd() {
    _radarLoopTimer?.cancel();
    if (mounted) {
      setState(() {
        _radarLastLocalPos = null;
        _radarPulseFlash = false;
        _radarProximity = 0;
      });
    }
  }

  /// "Жешко-студено": колку си поблизу, толку вибрациите се почести
  /// (700ms далеку -> 80ms блиску), подолги (30 -> 140ms) - а сосема
  /// блиску стануваат речиси непрекинати.
  Future<void> _radarTick() async {
    if (_radarLastNormPos == null || _radarFound || _radarGameOver || !mounted) return;
    final dist = (_radarLastNormPos! - _radarTarget).distance;
    if (dist < 0.06) {
      _radarLoopTimer?.cancel();
      await _onRadarFound();
      return;
    }
    final closeness = (1 - (dist / 0.75)).clamp(0.0, 1.0);
    _radarProximity = closeness;
    _radarMsSinceLastPulse += 30;
    final interval = (700 - 620 * closeness).round();
    if (_radarMsSinceLastPulse >= interval) {
      _radarMsSinceLastPulse = 0;
      final duration = (30 + 110 * closeness).round();
      unawaited(_pulseRadar(duration));
    }
  }

  Future<void> _pulseRadar(int duration) async {
    if (mounted) setState(() => _radarPulseFlash = true);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: duration);
    }
    await Future.delayed(const Duration(milliseconds: 110));
    if (mounted) setState(() => _radarPulseFlash = false);
  }

  Future<void> _onRadarFound() async {
    setState(() => _radarFound = true);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 400);
    }
  }

  Future<void> _onRadarDropSuccess() async {
    setState(() => _radarHits++);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 300);
    }
    await _playClip('correct', 'spatial.correct'.tr());
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final newRound = _radarRound + 1;
    if (newRound >= _radarTotalRounds) {
      setState(() {
        _radarRound = newRound;
        _radarGameOver = true;
      });
    } else {
      setState(() => _radarRound = newRound);
      _prepareRadarRound();
    }
  }

  // =====================================================================
  // "Компас" - логика
  // =====================================================================

  Future<void> _startCompass() async {
    if (_useCompassAlt) {
      _startCompassAlt();
      return;
    }
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      setState(() => _compassPermissionDenied = true);
      return;
    }
    setState(() {
      _compassPermissionDenied = false;
      _compassRound = 0;
      _compassHits = 0;
      _compassGameOver = false;
    });
    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen(_onCompassEvent);
    _pickCompassTarget();
  }

  void _pickCompassTarget() {
    _compassLockTimer?.cancel();
    _compassLockTimer = null;
    setState(() {
      _compassTargetHeading = _compassDirs[_random.nextInt(_compassDirs.length)];
      _compassStarted = true;
      _compassLockProgress = 0;
    });
  }

  double _angleDiff(double a, double b) {
    var d = (a - b) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  void _onCompassEvent(CompassEvent event) {
    final heading = event.heading;
    if (heading == null || !mounted || _compassGameOver) return;
    setState(() => _compassHeading = heading);
    final diff = _angleDiff(heading, _compassTargetHeading);

    if (diff.abs() <= 15) {
      _compassLockTimer ??= Timer.periodic(const Duration(milliseconds: 100), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _compassLockProgress = (_compassLockProgress + 0.1).clamp(0.0, 1.0));
        if (await VibrationUtils.hasVibrator()) {
          await VibrationUtils.vibrate(duration: 25);
        }
        if (_compassLockProgress >= 1.0) {
          t.cancel();
          _compassLockTimer = null;
          _onCompassLocked();
        }
      });
    } else {
      _compassLockTimer?.cancel();
      _compassLockTimer = null;
      if (_compassLockProgress != 0) setState(() => _compassLockProgress = 0);
    }
  }

  Future<void> _onCompassLocked() async {
    setState(() => _compassHits++);
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 500);
    }
    await _playClip('correct', 'spatial.correct'.tr());
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final newRound = _compassRound + 1;
    if (newRound >= _compassTotalRounds) {
      setState(() {
        _compassRound = newRound;
        _compassGameOver = true;
      });
      _compassSub?.cancel();
    } else {
      setState(() => _compassRound = newRound);
      _pickCompassTarget();
    }
  }

  // =====================================================================
  // "Компас" (веб/десктоп верзија со копчиња) - логика
  // =====================================================================

  void _startCompassAlt() {
    setState(() {
      _compassAltRound = 0;
      _compassAltHits = 0;
      _compassAltGameOver = false;
    });
    _prepareCompassAltRound();
  }

  void _prepareCompassAltRound() {
    final length = _compassAltLengthPerRound[_compassAltRound];
    setState(() {
      _compassAltSequence =
          List.generate(length, (_) => _compassMoves[_random.nextInt(_compassMoves.length)]);
      _compassAltUserIndex = 0;
      _compassAltRevealed = false;
      _compassAltDemoPlaying = false;
      _compassAltProcessing = false;
      _compassAltX = 0;
      _compassAltY = 0;
      _compassAltRotation = 0;
      // Дефанзивно - ресетирај ја и „целната" (проѕирна) стрелка, за да
      // никогаш не покаже застарена вредност од претходната рунда пред
      // демото за новата рунда да заврши.
      _compassAltTargetX = 0;
      _compassAltTargetY = 0;
      _compassAltTargetRotation = 0;
      _compassAltHintRevealed = false;
    });
  }

  /// Ја применува една насока врз (x, y, rotation) и ги враќа новите вредности.
  (double, double, double) _applyMove(String move, double x, double y, double rot) {
    switch (move) {
      case 'up':
        return (x, y - _compassAltStep, rot);
      case 'down':
        return (x, y + _compassAltStep, rot);
      case 'left':
        return (x - _compassAltStep, y, rot);
      case 'right':
        return (x + _compassAltStep, y, rot);
      case 'rotate_left':
        return (x, y, rot - _compassAltRotateStep);
      case 'rotate_right':
        return (x, y, rot + _compassAltRotateStep);
      case 'stay':
      default:
        return (x, y, rot);
    }
  }

  Future<void> _vibrateCompassMove(String move) async {
    if (await VibrationUtils.hasVibrator()) {
      final pattern = _compassMoveVibrationPatterns[move]!;
      await VibrationUtils.vibrate(pattern: pattern);
    }
  }

  Future<void> _playCompassAltDemo() async {
    setState(() {
      _compassAltDemoPlaying = true;
      _compassAltRevealed = true;
      _compassAltUserIndex = 0;
      _compassAltX = 0;
      _compassAltY = 0;
      _compassAltRotation = 0;
    });

    double x = 0, y = 0, rot = 0;
    for (final move in _compassAltSequence) {
      if (!mounted) return;
      final result = _applyMove(move, x, y, rot);
      x = result.$1;
      y = result.$2;
      rot = result.$3;
      unawaited(_vibrateCompassMove(move));
      setState(() {
        _compassAltX = x;
        _compassAltY = y;
        _compassAltRotation = rot;
        _compassAltFlashTick++;
      });
      await Future.delayed(const Duration(milliseconds: 550));
    }

    setState(() {
      _compassAltTargetX = x;
      _compassAltTargetY = y;
      _compassAltTargetRotation = rot;
      // Враќање на иконата на почеток за играчот да почне од таму.
      _compassAltX = 0;
      _compassAltY = 0;
      _compassAltRotation = 0;
      _compassAltDemoPlaying = false;
    });
  }

  Future<void> _onCompassAltMovePressed(String move) async {
    if (_compassAltDemoPlaying || !_compassAltRevealed || _compassAltGameOver) return;
    if (_compassAltProcessing) return;

    final result = _applyMove(
      move,
      _compassAltX,
      _compassAltY,
      _compassAltRotation,
    );
    final isCorrectStep = move == _compassAltSequence[_compassAltUserIndex];

    setState(() {
      _compassAltX = result.$1;
      _compassAltY = result.$2;
      _compassAltRotation = result.$3;
      _compassAltFlashTick++;
    });
    unawaited(_vibrateCompassMove(move));

    if (!isCorrectStep) {
      _compassAltProcessing = true;
      await _playClip('incorrect', 'spatial.incorrect'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      _compassAltProcessing = false;
      if (!mounted) return;
      _nextCompassAltRound();
      return;
    }

    setState(() {
      _compassAltUserIndex++;
      _compassAltHintRevealed = false;
    });

    if (_compassAltUserIndex >= _compassAltSequence.length) {
      _compassAltProcessing = true;
      setState(() => _compassAltHits++);
      await _playClip('correct', 'spatial.correct'.tr());
      await Future.delayed(const Duration(milliseconds: 900));
      _compassAltProcessing = false;
      if (!mounted) return;
      _nextCompassAltRound();
    }
  }

  void _nextCompassAltRound() {
    final newRound = _compassAltRound + 1;
    if (newRound >= _compassAltTotalRounds) {
      setState(() {
        _compassAltRound = newRound;
        _compassAltGameOver = true;
      });
    } else {
      setState(() => _compassAltRound = newRound);
      _prepareCompassAltRound();
    }
  }

  // =====================================================================
  // Build
  // =====================================================================

  /// Полни, живи бои за копчињата за насока / потег (бела икона врз нив е
  /// секогаш читлива).
  static const Map<String, Color> _moveColors = {
    'up': Color(0xFF2563EB),
    'down': Color(0xFFD97706),
    'left': Color(0xFF9333EA),
    'right': Color(0xFFDB2777),
    'rotate_left': Color(0xFF0D9488),
    'rotate_right': Color(0xFF0891B2),
    'stay': Color(0xFF64748B),
  };

  /// Текст врз темната позадина: бел (во висок контраст - бојата за контраст).
  Color _fg(bool hc) => hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'spatial.title'.tr(),
      // Копчето за гласовна команда е во лентата со јазичиња.
      voiceCommand: false,
      bodyBackground: const EmojiBackdrop(
        emojis: ['🧭', '⬆️', '➡️', '🗺️', '📡', '⭐'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 860) / 2).clamp(16.0, double.infinity);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Објаснувањето може да е долго - се лизга само тоа, а играта
                // под него секогаш го добива остатокот од висината.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.42),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildExplanationButton(contrast),
                        if (_explanationOpen) _buildExplanationPanel(contrast),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: _buildTabBar(contrast),
                ),
                Expanded(child: _buildTabContent(contrast, hc, side)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    return PlayfulExplainButton(
      open: _explanationOpen,
      label: _explanationOpen
          ? 'spatial.explanation_toggle_close'.tr()
          : 'spatial.explanation_toggle_open'.tr(),
      onTap: _toggleExplanation,
    );
  }

  Widget _buildExplanationPanel(Color contrast) {
    return PlayfulExplainPanel(
      icon: _tabIcons[_tab]!,
      title: 'spatial.explanation_title'.tr(),
      text: 'spatial.explanation_${_explanationKeySuffix}_text'.tr(),
      accent: _moduleAccent,
    );
  }

  static const Map<_SpatialTab, IconData> _tabIcons = {
    _SpatialTab.simon: Icons.grid_view_rounded,
    _SpatialTab.maze: Icons.route_rounded,
    _SpatialTab.radar: Icons.radar_rounded,
    _SpatialTab.compass: Icons.explore_rounded,
  };

  Widget _buildTabBar(Color contrast) {
    final tabs = [
      (_SpatialTab.simon, 'spatial.tab_simon'.tr()),
      (_SpatialTab.maze, 'spatial.tab_maze'.tr()),
      (_SpatialTab.radar, 'spatial.tab_radar'.tr()),
      (_SpatialTab.compass, 'spatial.tab_compass'.tr()),
    ];
    final hc = AccessibilityUtils.isHighContrast(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: CategoryVoiceCommandButton(
                compact: true,
                background: hc ? null : Playful.sun,
                foreground: hc ? null : Playful.ink,
                onBack: () => Navigator.of(context).pop(),
                options: [
                  VoiceCategoryOption(
                    keywords: const ['simon', 'симон', 'насоки', 'directions', 'drejtimet'],
                    onSelected: () => _switchTab(_SpatialTab.simon),
                  ),
                  VoiceCategoryOption(
                    keywords: const ['maze', 'лавиринт', 'labirint'],
                    onSelected: () => _switchTab(_SpatialTab.maze),
                  ),
                  VoiceCategoryOption(
                    keywords: const ['radar', 'радар'],
                    onSelected: () => _switchTab(_SpatialTab.radar),
                  ),
                  VoiceCategoryOption(
                    keywords: const ['compass', 'компас', 'kompas'],
                    onSelected: () => _switchTab(_SpatialTab.compass),
                  ),
                ],
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _tabTile(tabs[i].$1, tabs[i].$2, hc)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Голема плочка за режим: голема икона горе, име долу. Избраната е
  /// златна (темен текст, бел раб и сјај), другите се проѕирни со бел раб.
  Widget _tabTile(_SpatialTab tab, String label, bool hc) {
    final isActive = _tab == tab;
    final Color fg;
    final Color bg;
    final Color iconColor;
    if (hc) {
      fg = isActive ? Colors.black : Colors.white;
      bg = isActive ? const Color(0xFFFFFF00) : Colors.black;
      iconColor = fg;
    } else {
      fg = isActive ? Playful.ink : Colors.white;
      bg = isActive ? Playful.sun : Colors.white.withValues(alpha: 0.1);
      iconColor = isActive ? Playful.ink : Playful.sun;
    }
    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _switchTab(tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 92),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hc || isActive ? Colors.white : Colors.white.withValues(alpha: 0.55),
                  width: isActive ? 3 : 2,
                ),
                boxShadow: hc || !isActive
                    ? null
                    : [BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: 20)],
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_tabIcons[tab], size: 40, color: iconColor),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Playful.title(12.5, color: fg),
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

  /// Златна „брава“ над копчето за започнување на заклучената игра.
  Widget _lockChip(bool hc) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: hc ? Colors.black : Playful.sun,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 14)],
        ),
        child: Icon(Icons.lock_rounded, size: 24, color: hc ? const Color(0xFFFFFF00) : Playful.ink),
      ),
    );
  }

  /// Заеднички "заклучен" приказ: играта е видлива (засенчена и недостапна)
  /// а копчето за започнување стои врз неа - со негово притискање се отклучува.
  Widget _lockedStage({
    required bool locked,
    required Color contrast,
    required bool hc,
    required String startLabel,
    required IconData startIcon,
    required VoidCallback onStart,
    required Widget child,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: locked ? 0.3 : 1.0,
          child: AbsorbPointer(absorbing: locked, child: child),
        ),
        if (locked)
          Positioned.fill(
            child: Center(
              // Ако сцената е ниска, картичката само се намалува (без прелевање).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: PopIn(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: hc ? Colors.white : Colors.white.withValues(alpha: 0.6),
                        width: hc ? 3 : 2.5,
                      ),
                      boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.5), blurRadius: 28)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _lockChip(hc),
                        const SizedBox(height: 22),
                        _buildStartCircle(
                          contrast,
                          hc,
                          label: startLabel,
                          icon: startIcon,
                          onTap: onStart,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabContent(Color contrast, bool hc, double side) {
    // Рундите ја добиваат истата странична маргина како заглавието; крајните
    // екрани (листа) имаат сопствена, за лизгачот да е на работ на екранот.
    Widget padded(Widget child) => Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: child,
        );
    switch (_tab) {
      case _SpatialTab.simon:
        return _simonGameOver ? _buildSimonEndScreen(contrast) : padded(_buildSimonRound(contrast, hc));
      case _SpatialTab.maze:
        return _mazeGameOver ? _buildMazeEndScreen(contrast) : padded(_buildMazeRound(contrast, hc));
      case _SpatialTab.radar:
        return _radarGameOver ? _buildRadarEndScreen(contrast) : padded(_buildRadarRound(contrast, hc));
      case _SpatialTab.compass:
        return _useCompassAlt
            ? (_compassAltGameOver ? _buildCompassAltEndScreen(contrast) : padded(_buildCompassAltRound(contrast, hc)))
            : (_compassGameOver ? _buildCompassEndScreen(contrast) : padded(_buildCompassRound(contrast, hc)));
    }
  }

  // --- Заеднички резиме-екран ---
  Widget _buildSummaryScreen(Color contrast, String text, VoidCallback onPlayAgain, {int? stars, int? total}) {
    return PlayfulResult(
      text: text,
      buttonLabel: 'spatial.play_again'.tr(),
      onAgain: onPlayAgain,
      stars: stars,
      total: total,
    );
  }

  /// Мало проѕирно копче со бел раб (пушти повторно / хинт) - помало од
  /// PlayfulGhostButton за да остане простор за играта.
  Widget _miniGhostButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool hc,
  }) {
    final fg = _fg(hc);
    final enabled = onTap != null;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          enabled: enabled,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled ? 1.0 : 0.45,
            child: Material(
              color: hc ? Colors.black : Colors.white.withValues(alpha: 0.1),
              shape: StadiumBorder(
                side: BorderSide(color: hc ? fg : Colors.white.withValues(alpha: 0.7), width: 2),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: hc ? fg : Playful.sun),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Playful.title(15, color: fg),
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

  // =====================================================================
  // "Симон - насоки" - UI
  // =====================================================================

  Widget _buildSimonRound(Color contrast, bool hc) {
    final fg = _fg(hc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        RoundProgress(
          label: 'spatial.rounds_progress'.tr(args: [(_simonRound + 1).toString(), _simonTotalRounds.toString()]),
          current: _simonRound,
          total: _simonTotalRounds,
          extra: 'spatial.score'.tr(args: [_simonHits.toString()]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _lockedStage(
            locked: !_simonRevealed,
            contrast: contrast,
            hc: hc,
            startLabel: 'spatial.start_sensing'.tr(),
            startIcon: Icons.vibration_rounded,
            onStart: _playSimonSequence,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'spatial.choose_prompt'.tr(),
                  textAlign: TextAlign.center,
                  style: Playful.body(15.5, color: fg),
                ),
                const SizedBox(height: 6),
                Center(
                  child: _miniGhostButton(
                    icon: Icons.replay_rounded,
                    label: 'spatial.sense_again'.tr(),
                    onTap: _simonIsPlaying ? null : _playSimonSequence,
                    hc: hc,
                  ),
                ),
                Expanded(child: _buildDPad(contrast, hc)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Големиот златен круг за започнување (над заклучената игра).
  Widget _buildStartCircle(Color contrast, bool hc,
      {required String label, required IconData icon, required VoidCallback onTap}) {
    return PressableScale(
      child: SoundOrb(
        icon: icon,
        label: label,
        onTap: onTap,
        size: 112,
      ),
    );
  }

  /// Четири ИСТИ копчиња (секое 1/3 од ширината и 1/3 од висината) во
  /// форма на крст - горе, лево, десно, долу; во средината е декорација.
  Widget _buildDPad(Color contrast, bool hc) {
    final interactive = _simonRevealed && !_simonIsPlaying && !_simonGameOver;
    const empty = SizedBox.shrink();
    Widget row(Widget a, Widget b, Widget c) => Expanded(
          child: Row(
            children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
              const SizedBox(width: 10),
              Expanded(child: c),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              row(empty, _dirZone('up', contrast, hc, interactive), empty),
              const SizedBox(height: 10),
              row(
                _dirZone('left', contrast, hc, interactive),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: hc ? Colors.white : Playful.sun.withValues(alpha: _simonIsPlaying ? 0.95 : 0.45),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.vibration_rounded,
                      size: 40,
                      color: hc ? Colors.white : Playful.sun.withValues(alpha: _simonIsPlaying ? 1.0 : 0.6),
                    ),
                    ),
                  ),
                ),
                _dirZone('right', contrast, hc, interactive),
              ),
              const SizedBox(height: 10),
              row(empty, _dirZone('down', contrast, hc, interactive), empty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dirZone(String dir, Color contrast, bool hc, bool interactive) {
    final isFlashing = _simonFlashingDir == dir;
    final label = _directionLabelKeys[dir]!.tr();
    return SoundTile(
      icon: _directionIcons[dir]!,
      label: label,
      color: _moveColors[dir]!,
      onTap: interactive ? () => _onTapDirection(dir) : null,
      enabled: interactive,
      flash: isFlashing,
      showLabel: false,
    );
  }

  Widget _buildSimonEndScreen(Color contrast) {
    final misses = _simonTotalRounds - _simonHits;
    return _buildSummaryScreen(
      contrast,
      'spatial.final_summary'.tr(args: [_simonHits.toString(), misses.toString(), _simonTotalRounds.toString()]),
      _restartSimon,
      stars: _simonHits,
      total: _simonTotalRounds,
    );
  }

  // =====================================================================
  // "Лавиринт" - UI
  // =====================================================================

  Widget _buildMazeRound(Color contrast, bool hc) {
    // Само полињата по кои се движи прстот (патеката) се обоени - за јак
    // контраст. Почеток = зелено, крај = портокалово, веќе поминатите
    // полиња = злато, останатите полиња се речиси невидливи.
    final fg = _fg(hc);
    final pathColor = hc ? const Color(0xFF6B7280) : Playful.mist.withValues(alpha: 0.42);
    final visitedColor = hc ? const Color(0xFFFFFF00) : Playful.sun;
    final emptyColor = hc ? Colors.transparent : Colors.white.withValues(alpha: 0.04);
    final frameColor = _mazeErrorFlash
        ? const Color(0xFFDC2626)
        : (hc ? contrast : Colors.white.withValues(alpha: 0.7));
    final Set<Point<int>> visited =
        _mazeProgressIndex >= 0 ? _mazePath.sublist(0, _mazeProgressIndex + 1).toSet() : <Point<int>>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        RoundProgress(
          label: 'spatial.maze_progress'.tr(args: [(_mazeRound + 1).toString(), _mazeTotalRounds.toString()]),
          current: _mazeRound,
          total: _mazeTotalRounds,
          extra: 'spatial.maze_mistakes'.tr(args: [_mazeMistakesThisMaze.toString()]),
        ),
        const SizedBox(height: 8),
        Text(
          'spatial.maze_prompt'.tr(),
          textAlign: TextAlign.center,
          style: Playful.body(14.5, color: fg),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
            child: _lockedStage(
              locked: !_mazeStarted,
              contrast: contrast,
              hc: hc,
              startLabel: 'spatial.maze_start'.tr(),
              startIcon: Icons.route_rounded,
              onStart: _startMaze,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _onMazePointer(d.localPosition, size),
                    onPanUpdate: (d) => _onMazePointer(d.localPosition, size),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: frameColor,
                          width: _mazeErrorFlash ? 6 : 3,
                        ),
                        boxShadow: hc
                            ? null
                            : [
                                BoxShadow(
                                  color: (_mazeErrorFlash ? const Color(0xFFDC2626) : _moduleAccent)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 22,
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Column(
                          children: List.generate(_mazeRows, (row) {
                            return Expanded(
                              child: Row(
                                children: List.generate(_mazeCols, (col) {
                                  final cell = Point(row, col);
                                  final onPath = _mazePathSet.contains(cell);
                                  final isStart = _mazePath.isNotEmpty && cell == _mazePath.first;
                                  final isEnd = _mazePath.isNotEmpty && cell == _mazePath.last;
                                  final isCurrent = cell == _mazeCurrentCell;
                                  Color cellColor;
                                  if (isEnd) {
                                    cellColor = const Color(0xFFF97316);
                                  } else if (isStart) {
                                    cellColor = const Color(0xFF22C55E);
                                  } else if (visited.contains(cell)) {
                                    cellColor = visitedColor;
                                  } else if (onPath) {
                                    cellColor = pathColor;
                                  } else {
                                    cellColor = emptyColor;
                                  }
                                  return Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.all(1.5),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: cellColor,
                                        borderRadius: BorderRadius.circular(6),
                                        border: isCurrent
                                            ? Border.all(color: Colors.white, width: 3)
                                            : null,
                                      ),
                                      child: isStart || isEnd
                                          ? FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(
                                                  isEnd ? Icons.flag_rounded : Icons.play_arrow_rounded,
                                                  size: 26,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMazeEndScreen(Color contrast) {
    return _buildSummaryScreen(
      contrast,
      'spatial.maze_final_summary'.tr(args: [_mazeTotalRounds.toString(), _mazeTotalMistakes.toString()]),
      _startMaze,
    );
  }

  // =====================================================================
  // "Радар" - UI
  // =====================================================================

  Widget _buildRadarRound(Color contrast, bool hc) {
    final fg = _fg(hc);
    final amber = hc ? const Color(0xFFFFFF00) : Playful.sun;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        RoundProgress(
          label: 'spatial.radar_progress'.tr(args: [(_radarRound + 1).toString(), _radarTotalRounds.toString()]),
          current: _radarRound,
          total: _radarTotalRounds,
          extra: 'spatial.score'.tr(args: [_radarHits.toString()]),
        ),
        const SizedBox(height: 8),
        Text(
          _radarFound ? 'spatial.radar_drag_prompt'.tr() : 'spatial.radar_prompt'.tr(),
          textAlign: TextAlign.center,
          style: Playful.body(14.5, color: fg),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
            child: _lockedStage(
              locked: !_radarStarted,
              contrast: contrast,
              hc: hc,
              startLabel: 'spatial.radar_start'.tr(),
              startIcon: Icons.radar_rounded,
              onStart: _startRadar,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  // Визуелен пулс околу прстот - расте како што се приближуваш
                  // и светнува на секоја вибрација.
                  final ringRadius = 22 + 34 * _radarProximity + (_radarPulseFlash ? 8 : 0);
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: hc ? contrast : Colors.white.withValues(alpha: 0.6), width: 3),
                      color: hc ? Colors.black : null,
                      gradient: hc
                          ? null
                          : const RadialGradient(
                              colors: [Color(0xFF115E59), Playful.nightDeep],
                              radius: 0.95,
                            ),
                      boxShadow: hc
                          ? null
                          : [BoxShadow(color: const Color(0xFF0E7490).withValues(alpha: 0.45), blurRadius: 22)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        children: [
                          // Сцена: концентрични кругови како на радар.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _RingsScenePainter(
                                  color: hc
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : const Color(0xFF5EEAD4).withValues(alpha: 0.28),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: _radarFound
                                ? _buildRadarDragPhase(contrast)
                                : Stack(
                                    children: [
                                      // Слаб светол круг околу скриениот предмет - за
                                      // визуелна помош. Видливоста опаѓа секоја рунда.
                                      Positioned(
                                        left: _radarTarget.dx * size.width - 40,
                                        top: _radarTarget.dy * size.height - 40,
                                        child: IgnorePointer(
                                          child: Opacity(
                                            opacity: _radarStarted ? _radarHintOpacity : 0,
                                            child: Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: amber.withValues(alpha: 0.35),
                                                border: Border.all(color: amber, width: 2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_radarLastLocalPos != null)
                                        Positioned(
                                          left: _radarLastLocalPos!.dx - ringRadius,
                                          top: _radarLastLocalPos!.dy - ringRadius,
                                          child: IgnorePointer(
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 90),
                                              width: ringRadius * 2,
                                              height: ringRadius * 2,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: amber.withValues(alpha: _radarPulseFlash ? 0.35 : 0.06),
                                                border: Border.all(
                                                  color: amber.withValues(alpha: _radarPulseFlash ? 1.0 : 0.5),
                                                  width: 3,
                                                ),
                                                boxShadow: hc || !_radarPulseFlash
                                                    ? null
                                                    : [BoxShadow(color: amber.withValues(alpha: 0.6), blurRadius: 18)],
                                              ),
                                            ),
                                          ),
                                        ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanStart: (d) => _onRadarPanStart(d.localPosition, size),
                                        onPanUpdate: (d) => _onRadarPanUpdate(d.localPosition, size),
                                        onPanEnd: (_) => _onRadarPanEnd(),
                                        onPanCancel: _onRadarPanEnd,
                                        child: const SizedBox.expand(),
                                      ),
                                    ],
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
        ),
      ],
    );
  }

  Widget _buildRadarDragPhase(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final gold = hc ? const Color(0xFFFFFF00) : Playful.sun;
    return Stack(
      children: [
        Positioned(
          top: 16,
          right: 16,
          child: DragTarget<int>(
            onAccept: (_) => _onRadarDropSuccess(),
            builder: (context, candidate, rejected) {
              final active = candidate.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? gold.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1),
                  border: Border.all(color: gold, width: active ? 5 : 3),
                  boxShadow: hc ? null : [BoxShadow(color: gold.withValues(alpha: active ? 0.7 : 0.35), blurRadius: active ? 24 : 14)],
                ),
                child: Icon(Icons.lock_open_rounded, color: gold, size: 34),
              );
            },
          ),
        ),
        Center(
          child: Draggable<int>(
            data: 1,
            feedback: _radarKeyIcon(),
            childWhenDragging: Opacity(opacity: 0.3, child: _radarKeyIcon()),
            child: _radarKeyIcon(),
          ),
        ),
      ],
    );
  }

  Widget _radarKeyIcon() {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? const Color(0xFFFFFF00) : Playful.sun,
        border: Border.all(color: hc ? Colors.black : Colors.white, width: 3),
        boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.6), blurRadius: 18)],
      ),
      child: Icon(Icons.vpn_key_rounded, color: hc ? Colors.black : Playful.ink, size: 34),
    );
  }

  Widget _buildRadarEndScreen(Color contrast) {
    return _buildSummaryScreen(
      contrast,
      'spatial.radar_final_summary'.tr(args: [_radarTotalRounds.toString()]),
      _startRadar,
      stars: _radarHits,
      total: _radarTotalRounds,
    );
  }

  // =====================================================================
  // "Компас" - UI
  // =====================================================================

  Widget _buildCompassRound(Color contrast, bool hc) {
    if (_compassPermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: PlayfulHint('spatial.compass_permission_denied'.tr()),
        ),
      );
    }

    final fg = _fg(hc);
    final targetLabel = _compassDirLabelKeys[_compassTargetHeading]!.tr();
    final headingText = _compassHeading != null ? _compassHeading!.round().toString() : '--';
    final arrowColor = hc ? const Color(0xFFFFFF00) : Playful.sun;

    return _lockedStage(
      locked: !_compassStarted,
      contrast: contrast,
      hc: hc,
      startLabel: 'spatial.compass_start'.tr(),
      startIcon: Icons.explore_rounded,
      onStart: _startCompass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          RoundProgress(
            label: 'spatial.compass_progress'.tr(args: [(_compassRound + 1).toString(), _compassTotalRounds.toString()]),
            current: _compassRound,
            total: _compassTotalRounds,
            extra: 'spatial.score'.tr(args: [_compassHits.toString()]),
          ),
          const SizedBox(height: 10),
          Text(
            'spatial.compass_target'.tr(args: [targetLabel]),
            textAlign: TextAlign.center,
            style: Playful.display(22, color: hc ? fg : Playful.sun),
          ),
          const SizedBox(height: 4),
          Text(
            'spatial.compass_current'.tr(args: [headingText]),
            textAlign: TextAlign.center,
            style: Playful.body(15, color: fg),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 16),
              decoration: _sceneDecoration(hc),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: CustomPaint(
                        painter: _RingsScenePainter(
                          color: hc ? Colors.white.withValues(alpha: 0.4) : Playful.mist.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: _compassLockProgress,
                      strokeWidth: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
                    ),
                  ),
                  Transform.rotate(
                    angle: ((_compassHeading ?? 0) * (pi / 180)),
                    child: Icon(Icons.navigation_rounded, size: 90, color: arrowColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Темна "сцена" (позадина) за компасот.
  BoxDecoration _sceneDecoration(bool hc) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.6), width: 3),
      gradient: hc
          ? null
          : const LinearGradient(
              colors: [Playful.nightRaised, Playful.nightDeep],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
      color: hc ? Colors.black : null,
      boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.45), blurRadius: 22)],
    );
  }

  Widget _buildCompassEndScreen(Color contrast) {
    return _buildSummaryScreen(
      contrast,
      'spatial.compass_final_summary'.tr(args: [_compassTotalRounds.toString()]),
      _startCompass,
      stars: _compassHits,
      total: _compassTotalRounds,
    );
  }

  Widget _buildCompassAltRound(Color contrast, bool hc) {
    final fg = _fg(hc);
    return _lockedStage(
      locked: !_compassAltRevealed,
      contrast: contrast,
      hc: hc,
      startLabel: 'spatial.compass_alt_start'.tr(),
      startIcon: Icons.explore_rounded,
      onStart: _playCompassAltDemo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          RoundProgress(
            label: 'spatial.compass_alt_progress'
                .tr(args: [(_compassAltRound + 1).toString(), _compassAltTotalRounds.toString()]),
            current: _compassAltRound,
            total: _compassAltTotalRounds,
            extra: 'spatial.score'.tr(args: [_compassAltHits.toString()]),
          ),
          const SizedBox(height: 8),
          Text(
            _compassAltDemoPlaying
                ? 'spatial.compass_alt_prompt'.tr()
                : 'spatial.compass_alt_choose_prompt'.tr(),
            textAlign: TextAlign.center,
            style: Playful.body(14.5, color: fg),
          ),
          if (!_compassAltDemoPlaying) ...[
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                _miniGhostButton(
                  icon: Icons.replay_rounded,
                  label: 'spatial.compass_alt_replay'.tr(),
                  onTap: _playCompassAltDemo,
                  hc: hc,
                ),
                _miniGhostButton(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'spatial.compass_alt_hint'.tr(),
                  onTap: () => setState(() => _compassAltHintRevealed = true),
                  hc: hc,
                ),
              ],
            ),
            if (_compassAltHintRevealed &&
                _compassAltUserIndex < _compassAltSequence.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Playful.sun,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _compassMoveIcons[_compassAltSequence[_compassAltUserIndex]],
                          color: hc ? Colors.white : Playful.ink,
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'spatial.compass_alt_hint_label'.tr(args: [
                              _compassMoveLabelKeys[_compassAltSequence[_compassAltUserIndex]]!.tr(),
                            ]),
                            style: Playful.title(15, color: hc ? Colors.white : Playful.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          Expanded(flex: 4, child: _buildCompassAltScene(contrast, hc)),
          if (!_compassAltDemoPlaying)
            Expanded(flex: 2, child: _buildCompassAltPad(contrast, hc)),
        ],
      ),
    );
  }

  /// Сцена со мрежа зад стрелката - едно квадратче = еден чекор на движење,
  /// со означена почетна точка во средината. Се отклучува со "Старт".
  Widget _buildCompassAltScene(Color contrast, bool hc) {
    final arrowColor = hc ? const Color(0xFFFFFF00) : Playful.sun;
    final ghostColor = Colors.white.withValues(alpha: hc ? 0.5 : 0.35);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      decoration: _sceneDecoration(hc),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: CustomPaint(
                painter: _GridScenePainter(
                  lineColor: hc ? Colors.white.withValues(alpha: 0.35) : Playful.mist.withValues(alpha: 0.16),
                  ringColor: hc ? Colors.white.withValues(alpha: 0.8) : Playful.sun.withValues(alpha: 0.7),
                  step: _compassAltStep,
                ),
              ),
            ),
          ),
          if (!_compassAltDemoPlaying)
            Transform.translate(
              offset: Offset(_compassAltTargetX, _compassAltTargetY),
              child: Transform.rotate(
                angle: _compassAltTargetRotation * (pi / 180),
                child: Icon(Icons.navigation_rounded, size: 96, color: ghostColor),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            transform: Matrix4.translationValues(_compassAltX, _compassAltY, 0),
            child: AnimatedRotation(
              turns: _compassAltRotation / 360,
              duration: const Duration(milliseconds: 400),
              child: _flashWrap(arrowColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Стрелката светнува ТОЧНО ЕДНАШ (со сјај околу неа) при секое движење -
  /// едно движење = едно светнување.
  Widget _flashWrap(Color baseColor) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_compassAltFlashTick),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      builder: (context, t, _) {
        // Еден пулс: 0 -> 1 -> 0 во текот на анимацијата (без повторување).
        final f = _compassAltFlashTick == 0 ? 0.0 : sin(t * pi).clamp(0.0, 1.0);
        final color = Color.lerp(baseColor, Colors.white, f)!;
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: baseColor.withValues(alpha: 0.85 * f),
                blurRadius: 36 * f,
                spreadRadius: 10 * f,
              ),
            ],
          ),
          child: Center(child: Icon(Icons.navigation_rounded, size: 96, color: color)),
        );
      },
    );
  }

  Widget _buildCompassAltPad(Color contrast, bool hc) {
    Widget cell(String? move) {
      if (move == null) return const SizedBox.shrink();
      return _compassMoveButton(move, contrast, hc);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell('rotate_left')),
                    const SizedBox(width: 8),
                    Expanded(child: cell('up')),
                    const SizedBox(width: 8),
                    Expanded(child: cell('rotate_right')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell('left')),
                    const SizedBox(width: 8),
                    Expanded(child: cell('stay')),
                    const SizedBox(width: 8),
                    Expanded(child: cell('right')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    const Spacer(),
                    Expanded(child: cell('down')),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compassMoveButton(String move, Color contrast, bool hc) {
    final label = _compassMoveLabelKeys[move]!.tr();
    return SoundTile(
      icon: _compassMoveIcons[move]!,
      label: label,
      color: _moveColors[move]!,
      onTap: _compassAltProcessing ? null : () => _onCompassAltMovePressed(move),
      enabled: !_compassAltProcessing,
      showLabel: false,
    );
  }

  Widget _buildCompassAltEndScreen(Color contrast) {
    final misses = _compassAltTotalRounds - _compassAltHits;
    return _buildSummaryScreen(
      contrast,
      'spatial.compass_alt_final_summary'.tr(args: [
        _compassAltHits.toString(),
        misses.toString(),
        _compassAltTotalRounds.toString(),
      ]),
      _startCompassAlt,
      stars: _compassAltHits,
      total: _compassAltTotalRounds,
    );
  }
}

/// Сцена со концентрични кругови и крст - за радарот и компасот.
class _RingsScenePainter extends CustomPainter {
  final Color color;
  const _RingsScenePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = min(size.width, size.height) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final k in const [0.3, 0.6, 0.9, 1.2]) {
      canvas.drawCircle(c, base * k, paint);
    }
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), paint);
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _RingsScenePainter oldDelegate) => oldDelegate.color != color;
}

/// Мрежа (квадратчиња = чекори) со означена почетна точка во центарот.
class _GridScenePainter extends CustomPainter {
  final Color lineColor;
  final Color ringColor;
  final double step;
  const _GridScenePainter({required this.lineColor, required this.ringColor, required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var x = c.dx; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var x = c.dx - step; x >= 0; x -= step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = c.dy; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var y = c.dy - step; y >= 0; y -= step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final ring = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, step * 0.7, ring);
    canvas.drawCircle(c, step * 2.0, ring..color = ringColor.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _GridScenePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.step != step;
}