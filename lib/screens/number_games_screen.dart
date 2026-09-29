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
    setState(() {
      _mode = mode;
      _view = _View.playing;
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            _promptText(),
            textAlign: TextAlign.center,
            style: GameTypography.heading(context, contrast, 19),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _replayPrompt,
              icon: const Icon(Icons.replay_rounded),
              label: Text('number_extra.replay'.tr()),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _toggleExtraExplanation,
              icon: Icon(_extraExplanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded),
              label: Text(_extraExplanationOpen
                  ? 'number_games.explanation_toggle_close'.tr()
                  : 'number_games.explanation_toggle_open'.tr()),
            ),
          ],
        ),
        if (_extraExplanationOpen)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _moduleAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _moduleAccent.withOpacity(0.35), width: 1.5),
            ),
            child: Text(
              'number_extra.explanation_$_extraKey'.tr(),
              style: GameTypography.body(context, contrast, 15),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _extraConfirmButton(VoidCallback onTap, bool hc) {
    return Semantics(
      label: 'number_extra.confirm'.tr(),
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton.icon(
          onPressed: _inputLocked ? null : onTap,
          icon: const Icon(Icons.check_rounded, size: 30),
          label: Text('number_extra.confirm'.tr(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A),
            foregroundColor: hc ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                    decoration: BoxDecoration(
                      color: AccessibilityUtils.getCardBackgroundColor(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 3),
                    ),
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
                    child: Semantics(
                      label: v.toString(),
                      button: true,
                      child: SizedBox(
                        height: 76,
                        child: ElevatedButton(
                          onPressed: _inputLocked ? null : () => _tallyAnswer(v),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hc ? const Color(0xFFFFFF00) : _moduleAccent,
                            foregroundColor: hc ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: Text(v.toString(), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                        ),
                      ),
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
    return AnimatedScale(
      scale: flash ? 1.18 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: _tallyRadius * 2,
        height: _tallyRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: touched ? (hc ? const Color(0xFFFFFF00) : _moduleAccent) : _moduleAccent.withOpacity(0.18),
          border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 3),
          boxShadow: flash
              ? [BoxShadow(color: _moduleAccent.withOpacity(0.7), blurRadius: 24, spreadRadius: 4)]
              : const [],
        ),
        child: Center(
          child: touched
              ? Text(
                  '${_tallyOrder[i]}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: hc ? Colors.black : Colors.white,
                  ),
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
            style: GameTypography.body(context, contrast, 14),
          ),
        ],
      ),
    );
  }

  Widget _gridCell(int index, Color contrast, bool hc) {
    final isTarget = index == _gridTarget;
    final isCurrent = index == _gridCurrent;
    Color bg = AccessibilityUtils.getCardBackgroundColor(context);
    if (_gridFound && isTarget) {
      bg = hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A);
    } else if (isCurrent) {
      bg = _moduleAccent.withOpacity(0.3);
    }
    final fg = (_gridFound && isTarget) ? (hc ? Colors.black : Colors.white) : contrast;
    return Container(
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 3),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _gridValues[index].toString(),
              style: TextStyle(fontSize: 84, fontWeight: FontWeight.bold, color: fg),
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
                      decoration: BoxDecoration(
                        color: AccessibilityUtils.getCardBackgroundColor(context),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.keyboard_arrow_up_rounded, size: 40, color: hc ? Colors.white : _moduleAccent),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _seqAnswer.toString(),
                              style: TextStyle(fontSize: 110, fontWeight: FontWeight.bold, color: contrast),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 40, color: hc ? Colors.white : _moduleAccent),
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: contrast),
              decoration: InputDecoration(
                labelText: 'number_extra.seq_type_label'.tr(),
                filled: true,
                fillColor: AccessibilityUtils.getCardBackgroundColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: contrast, width: 2)),
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
    return Container(
      width: w,
      height: 70,
      decoration: BoxDecoration(
        color: isBlank
            ? (hc ? const Color(0xFFFFFF00) : _moduleAccent.withOpacity(0.25))
            : AccessibilityUtils.getCardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hc ? Colors.white : _moduleAccent, width: isBlank ? 4 : 2),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              isBlank ? '? $text' : text,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: (isBlank && hc) ? Colors.black : contrast,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seqArrowButton(IconData icon, String label, int delta, bool hc) {
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        width: 76,
        height: 76,
        child: ElevatedButton(
          onPressed: _inputLocked ? null : () => _seqChange(delta),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: hc ? const Color(0xFFFFFF00) : _moduleAccent,
            foregroundColor: hc ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Icon(icon, size: 52),
        ),
      ),
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
                child: Text('▲ ${'number_extra.sort_smallest'.tr()}', style: GameTypography.body(context, contrast, 15)),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                buildDefaultDragHandles: false,
                itemCount: n,
                onReorder: _sortReorder,
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
                child: Text('▼ ${'number_extra.sort_largest'.tr()}', style: GameTypography.body(context, contrast, 15)),
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
        color: AccessibilityUtils.getCardBackgroundColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text(
                v.toString(),
                style: TextStyle(fontSize: h * 0.62, fontWeight: FontWeight.bold, color: contrast),
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

  // --- Избор на режим ---

  Widget _buildModeSelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 16),
        Text(
          'number_games.choose_difficulty'.tr(),
          textAlign: TextAlign.center,
          style: GameTypography.heading(context, contrast, 18),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _difficultyChip(context, _Difficulty.easy, 'number_games.difficulty_easy'.tr())),
            const SizedBox(width: 8),
            Expanded(child: _difficultyChip(context, _Difficulty.medium, 'number_games.difficulty_medium'.tr())),
            const SizedBox(width: 8),
            Expanded(child: _difficultyChip(context, _Difficulty.hard, 'number_games.difficulty_hard'.tr())),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'number_games.choose_mode'.tr(),
          textAlign: TextAlign.center,
          style: GameTypography.heading(context, contrast, 18),
        ),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.recognize, Icons.pin_rounded, 'number_games.counting'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.biggerSmaller, Icons.compare_arrows_rounded, 'number_games.bigger_smaller'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.operations, Icons.calculate_rounded, 'number_games.addition'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.countObjects, Icons.category_rounded, 'number_games.objects'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.tally, Icons.touch_app_rounded, 'number_extra.title_tally'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.grid, Icons.grid_on_rounded, 'number_extra.title_grid'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.sequence, Icons.linear_scale_rounded, 'number_extra.title_sequence'.tr()),
        const SizedBox(height: 14),
        _modeCard(context, _GameMode.sort, Icons.swap_horiz_rounded, 'number_extra.title_sort'.tr()),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _difficultyChip(BuildContext context, _Difficulty d, String label) {
    final active = _difficulty == d;
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _setDifficulty(d),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: active
                  ? (hc ? const Color(0xFFFFFF00) : _moduleAccent)
                  : AccessibilityUtils.getDisabledColor(context).withOpacity(0.25),
              border: Border.all(
                color: active ? (hc ? Colors.white : _moduleAccent) : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: active ? (hc ? Colors.black : Colors.white) : AccessibilityUtils.getContrastColor(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeCard(BuildContext context, _GameMode mode, IconData icon, String label) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _startRound(mode),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: hc ? Colors.black : _moduleAccent.withOpacity(0.1),
              border: Border.all(color: hc ? Colors.white : _moduleAccent, width: hc ? 2 : 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hc ? const Color(0xFFFFFF00) : _moduleAccent,
                  ),
                  child: Icon(icon, color: hc ? Colors.black : Colors.white, size: 30),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AccessibilityUtils.getContrastColor(context),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: hc ? Colors.white : _moduleAccent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Играње ---

  Widget _buildPlaying(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Semantics(
                label: 'number_games.back'.tr(),
                button: true,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: contrast),
                  onPressed: _backToModeSelect,
                ),
              ),
              Expanded(
                child: Text(
                  'number_games.progress'.tr(args: [(_asked + 1).clamp(1, _questionsPerRound).toString(), _questionsPerRound.toString()]),
                  textAlign: TextAlign.center,
                  style: GameTypography.heading(context, contrast, 18),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('number_games.score'.tr(args: [_score.toString()]), style: GameTypography.body(context, contrast, 15)),
              const SizedBox(width: 18),
              if (_streak >= 2)
                Text('🔥 ${'number_games.streak'.tr(args: [_streak.toString()])}',
                    style: GameTypography.body(context, contrast, 15)),
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
    );
  }

  /// Голем визуелен банер - независен од звук - точно/неточно.
  Widget _buildFeedbackBanner(BuildContext context) {
    final correct = _lastAnswerCorrect!;
    final hc = AccessibilityUtils.isHighContrast(context);
    final bg = correct ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A)) : (hc ? Colors.black : const Color(0xFFDC2626));
    final fg = hc && correct ? Colors.black : Colors.white;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: hc ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Column(
        children: [
          Text(
            correct ? '✓ ${'number_games.correct_banner'.tr()}' : '✗ ${'number_games.incorrect_banner'.tr()}',
            textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (_feedbackDetail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _feedbackDetail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          if (!correct && _lastCorrectValue != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'number_games.correct_answer'.tr(args: [_lastCorrectValue.toString()]),
                textAlign: TextAlign.center,
                style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
        ],
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

  Widget _buildRecognizeView(BuildContext context, Color contrast) {
    final size = MediaQuery.of(context).size;
    final numberSize = (size.height * 0.24).clamp(90.0, 200.0);
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AccessibilityUtils.getCardBackgroundColor(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: contrast, width: 4),
        ),
        child: Center(
          child: Text(
            _displayNumber.toString(),
            style: TextStyle(fontSize: numberSize, fontWeight: FontWeight.bold, color: contrast),
          ),
        ),
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
          Text(prompt, textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 22)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _bigNumberButton(context, _numA, hc)),
              const SizedBox(width: 16),
              Expanded(child: _bigNumberButton(context, _numB, hc)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigNumberButton(BuildContext context, int value, bool hc) {
    return Semantics(
      label: value.toString(),
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _inputLocked ? null : () => _answerBiggerSmaller(value),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: AccessibilityUtils.getCardBackgroundColor(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: hc ? Colors.white : _moduleAccent, width: 4),
            ),
            child: Center(
              child: Text(
                value.toString(),
                style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: AccessibilityUtils.getContrastColor(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperationsView(BuildContext context, Color contrast) {
    final opText = _isAddition ? '$_opA + $_opB = ?' : '$_opA − $_opB = ?';
    final size = MediaQuery.of(context).size;
    final textSize = (size.height * 0.1).clamp(44.0, 100.0);
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AccessibilityUtils.getCardBackgroundColor(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: contrast, width: 4),
        ),
        child: Center(
          child: Text(opText, style: TextStyle(fontSize: textSize, fontWeight: FontWeight.bold, color: contrast)),
        ),
      ),
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
                    decoration: BoxDecoration(
                      color: AccessibilityUtils.getCardBackgroundColor(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: contrast, width: 4),
                    ),
                    child: Stack(
                      children: [
                        for (var i = 0; i < lay.centers.length; i++)
                          Positioned(
                            left: lay.centers[i].dx - lay.size / 2,
                            top: lay.centers[i].dy - lay.size / 2,
                            child: IgnorePointer(child: _countShape(i, lay.size, contrast, hc)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Semantics(
          label: 'number_extra.replay'.tr(),
          button: true,
          child: TextButton.icon(
            onPressed: _inputLocked ? null : _startCountDemo,
            icon: const Icon(Icons.replay_rounded),
            label: Text('number_extra.replay'.tr()),
          ),
        ),
      ],
    );
  }

  Widget _countShape(int i, double size, Color contrast, bool hc) {
    final flash = _countFlash == i;
    final glow = hc ? const Color(0xFFFFFF00) : const Color(0xFFF59E0B);
    return AnimatedScale(
      scale: flash ? 1.3 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: flash ? [BoxShadow(color: glow.withOpacity(0.85), blurRadius: 26, spreadRadius: 6)] : const [],
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
          color: color.withOpacity(0.3),
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
        decoration: BoxDecoration(color: color.withOpacity(0.3), shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
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
    return Semantics(
      label: digit,
      button: true,
      child: SizedBox(
        width: 60,
        height: 52,
        child: ElevatedButton(
          onPressed: _inputLocked ? null : () => _appendDigit(digit),
          style: ElevatedButton.styleFrom(
            backgroundColor: AccessibilityUtils.getPrimaryButtonBackground(context),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, Color contrast) {
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
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: contrast),
                decoration: InputDecoration(
                  hintText: '0',
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: contrast, width: 3)),
                  filled: true,
                  fillColor: AccessibilityUtils.getCardBackgroundColor(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: 'number_games.clear'.tr(),
            button: true,
            child: SizedBox(
              width: 88,
              height: 52,
              child: ElevatedButton(
                onPressed: _inputLocked ? null : _clearInput,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccessibilityUtils.getDisabledColor(context),
                  foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('number_games.clear'.tr())),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: 'number_games.submit'.tr(),
            button: true,
            child: SizedBox(
              width: 88,
              height: 52,
              child: ElevatedButton(
                onPressed: _inputLocked ? null : _submitTypedAnswer,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('number_games.submit'.tr())),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Резултати ---

  Widget _buildResults(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final accuracy = _questionsPerRound == 0 ? 0 : ((_score / _questionsPerRound) * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: _moduleAccent),
            const SizedBox(height: 16),
            Text(
              'number_games.results_title'.tr(),
              style: GameTypography.heading(context, contrast, 24),
            ),
            const SizedBox(height: 10),
            Text(
              'number_games.results_score'.tr(args: [_score.toString(), _questionsPerRound.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 6),
            Text(
              'number_games.results_accuracy'.tr(args: [accuracy.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 16),
            ),
            const SizedBox(height: 6),
            Text(
              'number_games.results_streak'.tr(args: [_bestStreak.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 16),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _startRound(_mode),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('number_games.play_again'.tr()),
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
              label: Text('number_games.change_mode'.tr()),
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
      ..color = color.withOpacity(0.5)
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