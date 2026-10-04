import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

enum _GameMode { recognize, biggerSmaller, operations, countObjects, tally, grid, sequence, sort }
enum _Difficulty { easy, medium, hard }
enum _View { modeSelect, playing, results }

class _Range {
  final int min;
  final int max;
  const _Range(this.min, this.max);
}

/// Опсег на бројки по режим и по тежина.
const Map<_Difficulty, _Range> _recognizeRanges = {
  _Difficulty.easy: _Range(1, 9),
  _Difficulty.medium: _Range(1, 20),
  _Difficulty.hard: _Range(1, 100),
};
const Map<_Difficulty, _Range> _operationRanges = {
  _Difficulty.easy: _Range(1, 9),
  _Difficulty.medium: _Range(1, 20),
  _Difficulty.hard: _Range(1, 50),
};
const Map<_Difficulty, _Range> _countRanges = {
  _Difficulty.easy: _Range(1, 5),
  _Difficulty.medium: _Range(1, 10),
  _Difficulty.hard: _Range(1, 20),
};

/// Распоред на облиците во "Броење предмети" (центри + големина).
class _CountLayout {
  final List<Offset> centers;
  final double size;
  const _CountLayout(this.centers, this.size);
}

class NumberGamesScreen extends StatefulWidget {
  const NumberGamesScreen({super.key});

  @override
  State<NumberGamesScreen> createState() => _NumberGamesScreenState();
}

class _NumberGamesScreenState extends State<NumberGamesScreen> {
  static const Color _moduleAccent = Color(0xFF059669);
  static const int _questionsPerRound = 10;

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _seqInputController = TextEditingController();
  final Random _random = Random();

  _View _view = _View.modeSelect;
  _GameMode _mode = _GameMode.recognize;
  _Difficulty _difficulty = _Difficulty.easy;

  int _score = 0;
  int _asked = 0;
  int _streak = 0;
  int _bestStreak = 0;

  int _displayNumber = 0;
  int _numA = 0, _numB = 0; // за "поголем/помал" - двата прикажани броја
  bool _askBigger = true; // "поголем/помал" - кое се прашува

  int _opA = 0, _opB = 0;
  bool _isAddition = true;
  int get _correctOpAnswer => _isAddition ? _opA + _opB : _opA - _opB;

  int _shapeCount = 0;
  String _shapeType = 'circle';

  /// Визуелен фидбек - НЕ зависи од звук. null = нема фидбек моментално.
  bool? _lastAnswerCorrect;
  int? _lastCorrectValue;
  bool _inputLocked = false;

  // ---------------------------------------------------------------------
  // Нови игри (аудио-тактилни) - целиот говор е ИСКЛУЧИВО од твои снимки
  // (assets/audio/number_games/<mk|en|sq>/<клуч>.mp3), без TTS.
  // ---------------------------------------------------------------------
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  static const int _maxNumber = 20;
  static const double _tallyRadius = 34;
  bool _extraExplanationOpen = false;
  String? _feedbackDetail;

  int get _d => _difficulty.index;
  bool get _isExtraMode => _mode.index >= _GameMode.tally.index;

  // Тактилен бројач.
  int _tallyCount = 0;
  List<Offset> _tallyPoints = [];
  final Map<int, int> _tallyOrder = {};
  int? _tallyFlash;
  List<int> _tallyChoices = [];

  // Локатор на броеви.
  int _gridRows = 2;
  int _gridCols = 2;
  List<int> _gridValues = [];
  int _gridTarget = 0;
  int _gridLastCell = -1;
  int _gridCurrent = -1;
  final Set<int> _gridWrong = {};
  bool _gridFound = false;
  int get _gridAllowedWrong => _d == 0 ? 1 : 3;
  /// Најголем број во Магична низа: 9 (лесно - само цифрите од Брајовата
  /// азбука), 20 (средно), 30 (тешко).
  int get _seqMax => const [9, 20, 30][_d];

  // Магична низа.
  List<int> _seq = [];
  int _seqBlank = 1;
  int _seqAnswer = 10;
  double _seqDragAcc = 0;

  // Редослед.
  List<int> _sortItems = [];

  /// Дали упатството "Допри ги сите кругови..." веќе е кажано оваа игра -
  /// се кажува само еднаш, на почетокот, не секоја рунда.
  bool _tallyIntroSpoken = false;

  // Броење предмети (тактилно/звучно - без изговарање на бројот).
  final Set<int> _countTouched = {};
  int? _countFlash;
  bool _countDemoRunning = false;
  int _countToken = 0;

  /// Спречува преклопување говор ако детето брзо продолжи додека сè уште
  /// трае претходниот говор.
  int _narrationToken = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _narrationToken++;
    _countToken++;
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _inputController.dispose();
    _seqInputController.dispose();
    super.dispose();
  }

  String get _langCode => context.locale.languageCode;
  _Range get _activeRange {
    switch (_mode) {
      case _GameMode.recognize:
      case _GameMode.biggerSmaller:
        return _recognizeRanges[_difficulty]!;
      case _GameMode.operations:
        return _operationRanges[_difficulty]!;
      case _GameMode.countObjects:
      case _GameMode.tally:
      case _GameMode.grid:
      case _GameMode.sequence:
      case _GameMode.sort:
        return _countRanges[_difficulty]!;
    }
  }

  // =====================================================================
  // Избор на режим и тежина.
  // =====================================================================

  void _startRound(_GameMode mode) {
    _narrationToken++;
    // Може да се повика и од друг режим (со глас) - прекини го броењето.
    _countToken++;
    setState(() {
      _mode = mode;
      _view = _View.playing;
      _countDemoRunning = false;
      _score = 0;
      _asked = 0;
      _streak = 0;
      _bestStreak = 0;
      _lastAnswerCorrect = null;
      _feedbackDetail = null;
      _extraExplanationOpen = false;
      _inputLocked = false;
      _tallyIntroSpoken = false;
    });
    _pickNewQuestion();
    _announceQuestion();
  }

  void _setDifficulty(_Difficulty d) {
    setState(() => _difficulty = d);
    VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 40);
    });
  }

  void _backToModeSelect() {
    _narrationToken++;
    _countToken++;
    _voicePlayer.stop();
    setState(() => _view = _View.modeSelect);
  }

  // =====================================================================
  // Генерирање прашања - случајно, не предвидливо.
  // =====================================================================

  void _pickNewQuestion() {
    final r = _activeRange;
    setState(() {
      _inputController.clear();
      _lastAnswerCorrect = null;
      _feedbackDetail = null;
      _inputLocked = false;

      switch (_mode) {
        case _GameMode.recognize:
          _displayNumber = r.min + _random.nextInt(r.max - r.min + 1);
          break;
        case _GameMode.biggerSmaller:
          _numA = r.min + _random.nextInt(r.max - r.min + 1);
          do {
            _numB = r.min + _random.nextInt(r.max - r.min + 1);
          } while (_numB == _numA);
          _askBigger = _random.nextBool();
          break;
        case _GameMode.operations:
          _isAddition = _random.nextBool();
          if (_isAddition) {
            _opA = r.min + _random.nextInt(r.max - r.min + 1);
            _opB = r.min + _random.nextInt(r.max - r.min + 1);
          } else {
            _opA = r.min + _random.nextInt(r.max - r.min + 1);
            _opB = r.min + _random.nextInt(_opA - r.min + 1);
          }
          break;
        case _GameMode.countObjects:
          _shapeCount = r.min + _random.nextInt(r.max - r.min + 1);
          const types = ['circle', 'square', 'star'];
          _shapeType = types[_random.nextInt(types.length)];
          _countToken++;
          _countTouched.clear();
          _countFlash = null;
          _countDemoRunning = false;
          break;
        case _GameMode.tally:
          _genTally();
          break;
        case _GameMode.grid:
          _genGrid();
          break;
        case _GameMode.sequence:
          _genSequence();
          break;
        case _GameMode.sort:
          _genSort();
          break;
      }
    });
  }

  Future<void> _announceQuestion() async {
    switch (_mode) {
      case _GameMode.recognize:
        await _playSequence(['number_word', ..._numKeys(_displayNumber), 'what_number']);
        break;
      case _GameMode.biggerSmaller:
        await _playSequence([
          ..._numKeys(_numA),
          ..._numKeys(_numB),
          _askBigger ? 'which_bigger' : 'which_smaller',
        ]);
        break;
      case _GameMode.operations:
        await _playSequence([
          ..._numKeys(_opA),
          _isAddition ? 'plus' : 'minus',
          ..._numKeys(_opB),
          'equals_q',
        ]);
        break;
      case _GameMode.countObjects:
        // Бројот НЕ се изговара - облиците еден по еден вибрираат, светкаат
        // и испуштаат звук (tick); детето го брои колку пати го слушнало.
        await _playSequence(['how_many_shapes']);
        if (mounted && _view == _View.playing && _mode == _GameMode.countObjects && !_inputLocked) {
          _startCountDemo();
        }
        break;
      case _GameMode.tally:
        if (!_tallyIntroSpoken) {
          _tallyIntroSpoken = true;
          await _playSequence(_promptKeys());
        }
        break;
      case _GameMode.grid:
      case _GameMode.sequence:
      case _GameMode.sort:
        await _playSequence(_promptKeys());
        break;
    }
  }

  int? _getCorrectAnswer() {
    switch (_mode) {
      case _GameMode.recognize:
        return _displayNumber;
      case _GameMode.operations:
        return _correctOpAnswer;
      case _GameMode.countObjects:
        return _shapeCount;
      case _GameMode.biggerSmaller:
      case _GameMode.tally:
      case _GameMode.grid:
      case _GameMode.sequence:
      case _GameMode.sort:
        return null; // се одговара со допир, не со број
    }
  }

  // =====================================================================
  // Одговор + визуелен/вибрациски/гласовен фидбек (независни канали).
  // =====================================================================

  Future<void> _submitTypedAnswer() async {
    if (_inputLocked) return;
    final raw = _inputController.text.trim();
    if (raw.isEmpty) return;
    final parsed = int.tryParse(raw);
    if (parsed == null) return;
    await _answer(parsed == _getCorrectAnswer(), _getCorrectAnswer()!);
  }

  Future<void> _answerBiggerSmaller(int chosen) async {
    if (_inputLocked) return;
    final correctValue = _askBigger ? max(_numA, _numB) : min(_numA, _numB);
    await _answer(chosen == correctValue, correctValue);
  }

  Future<void> _answer(bool isCorrect, int correctValue) async {
    // Го запира демото за "Броење предмети" (следен циклус на пулсирање
    // веќе нема да почне) и го прекинува тековниот звук веднаш.
    _countToken++;
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    setState(() {
      _inputLocked = true;
      _countDemoRunning = false;
      _countFlash = null;
      _lastAnswerCorrect = isCorrect;
      _lastCorrectValue = correctValue;
      _asked++;
      if (isCorrect) {
        _score++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    if (await VibrationUtils.hasVibrator()) {
      if (isCorrect) {
        await VibrationUtils.vibrate(duration: 200);
      } else {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
    }
    // Звуците hit/miss (од Гласовен Понг) - во СИТЕ игри при точно/неточно.
    unawaited(_effect(isCorrect ? 'sounds/pong/hit.mp3' : 'sounds/pong/miss.mp3'));
    final List<String> speech;
    if (_mode == _GameMode.biggerSmaller) {
      // Поголем/помал: само hit/miss (и точниот одговор кога е погрешно).
      speech = isCorrect ? const <String>[] : ['answer_is', ..._numKeys(correctValue)];
    } else {
      speech = isCorrect ? ['correct'] : ['incorrect', 'answer_is', ..._numKeys(correctValue)];
    }
    await _playSequence(speech);

    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    if (_asked >= _questionsPerRound) {
      setState(() => _view = _View.results);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150, 100, 250]);
      }
      // На крајот на играта не се изговара ништо - резултатот е веќе
      // напишан на екранот.
    } else {
      _pickNewQuestion();
      _announceQuestion();
    }
  }

  void _appendDigit(String digit) {
    if (_inputLocked) return;
    final now = _inputController.text;
    if (now.length >= 3) return;
    setState(() => _inputController.text = now + digit);
    _playSequence(['d_$digit']);
  }

  void _clearInput() {
    if (_inputLocked) return;
    setState(() => _inputController.clear());
  }

  // =====================================================================
  // Нови игри: Тактилен бројач, Локатор на броеви, Магична низа, Редослед.
  // Звук - ИСКЛУЧИВО мп3 (без TTS). Ако клипот недостасува - тишина.
  // =====================================================================

  String get _extraKey {
    switch (_mode) {
      case _GameMode.tally:
        return 'tally';
      case _GameMode.grid:
        return 'grid';
      case _GameMode.sequence:
        return 'sequence';
      case _GameMode.sort:
        return 'sort';
      default:
        return '';
    }
  }

  /// Пушта еден клип и го чека да заврши. Некои платформи (веб) тивко
  /// "голтаат" грешка без исклучок, па чекаме потврда дека навистина
  /// почнал; ако не почне за 4 секунди (недостасува датотека), се продолжува.
  Future<void> _playKey(String key) async {
    if (!mounted) return;
    final path = _clipPath(key);
    try {
      await _voicePlayer.stop();
    } catch (_) {}

    bool reached = false;
    final started = Completer<void>();
    final finished = Completer<void>();
    late final StreamSubscription<PlayerState> sub;
    sub = _voicePlayer.onPlayerStateChanged.listen((st) {
      if (st == PlayerState.playing) {
        reached = true;
        if (!started.isCompleted) started.complete();
      }
      if (st == PlayerState.completed) {
        if (!started.isCompleted) started.complete();
        if (!finished.isCompleted) finished.complete();
      }
      if (st == PlayerState.stopped && reached) {
        if (!finished.isCompleted) finished.complete();
      }
    });

    bool ok = false;
    try {
      await _voicePlayer.play(AssetSource(path));
      ok = true;
    } catch (_) {
      ok = false;
    }

    if (ok) {
      await started.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      if (reached) {
        await finished.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      }
    }
    await sub.cancel();
  }

  /// Пушта повеќе клипови по ред (се прекинува ако почне нов говор).
  Future<void> _playSequence(List<String> keys) async {
    final token = ++_narrationToken;
    for (final k in keys) {
      if (!mounted || token != _narrationToken) return;
      await _playKey(k);
    }
  }

  /// Го претвора бројот во клипови: 0-9 = истите снимки од Брајовата азбука
  /// (audio/braille/<јазик>/char_<цифра>.mp3), 10-20 и цели десетки/100 = свои
  /// снимки (n_10 ... n_20, n_30 ... n_90, n_100); 21-99 = десетка + сврзник
  /// (num_and, само за mk и sq) + цифра.
  List<String> _numKeys(int n) {
    if (n < 0) return const ['d_0'];
    if (n <= 9) return ['d_$n'];
    if (n <= 20) return ['n_$n'];
    if (n == 100) return const ['n_100'];
    if (n < 100) {
      final tens = (n ~/ 10) * 10;
      final ones = n % 10;
      if (ones == 0) return ['n_$tens'];
      return ['n_$tens', if (_langCode != 'en') 'num_and', 'd_$ones'];
    }
    return [for (final ch in n.toString().split('')) 'd_$ch'];
  }

  /// Каде е снимката: цифрите 0-9 се од Брајовата азбука, останатото
  /// од assets/audio/number_games/.
  String _clipPath(String key) {
    if (RegExp(r'^d_\d$').hasMatch(key)) {
      return 'audio/braille/$_langCode/char_${key.substring(2)}.mp3';
    }
    return 'audio/number_games/$_langCode/$key.mp3';
  }

  Future<void> _effect(String assetPath) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource(assetPath));
    } catch (_) {}
  }

  Future<void> _vib({int? duration, List<int>? pattern}) async {
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: duration, pattern: pattern);
    }
  }

  void _replayPrompt() {
    if (_inputLocked) return;
    _playSequence(_promptKeys());
  }

  void _toggleExtraExplanation() {
    final open = !_extraExplanationOpen;
    setState(() => _extraExplanationOpen = open);
    if (open) {
      _playSequence(['explanation_$_extraKey']);
    } else {
      _narrationToken++;
      _voicePlayer.stop();
    }
  }

  /// Краен чекор на рунда за новите игри (поени, визуелно + вибрација +
  /// снимки, па следна рунда или резултати).
  Future<void> _finishExtraRound({
    required bool correct,
    bool? scores,
    String? detail,
    int? correctValue,
    List<String> extraSpeech = const [],
    List<int>? successPattern,
  }) async {
    if (_inputLocked) return;
    setState(() {
      _inputLocked = true;
      _lastAnswerCorrect = correct;
      _lastCorrectValue = correct ? null : correctValue;
      _feedbackDetail = detail;
      _asked++;
      if (scores ?? correct) {
        _score++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      unawaited(_vib(pattern: successPattern, duration: successPattern == null ? 200 : null));
      unawaited(_effect('sounds/pong/hit.mp3'));
    } else {
      unawaited(_vib(pattern: const [0, 120, 100, 120]));
      unawaited(_effect('sounds/pong/miss.mp3'));
    }

    await _playSequence([correct ? 'correct' : 'incorrect', ...extraSpeech]);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (_asked >= _questionsPerRound) {
      setState(() => _view = _View.results);
      unawaited(_vib(pattern: const [0, 150, 100, 150, 100, 250]));
      // На крајот на играта не се изговара ништо - резултатот е веќе
      // напишан на екранот.
    } else {
      _pickNewQuestion();
      _announceQuestion();
    }
  }

  // ---------------------------------------------------------------------
  // Генерирање (без setState - се повикува внатре во _pickNewQuestion).
  // ---------------------------------------------------------------------

  void _genTally() {
    const mins = [3, 4, 6];
    const maxs = [5, 8, 10];
    _tallyCount = mins[_d] + _random.nextInt(maxs[_d] - mins[_d] + 1);
    _tallyPoints = _scatterPoints(_tallyCount);
    _tallyOrder.clear();
    _tallyFlash = null;
    final pool = <int>[
      for (var v = max(1, _tallyCount - 3); v <= _tallyCount + 3; v++)
        if (v != _tallyCount) v,
    ]..shuffle(_random);
    final others = _d == 0 ? 2 : 3;
    _tallyChoices = [_tallyCount, ...pool.take(others)]..shuffle(_random);
  }

  /// Расфрла n точки (нормализирани 0..1) со минимално растојание.
  List<Offset> _scatterPoints(int n) {
    final pts = <Offset>[];
    var minDist = 0.24;
    for (var i = 0; i < n; i++) {
      Offset? placed;
      for (var attempt = 0; attempt < 300 && placed == null; attempt++) {
        final p = Offset(0.12 + _random.nextDouble() * 0.76, 0.12 + _random.nextDouble() * 0.76);
        if (pts.every((q) => (q - p).distance >= minDist)) placed = p;
        if (attempt % 60 == 59) minDist *= 0.9;
      }
      pts.add(placed ?? Offset(0.12 + _random.nextDouble() * 0.76, 0.12 + _random.nextDouble() * 0.76));
    }
    return pts;
  }

  void _genGrid() {
    _gridRows = _d == 0 ? 2 : 3;
    _gridCols = _gridRows;
    final cells = _gridRows * _gridCols;
    final maxV = _d == 0 ? 9 : _maxNumber;
    final pool = <int>[for (var v = 1; v <= maxV; v++) v]..shuffle(_random);
    _gridValues = pool.take(cells).toList();
    _gridTarget = _random.nextInt(cells);
    _gridLastCell = -1;
    _gridCurrent = -1;
    _gridWrong.clear();
    _gridFound = false;
  }

  void _genSequence() {
    final len = _d == 2 ? 6 : 5;
    final steps = _d == 0 ? [1, 2] : (_d == 1 ? [1, 2, 3] : [2, 3, 4]);
    final step = steps[_random.nextInt(steps.length)];
    final desc = _d == 0 ? false : _random.nextBool();
    final span = step * (len - 1);
    final room = _seqMax + 1 - span; // >= 1
    final start = desc ? span + _random.nextInt(room) : _random.nextInt(room);
    _seq = List.generate(len, (i) => desc ? start - i * step : start + i * step);
    _seqBlank = 1 + _random.nextInt(len - 1);
    _seqAnswer = _seqMax ~/ 2;
    _seqDragAcc = 0;
    _seqInputController.text = _seqAnswer.toString();
  }

  void _genSort() {
    final n = const [4, 5, 6][_d];
    final lo = _d == 2 ? 0 : 1;
    final hi = const [9, 20, 30][_d];
    final pool = <int>[for (var v = lo; v <= hi; v++) v]..shuffle(_random);
    var items = pool.take(n).toList();
    final sorted = [...items]..sort();
    while (listEquals(items, sorted)) {
      items = [...items]..shuffle(_random);
    }
    _sortItems = items;
  }

  // ---------------------------------------------------------------------
  // Прашање (текст + клипови).
  // ---------------------------------------------------------------------

  String _posName(int r, int c) {
    final row = _gridRows == 2 ? (r == 0 ? 'top' : 'bottom') : const ['top', 'middle', 'bottom'][r];
    final col = _gridCols == 2 ? (c == 0 ? 'left' : 'right') : const ['left', 'center', 'right'][c];
    return '${row}_$col';
  }

  String get _targetPosName => _posName(_gridTarget ~/ _gridCols, _gridTarget % _gridCols);

  List<String> _promptKeys() {
    switch (_mode) {
      case _GameMode.tally:
        return ['prompt_tally'];
      case _GameMode.grid:
        return ['pos_$_targetPosName', 'grid_find', ..._numKeys(_gridValues[_gridTarget])];
      case _GameMode.sequence:
        return [
          for (var i = 0; i < _seq.length; i++)
            ...(i == _seqBlank ? const ['seq_blank'] : _numKeys(_seq[i])),
          'prompt_sequence',
        ];
      case _GameMode.sort:
        return ['prompt_sort', for (final v in _sortItems) ..._numKeys(v)];
      default:
        return const [];
    }
  }

  String _promptText() {
    switch (_mode) {
      case _GameMode.tally:
        return 'number_extra.prompt_tally'.tr();
      case _GameMode.grid:
        return 'number_extra.grid_prompt'.tr(args: [
          'number_extra.pos_$_targetPosName'.tr(),
          _gridValues[_gridTarget].toString(),
        ]);
      case _GameMode.sequence:
        return 'number_extra.prompt_sequence'.tr();
      case _GameMode.sort:
        return 'number_extra.prompt_sort'.tr();
      default:
        return '';
    }
  }

  // ---------------------------------------------------------------------
  // Заеднички рамка: прашање, повтори, објаснување.
  // ---------------------------------------------------------------------

  Widget _buildExtraFrame(Color contrast, Widget body) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = _fgOn(hc);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Text(
            _promptText(),
            textAlign: TextAlign.center,
            style: Playful.title(19, color: fg),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              PlayfulGhostButton(
                icon: Icons.replay_rounded,
                label: 'number_extra.replay'.tr(),
                onTap: _replayPrompt,
              ),
              PlayfulGhostButton(
                icon: _extraExplanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded,
                label: _extraExplanationOpen
                    ? 'number_games.explanation_toggle_close'.tr()
                    : 'number_games.explanation_toggle_open'.tr(),
                onTap: _toggleExtraExplanation,
              ),
            ],
          ),
        ),
        if (_extraExplanationOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
              child: SingleChildScrollView(
                primary: false,
                child: PlayfulExplainPanel(
                  icon: Icons.menu_book_rounded,
                  title: 'number_extra.title_$_extraKey'.tr(),
                  text: 'number_extra.explanation_$_extraKey'.tr(),
                  accent: _moduleAccent,
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: body),
      ],
    );
  }

  Widget _extraConfirmButton(VoidCallback onTap, bool hc) {
    final label = 'number_extra.confirm'.tr();
    return _tapCard(
      semanticsLabel: label,
      onTap: _inputLocked ? null : onTap,
      dimmed: _inputLocked,
      height: 64,
      color: hc ? const Color(0xFFFFFF00) : _green,
      gradient: _vivid(_green),
      glow: _green,
      borderColor: hc ? Colors.black : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 30, color: hc ? Colors.black : Colors.white),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: Playful.title(22, color: hc ? Colors.black : Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Заеднички делови за ноќниот изглед (само изглед, без логика).
  // ---------------------------------------------------------------------

  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFDC2626);

  /// Живи бои за плочките (бел текст врз нив е секогаш читлив).
  static const List<Color> _tileColors = [
    Color(0xFF7C3AED),
    Color(0xFFC2410C),
    Color(0xFF0E7490),
    Color(0xFFBE185D),
    Color(0xFF2563EB),
    Color(0xFF047857),
  ];

  /// Боја за текст врз темната позадина.
  Color _fgOn(bool hc) => hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

  /// Градиент во дадената боја (горе посветло, долу потемно).
  LinearGradient _vivid(Color c) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(c, Colors.white, 0.06)!, Color.lerp(c, Colors.black, 0.38)!],
      );

  /// Темна табла со бел раб - подлога за тактилните игри.
  BoxDecoration _boardDecoration(bool hc) {
    return BoxDecoration(
      color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.55), width: hc ? 3 : 2.5),
      boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.35), blurRadius: 20)],
    );
  }

  /// Бела картичка со златен раб (темен текст); во висок контраст - црна
  /// со бел раб.
  BoxDecoration _whiteCardDecoration(bool hc, {double radius = 22, double border = 3, bool glow = false}) {
    return BoxDecoration(
      color: hc ? Colors.black : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: hc ? Colors.white : Playful.sun, width: border),
      boxShadow: hc || !glow ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.4), blurRadius: 22)],
    );
  }

  /// Заедничко копче / плочка: полна боја или градиент, бел раб, мек сјај,
  /// „притискање“ при допир. Во висок контраст - рамно (без градиент и сјај).
  Widget _tapCard({
    required String semanticsLabel,
    required Widget child,
    required VoidCallback? onTap,
    required Color color,
    Gradient? gradient,
    Color? glow,
    Color borderColor = Colors.white,
    double borderWidth = 3,
    double radius = 20,
    double? width,
    double? height,
    bool dimmed = false,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: dimmed ? 0.5 : 1.0,
          child: PressableScale(
            enabled: onTap != null,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: hc || glow == null ? null : [BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 18)],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(radius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(radius),
                  onTap: onTap,
                  child: Ink(
                    padding: padding,
                    decoration: BoxDecoration(
                      color: hc || gradient == null ? color : null,
                      gradient: hc ? null : gradient,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: borderColor, width: borderWidth),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Копче со број (одговор) во жива боја.
  Widget _numberChoice(int v, Color color, bool hc, VoidCallback? onTap, {double height = 76, double fontSize = 34}) {
    return _tapCard(
      semanticsLabel: v.toString(),
      onTap: onTap,
      dimmed: onTap == null,
      height: height,
      color: hc ? const Color(0xFFFFFF00) : color,
      gradient: _vivid(color),
      glow: color,
      borderColor: Colors.white,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(v.toString(), style: Playful.display(fontSize, color: hc ? Colors.black : Colors.white)),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Игра 1: Тактилен бројач.
  // ---------------------------------------------------------------------

  void _tallyPointer(Offset pos, Size size) {
    if (_inputLocked) return;
    for (var i = 0; i < _tallyPoints.length; i++) {
      final c = Offset(_tallyPoints[i].dx * size.width, _tallyPoints[i].dy * size.height);
      if ((pos - c).distance <= _tallyRadius + 8) {
        if (!_tallyOrder.containsKey(i)) {
          final order = _tallyOrder.length + 1;
          setState(() {
            _tallyOrder[i] = order;
            _tallyFlash = i;
          });
          _playSequence(_numKeys(order));
          _vib(duration: 45);
          Future.delayed(const Duration(milliseconds: 180), () {
            if (mounted && _tallyFlash == i) setState(() => _tallyFlash = null);
          });
        }
        return;
      }
    }
  }

  Future<void> _tallyAnswer(int v) async {
    if (_inputLocked) return;
    final ok = v == _tallyCount;
    await _finishExtraRound(
      correct: ok,
      correctValue: _tallyCount,
      extraSpeech: ok ? const <String>[] : ['answer_is', ..._numKeys(_tallyCount)],
    );
  }

  Widget _buildTallyBody(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _tallyPointer(e.localPosition, size),
                  onPointerMove: (e) => _tallyPointer(e.localPosition, size),
                  child: Container(
                    decoration: _boardDecoration(hc),
                    child: Stack(
                      children: [
                        for (var i = 0; i < _tallyPoints.length; i++)
                          Positioned(
                            left: _tallyPoints[i].dx * size.width - _tallyRadius,
                            top: _tallyPoints[i].dy * size.height - _tallyRadius,
                            child: IgnorePointer(child: _tallyCircle(i, hc)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(
            children: [
              for (final v in _tallyChoices)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _numberChoice(
                      v,
                      _tileColors[_tallyChoices.indexOf(v) % _tileColors.length],
                      hc,
                      _inputLocked ? null : () => _tallyAnswer(v),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tallyCircle(int i, bool hc) {
    final touched = _tallyOrder.containsKey(i);
    final flash = _tallyFlash == i;
    final Color fill;
    if (hc) {
      fill = touched ? const Color(0xFFFFFF00) : Colors.black;
    } else {
      fill = touched ? Playful.sun : Colors.white.withValues(alpha: 0.14);
    }
    return AnimatedScale(
      scale: flash ? 1.18 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: _tallyRadius * 2,
        height: _tallyRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: hc ? Colors.white : (touched ? Colors.white : Colors.white.withValues(alpha: 0.8)), width: 3),
          boxShadow: flash && !hc
              ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.8), blurRadius: 24, spreadRadius: 4)]
              : null,
        ),
        child: Center(
          child: touched
              ? Text(
                  '${_tallyOrder[i]}',
                  style: Playful.display(26, color: hc ? Colors.black : Playful.ink),
                )
              : null,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Игра 2: Локатор на броеви.
  // ---------------------------------------------------------------------

  void _gridPointer(Offset pos, Size size) {
    if (_inputLocked || _gridFound) return;
    final col = (pos.dx / (size.width / _gridCols)).floor().clamp(0, _gridCols - 1).toInt();
    final row = (pos.dy / (size.height / _gridRows)).floor().clamp(0, _gridRows - 1).toInt();
    final cell = row * _gridCols + col;
    if (cell == _gridLastCell) return;
    _gridLastCell = cell;
    setState(() => _gridCurrent = cell);

    if (cell == _gridTarget) {
      _gridSuccess();
    } else {
      setState(() => _gridWrong.add(cell));
      _playSequence(_numKeys(_gridValues[cell]));
      _vib(duration: 30);
    }
  }

  Future<void> _gridSuccess() async {
    setState(() => _gridFound = true);
    final ok = _gridWrong.length <= _gridAllowedWrong;
    await _finishExtraRound(
      correct: true,
      scores: ok,
      detail: ok ? null : 'number_extra.grid_wrong'.tr(args: [_gridWrong.length.toString()]),
      // Посебен ритам на вибрации кога е пронајдено точното поле.
      successPattern: const [0, 90, 70, 90, 70, 220],
    );
  }

  Widget _buildGridBody(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _gridPointer(e.localPosition, size),
                  onPointerMove: (e) => _gridPointer(e.localPosition, size),
                  child: Column(
                    children: [
                      for (var r = 0; r < _gridRows; r++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var col = 0; col < _gridCols; col++)
                                Expanded(child: _gridCell(r * _gridCols + col, contrast, hc)),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'number_extra.grid_wrong'.tr(args: [_gridWrong.length.toString()]),
            textAlign: TextAlign.center,
            style: Playful.body(15, color: _fgOn(hc)),
          ),
        ],
      ),
    );
  }

  Widget _gridCell(int index, Color contrast, bool hc) {
    final isTarget = index == _gridTarget;
    final isCurrent = index == _gridCurrent;
    final found = _gridFound && isTarget;
    Color bg;
    Color fg;
    Color border;
    Gradient? gradient;
    List<BoxShadow>? shadow;
    if (hc) {
      bg = found ? const Color(0xFFFFFF00) : (isCurrent ? Colors.white24 : Colors.black);
      fg = found ? Colors.black : contrast;
      border = Colors.white;
    } else if (found) {
      bg = _green;
      fg = Colors.white;
      border = Colors.white;
      gradient = _vivid(_green);
      shadow = [BoxShadow(color: _green.withValues(alpha: 0.6), blurRadius: 22)];
    } else if (isCurrent) {
      bg = const Color(0xFFFFF4CC);
      fg = Playful.ink;
      border = _moduleAccent;
      shadow = [BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: 18)];
    } else {
      bg = Colors.white;
      fg = Playful.ink;
      border = Playful.sun;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: (isCurrent || found) ? 4 : 3),
        boxShadow: shadow,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _gridValues[index].toString(),
              style: Playful.display(84, color: fg),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Игра 3: Магична низа.
  // ---------------------------------------------------------------------

  void _seqChange(int delta) {
    if (_inputLocked) return;
    final int nv = (_seqAnswer + delta).clamp(0, _seqMax).toInt();
    if (nv == _seqAnswer) return;
    setState(() {
      _seqAnswer = nv;
      _seqInputController.text = nv.toString();
    });
    _playSequence(_numKeys(nv));
    _vib(duration: 25);
  }

  /// Директен внес преку тастатура - алтернатива на влечење/стрелките.
  void _seqTypedChange(String text) {
    if (_inputLocked) return;
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return;
    setState(() => _seqAnswer = parsed.clamp(0, _seqMax).toInt());
  }

  Future<void> _seqConfirm() async {
    if (_inputLocked) return;
    final correctValue = _seq[_seqBlank];
    final ok = _seqAnswer == correctValue;
    await _finishExtraRound(
      correct: ok,
      correctValue: correctValue,
      extraSpeech: ok ? const <String>[] : ['answer_is', ..._numKeys(correctValue)],
    );
  }

  Widget _buildSequenceBody(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final valueColor = hc ? contrast : Playful.ink;
    final arrowColor = hc ? Colors.white : _moduleAccent;
    final fieldFg = hc ? Colors.white : Playful.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final len = _seq.length;
              final w = ((c.maxWidth - (len - 1) * 8) / len).clamp(40.0, 76.0).toDouble();
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < len; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _seqTile(i, w, contrast, hc),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => _seqDragAcc = 0,
                    onVerticalDragUpdate: (d) {
                      _seqDragAcc -= d.delta.dy;
                      const stepPx = 28.0;
                      while (_seqDragAcc >= stepPx) {
                        _seqDragAcc -= stepPx;
                        _seqChange(1);
                      }
                      while (_seqDragAcc <= -stepPx) {
                        _seqDragAcc += stepPx;
                        _seqChange(-1);
                      }
                    },
                    child: Container(
                      decoration: _whiteCardDecoration(hc, radius: 24, border: 4, glow: true),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.keyboard_arrow_up_rounded, size: 40, color: arrowColor),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _seqAnswer.toString(),
                                style: Playful.display(110, color: valueColor),
                              ),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 40, color: arrowColor),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _seqArrowButton(Icons.keyboard_arrow_up_rounded, 'number_extra.seq_up'.tr(), 1, hc),
                    const SizedBox(height: 14),
                    _seqArrowButton(Icons.keyboard_arrow_down_rounded, 'number_extra.seq_down'.tr(), -1, hc),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'number_extra.seq_type_label'.tr(),
            textField: true,
            child: TextField(
              controller: _seqInputController,
              enabled: !_inputLocked,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: _seqTypedChange,
              onSubmitted: (_) => _seqConfirm(),
              style: Playful.title(24, color: fieldFg),
              decoration: InputDecoration(
                labelText: 'number_extra.seq_type_label'.tr(),
                labelStyle: Playful.body(16, color: hc ? Colors.white : Playful.ink.withValues(alpha: 0.75)),
                floatingLabelStyle: Playful.title(16, color: hc ? Colors.white : Playful.ink),
                filled: true,
                fillColor: hc ? Colors.black : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: hc ? Colors.white : Playful.sun, width: 3),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: hc ? Colors.white : Playful.sun, width: 3),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: hc ? Colors.white54 : Playful.sun.withValues(alpha: 0.6), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: hc ? const Color(0xFFFFFF00) : _moduleAccent, width: 4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _extraConfirmButton(_seqConfirm, hc),
        ],
      ),
    );
  }

  Widget _seqTile(int i, double w, Color contrast, bool hc) {
    final isBlank = i == _seqBlank;
    final text = isBlank ? _seqAnswer.toString() : _seq[i].toString();
    final Color bg;
    final Color fg;
    if (hc) {
      bg = isBlank ? const Color(0xFFFFFF00) : Colors.black;
      fg = isBlank ? Colors.black : contrast;
    } else {
      bg = isBlank ? Playful.sun : Colors.white;
      fg = Playful.ink;
    }
    return Container(
      width: w,
      height: 70,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hc ? Colors.white : (isBlank ? Colors.white : Playful.sun),
          width: isBlank ? 4 : 2.5,
        ),
        boxShadow: hc || !isBlank ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.6), blurRadius: 18)],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              isBlank ? '? $text' : text,
              style: Playful.display(30, color: fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seqArrowButton(IconData icon, String label, int delta, bool hc) {
    return _tapCard(
      semanticsLabel: label,
      onTap: _inputLocked ? null : () => _seqChange(delta),
      dimmed: _inputLocked,
      width: 76,
      height: 76,
      radius: 22,
      color: hc ? const Color(0xFFFFFF00) : Playful.sun,
      glow: Playful.sun,
      borderColor: Colors.white,
      child: Center(child: Icon(icon, size: 52, color: hc ? Colors.black : Playful.ink)),
    );
  }

  // ---------------------------------------------------------------------
  // Игра 4: Редослед.
  // ---------------------------------------------------------------------

  void _sortReorder(int oldIndex, int newIndex) {
    if (_inputLocked) return;
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final v = _sortItems.removeAt(oldIndex);
      _sortItems.insert(newIndex, v);
    });
    // Механичко "клик" и вибрација при секое поместување.
    _effect('sounds/picture_book/flip.mp3');
    _vib(duration: 35);
  }

  Future<void> _sortConfirm() async {
    if (_inputLocked) return;
    final sorted = [..._sortItems]..sort();
    final ok = listEquals(_sortItems, sorted);
    await _finishExtraRound(correct: ok);
  }

  Widget _buildSortBody(Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = _fgOn(hc);
    return LayoutBuilder(
      builder: (context, c) {
        final n = _sortItems.length;
        // Големи картички (на цела ширина), една под друга: горе = најмал.
        final avail = c.maxHeight - 40 - 40 - 96;
        final itemH = (avail / n).clamp(64.0, 120.0).toDouble();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('▲ ${'number_extra.sort_smallest'.tr()}', style: Playful.title(15, color: fg)),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                buildDefaultDragHandles: false,
                itemCount: n,
                onReorder: _sortReorder,
                // Без бел правоаголник зад картичката што се влече.
                proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) {
                  final v = _sortItems[i];
                  return ReorderableDragStartListener(
                    key: ValueKey('sort_$v'),
                    index: i,
                    child: Listener(
                      // Допир на број = го изговара.
                      onPointerDown: (_) {
                        if (!_inputLocked) _playSequence(_numKeys(v));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: _sortTile(v, itemH - 10, contrast, hc),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('▼ ${'number_extra.sort_largest'.tr()}', style: Playful.title(15, color: fg)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _extraConfirmButton(_sortConfirm, hc),
            ),
          ],
        );
      },
    );
  }

  Widget _sortTile(int v, double h, Color contrast, bool hc) {
    return Container(
      height: h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hc ? Colors.white : Playful.sun, width: hc ? 4 : 3.5),
        boxShadow: hc ? null : [BoxShadow(color: _moduleAccent.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  v.toString(),
                  style: Playful.display(h * 0.56, color: hc ? contrast : Playful.ink),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(Icons.drag_handle_rounded, size: 40, color: hc ? Colors.white : _moduleAccent),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // Build.
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return GameScreenChrome(
      accent: _moduleAccent,
      title: 'number_games.title'.tr().isNotEmpty ? 'number_games.title'.tr() : 'features.number_games'.tr(),
      voiceCommand: _view != _View.modeSelect,
      voiceOptions: _modeVoiceOptions(),
      onVoiceBack: _backToModeSelect,
      bodyBackground: const EmojiBackdrop(
        emojis: ['🔢', '➕', '➖', '🧮', '⭐', '🎲'],
        tint: _moduleAccent,
      ),
      child: SafeArea(
        child: Builder(
          builder: (context) {
            switch (_view) {
              case _View.modeSelect:
                return _buildModeSelect(context);
              case _View.playing:
                return _buildPlaying(context);
              case _View.results:
                return _buildResults(context);
            }
          },
        ),
      ),
    );
  }

  /// Режимите со глас - во менито, но и од внатре во игра (копчето горе
  /// десно), за директно префрлање од режим во режим.
  List<VoiceCategoryOption> _modeVoiceOptions() => [
      VoiceCategoryOption(
        keywords: const [
          'кој е бројот',
          'what is the number',
          'cili është numri',
          'broj',
          'number',
          'numri',
        ],
        onSelected: () => _startRound(_GameMode.recognize),
      ),
      VoiceCategoryOption(
        keywords: const [
          'поголем или помал',
          'поголем',
          'помал',
          'bigger or smaller',
          'bigger',
          'smaller',
          'më i madh apo më i vogël',
          'më i madh',
          'më i vogël',
        ],
        onSelected: () => _startRound(_GameMode.biggerSmaller),
      ),
      VoiceCategoryOption(
        keywords: const [
          'собирање и одземање',
          'собирање',
          'одземање',
          'плус',
          'минус',
          'addition and subtraction',
          'addition',
          'subtraction',
          'plus',
          'minus',
          'mbledhje dhe zbritje',
          'mbledhje',
          'zbritje',
        ],
        onSelected: () => _startRound(_GameMode.operations),
      ),
      VoiceCategoryOption(
        keywords: const [
          'броење предмети',
          'предмети',
          'count objects',
          'objects',
          'numëro objektet',
          'objektet',
        ],
        onSelected: () => _startRound(_GameMode.countObjects),
      ),
      VoiceCategoryOption(
        keywords: const [
          'тактилен бројач',
          'бројач',
          'tactile counter',
          'counter',
          'numëruesi me prekje',
          'numëruesi',
        ],
        onSelected: () => _startRound(_GameMode.tally),
      ),
      VoiceCategoryOption(
        keywords: const [
          'локатор на броеви',
          'локатор',
          'number locator',
          'locator',
          'gjetësi i numrave',
          'gjetësi',
        ],
        onSelected: () => _startRound(_GameMode.grid),
      ),
      VoiceCategoryOption(
        keywords: const [
          'магична низа',
          'низа',
          'magic sequence',
          'sequence',
          'vargu magjik',
          'vargu',
        ],
        onSelected: () => _startRound(_GameMode.sequence),
      ),
      VoiceCategoryOption(
        keywords: const [
          'редослед',
          'ordering',
          'order',
          'sort',
          'renditja',
        ],
        onSelected: () => _startRound(_GameMode.sort),
      ),
    ];

  // --- Избор на режим ---

  Widget _buildModeSelect(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = _fgOn(hc);
    final modes = [
      (_GameMode.recognize, Icons.pin_rounded, 'number_games.counting'.tr(), const Color(0xFF047857)),
      (_GameMode.biggerSmaller, Icons.compare_arrows_rounded, 'number_games.bigger_smaller'.tr(), const Color(0xFF6D28D9)),
      (_GameMode.operations, Icons.calculate_rounded, 'number_games.addition'.tr(), const Color(0xFFC2410C)),
      (_GameMode.countObjects, Icons.category_rounded, 'number_games.objects'.tr(), const Color(0xFFBE185D)),
      (_GameMode.tally, Icons.touch_app_rounded, 'number_extra.title_tally'.tr(), const Color(0xFF0E7490)),
      (_GameMode.grid, Icons.grid_on_rounded, 'number_extra.title_grid'.tr(), const Color(0xFF1D4ED8)),
      (_GameMode.sequence, Icons.linear_scale_rounded, 'number_extra.title_sequence'.tr(), const Color(0xFFB45309)),
      (_GameMode.sort, Icons.swap_horiz_rounded, 'number_extra.title_sort'.tr(), const Color(0xFF4338CA)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 860) / 2).clamp(16.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 12, side, 28),
          children: [
            // Тежина - во проѕирна табла.
            PopIn(
              index: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                decoration: BoxDecoration(
                  color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.3), width: hc ? 2 : 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'number_games.choose_difficulty'.tr(),
                      textAlign: TextAlign.center,
                      style: Playful.title(20, color: fg),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _difficultyChip(context, _Difficulty.easy, 'number_games.difficulty_easy'.tr())),
                        const SizedBox(width: 8),
                        Expanded(child: _difficultyChip(context, _Difficulty.medium, 'number_games.difficulty_medium'.tr())),
                        const SizedBox(width: 8),
                        Expanded(child: _difficultyChip(context, _Difficulty.hard, 'number_games.difficulty_hard'.tr())),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            PopIn(
              index: 1,
              child: Text(
                'number_games.choose_mode'.tr(),
                textAlign: TextAlign.center,
                style: Playful.display(24, color: fg),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: CategoryVoiceCommandButton(
                background: hc ? null : Playful.sun,
                foreground: hc ? null : Playful.ink,
                onBack: () => Navigator.of(context).pop(),
                options: _modeVoiceOptions(),
              ),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < modes.length; i++) ...[
              PopIn(
                index: 2 + i,
                child: _modeCard(context, modes[i].$1, modes[i].$2, modes[i].$3, number: i + 1, color: modes[i].$4),
              ),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }

  Widget _difficultyChip(BuildContext context, _Difficulty d, String label) {
    final active = _difficulty == d;
    final hc = AccessibilityUtils.isHighContrast(context);
    final Color bg;
    final Color fg;
    if (hc) {
      bg = active ? const Color(0xFFFFFF00) : Colors.black;
      fg = active ? Colors.black : AccessibilityUtils.getContrastColor(context);
    } else {
      bg = active ? Playful.sun : Colors.white.withValues(alpha: 0.10);
      fg = active ? Playful.ink : Colors.white;
    }
    return Semantics(
      label: label,
      button: true,
      selected: active,
      onTap: () => _setDifficulty(d),
      child: ExcludeSemantics(
        child: PressableScale(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: hc || !active ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: 18)],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _setDifficulty(d),
                child: Ink(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: hc || active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      width: active ? 3 : 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (active) ...[
                        Icon(Icons.check_circle_rounded, size: 20, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, style: Playful.title(16, color: fg)),
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

  /// Картичка за игра: градиент во бојата на играта, бел раб, сјај, икона во
  /// бел круг со златен реден број, име и стрелка.
  Widget _modeCard(BuildContext context, _GameMode mode, IconData icon, String label, {required int number, required Color color}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final deep = Color.lerp(color, Colors.black, 0.35)!;
    return Semantics(
      label: label,
      button: true,
      onTap: () => _startRound(mode),
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => _startRound(mode),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: hc ? null : LinearGradient(colors: [color, deep], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  color: hc ? Colors.black : null,
                  border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.85), width: 3),
                  boxShadow: hc ? null : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      if (!hc)
                        Positioned(
                          right: -16,
                          bottom: -24,
                          child: Icon(icon, size: 120, color: Colors.white.withValues(alpha: 0.10)),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hc ? Colors.black : Colors.white,
                                    border: hc ? Border.all(color: Colors.white, width: 2) : null,
                                  ),
                                  child: Icon(icon, color: hc ? const Color(0xFFFFFF00) : deep, size: 34),
                                ),
                                Positioned(
                                  left: -6,
                                  top: -6,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                                      border: Border.all(color: hc ? Colors.black : Colors.white, width: 2),
                                    ),
                                    child: Text(
                                      '$number',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Playful.ink),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(label, style: Playful.display(21, color: Colors.white)),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: hc ? 0.1 : 0.22),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 26),
                            ),
                          ],
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

  // --- Играње ---

  Widget _buildPlaying(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = _fgOn(hc);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 900) / 2).clamp(0.0, double.infinity);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: 'number_games.back'.tr(),
                      button: true,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hc ? Colors.black : Colors.white.withValues(alpha: 0.12),
                          border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.7), width: 2),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: fg),
                          onPressed: _backToModeSelect,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RoundProgress(
                        label: 'number_games.progress'.tr(args: [(_asked + 1).clamp(1, _questionsPerRound).toString(), _questionsPerRound.toString()]),
                        current: _asked.clamp(0, _questionsPerRound - 1).toInt(),
                        total: _questionsPerRound,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _statPill('⭐ ${'number_games.score'.tr(args: [_score.toString()])}', hc, gold: true),
                    if (_streak >= 2) _statPill('🔥 ${'number_games.streak'.tr(args: [_streak.toString()])}', hc),
                  ],
                ),
              ),
              if (_lastAnswerCorrect != null) _buildFeedbackBanner(context),
              Expanded(child: _buildMainContent(context, contrast)),
              if (!_isExtraMode && _mode != _GameMode.biggerSmaller) ...[
                _buildNumberPad(context),
                _buildInputRow(context, contrast),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Мала пилула (резултат, серија) - златна или проѕирна.
  Widget _statPill(String text, bool hc, {bool gold = false}) {
    final Color bg;
    final Color fg;
    if (hc) {
      bg = Colors.black;
      fg = AccessibilityUtils.getContrastColor(context);
    } else if (gold) {
      bg = Playful.sun;
      fg = Playful.ink;
    } else {
      bg = Colors.white.withValues(alpha: 0.14);
      fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: gold ? 1.0 : 0.5), width: hc ? 1.5 : 2),
      ),
      child: Text(text, style: Playful.title(15.5, color: fg)),
    );
  }

  /// Голем визуелен банер - независен од звук - точно/неточно.
  Widget _buildFeedbackBanner(BuildContext context) {
    final correct = _lastAnswerCorrect!;
    final hc = AccessibilityUtils.isHighContrast(context);
    final base = correct ? _green : _red;
    final bg = correct ? (hc ? const Color(0xFFFFFF00) : _green) : (hc ? Colors.black : _red);
    final fg = hc && correct ? Colors.black : Colors.white;
    return PopIn(
      startMs: 0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: hc ? bg : null,
          gradient: hc ? null : _vivid(base),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hc && correct ? Colors.black : Colors.white, width: 3),
          boxShadow: hc ? null : [BoxShadow(color: base.withValues(alpha: 0.55), blurRadius: 22)],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? bg : Colors.white,
                border: hc ? Border.all(color: fg, width: 2) : null,
              ),
              child: Icon(correct ? Icons.check_rounded : Icons.close_rounded, size: 30, color: hc ? fg : base),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    correct ? '✓ ${'number_games.correct_banner'.tr()}' : '✗ ${'number_games.incorrect_banner'.tr()}',
                    style: Playful.display(22, color: fg),
                  ),
                  if (_feedbackDetail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _feedbackDetail!,
                        style: Playful.body(15.5, color: fg),
                      ),
                    ),
                  if (!correct && _lastCorrectValue != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'number_games.correct_answer'.tr(args: [_lastCorrectValue.toString()]),
                        style: Playful.title(16, color: fg),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, Color contrast) {
    switch (_mode) {
      case _GameMode.recognize:
        return _buildRecognizeView(context, contrast);
      case _GameMode.biggerSmaller:
        return _buildBiggerSmallerView(context, contrast);
      case _GameMode.operations:
        return _buildOperationsView(context, contrast);
      case _GameMode.countObjects:
        return _buildCountObjectsView(context, contrast);
      case _GameMode.tally:
        return _buildExtraFrame(contrast, _buildTallyBody(contrast));
      case _GameMode.grid:
        return _buildExtraFrame(contrast, _buildGridBody(contrast));
      case _GameMode.sequence:
        return _buildExtraFrame(contrast, _buildSequenceBody(contrast));
      case _GameMode.sort:
        return _buildExtraFrame(contrast, _buildSortBody(contrast));
    }
  }

  /// Бела картичка со златен раб и сјај - за бројот / задачата. Текстот се
  /// смалува ако нема доволно место (без прелевање).
  Widget _questionCard(bool hc, Widget child) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: hc ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: hc ? Colors.white : Playful.sun, width: hc ? 4 : 5),
            boxShadow: hc
                ? null
                : [
                    BoxShadow(color: Playful.sun.withValues(alpha: 0.45), blurRadius: 28),
                    BoxShadow(color: _moduleAccent.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 12)),
                  ],
          ),
          child: Align(
            heightFactor: 1.0,
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildRecognizeView(BuildContext context, Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final size = MediaQuery.of(context).size;
    final numberSize = (size.height * 0.24).clamp(90.0, 200.0).toDouble();
    return _questionCard(
      hc,
      Text(
        _displayNumber.toString(),
        style: Playful.display(numberSize, color: hc ? contrast : Playful.ink),
      ),
    );
  }

  Widget _buildBiggerSmallerView(BuildContext context, Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final prompt = _askBigger ? 'number_games.which_bigger'.tr() : 'number_games.which_smaller'.tr();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(prompt, textAlign: TextAlign.center, style: Playful.display(24, color: _fgOn(hc))),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: PopIn(index: 0, child: _bigNumberButton(context, _numA, hc, _tileColors[0]))),
              const SizedBox(width: 16),
              Expanded(child: PopIn(index: 1, child: _bigNumberButton(context, _numB, hc, _tileColors[1]))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigNumberButton(BuildContext context, int value, bool hc, Color color) {
    // По одговорот: точниот број позеленува, другиот се повлекува.
    final answered = _inputLocked && _lastAnswerCorrect != null;
    final isCorrectValue = answered && value == _lastCorrectValue;
    final c = isCorrectValue ? _green : color;
    return _tapCard(
      semanticsLabel: value.toString(),
      onTap: _inputLocked ? null : () => _answerBiggerSmaller(value),
      dimmed: answered && !isCorrectValue,
      height: 150,
      radius: 24,
      color: hc ? (isCorrectValue ? const Color(0xFFFFFF00) : Colors.black) : c,
      gradient: _vivid(c),
      glow: c,
      borderColor: Colors.white,
      borderWidth: isCorrectValue ? 4 : 3,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              value.toString(),
              style: Playful.display(60, color: hc ? (isCorrectValue ? Colors.black : AccessibilityUtils.getContrastColor(context)) : Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperationsView(BuildContext context, Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final opText = _isAddition ? '$_opA + $_opB = ?' : '$_opA − $_opB = ?';
    final size = MediaQuery.of(context).size;
    final textSize = (size.height * 0.1).clamp(44.0, 100.0).toDouble();
    return _questionCard(
      hc,
      Text(opText, style: Playful.display(textSize, color: hc ? contrast : Playful.ink)),
    );
  }

  // ---------------------------------------------------------------------
  // Броење предмети: облиците еден по еден вибрираат, светкаат и даваат
  // звук (tick од Понг). Бројот НЕ се изговара.
  // ---------------------------------------------------------------------

  _CountLayout _countLayout(Size area) {
    final count = _shapeCount;
    final perRow = count <= 4 ? max(count, 1) : (count <= 9 ? 3 : 5);
    final rows = (count / perRow).ceil();
    const gap = 16.0;
    final byW = (area.width - 32 - (perRow - 1) * gap) / perRow;
    final byH = (area.height - 24 - (rows - 1) * gap) / rows;
    final size = max(24.0, min(64.0, min(byW, byH)));
    final gridH = rows * size + (rows - 1) * gap;
    final y0 = (area.height - gridH) / 2;
    final centers = <Offset>[];
    for (var r = 0; r < rows; r++) {
      final items = min(perRow, count - r * perRow);
      final rowW = items * size + (items - 1) * gap;
      final x0 = (area.width - rowW) / 2;
      for (var i = 0; i < items; i++) {
        centers.add(Offset(x0 + i * (size + gap) + size / 2, y0 + r * (size + gap) + size / 2));
      }
    }
    return _CountLayout(centers, size);
  }

  Future<void> _countPulse(int i, [int? token]) async {
    if (!mounted) return;
    // Ако е даден токен (автоматското демо) и веќе не одговара на тековниот
    // - одговорот меѓувреме е потврден - не пуштај го овој пулс воопшто.
    if (token != null && token != _countToken) return;
    setState(() => _countFlash = i);
    _vib(duration: 45);
    unawaited(_effect('sounds/pong/tick.mp3'));
    await Future.delayed(const Duration(milliseconds: 220));
    if (mounted && _countFlash == i) setState(() => _countFlash = null);
  }

  /// Автоматски: секој облик по ред (~0,7 сек) вибрира, светнува и звучи.
  Future<void> _startCountDemo() async {
    final token = ++_countToken;
    if (!mounted) return;
    setState(() {
      _countTouched.clear();
      _countDemoRunning = true;
    });
    for (var i = 0; i < _shapeCount; i++) {
      if (!mounted || token != _countToken) return;
      await _countPulse(i, token);
      await Future.delayed(const Duration(milliseconds: 480));
    }
    if (mounted && token == _countToken) setState(() => _countDemoRunning = false);
  }

  /// Со влечење на прст: секој нов допрен облик вибрира, светнува и звучи.
  void _countPointer(Offset pos, _CountLayout lay) {
    if (_inputLocked || _countDemoRunning) return;
    for (var i = 0; i < lay.centers.length; i++) {
      if ((pos - lay.centers[i]).distance <= lay.size / 2 + 10) {
        if (_countTouched.add(i)) unawaited(_countPulse(i));
        return;
      }
    }
  }

  Widget _buildCountObjectsView(BuildContext context, Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final shapeColor = hc ? contrast : Colors.white;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: LayoutBuilder(
              builder: (context, c) {
                final area = Size(c.maxWidth, c.maxHeight);
                final lay = _countLayout(area);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _countPointer(e.localPosition, lay),
                  onPointerMove: (e) => _countPointer(e.localPosition, lay),
                  child: Container(
                    decoration: _boardDecoration(hc),
                    child: Stack(
                      children: [
                        for (var i = 0; i < lay.centers.length; i++)
                          Positioned(
                            left: lay.centers[i].dx - lay.size / 2,
                            top: lay.centers[i].dy - lay.size / 2,
                            child: IgnorePointer(child: _countShape(i, lay.size, shapeColor, hc)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: PlayfulGhostButton(
            icon: Icons.replay_rounded,
            label: 'number_extra.replay'.tr(),
            onTap: _inputLocked ? null : _startCountDemo,
          ),
        ),
      ],
    );
  }

  Widget _countShape(int i, double size, Color contrast, bool hc) {
    final flash = _countFlash == i;
    final glow = hc ? const Color(0xFFFFFF00) : Playful.sun;
    return AnimatedScale(
      scale: flash ? 1.3 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: flash ? [BoxShadow(color: glow.withValues(alpha: 0.85), blurRadius: 26, spreadRadius: 6)] : const [],
        ),
        child: Center(child: _buildShape(size, flash ? glow : contrast)),
      ),
    );
  }

  Widget _buildShape(double size, Color color) {
    Widget child;
    if (_shapeType == 'square') {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.3),
          border: Border.all(color: color, width: 4),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    } else if (_shapeType == 'star') {
      child = CustomPaint(size: Size(size, size), painter: _StarPainter(color: color));
    } else {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.3), shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
      );
    }
    return child;
  }

  Widget _buildNumberPad(BuildContext context) {
    const digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: digits.map((d) => _digitButton(context, d)).toList(),
      ),
    );
  }

  Widget _digitButton(BuildContext context, String digit) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return _tapCard(
      semanticsLabel: digit,
      onTap: _inputLocked ? null : () => _appendDigit(digit),
      dimmed: _inputLocked,
      width: 60,
      height: 52,
      radius: 16,
      color: hc ? Colors.black : Colors.white,
      glow: _moduleAccent,
      borderColor: hc ? Colors.white : Playful.sun,
      borderWidth: hc ? 2 : 2.5,
      child: Center(
        child: Text(digit, style: Playful.display(24, color: hc ? AccessibilityUtils.getContrastColor(context) : Playful.ink)),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, Color contrast) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fieldFg = hc ? contrast : Playful.ink;
    final clearLabel = 'number_games.clear'.tr();
    final submitLabel = 'number_games.submit'.tr();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Semantics(
              label: 'number_games.enter_number'.tr(),
              child: TextField(
                controller: _inputController,
                enabled: !_inputLocked,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 3,
                onSubmitted: (_) => _submitTypedAnswer(),
                textAlign: TextAlign.center,
                style: Playful.display(26, color: fieldFg),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: Playful.display(26, color: fieldFg.withValues(alpha: 0.25)),
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  filled: true,
                  fillColor: hc ? Colors.black : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: hc ? contrast : Playful.sun, width: 3),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: hc ? contrast : Playful.sun, width: 3),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: hc ? Colors.white54 : Playful.sun.withValues(alpha: 0.6), width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: hc ? const Color(0xFFFFFF00) : _moduleAccent, width: 4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _tapCard(
            semanticsLabel: clearLabel,
            onTap: _inputLocked ? null : _clearInput,
            dimmed: _inputLocked,
            width: 88,
            height: 52,
            radius: 16,
            color: hc ? Colors.black : Colors.white.withValues(alpha: 0.12),
            borderColor: hc ? Colors.white : Colors.white.withValues(alpha: 0.7),
            borderWidth: 2,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(clearLabel, style: Playful.title(17, color: hc ? contrast : Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _tapCard(
            semanticsLabel: submitLabel,
            onTap: _inputLocked ? null : _submitTypedAnswer,
            dimmed: _inputLocked,
            width: 88,
            height: 52,
            radius: 16,
            color: hc ? const Color(0xFFFFFF00) : _green,
            gradient: _vivid(_green),
            glow: _green,
            borderColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(submitLabel, style: Playful.title(17, color: hc ? Colors.black : Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Резултати ---

  Widget _buildResults(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = _fgOn(hc);
    final accuracy = _questionsPerRound == 0 ? 0 : ((_score / _questionsPerRound) * 100).round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 860) / 2).clamp(16.0, double.infinity);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                primary: false,
                padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'number_games.results_title'.tr(),
                      textAlign: TextAlign.center,
                      style: Playful.display(26, color: fg),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _statPill('🎯 ${'number_games.results_accuracy'.tr(args: [accuracy.toString()])}', hc),
                        _statPill('🔥 ${'number_games.results_streak'.tr(args: [_bestStreak.toString()])}', hc),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PlayfulResult(
                text: 'number_games.results_score'.tr(args: [_score.toString(), _questionsPerRound.toString()]),
                buttonLabel: 'number_games.play_again'.tr(),
                onAgain: () => _startRound(_mode),
                stars: _score,
                total: _questionsPerRound,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 20),
              child: Center(
                child: PlayfulGhostButton(
                  icon: Icons.grid_view_rounded,
                  label: 'number_games.change_mode'.tr(),
                  onTap: _backToModeSelect,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StarPainter extends CustomPainter {
  final Color color;

  _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width * 0.45;
    final inner = size.width * 0.2;
    final path = Path();

    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final angle = (i * 36 - 90) * (pi / 180);
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}