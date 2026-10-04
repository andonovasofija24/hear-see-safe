import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/voice_system/application/voice_command_orchestrator.dart';
import 'package:hear_and_see_safe/braille/braille_data.dart';
import 'package:hear_and_see_safe/utils/book_page_keys.dart';

class BrailleLearningScreen extends StatefulWidget {
  const BrailleLearningScreen({super.key});

  @override
  State<BrailleLearningScreen> createState() => _BrailleLearningScreenState();
}

enum _View {
  categorySelect,
  explore,
  practiceModeSelect,
  practiceCompose,
  practiceRecognize,
  practiceWrite,
  wordRound,
  expressThought,
  sentenceGame,
  reference,
  savedSentences,
}

class _BrailleLearningScreenState extends State<BrailleLearningScreen> {
  static const Color _accent = Color(0xFF4F46E5);

  late VoiceAssistantService _voiceAssistant;
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  PageController? _explorePageController;

  /// Копчето Г на тастатура ја активира гласовната команда (во „Искажи ја
  /// својата мисла“ и „Пишувај реченици“) - секое зголемување на вредноста
  /// е еден „допир“ на копчето за гласовна команда.
  final ValueNotifier<int> _voiceTrigger = ValueNotifier<int>(0);

  /// ФИЗИЧКИ копчиња (а не буквата што ја дава распоредот) - така работи
  /// исто и на англиска и на македонска/албанска тастатура.
  static final Map<PhysicalKeyboardKey, int> _keyToDot = {
    PhysicalKeyboardKey.keyF: 0,
    PhysicalKeyboardKey.keyD: 1,
    PhysicalKeyboardKey.keyS: 2,
    PhysicalKeyboardKey.keyJ: 3,
    PhysicalKeyboardKey.keyK: 4,
    PhysicalKeyboardKey.keyL: 5,
  };

  static const List<String> _positionNames = [
    'braille.pos1', 'braille.pos2', 'braille.pos3', 'braille.pos4', 'braille.pos5', 'braille.pos6',
  ];

  static const List<String> _keyLetters = ['F', 'D', 'S', 'J', 'K', 'L'];

  _View _view = _View.categorySelect;
  /// Од каде е отворен потсетникот (_View.reference) - за да враќањето со
  /// назад-копчето оди точно таму (главно мени, „Искажи ја својата мисла“
  /// или „Пишувај реченици“).
  _View _viewBeforeReference = _View.categorySelect;
  int _groupIndex = 0;
  int _symbolIndex = 0;
  int _narrationToken = 0;

  /// Додека е true, категориите (групи/потсетник/игри) се заклучени -
  /// воведот самиот е СЕКОГАШ видлив, ова важи само за содржината подолу.
  bool _introLocked = true;

  final Set<String> _exploredKeys = {};

  // --- Вежбање (Состави / Препознај / Напиши) ---
  BrailleSymbol? _practiceTarget;
  List<BrailleSymbol> _practicePool = [];
  int _practiceRound = 0;
  static const int _practiceRoundsTotal = 8;
  int _practiceScore = 0;
  bool _practiceFinished = false;
  /// Погодени точки по парови: [пар 1, пар 2] (пар 2 само за знаците од
  /// две клетки, пр. @ и /).
  final List<Set<int>> _correctDotsHit = [<int>{}, <int>{}];
  bool _writeFailed = false;
  List<BrailleSymbol> _recognizeChoices = [];
  /// `key` на избраниот одговор во Препознај.
  String? _recognizePicked;
  bool _recognizeWasCorrect = false;

  /// Како кај квизот во Кибер безбедност: прво се слушаат точките, па
  /// понудените одговори еден по еден. Одговорот може да се избере дури
  /// откако ќе се изговори (`index < _recognizeUnlocked`).
  int _recognizeUnlocked = 0;
  int? _recognizeReadingOption;
  bool _recognizeDotsDone = false;

  final Set<PhysicalKeyboardKey> _pressedKeys = {};

  /// Кој пар точки е активен за тастатурата (0 = пар 1, 1 = пар 2).
  /// Копчето H го менува; на екранот може да се допира било кој пар.
  int _activePair = 0;

  /// Редослед на притиснатите точки по парови - за „.“ (поништи ја
  /// последната точка).
  final List<List<int>> _dotOrder = [<int>[], <int>[]];

  // --- Игра со зборови ---
  BrailleWord? _currentWord;
  /// Зборот претворен во Брајови симболи (со знак за голема буква / број).
  List<BrailleSymbol> _wordTokens = [];
  /// Индекс на знакот што моментално се пишува.
  int _wordStep = 0;
  /// Точки веќе погодени за тековниот знак, по парови - точка-по-точка.
  final List<Set<int>> _wordCorrectDotsHit = [<int>{}, <int>{}];
  List<BrailleWord> _wordQueue = [];

  // --- Заедничко за „Искажи ја својата мисла“ и „Пишувај реченици“ ---
  /// Ги чува напишаното и состојбата (режим за броеви, голема буква,
  /// започнат повеќеклеточен знак) и ги толкува точките во знак.
  BrailleComposer _composer = BrailleComposer(BrailleLang.mk);
  /// Притиснати точки (0-5) по парови: [пар 1, пар 2]. Вториот пар е за
  /// знаците од две клетки (пр. @ и /).
  final List<Set<int>> _writingDots = [<int>{}, <int>{}];
  /// Резултатот од првиот притисок на А (изговорен преглед) - чека втор А
  /// за потврда. null = нема преглед.
  BrailleDecodeResult? _preview;
  bool _expressExplanationOpen = false;

  // --- „Пишувај реченици“ ---
  static const int _sentenceSessionTarget = 3;
  List<BrailleSentence> _sentenceQueue = [];
  BrailleSentence? _sentence;
  List<BrailleSymbol> _sentenceTokens = [];
  /// Колку симболи од реченицата се веќе точно напишани.
  int _sentenceStep = 0;
  int _sentenceCount = 0;
  int _sentenceMistakes = 0;
  int _sentenceMistakesTotal = 0;
  bool _sentenceFinished = false;

  /// Зачувани реченици (трајно, преку SharedPreferences) - секој елемент е
  /// една целосно завршена реченица/ред од „Искажи ја својата мисла“.
  static const String _savedSentencesPrefsKey = 'braille_express_saved_sentences';
  List<String> _savedSentences = [];
  bool _savedSentencesLoaded = false;

  Future<void> _loadSavedSentences() async {
    if (_savedSentencesLoaded) return;
    _savedSentencesLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_savedSentencesPrefsKey) ?? [];
      if (!mounted) return;
      setState(() => _savedSentences = saved);
    } catch (_) {}
  }

  Future<void> _persistSavedSentences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedSentencesPrefsKey, _savedSentences);
    } catch (_) {}
  }

  /// Текстот на реченицата што треба да се зачува: последната завршена
  /// реченица (со . ? !), а ако сеуште нема ниту една - тековниот ред.
  String? _currentSentenceForSaving() {
    if (_composer.lines.isNotEmpty) return _composer.lines.last;
    final current = _composer.currentLineText.trim();
    return current.isEmpty ? null : current;
  }

  Future<void> _saveCurrentSentence() async {
    final sentence = _currentSentenceForSaving();
    if (sentence == null || sentence.trim().isEmpty) return;
    setState(() => _savedSentences = [..._savedSentences, sentence]);
    await _persistSavedSentences();
    await _playClip('sentence_saved');
  }

  Future<void> _deleteSavedSentence(int index) async {
    if (index < 0 || index >= _savedSentences.length) return;
    setState(() {
      final updated = List<String>.from(_savedSentences)..removeAt(index);
      _savedSentences = updated;
    });
    await _persistSavedSentences();
  }

  /// Гласовна команда „избриши реченица“ (без назначен број) - ја брише
  /// најскоро додадената зачувана реченица.
  Future<void> _deleteLastSavedSentenceByVoice() async {
    if (_savedSentences.isEmpty) return;
    await _deleteSavedSentence(_savedSentences.length - 1);
  }

  // --- Гласовна команда во потсетникот (свети + изговара избран знак) ---
  String? _referenceHighlightKey;
  int _referenceHighlightToken = 0;
  bool _referenceListening = false;

  Future<void> _onReferenceMicTap() async {
    if (_referenceListening) return;
    setState(() => _referenceListening = true);
    try {
      await _startReferenceVoiceListen();
    } finally {
      if (mounted) setState(() => _referenceListening = false);
    }
  }

  void _openSavedSentences() {
    _loadSavedSentences();
    setState(() => _view = _View.savedSentences);
  }

  void _closeSavedSentences() {
    setState(() => _view = _View.expressThought);
  }

  String get _langCode => context.locale.languageCode;

  BrailleLang get _lang {
    switch (_langCode) {
      case 'mk':
        return BrailleLang.mk;
      case 'sq':
        return BrailleLang.sq;
      default:
        return BrailleLang.en;
    }
  }

  // Кеширани групи - СТАБИЛНИ идентитети на објектите додека не се смени
  // јазикот.
  List<BrailleGroup>? _cachedGroups;
  BrailleLang? _cachedLang;

  List<BrailleGroup> get _groups {
    if (_cachedGroups == null || _cachedLang != _lang) {
      _cachedLang = _lang;
      _cachedGroups = BrailleData.groupsFor(_lang);
    }
    return _cachedGroups!;
  }

  BrailleGroup get _group => _groups[_groupIndex];

  bool _isGroupFullyExplored(int index) {
    for (final s in _groups[index].symbols) {
      if (!_exploredKeys.contains('$index:${s.key}')) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIntroLockSequence());
  }

  /// Прво 3 секунди тишина, потоа "Брајова азбука" (game_name.mp3).
  /// Категориите се ЗАКЛУЧЕНИ додека трае овој звук - освен ако корисникот
  /// не притисне на копчето „стоп“ на дното на воведот.
  Future<void> _startIntroLockSequence() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _playClipAwaitingCompletion('game_name', timeout: const Duration(seconds: 8));
    if (!mounted) return;
    setState(() => _introLocked = false);
  }

  /// Рачно копче „стоп“ - веднаш го прекинува звукот на воведот и ги
  /// отклучува категориите.
  void _stopIntroNow() {
    _voicePlayer.stop();
    if (_introLocked) setState(() => _introLocked = false);
  }

  @override
  void dispose() {
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _focusNode.dispose();
    _explorePageController?.dispose();
    _voiceTrigger.dispose();
    super.dispose();
  }

  // =====================================================================
  // Звук - ИСКЛУЧИВО однапред снимени мп3 клипови. Ако клипот не постои,
  // не се пушта НИШТО (без TTS-резерва) - намерно, по барање. Исклучок се
  // зборовите и речениците: ако нивната снимка ја нема, се спелуваат буква
  // по буква со постоечките снимки.
  // =====================================================================

  Future<void> _playClip(String key) async {
    if (!mounted) return;
    final relativePath = 'audio/braille/$_langCode/$key.mp3';
    try {
      await _voicePlayer.stop();
      await _voicePlayer.play(AssetSource(relativePath));
    } catch (_) {
      // Намерно нема TTS-резерва - тишина ако клипот недостасува.
    }
  }

  Future<void> _playCharClip(BrailleSymbol s) async {
    await _playClip(s.audioClip);
  }

  /// Игра еден клип и ЧЕКА тој навистина да заврши (или да истече рокот)
  /// пред да се врати - потребно за секвенцијално пуштање. Враќа false ако
  /// клипот не постои (за да може да се спелува наместо тоа).
  Future<bool> _playClipAwaitingCompletion(String key, {Duration timeout = const Duration(seconds: 6)}) async {
    if (!mounted) return false;
    final relativePath = 'audio/braille/$_langCode/$key.mp3';
    final completer = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _voicePlayer.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    bool playSucceeded = false;
    try {
      await _voicePlayer.stop();
      await _voicePlayer.play(AssetSource(relativePath));
      playSucceeded = true;
    } catch (_) {
      playSucceeded = false;
    }

    if (playSucceeded) {
      await completer.future.timeout(timeout, onTimeout: () {});
    }
    await sub.cancel();
    return playSucceeded;
  }

  /// Ги изговара точките на една клетка по ред (dot_1, dot_4 ...).
  Future<void> _playCellDots(List<int> dots, int myToken) async {
    for (final d in dots) {
      if (myToken != _narrationToken || !mounted) return;
      await _playClipAwaitingCompletion('dot_$d');
    }
  }

  /// Составен звук: прво знакот (напр. "Буква Б"), потоа по ред звукот за
  /// секоја точка (кај повеќеклеточните знаци - клетка по клетка, со кратка
  /// пауза). Празното место е char_space („Празно место“) + dot_0 („ниедна
  /// точка“).
  Future<void> _playCharExplanationSequence(BrailleSymbol s) async {
    final myToken = ++_narrationToken;
    await _playClipAwaitingCompletion(s.audioClip);
    if (s.kind == BrailleKind.space) {
      if (myToken != _narrationToken || !mounted) return;
      await _playClipAwaitingCompletion('dot_0');
      return;
    }
    await _playCellsNarration(s, myToken);
  }

  /// Точките на знакот по ред. Кај знаците од два пара (пр. @ и /) пред
  /// секој пар се кажува „пар 1“ / „пар 2“ (pair_1.mp3 / pair_2.mp3).
  Future<void> _playCellsNarration(BrailleSymbol s, int myToken) async {
    for (var c = 0; c < s.cells.length; c++) {
      if (myToken != _narrationToken || !mounted) return;
      if (s.isMultiCell) {
        if (c > 0) await Future.delayed(const Duration(milliseconds: 250));
        await _playClipAwaitingCompletion('pair_${c + 1}');
        if (myToken != _narrationToken || !mounted) return;
      }
      await _playCellDots(s.cells[c], myToken);
    }
  }

  /// За вежбата „Препознај“: по прашањето се пуштаат звуците за секоја
  /// точка. Намерно НЕ се изговара самиот знак - тоа би го издало одговорот.
  /// Потоа (како кај квизот во Кибер безбедност) ги изговара понудените
  /// одговори еден по еден - секој станува достапен штом ќе се изговори.
  Future<void> _playRecognizeDotsSequence(BrailleSymbol target) async {
    final myToken = ++_narrationToken;
    await _voicePlayer.stop();
    if (mounted) setState(() => _recognizeReadingOption = null);
    await _playClipAwaitingCompletion('recognize_prompt');
    if (myToken != _narrationToken || !mounted) return;
    await _playCellsNarration(target, myToken);
    if (myToken != _narrationToken || !mounted || _practiceTarget != target) return;
    setState(() => _recognizeDotsDone = true);
    for (var i = 0; i < _recognizeChoices.length; i++) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (myToken != _narrationToken || !mounted || _recognizePicked != null) return;
      setState(() => _recognizeReadingOption = i);
      await _playClipAwaitingCompletion(_recognizeChoices[i].audioClip);
      if (myToken != _narrationToken || !mounted) return;
      setState(() {
        _recognizeReadingOption = null;
        if (_recognizeUnlocked < i + 1) _recognizeUnlocked = i + 1;
      });
    }
  }

  /// Го „прочитува“ текстот симбол по симбол со постоечките снимки (char_*)
  /// - знаците за голема буква/број се прескокнуваат, празно место е пауза.
  Future<void> _readbackTokens(List<BrailleSymbol> tokens, {int? token}) async {
    final myToken = token ?? ++_narrationToken;
    for (final t in tokens) {
      if (myToken != _narrationToken || !mounted) return;
      if (t.isModifier) continue;
      if (t.kind == BrailleKind.space) {
        await Future.delayed(const Duration(milliseconds: 350));
        continue;
      }
      await _playClipAwaitingCompletion(t.audioClip);
    }
  }

  Future<void> _playPongEffect(String fileName) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  Future<void> _playFlipSound() async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/picture_book/flip.mp3'));
    } catch (_) {}
  }

  Future<void> _vibrateOk([int duration = 150]) async {
    if (await VibrationUtils.hasVibrator()) await VibrationUtils.vibrate(duration: duration);
  }

  Future<void> _vibrateError() async {
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
    }
  }

  // =====================================================================
  // Текстови за приказ.
  // =====================================================================

  String _dotsDescription(List<int> dots) =>
      dots.map((d) => '${'braille.dot'.tr()} $d ${_positionNames[d - 1].tr()}').join(', ');

  /// Име за изговор/приказ: буквите и бројките се самите себе, а знаците
  /// имаат преведено име (пр. „Прашалник“).
  String _symbolName(BrailleSymbol s) {
    switch (s.kind) {
      case BrailleKind.letter:
      case BrailleKind.digit:
        return s.char;
      default:
        return s.nameKey.tr();
    }
  }

  String _explanationFor(BrailleSymbol s) {
    if (s.kind == BrailleKind.space) return 'braille.explanation_space'.tr();
    final String dotList;
    if (s.isMultiCell) {
      dotList = [
        for (var i = 0; i < s.cells.length; i++) '${'braille.cell_n'.tr(args: ['${i + 1}'])}: ${_dotsDescription(s.cells[i])}',
      ].join('; ');
    } else {
      dotList = _dotsDescription(s.dots);
    }
    switch (s.kind) {
      case BrailleKind.letter:
        return 'braille.explanation_template'.tr(args: [s.char, dotList]);
      case BrailleKind.digit:
        return 'braille.explanation_template_number'.tr(args: [s.char, dotList]);
      case BrailleKind.capitalSign:
        return '${'braille.explanation_template_sign'.tr(args: [_symbolName(s), dotList])} ${'braille.explain_capital'.tr()}';
      case BrailleKind.numberSign:
        return '${'braille.explanation_template_sign'.tr(args: [_symbolName(s), dotList])} ${'braille.explain_number_sign'.tr()}';
      default:
        return 'braille.explanation_template_sign'.tr(args: [_symbolName(s), dotList]);
    }
  }

  // =====================================================================
  // Влез: тастатура.
  //
  // F D S / J K L - точки 1-6 (во сите вежби и игри).
  //
  // Во „Искажи ја својата мисла“ и „Пишувај реченици“:
  //  - А (прв пат)  - го ИЗГОВАРА знакот формиран од точките (преглед);
  //                   ако нема ниедна точка - тоа е празно место;
  //  - А (втор пат) - го ПОТВРДУВА знакот. Празно место (А, А без точки) го
  //                   завршува зборот; . ? ! ја завршуваат реченицата;
  //  - Г            - гласовна команда;
  //  - „.“          - поништи точка (ја брише само последната притисната точка);
  //  - „:“          - поништи буква (ја брише започнатата клетка; ако нема
  //                   ништо започнато - го брише последниот напишан знак);
  //  - П            - потсетник (со повторен П - назад);
  //  - H            - втор пар точки (за знаците од две клетки, пр. @ и /);
  //                   повторен H - назад на пар 1.
  // =====================================================================

  static const PhysicalKeyboardKey _keyConfirm = PhysicalKeyboardKey.keyA;
  static const PhysicalKeyboardKey _keyVoice = PhysicalKeyboardKey.keyG;
  static const PhysicalKeyboardKey _keyReset = PhysicalKeyboardKey.semicolon;
  static const PhysicalKeyboardKey _keyReference = PhysicalKeyboardKey.keyP;
  static const PhysicalKeyboardKey _keyPair = PhysicalKeyboardKey.keyH;
  static const PhysicalKeyboardKey _keyRemoveDot = PhysicalKeyboardKey.period;

  /// Колку парови точки има тековната задача (2 = знак од две клетки).
  int get _currentPairCount {
    switch (_view) {
      case _View.practiceCompose:
      case _View.practiceWrite:
        return _practiceTarget?.cells.length ?? 1;
      case _View.wordRound:
        return _wordStep < _wordTokens.length ? _wordTokens[_wordStep].cells.length : 1;
      case _View.expressThought:
      case _View.sentenceGame:
        return 2;
      default:
        return 1;
    }
  }

  /// H - префрлување помеѓу пар 1 и пар 2.
  void _togglePair() {
    if (_currentPairCount < 2) return;
    setState(() => _activePair = 1 - _activePair);
    _narrationToken++;
    _playClip('pair_${_activePair + 1}');
  }

  bool get _isWritingView => _view == _View.expressThought || _view == _View.sentenceGame;

  bool _isWritingViewValue(_View v) => v == _View.expressThought || v == _View.sentenceGame;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.physicalKey;

    // Во потсетникот отворен од пишување: повторно П враќа точно таму
    // (напишаното останува зачувано).
    if (_view == _View.reference && key == _keyReference && _isWritingViewValue(_viewBeforeReference)) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) _closeReference();
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_isWritingView &&
        (key == _keyConfirm || key == _keyVoice || key == _keyReset || key == _keyReference || key == _keyRemoveDot)) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) {
          if (key == _keyConfirm) {
            _onConfirmKey();
          } else if (key == _keyVoice) {
            _voiceTrigger.value++;
          } else if (key == _keyReset) {
            _onResetKey();
          } else if (key == _keyRemoveDot) {
            _removeLastWritingDot();
          } else if (key == _keyReference) {
            _openReference(_view);
          }
        }
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Игра со зборови: Г - гласовна команда, : - поништи буква. (Нема
    // „поништи точка“ - погрешна точка овде и онака не се додава.)
    if (_view == _View.wordRound && (key == _keyVoice || key == _keyReset)) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) {
          if (key == _keyVoice) {
            _voiceTrigger.value++;
          } else {
            _clearWordLetter();
          }
        }
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == _keyPair && _currentPairCount > 1) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) _togglePair();
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Истражувај (сликовница): < > (и стрелките) за листање.
    if (_view == _View.explore) {
      final dir = bookPageDirection(event);
      if (dir < 0) {
        _goPrevExplore();
        return KeyEventResult.handled;
      }
      if (dir > 0) {
        _goNextExplore();
        return KeyEventResult.handled;
      }
    }

    final dot = _keyToDot[key];
    if (dot == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (_pressedKeys.add(key)) {
        final pair = _activePair < _currentPairCount ? _activePair : 0;
        if (_view == _View.practiceCompose) {
          _tapComposeDot(pair, dot);
        } else if (_view == _View.practiceWrite) {
          _tapWriteDot(pair, dot);
        } else if (_view == _View.wordRound) {
          _tapWordDot(pair, dot);
        } else if (_isWritingView) {
          _tapWritingDot(pair, dot);
        }
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // =====================================================================
  // Наслов / премин.
  // =====================================================================

  /// Целосно ресетирање на состојбата на вежбање.
  void _resetPracticeState() {
    _practiceTarget = null;
    _practiceFinished = false;
    _clearPairs(_correctDotsHit);
    _writeFailed = false;
    _recognizePicked = null;
    _practiceRound = 0;
  }

  void _resetWritingState() {
    _composer = BrailleComposer(_lang);
    _clearPairs(_writingDots);
    _preview = null;
  }

  /// Ги празни двата пара и го враќа активниот пар на пар 1.
  void _clearPairs(List<Set<int>> pairs) {
    for (final p in pairs) {
      p.clear();
    }
    for (final o in _dotOrder) {
      o.clear();
    }
    _activePair = 0;
  }

  /// Додава точка во парот и го памети редоследот (за „.“).
  void _addDot(List<Set<int>> pairs, int pair, int dot) {
    if (pairs[pair].add(dot)) _dotOrder[pair].add(dot);
  }

  /// Ја вади последната притисната точка - прво од активниот пар, па од
  /// другиот. Враќа (пар, точка) или null ако нема точки.
  (int, int)? _popLastDot(List<Set<int>> pairs) {
    for (final p in [_activePair, 1 - _activePair]) {
      final order = _dotOrder[p];
      while (order.isNotEmpty) {
        final d = order.removeLast();
        if (pairs[p].remove(d)) return (p, d);
      }
      if (pairs[p].isNotEmpty) {
        final d = pairs[p].last;
        pairs[p].remove(d);
        return (p, d);
      }
    }
    return null;
  }

  /// Звук по бришење на една точка: кус звук за грешка + која точка е
  /// избришана (dot_N); ако немало точка - само звукот за грешка.
  Future<void> _afterDotRemoved((int, int)? removed) async {
    await _playPongEffect('miss.mp3');
    if (removed == null) return;
    await _vibrateOk(60);
    _narrationToken++;
    await _playClipAwaitingCompletion('dot_${removed.$2 + 1}');
  }

  /// Точките (0-5) што треба да се погодат во даден пар за знакот.
  Set<int> _targetPair(BrailleSymbol s, int pair) =>
      pair < s.cells.length ? s.cells[pair].map((d) => d - 1).toSet() : <int>{};

  /// Дали сите парови на знакот се целосно погодени.
  bool _pairsComplete(BrailleSymbol s, List<Set<int>> hits) {
    for (var p = 0; p < s.cells.length; p++) {
      if (hits[p].length != s.cells[p].length) return false;
    }
    return true;
  }

  /// Кога пар 1 е готов, а знакот има и пар 2 - автоматски се преминува на
  /// пар 2 и се кажува „пар 2“.
  void _autoAdvancePair(BrailleSymbol s, List<Set<int>> hits) {
    if (!mounted) return;
    if (_activePair == 0 && s.cells.length > 1 && hits[0].length == s.cells[0].length) {
      setState(() => _activePair = 1);
      _playClip('pair_2');
    }
  }

  void _backToCategories() {
    _narrationToken++;
    if (_view == _View.explore && _group.symbols.isNotEmpty) {
      _exploredKeys.add('$_groupIndex:${_group.symbols[_symbolIndex].key}');
    }
    _voiceAssistant.stop();
    _voicePlayer.stop();
    setState(() {
      _resetPracticeState();
      _currentWord = null;
      _resetWritingState();
      _sentence = null;
      _sentenceFinished = false;
      _expressExplanationOpen = false;
      _view = _View.categorySelect;
    });
  }

  /// Го отвора потсетникот, паметејќи од кој екран е повикан.
  void _openReference(_View from) {
    _narrationToken++;
    _voicePlayer.stop();
    setState(() {
      _viewBeforeReference = from;
      _view = _View.reference;
    });
  }

  void _closeReference() {
    _narrationToken++;
    _voicePlayer.stop();
    setState(() => _view = _viewBeforeReference);
  }

  // =====================================================================
  // Фаза 1: Истражувај (сликовница-стил, исто како picture_book).
  // =====================================================================

  void _openGroup(int index) {
    _narrationToken++;
    _explorePageController?.dispose();
    _explorePageController = PageController(initialPage: 0);
    setState(() {
      _groupIndex = index;
      _symbolIndex = 0;
      _view = _View.explore;
    });
    _playCharExplanationSequence(_group.symbols[0]);
  }

  void _onExplorePageChanged(int newIndex) {
    if (newIndex == _symbolIndex) return;
    _narrationToken++;
    _voicePlayer.stop();
    _exploredKeys.add('$_groupIndex:${_group.symbols[_symbolIndex].key}');
    _playFlipSound();
    setState(() => _symbolIndex = newIndex);
    _playCharExplanationSequence(_group.symbols[newIndex]);
  }

  void _goNextExplore() {
    _explorePageController?.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  void _goPrevExplore() {
    _explorePageController?.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  // =====================================================================
  // Фаза 2: Практика.
  // =====================================================================

  /// Празното место нема точки за притискање - се учи само во Истражувај.
  List<BrailleSymbol> get _practiceableSymbols =>
      _group.symbols.where((s) => s.kind != BrailleKind.space).toList();

  void _openPracticeModeSelect([int? index]) {
    _narrationToken++;
    _voicePlayer.stop();
    setState(() {
      if (index != null) _groupIndex = index;
      _resetPracticeState();
      _view = _View.practiceModeSelect;
    });
  }

  void _startPractice(_View mode) {
    _narrationToken++;
    _resetPracticeState();
    _practicePool = _practiceableSymbols..shuffle(_random);
    _practiceScore = 0;
    setState(() => _view = mode);
    _nextPracticeRound();
  }

  /// Состави е вежбање без резултат - циклично поминува низ сите знаци.
  void _nextPracticeRound() {
    final isCompose = _view == _View.practiceCompose;
    if (_practicePool.isEmpty ||
        (!isCompose && (_practiceRound >= _practiceRoundsTotal || _practiceRound >= _practicePool.length * 3))) {
      _announcePracticeDone();
      return;
    }
    if (isCompose && _practiceRound >= _practicePool.length) {
      _announcePracticeDone();
      return;
    }
    final target = _practicePool[_practiceRound % _practicePool.length];
    setState(() {
      _practiceTarget = target;
      _clearPairs(_correctDotsHit);
      _writeFailed = false;
      _recognizePicked = null;
      _recognizeUnlocked = 0;
      _recognizeReadingOption = null;
      _recognizeDotsDone = false;
      if (_view == _View.practiceRecognize) {
        final others = _practiceableSymbols..removeWhere((s) => s.key == target.key);
        others.shuffle(_random);
        final pickCount = min(3, others.length);
        _recognizeChoices = ([target, ...others.take(pickCount)]..shuffle(_random));
      }
    });
    if (_view == _View.practiceCompose || _view == _View.practiceWrite) {
      _playCharClip(target);
    } else if (_view == _View.practiceRecognize) {
      _playRecognizeDotsSequence(target);
    }
  }

  Future<void> _announcePracticeDone() async {
    setState(() {
      _practiceFinished = true;
      _practiceTarget = null;
    });
    await _playClip('practice_done');
  }

  Future<void> _tapComposeDot(int pair, int dotIndex) async {
    final t = _practiceTarget;
    if (t == null) return;
    if (pair != _activePair) setState(() => _activePair = pair);
    final target = _targetPair(t, pair);
    final isCorrect = target.contains(dotIndex);

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(
        duration: isCorrect ? 150 : null,
        pattern: isCorrect ? null : const [0, 80, 60, 80],
      );
    }

    if (isCorrect) {
      setState(() => _addDot(_correctDotsHit, pair, dotIndex));
      await _playPongEffect('hit.mp3');
      if (_pairsComplete(t, _correctDotsHit)) {
        setState(() => _practiceScore++);
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted || _view != _View.practiceCompose || _practiceTarget != t) return;
        setState(() => _practiceRound++);
        _nextPracticeRound();
      } else {
        _autoAdvancePair(t, _correctDotsHit);
      }
    } else {
      await _playPongEffect('miss.mp3');
    }
  }

  Future<void> _tapWriteDot(int pair, int dotIndex) async {
    final t = _practiceTarget;
    if (t == null || _writeFailed) return;
    if (pair != _activePair) setState(() => _activePair = pair);
    final target = _targetPair(t, pair);
    final isCorrect = target.contains(dotIndex);

    if (isCorrect) {
      setState(() => _addDot(_correctDotsHit, pair, dotIndex));
      await _vibrateOk();
      if (_pairsComplete(t, _correctDotsHit)) {
        setState(() => _practiceScore++);
        await _playPongEffect('hit.mp3');
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted || _view != _View.practiceWrite || _practiceTarget != t) return;
        setState(() => _practiceRound++);
        _nextPracticeRound();
      } else {
        _autoAdvancePair(t, _correctDotsHit);
      }
    } else {
      setState(() => _writeFailed = true);
      await _vibrateError();
      await _playPongEffect('miss.mp3');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted || _view != _View.practiceWrite) return;
      setState(() => _practiceRound++);
      _nextPracticeRound();
    }
  }

  Future<void> _pickRecognizeAnswer(BrailleSymbol choice) async {
    if (_practiceTarget == null || _recognizePicked != null) return;
    final idx = _recognizeChoices.indexWhere((c) => c.key == choice.key);
    if (idx < 0 || idx >= _recognizeUnlocked) return;
    // Го прекинува читањето на останатите одговори.
    _narrationToken++;
    await _voicePlayer.stop();
    final correct = choice.key == _practiceTarget!.key;
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(
        duration: correct ? 200 : null,
        pattern: correct ? null : const [0, 120, 100, 120],
      );
    }
    if (correct) setState(() => _practiceScore++);
    await _playPongEffect(correct ? 'hit.mp3' : 'miss.mp3');
    setState(() {
      _recognizePicked = choice.key;
      _recognizeWasCorrect = correct;
      _recognizeReadingOption = null;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || _view != _View.practiceRecognize) return;
    setState(() => _practiceRound++);
    _nextPracticeRound();
  }

  // =====================================================================
  // Игра со зборови.
  //
  // Зборовите се комбинации од СИТЕ категории (букви од сите групи,
  // специјални букви, зборови со голема буква, броеви и зборови со знак).
  // Секој збор НАЈПРВО се спелува буква по буква (со постоечките снимки),
  // па се пишува знак по знак - вклучувајќи го знакот за голема буква и
  // знакот за број каде што треба.
  // =====================================================================

  static const int _wordSessionTarget = 5;
  int _wordSessionCount = 0;

  void _startWordSession() {
    _narrationToken++;
    _wordSessionCount = 0;
    _wordQueue = List<BrailleWord>.from(BrailleData.words[_lang] ?? const <BrailleWord>[])..shuffle(_random);
    _pickNextWord();
  }

  void _pickNextWord() {
    while (_wordQueue.isNotEmpty) {
      final w = _wordQueue.removeLast();
      final tokens = BrailleData.tokenize(w.text, _lang);
      if (tokens == null || tokens.isEmpty) continue;
      setState(() {
        _currentWord = w;
        _wordTokens = tokens;
        _wordStep = 0;
        _clearPairs(_wordCorrectDotsHit);
        _view = _View.wordRound;
      });
      _announceWord();
      return;
    }
    _playClip('word_round_unavailable');
    if (_view == _View.wordRound) setState(() => _view = _View.categorySelect);
  }

  /// Зборот се спелува буква по буква. Намерно потоа НЕ се изговара првата
  /// буква уште еднаш (порано тоа звучеше како првата буква да се повторува
  /// на крајот од зборот).
  Future<void> _announceWord() async {
    final myToken = ++_narrationToken;
    if (_currentWord == null) return;
    await _readbackTokens(_wordTokens, token: myToken);
  }

  /// Го изговара знакот што е на ред (по завршување на претходниот).
  void _announceWordStep() {
    if (_wordStep >= _wordTokens.length) return;
    _playCharClip(_wordTokens[_wordStep]);
  }

  void _repeatWord() {
    if (_currentWord == null) return;
    _announceWord();
  }

  /// „:“ во Играта со зборови - ги брише сите точки на тековната буква.
  void _clearWordLetter() {
    if (_view != _View.wordRound) return;
    setState(() => _clearPairs(_wordCorrectDotsHit));
    _playPongEffect('miss.mp3');
  }

  /// Точка-по-точка (исто како Состави): точна точка - светнува и останува
  /// селектирана; неточна - само звук+вибрација.
  Future<void> _tapWordDot(int pair, int dotIndex) async {
    if (_currentWord == null || _wordStep >= _wordTokens.length) return;
    final tok = _wordTokens[_wordStep];
    if (pair != _activePair) setState(() => _activePair = pair);
    final target = _targetPair(tok, pair);
    final isCorrect = target.contains(dotIndex);

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(
        duration: isCorrect ? 150 : null,
        pattern: isCorrect ? null : const [0, 80, 60, 80],
      );
    }

    if (!isCorrect) {
      await _playPongEffect('miss.mp3');
      return;
    }

    setState(() => _addDot(_wordCorrectDotsHit, pair, dotIndex));
    await _playPongEffect('hit.mp3');
    if (!_pairsComplete(tok, _wordCorrectDotsHit)) {
      _autoAdvancePair(tok, _wordCorrectDotsHit);
      return;
    }

    final stepAtCompletion = _wordStep;
    final wordDone = _wordStep + 1 >= _wordTokens.length;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted || _view != _View.wordRound || _wordStep != stepAtCompletion) return;

    if (!wordDone) {
      _narrationToken++;
      setState(() {
        _wordStep++;
        _clearPairs(_wordCorrectDotsHit);
      });
      _announceWordStep();
      return;
    }

    _wordSessionCount++;
    if (_wordSessionCount >= _wordSessionTarget) {
      setState(() {
        _currentWord = null;
        _view = _View.categorySelect;
      });
    } else {
      _pickNextWord();
    }
  }

  // =====================================================================
  // Пишување: „Искажи ја својата мисла“ (слободно) и „Пишувај реченици“
  // (зададена реченица). Исти правила за двете (види _handleKey).
  // =====================================================================

  /// Точките (1-6) на даден пар во пишувањето.
  Set<int> _pairDots1(int pair) => _writingDots[pair].map((d) => d + 1).toSet();

  bool get _hasWritingDots => _writingDots[0].isNotEmpty || _writingDots[1].isNotEmpty;

  void _startExpressThought() {
    _narrationToken++;
    _voicePlayer.stop();
    setState(() {
      _resetWritingState();
      _view = _View.expressThought;
    });
    _playClip('express_prompt');
  }

  /// Секое притискање регистрира точка и ја изговара. Ако веќе има преглед
  /// (по А) кој не е потврден, новата точка го поништува прегледот -
  /// корисникот очигледно сака да го коригира знакот.
  Future<void> _tapWritingDot(int pair, int dotIndex) async {
    if (!_isWritingView) return;
    if (_view == _View.sentenceGame && (_sentence == null || _sentenceStep >= _sentenceTokens.length)) return;
    setState(() {
      _preview = null;
      _activePair = pair;
      _addDot(_writingDots, pair, dotIndex);
    });
    await _vibrateOk(90);
    await _playClipAwaitingCompletion('dot_${dotIndex + 1}');
  }

  /// А: прв притисок - преглед (се изговара знакот), втор - потврда.
  Future<void> _onConfirmKey() async {
    if (_view == _View.sentenceGame && (_sentence == null || _sentenceStep >= _sentenceTokens.length)) return;
    final preview = _preview;
    if (preview == null) {
      await _previewCurrentCell();
      return;
    }
    if (_view == _View.expressThought) {
      await _expressConfirm(preview);
    } else if (_view == _View.sentenceGame) {
      await _sentenceConfirm(preview);
    }
  }

  Future<void> _previewCurrentCell() async {
    final result = _composer.decodePairs(_pairDots1(0), _pairDots1(1));
    if (result.status == BrailleDecodeStatus.invalid) {
      await _vibrateError();
      await _playPongEffect('miss.mp3');
      return;
    }
    if (result.status == BrailleDecodeStatus.prefix) {
      // Пар 1 е почеток на знак од две клетки (пр. точка 4 за @) - фали пар 2.
      setState(() => _activePair = 1);
      await _vibrateError();
      _narrationToken++;
      await _playClipAwaitingCompletion('pair_2');
      return;
    }
    setState(() => _preview = result);
    await _playCharClip(result.symbol!);
  }

  /// „:“ - ја поништува започнатата клетка (двата пара); ако нема ништо
  /// започнато, во „Искажи ја својата мисла“ го брише последниот напишан знак.
  void _onResetKey() {
    if (_hasWritingDots || _preview != null || _composer.pendingCells.isNotEmpty) {
      setState(() {
        _clearPairs(_writingDots);
        _preview = null;
        _composer.clearPending();
      });
      _playPongEffect('miss.mp3');
      return;
    }
    if (_view == _View.expressThought) {
      BrailleSymbol? removed;
      setState(() => removed = _composer.backspace());
      if (removed != null) _playPongEffect('miss.mp3');
    }
  }

  /// „.“ - ја брише само последната притисната точка.
  Future<void> _removeLastWritingDot() async {
    if (!_isWritingView) return;
    (int, int)? removed;
    setState(() {
      _preview = null;
      final r = _popLastDot(_writingDots);
      removed = r;
      if (r != null) _activePair = r.$1;
    });
    await _afterDotRemoved(removed);
  }

  /// Гласовно „изговори“ - секогаш одново го изговара знакот од точките.
  Future<void> _voiceSpeak() async {
    if (!_isWritingView) return;
    setState(() => _preview = null);
    await _onConfirmKey();
  }

  /// Гласовно „потврди“ - ако знакот не е изговорен, прво се изговара, па
  /// веднаш се потврдува (исто како А, А).
  Future<void> _voiceConfirm() async {
    if (!_isWritingView) return;
    if (_preview == null) {
      await _onConfirmKey();
      if (!mounted || _preview == null) return;
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || _preview == null) return;
    }
    await _onConfirmKey();
  }

  /// Заеднички гласовни команди за пишувањето (Искажи / Пишувај реченици).
  /// „поништи точка“ е пред „поништи буква“ бидејќи второто содржи и само
  /// „поништи“.
  List<VoiceCategoryOption> _writingVoiceOptions() => [
        VoiceCategoryOption(keywords: _kwRemoveDot, onSelected: _removeLastWritingDot),
        VoiceCategoryOption(keywords: _kwRemoveLetter, onSelected: _onResetKey),
        VoiceCategoryOption(keywords: _kwSpeak, onSelected: _voiceSpeak),
        VoiceCategoryOption(keywords: _kwConfirm, onSelected: _voiceConfirm),
        VoiceCategoryOption(keywords: _kwReference, onSelected: () => _openReference(_view)),
      ];

  static const List<String> _kwRemoveDot = [
    'поништи точка', 'поништи ја точката', 'избриши точка', 'избриши ја точката', 'бриши точка', 'отстрани точка',
    'delete dot', 'remove dot', 'undo dot', 'cancel dot', 'delete the dot',
    'fshi pikën', 'fshi piken', 'anulo pikën', 'anulo piken', 'hiq pikën', 'hiq piken',
  ];
  static const List<String> _kwRemoveLetter = [
    'поништи буква', 'поништи ја буквата', 'избриши буква', 'избриши ја буквата', 'бриши буква', 'поништи',
    'delete letter', 'remove letter', 'cancel letter', 'delete the letter', 'cancel',
    'fshi shkronjën', 'fshi shkronjen', 'anulo shkronjën', 'anulo shkronjen', 'anulo',
  ];
  static const List<String> _kwSpeak = ['изговори', 'кажи ја буквата', 'кажи', 'speak', 'say it', 'say', 'thuaj', 'shqipto'];
  static const List<String> _kwConfirm = ['потврди', 'потврда', 'confirm', 'konfirmo'];
  static const List<String> _kwReference = ['потсетник', 'reference', 'reminder', 'përkujtues', 'perkujtues'];

  Future<void> _expressConfirm(BrailleDecodeResult r) async {
    final symbol = r.symbol;
    if (symbol == null) return;
    final lineTokens = [..._composer.lineTokens, symbol];
    String? finishedLine;
    setState(() {
      finishedLine = _composer.commit(symbol);
      _clearPairs(_writingDots);
      _preview = null;
    });
    await _vibrateOk();
    await _playPongEffect('hit.mp3');

    if (finishedLine != null) {
      // Крај на реченица (. ? !) - се чита целата реченица.
      await Future.delayed(const Duration(milliseconds: 250));
      await _readbackTokens(lineTokens);
    } else if (symbol.kind == BrailleKind.space) {
      // Крај на збор - се чита зборот.
      await Future.delayed(const Duration(milliseconds: 250));
      await _readbackTokens(_composer.lastWordTokens());
    }
  }

  void _toggleExpressExplanation() {
    final opening = !_expressExplanationOpen;
    setState(() => _expressExplanationOpen = opening);
    if (opening) {
      // Посебна снимка за секоја игра: express_explanation.mp3 /
      // sentence_explanation.mp3.
      _playClip(_view == _View.sentenceGame ? 'sentence_explanation' : 'express_explanation');
    } else {
      _voicePlayer.stop();
    }
  }

  // --- „Пишувај реченици“ ---

  void _startSentenceGame() {
    _narrationToken++;
    _voicePlayer.stop();
    _sentenceQueue = List<BrailleSentence>.from(BrailleData.sentences[_lang] ?? const <BrailleSentence>[])..shuffle(_random);
    _sentenceCount = 0;
    _sentenceMistakesTotal = 0;
    setState(() {
      _sentenceFinished = false;
      _expressExplanationOpen = false;
      _view = _View.sentenceGame;
    });
    _loadNextSentence();
  }

  void _loadNextSentence() {
    while (_sentenceQueue.isNotEmpty) {
      final s = _sentenceQueue.removeLast();
      final tokens = BrailleData.tokenize(s.text, _lang);
      if (tokens == null || tokens.isEmpty) continue;
      setState(() {
        _sentence = s;
        _sentenceTokens = tokens;
        _sentenceStep = 0;
        _sentenceMistakes = 0;
        _resetWritingState();
      });
      _playSentenceIntro();
      return;
    }
    setState(() => _sentenceFinished = true);
  }

  Future<void> _playSentenceIntro() async {
    final myToken = ++_narrationToken;
    await _playClipAwaitingCompletion('sentence_prompt');
    if (myToken != _narrationToken || !mounted) return;
    await _playSentenceAudio(token: myToken);
  }

  /// Преслушување на реченицата: снимка sentence_<key>.mp3, а ако ја нема -
  /// спелување буква по буква.
  Future<void> _playSentenceAudio({int? token}) async {
    final myToken = token ?? ++_narrationToken;
    final s = _sentence;
    if (s == null) return;
    final played = await _playClipAwaitingCompletion('sentence_${s.key}', timeout: const Duration(seconds: 15));
    if (myToken != _narrationToken || !mounted) return;
    if (!played) await _readbackTokens(_sentenceTokens, token: myToken);
  }

  /// Помош: го изговара знакот што е на ред.
  Future<void> _playSentenceHint() async {
    if (_sentenceStep >= _sentenceTokens.length) return;
    _narrationToken++;
    await _playCharClip(_sentenceTokens[_sentenceStep]);
  }

  Future<void> _sentenceMistake() async {
    setState(() {
      _clearPairs(_writingDots);
      _preview = null;
      _composer.clearPending();
      _sentenceMistakes++;
      _sentenceMistakesTotal++;
    });
    await _vibrateError();
    await _playPongEffect('miss.mp3');
  }

  /// Втор А во „Пишувај реченици“: потврдениот знак веднаш се споредува со
  /// оној што е на ред - точно = hit.mp3, погрешно = miss.mp3 (и не се запишува).
  Future<void> _sentenceConfirm(BrailleDecodeResult r) async {
    if (_sentenceStep >= _sentenceTokens.length) return;
    final expected = _sentenceTokens[_sentenceStep];
    final symbol = r.symbol;
    if (symbol == null || symbol.key != expected.key || symbol.kind != expected.kind) {
      await _sentenceMistake();
      return;
    }
    setState(() {
      _composer.commit(symbol);
      _clearPairs(_writingDots);
      _preview = null;
      _sentenceStep++;
    });
    await _vibrateOk();
    await _playPongEffect('hit.mp3');
    if (_sentenceStep >= _sentenceTokens.length) await _onSentenceCompleted();
  }

  Future<void> _onSentenceCompleted() async {
    _sentenceCount++;
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || _view != _View.sentenceGame) return;
    await _playClipAwaitingCompletion('sentence_done', timeout: const Duration(seconds: 4));
    if (!mounted || _view != _View.sentenceGame) return;
    if (_sentenceCount >= _sentenceSessionTarget) {
      setState(() => _sentenceFinished = true);
    } else {
      _loadNextSentence();
    }
  }

  // =====================================================================
  // Build.
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return GameScreenChrome(
      accent: _accent,
      title: 'braille.title'.tr(),
      // Секој поглед има свое копче за гласовна команда.
      voiceCommand: false,
      child: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Builder(
            builder: (context) {
              switch (_view) {
                case _View.categorySelect:
                  return _buildCategorySelect(context);
                case _View.explore:
                  return _buildExplore(context);
                case _View.practiceModeSelect:
                  return _buildPracticeModeSelect(context);
                case _View.practiceCompose:
                  return _buildPracticeCompose(context);
                case _View.practiceRecognize:
                  return _buildPracticeRecognize(context);
                case _View.practiceWrite:
                  return _buildPracticeWrite(context);
                case _View.wordRound:
                  return _buildWordRound(context);
                case _View.expressThought:
                  return _buildExpressThought(context);
                case _View.sentenceGame:
                  return _buildSentenceGame(context);
                case _View.reference:
                  return _buildReferenceGrid(context);
                case _View.savedSentences:
                  return _buildSavedSentences(context);
              }
            },
          ),
        ),
      ),
    );
  }

  // --- Избор на категорија ---

  /// Гласовни опции за екранот за избор на категорија. Броевите се
  /// препознаваат и како цифра („група 1“) и како збор („група еден“).
  List<VoiceCategoryOption> _categoryVoiceOptions() {
    final options = <VoiceCategoryOption>[];
    final groupKeywords = <List<String>>[];
    for (var i = 0; i < _groups.length; i++) {
      final key = _groups[i].titleKey;
      List<String> keywords;
      switch (key) {
        case 'braille.group1':
          keywords = [
            'група 1', 'група еден', 'група една', 'групата 1', 'групата еден', 'група један',
            'прва група', 'првата група', 'група прва',
            'group 1', 'group one', 'first group', 'group won',
            'grupi 1', 'grupi një', 'grupi nje', 'grupi i parë', 'grupi i pare', 'grupi i 1', 'grupa 1', 'grupa një',
          ];
          break;
        case 'braille.group2':
          keywords = [
            'група 2', 'група два', 'група две', 'групата 2', 'групата два', 'втора група', 'втората група', 'група втора',
            'group 2', 'group two', 'group to', 'group too', 'second group',
            'grupi 2', 'grupi dy', 'grupi i dytë', 'grupi i dyte', 'grupa 2', 'grupa dy',
          ];
          break;
        case 'braille.group3':
          keywords = [
            'група 3', 'група три', 'групата 3', 'групата три', 'трета група', 'третата група', 'група трета',
            'group 3', 'group three', 'third group',
            'grupi 3', 'grupi tre', 'grupi i tretë', 'grupi i trete', 'grupa 3', 'grupa tre',
          ];
          break;
        case 'braille.group_special':
          keywords = ['специјални букви', 'специјални', 'special letters', 'special', 'shkronja të veçanta', 'të veçanta', 'te vecanta'];
          break;
        case 'braille.group_numbers':
          keywords = ['броеви', 'бројки', 'numbers', 'number', 'numra', 'numrat'];
          break;
        case 'braille.group_punct':
          keywords = [
            'интерпункциски', 'интерпункција', 'знаци', 'знаковите',
            'punctuation', 'signs', 'marks', 'symbols',
            'shenjat', 'shenja pikësimi', 'pikësim', 'pikesim', 'shenja',
          ];
          break;
        default:
          keywords = [key.tr().toLowerCase()];
      }
      groupKeywords.add(keywords);
    }

    // „Вежба“ (+ група): „вежба група 1“ го отвора менито за вежба на таа
    // група; само „вежба“ - на последно отворената група (на почеток група 1).
    // Ова се проверува ПРЕД групите, за „вежба група 1“ да не ја отвори само
    // групата.
    bool saysPractice(String t) => _kwPractice.any((k) => t.contains(k));
    for (var i = 0; i < _groups.length; i++) {
      final index = i;
      final kws = groupKeywords[i];
      options.add(VoiceCategoryOption(
        keywords: const [],
        matches: (t) => saysPractice(t) && kws.any((k) => t.contains(k)),
        onSelected: () => _openPracticeModeSelect(index),
      ));
    }
    options.add(VoiceCategoryOption(
      keywords: _kwPractice,
      onSelected: () => _openPracticeModeSelect(_groupIndex),
    ));
    for (var i = 0; i < _groups.length; i++) {
      final index = i;
      options.add(VoiceCategoryOption(keywords: groupKeywords[i], onSelected: () => _openGroup(index)));
    }
    options.add(VoiceCategoryOption(
      keywords: ['потсетник', 'потсетникот', 'reference', 'reminder', 'përkujtues', 'perkujtues', 'përkujtuesi'],
      onSelected: () => _openReference(_View.categorySelect),
    ));
    options.add(VoiceCategoryOption(
      keywords: ['пишувај реченици', 'пишување реченици', 'реченици', 'реченица', 'write sentences', 'sentences', 'sentence', 'shkruaj fjali', 'fjalitë', 'fjalite', 'fjali'],
      onSelected: _startSentenceGame,
    ));
    options.add(VoiceCategoryOption(
      keywords: ['игра со зборови', 'зборови', 'word game', 'words', 'loja me fjalë', 'loja me fjale', 'fjalë', 'fjale'],
      onSelected: _startWordSession,
    ));
    options.add(VoiceCategoryOption(
      keywords: [
        'искажи ја својата мисла',
        'искажи мисла',
        'мисла',
        'express your thought',
        'express thought',
        'shpreh mendimin tënd',
        'shpreh mendimin',
        'mendimin',
      ],
      onSelected: _startExpressThought,
    ));
    return options;
  }

  Widget _buildCategorySelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('braille.intro_title'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 22)),
        const SizedBox(height: 12),
        _buildIntroArea(contrast, hc),
        const SizedBox(height: 22),
        AbsorbPointer(
          absorbing: _introLocked,
          child: Opacity(
            opacity: _introLocked ? 0.35 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'braille.choose_group'.tr(),
                  textAlign: TextAlign.center,
                  style: GameTypography.heading(context, contrast, 20),
                ),
                const SizedBox(height: 16),
                Center(child: CategoryVoiceCommandButton(options: _categoryVoiceOptions(), onBack: () => Navigator.of(context).pop())),
                const SizedBox(height: 16),
                Semantics(
                  label: 'braille.reference_button'.tr(),
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openReference(_View.categorySelect),
                      icon: const Icon(Icons.menu_book_rounded, size: 26),
                      label: Text('braille.reference_button'.tr(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < _groups.length; i++) ...[
                  _groupCard(context, i, contrast, hc),
                  const SizedBox(height: 18),
                ],
                _wordGameCard(contrast, hc),
                const SizedBox(height: 18),
                _expressThoughtCard(contrast, hc),
                const SizedBox(height: 18),
                _sentenceGameCard(contrast, hc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Воведот е СЕКОГАШ целосно видлив (текст + асоцијации точки↔тастатура).
  /// Копчето „стоп" се прикажува само додека трае заклучувањето и е на
  /// средина на дното.
  Widget _buildIntroArea(Color contrast, bool hc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('braille.intro_text'.tr(), style: GameTypography.body(context, contrast, 20)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _dotKeyColumn(const [1, 2, 3], contrast),
              if (_introLocked)
                Semantics(
                  label: 'braille.intro_stop'.tr(),
                  button: true,
                  child: Material(
                    color: _accent,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _stopIntroNow,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Icon(Icons.stop_rounded, size: 30, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              _dotKeyColumn(const [4, 5, 6], contrast),
            ],
          ),
        ],
      ),
    );
  }

  /// Три точки (една колона) со соодветните копчиња на тастатура,
  /// поставени во долниот агол - лева/десна страна од воведот.
  Widget _dotKeyColumn(List<int> dotNumbers, Color contrast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final d in dotNumbers) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.18)),
                  child: Text('$d', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _accent)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(7)),
                  child: Text(_keyLetters[d - 1], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _groupCard(BuildContext context, int index, Color contrast, bool hc) {
    final group = _groups[index];
    final exploredCount = group.symbols.where((s) => _exploredKeys.contains('$index:${s.key}')).length;
    final done = _isGroupFullyExplored(index);

    return Semantics(
      label: '${group.titleKey.tr()}. $exploredCount / ${group.symbols.length} ${'braille.explored'.tr()}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          constraints: const BoxConstraints(minHeight: 110),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: hc
                ? null
                : LinearGradient(colors: [_accent, Color.lerp(_accent, Colors.white, 0.3)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
            color: hc ? Colors.black : null,
            border: Border.all(color: hc ? Colors.white : _accent, width: hc ? 3 : 0),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openGroup(index),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(hc ? 0.1 : 0.25)),
                          child: Icon(
                            done ? Icons.check_circle_rounded : Icons.school_rounded,
                            color: hc ? const Color(0xFFFFFF00) : Colors.white,
                            size: 44,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.titleKey.tr(),
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$exploredCount / ${group.symbols.length} ${'braille.explored'.tr()}',
                                style: TextStyle(fontSize: 14, color: (hc ? const Color(0xFFFFFF00) : Colors.white).withOpacity(0.85)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'braille.go_practice'.tr(),
                button: true,
                child: Material(
                  color: Colors.white.withOpacity(hc ? 0.12 : 0.22),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openPracticeModeSelect(index),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fitness_center_rounded, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 34),
                          const SizedBox(height: 2),
                          Text(
                            'braille.go_practice'.tr(),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded, color: hc ? Colors.white : Colors.white.withOpacity(0.8), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordGameCard(Color contrast, bool hc) {
    return Semantics(
      label: '${'braille.mode_word'.tr()}. ${'braille.mode_word_desc'.tr()}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _startWordSession,
          child: Container(
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(minHeight: 110),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: hc ? null : const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF4ADE80)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: hc ? Colors.black : null,
              border: Border.all(color: hc ? Colors.white : const Color(0xFF16A34A), width: hc ? 3 : 0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(hc ? 0.1 : 0.25)),
                  child: Icon(Icons.auto_stories_rounded, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 44),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'braille.mode_word'.tr(),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'braille.mode_word_desc'.tr(),
                        style: TextStyle(fontSize: 14, color: (hc ? const Color(0xFFFFFF00) : Colors.white).withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: hc ? Colors.white : Colors.white.withOpacity(0.8), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expressThoughtCard(Color contrast, bool hc) {
    return Semantics(
      label: '${'braille.mode_express'.tr()}. ${'braille.mode_express_desc'.tr()}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _startExpressThought,
          child: Container(
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(minHeight: 110),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: hc ? null : const LinearGradient(colors: [Color(0xFFDB2777), Color(0xFFF472B6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: hc ? Colors.black : null,
              border: Border.all(color: hc ? Colors.white : const Color(0xFFDB2777), width: hc ? 3 : 0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(hc ? 0.1 : 0.25)),
                  child: Icon(Icons.chat_bubble_rounded, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 44),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'braille.mode_express'.tr(),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'braille.mode_express_desc'.tr(),
                        style: TextStyle(fontSize: 14, color: (hc ? const Color(0xFFFFFF00) : Colors.white).withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: hc ? Colors.white : Colors.white.withOpacity(0.8), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sentenceGameCard(Color contrast, bool hc) {
    return Semantics(
      label: '${'braille.mode_sentence'.tr()}. ${'braille.mode_sentence_desc'.tr()}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _startSentenceGame,
          child: Container(
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(minHeight: 110),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: hc ? null : const LinearGradient(colors: [Color(0xFFEA580C), Color(0xFFFB923C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: hc ? Colors.black : null,
              border: Border.all(color: hc ? Colors.white : const Color(0xFFEA580C), width: hc ? 3 : 0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(hc ? 0.1 : 0.25)),
                  child: Icon(Icons.edit_note_rounded, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 44),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'braille.mode_sentence'.tr(),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'braille.mode_sentence_desc'.tr(),
                        style: TextStyle(fontSize: 14, color: (hc ? const Color(0xFFFFFF00) : Colors.white).withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: hc ? Colors.white : Colors.white.withOpacity(0.8), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Истражувај: 3-зонски дизајн исто како кај сликовницата ---

  Widget _buildExplore(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories, withVoiceBack: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('${_symbolIndex + 1} / ${_group.symbols.length}', style: GameTypography.heading(context, contrast, 18)),
        ),
        Expanded(
          child: PageView.builder(
            controller: _explorePageController,
            itemCount: _group.symbols.length,
            onPageChanged: _onExplorePageChanged,
            itemBuilder: (context, index) => _exploreCard(context, contrast, index),
          ),
        ),
      ],
    );
  }

  Widget _exploreCard(BuildContext context, Color contrastColor, int index) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final s = _group.symbols[index];
    final hasPrev = index > 0;
    final hasNext = index < _group.symbols.length - 1;

    final gradientColors = hc
        ? const [Colors.black, Colors.black, Colors.black]
        : [
            Color.lerp(_accent, Colors.white, 0.72)!,
            Color.lerp(_accent, Colors.white, 0.28)!,
            Color.lerp(_accent, Colors.white, 0.72)!,
          ];

    return Container(
      margin: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: hc ? Colors.white : contrastColor, width: 3),
        gradient: LinearGradient(colors: gradientColors, stops: const [0.0, 0.5, 1.0], begin: Alignment.centerLeft, end: Alignment.centerRight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: _NavZone(enabled: hasPrev, icon: Icons.chevron_left_rounded, onTap: _goPrevExplore, label: 'braille.previous_item'.tr(), highContrast: hc),
          ),
          Expanded(
            flex: 6,
            child: GestureDetector(
              onTap: () => _playCharExplanationSequence(s),
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                label: _explanationFor(s),
                button: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textColor = hc ? Colors.white : contrastColor;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _bigCellsDisplay(s.cells, hc, scale: 2.0),
                              const SizedBox(height: 26),
                              Text(s.displayChar, style: TextStyle(fontSize: 104, fontWeight: FontWeight.w900, color: textColor)),
                              if (s.kind != BrailleKind.letter && s.kind != BrailleKind.digit) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _symbolName(s),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: textColor),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Text(
                                _explanationFor(s),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 28, color: textColor.withOpacity(0.9)),
                              ),
                              const SizedBox(height: 22),
                              Semantics(
                                label: 'braille.repeat'.tr(),
                                button: true,
                                child: Material(
                                  color: hc ? Colors.black : _accent,
                                  shape: const CircleBorder(),
                                  elevation: 3,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => _playCharExplanationSequence(s),
                                    child: const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Icon(Icons.replay_rounded, size: 34, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _NavZone(enabled: hasNext, icon: Icons.chevron_right_rounded, onTap: _goNextExplore, label: 'braille.next_item'.tr(), highContrast: hc),
          ),
        ],
      ),
    );
  }

  /// Една или повеќе Брајови клетки една до друга (пр. @ има две клетки).
  Widget _bigCellsDisplay(List<List<int>> cells, bool hc, {double scale = 1.0}) {
    if (cells.length == 1) return _bigDotDisplay(cells.first, hc, scale: scale);
    final cellScale = scale / cells.length * 1.15;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) SizedBox(width: 10 * cellScale),
          _bigDotDisplay(cells[i], hc, scale: cellScale),
        ],
      ],
    );
  }

  Widget _bigDotDisplay(List<int> dots, bool hc, {double scale = 1.0}) {
    final active = List<bool>.filled(6, false);
    for (final d in dots) {
      active[d - 1] = true;
    }
    Widget dot(int i) {
      final on = active[i];
      final color = on ? const Color(0xFFCCFF00) : (hc ? Colors.white38 : Colors.black26);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52 * scale,
        height: 52 * scale,
        margin: EdgeInsets.all(5 * scale),
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color : Colors.transparent, border: Border.all(color: color, width: 3)),
        child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.bold, color: on ? Colors.black : color))),
      );
    }

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [dot(0), dot(3)]),
          Row(mainAxisSize: MainAxisSize.min, children: [dot(1), dot(4)]),
          Row(mainAxisSize: MainAxisSize.min, children: [dot(2), dot(5)]),
        ],
      ),
    );
  }

  // --- Избор на режим (Состави / Препознај / Напиши / Игра со зборови) ---

  /// Гласовни опции за вежбите: „состави“, „препознај“, „напиши“ -
  /// се користат во менито за вежба И во самите вежби (за премин во друга).
  List<VoiceCategoryOption> _practiceVoiceOptions() => [
        VoiceCategoryOption(
          keywords: const ['состави', 'составување', 'compose', 'build', 'përbëj', 'perbej'],
          onSelected: () => _startPractice(_View.practiceCompose),
        ),
        VoiceCategoryOption(
          keywords: const ['препознај', 'препознавање', 'recognize', 'recognise', 'njih', 'njohje'],
          onSelected: () => _startPractice(_View.practiceRecognize),
        ),
        VoiceCategoryOption(
          keywords: const ['напиши', 'пишување', 'write', 'shkruaj'],
          onSelected: () => _startPractice(_View.practiceWrite),
        ),
      ];

  static const List<String> _kwPractice = ['вежба', 'вежбај', 'вежби', 'вежбање', 'practice', 'exercise', 'ushtrim', 'ushtro'];

  Widget _buildPracticeModeSelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_group.titleKey.tr(), style: GameTypography.heading(context, contrast, 20)),
        ),
        const SizedBox(height: 10),
        // Гласовно: „состави“, „препознај“, „напиши“ (и „назад“).
        Center(
          child: CategoryVoiceCommandButton(
            options: [..._practiceVoiceOptions(), ..._categoryVoiceOptions()],
            onBack: _backToCategories,
            compact: true,
            background: _accent,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _practiceModeCard(icon: Icons.touch_app_rounded, title: 'braille.mode_compose'.tr(), desc: 'braille.mode_compose_desc'.tr(), onTap: () => _startPractice(_View.practiceCompose)),
              const SizedBox(height: 14),
              _practiceModeCard(icon: Icons.visibility_rounded, title: 'braille.mode_recognize'.tr(), desc: 'braille.mode_recognize_desc'.tr(), onTap: () => _startPractice(_View.practiceRecognize)),
              const SizedBox(height: 14),
              _practiceModeCard(icon: Icons.edit_rounded, title: 'braille.mode_write'.tr(), desc: 'braille.mode_write_desc'.tr(), onTap: () => _startPractice(_View.practiceWrite)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _practiceModeCard({required IconData icon, required String title, required String desc, required VoidCallback onTap}) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: '$title. $desc',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(26),
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: hc ? Colors.black : Colors.white,
              border: Border.all(color: hc ? Colors.white : const Color(0xFFE2E8F0), width: hc ? 2 : 1),
              boxShadow: hc ? const [] : AppStyle.cardShadow(false),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.15)),
                  child: Icon(icon, color: _accent, size: 40),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: contrast)),
                      const SizedBox(height: 6),
                      Text(desc, style: TextStyle(fontSize: 16, color: contrast.withOpacity(0.75))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Практика: Состави / Напиши ---

  Widget _buildPracticeCompose(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    if (_practiceFinished) return _practiceDoneScreen(contrast, showScore: false);
    if (_practiceTarget == null) return const SizedBox.shrink();
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _openPracticeModeSelect, voiceOptions: _practiceVoiceOptions()),
        _practiceTargetHeader(contrast),
        Expanded(
          child: Center(
            child: _dotPairsGrid(pairCount: _practiceTarget!.cells.length, onTap: _tapComposeDot, hits: _correctDotsHit),
          ),
        ),
        _buildKeyboardHint(contrast),
      ],
    );
  }

  Widget _buildPracticeWrite(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    if (_practiceFinished) return _practiceDoneScreen(contrast, showScore: true);
    if (_practiceTarget == null) return const SizedBox.shrink();
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _openPracticeModeSelect, voiceOptions: _practiceVoiceOptions()),
        _practiceProgressLine(contrast),
        _practiceTargetHeader(contrast),
        Expanded(
          child: Center(
            child: AbsorbPointer(
              absorbing: _writeFailed,
              child: _dotPairsGrid(pairCount: _practiceTarget!.cells.length, onTap: _tapWriteDot, hits: _correctDotsHit, wrongVisual: _writeFailed),
            ),
          ),
        ),
        _buildKeyboardHint(contrast),
      ],
    );
  }

  /// Знакот што се вежба: голем приказ, име (за знаците) и која клетка е
  /// на ред (за повеќеклеточните знаци како @ и /).
  Widget _practiceTargetHeader(Color contrast) {
    final t = _practiceTarget!;
    final isSign = t.kind != BrailleKind.letter && t.kind != BrailleKind.digit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(t.displayChar, style: TextStyle(fontSize: isSign ? 80 : 100, fontWeight: FontWeight.w900, color: contrast)),
          if (isSign) Text(_symbolName(t), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 20)),
          if (t.isMultiCell)
            Text('braille.two_pairs_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 16)),
        ],
      ),
    );
  }

  /// Еден или два пара точки (пар 2 е за знаците од две клетки, пр. @ и /).
  /// Активниот пар (за тастатурата, се менува со H) е врамен во бојата на
  /// акцентот; на екранот може да се допира секој пар.
  Widget _dotPairsGrid({
    required int pairCount,
    required void Function(int pair, int dot) onTap,
    required List<Set<int>> hits,
    bool wrongVisual = false,
    double? dotSize,
    double? dotPadding,
  }) {
    if (pairCount <= 1) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: _interactiveDotGrid(
          onTap: (d) => onTap(0, d),
          wrongVisual: wrongVisual,
          hitDots: hits[0],
          dotSize: dotSize ?? 150,
          dotPadding: dotPadding ?? 14,
        ),
      );
    }
    final contrast = AccessibilityUtils.getContrastColor(context);
    final size = dotSize ?? 76;
    final pad = dotPadding ?? 7;

    Widget pairBox(int p) {
      final active = p == _activePair;
      final label = 'braille.pair_label'.tr(args: ['${p + 1}']);
      return Semantics(
        label: active ? '$label, ${'braille.pair_active'.tr()}' : label,
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? _accent : contrast.withOpacity(0.2), width: active ? 3 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: active ? _accent : contrast)),
              _interactiveDotGrid(
                onTap: (d) => onTap(p, d),
                wrongVisual: wrongVisual,
                hitDots: hits[p],
                dotSize: size,
                dotPadding: pad,
              ),
            ],
          ),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [pairBox(0), const SizedBox(width: 14), pairBox(1)],
      ),
    );
  }

  /// Точна форма на Брајовата клетка: лева колона точки 1-2-3, десна
  /// колона точки 4-5-6.
  Widget _interactiveDotGrid({
    required void Function(int) onTap,
    required bool wrongVisual,
    required Set<int> hitDots,
    double dotSize = 150,
    double dotPadding = 14,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final hits = hitDots;

    Widget dotButton(int i) {
      final hit = hits.contains(i);
      final color = wrongVisual ? const Color(0xFF6B7280) : (hit ? const Color(0xFF16A34A) : (hc ? Colors.white : _accent));
      return Padding(
        padding: EdgeInsets.all(dotPadding),
        child: Semantics(
          label: '${'braille.dot'.tr()} ${i + 1}',
          button: true,
          child: Material(
            color: hit ? color : color.withOpacity(0.12),
            shape: const CircleBorder(),
            elevation: hc ? 0 : 5,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onTap(i),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 4)),
                child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: dotSize * 0.29, fontWeight: FontWeight.bold, color: hit ? Colors.white : color))),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [dotButton(0), dotButton(1), dotButton(2)]),
        Column(mainAxisSize: MainAxisSize.min, children: [dotButton(3), dotButton(4), dotButton(5)]),
      ],
    );
  }

  // --- Практика: Препознај ---

  Widget _buildPracticeRecognize(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    if (_practiceFinished) return _practiceDoneScreen(contrast);
    if (_practiceTarget == null) return const SizedBox.shrink();
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _openPracticeModeSelect, voiceOptions: _practiceVoiceOptions()),
        _practiceProgressLine(contrast),
        Expanded(
          flex: 5,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('braille.recognize_prompt'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 22)),
                ),
                const SizedBox(height: 20),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: !_recognizeDotsDone ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFF59E0B)) : Colors.transparent,
                      width: 4,
                    ),
                  ),
                  child: _bigCellsDisplay(_practiceTarget!.cells, hc, scale: 1.5),
                ),
                const SizedBox(height: 18),
                Semantics(
                  label: 'braille.repeat'.tr(),
                  button: true,
                  child: Material(
                    color: hc ? Colors.black : _accent,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _playRecognizeDotsSequence(_practiceTarget!),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(Icons.replay_rounded, size: 28, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: _recognizeChoices.asMap().entries.map((entry) {
              final index = entry.key;
              final choice = entry.value;
              final isPicked = _recognizePicked == choice.key;
              final isCorrectAnswer = choice.key == _practiceTarget!.key;
              final showFeedback = _recognizePicked != null && (isPicked || isCorrectAnswer);
              final unlocked = index < _recognizeUnlocked;
              final reading = _recognizeReadingOption == index;
              final bg = !showFeedback
                  ? AccessibilityUtils.getPrimaryButtonBackground(context)
                  : (isCorrectAnswer ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
              final label = choice.kind == BrailleKind.letter || choice.kind == BrailleKind.digit
                  ? choice.char
                  : '${choice.displayChar}  ${_symbolName(choice)}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AbsorbPointer(
                  absorbing: _recognizePicked != null || !unlocked,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: (unlocked || reading || _recognizePicked != null) ? 1.0 : 0.3,
                    child: Semantics(
                      label: '${index + 1}. $label',
                      button: unlocked,
                      child: SizedBox(
                        width: double.infinity,
                        height: 84,
                        child: ElevatedButton(
                          onPressed: () => _pickRecognizeAnswer(choice),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: bg,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: reading
                                  ? BorderSide(color: hc ? const Color(0xFFFFFF00) : const Color(0xFFF59E0B), width: 4)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _practiceProgressLine(Color contrast) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        '${_practiceRound + 1} / $_practiceRoundsTotal  ·  ${'braille.score'.tr()}: $_practiceScore',
        style: GameTypography.heading(context, contrast, 16),
      ),
    );
  }

  Widget _practiceDoneScreen(Color contrast, {bool showScore = true}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 72, color: _accent),
            const SizedBox(height: 16),
            Text(
              showScore ? '${'braille.score'.tr()}: $_practiceScore / $_practiceRoundsTotal' : 'braille.practice_complete'.tr(),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openPracticeModeSelect,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text('braille.change_mode'.tr()),
              style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Ниво со зборови ---

  Widget _buildWordRound(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    if (_currentWord == null || _wordTokens.isEmpty) return const SizedBox.shrink();
    final currentToken = min(_wordStep, _wordTokens.length - 1);
    final current = _wordTokens[currentToken];
    final currentIsSign = current.isModifier || current.kind == BrailleKind.punctuation;
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${'braille.word_round_title'.tr()}  ·  ${_wordSessionCount + 1}/$_wordSessionTarget',
            style: GameTypography.heading(context, contrast, 20),
          ),
        ),
        const SizedBox(height: 12),
        // Зборот симбол по симбол. Знакот за голема буква / број се
        // прикажува како мала ознака (⇧ / #), бидејќи и тој се пишува.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_wordTokens.length, (i) {
            final tok = _wordTokens[i];
            final isCurrent = i == currentToken;
            final isDone = i < currentToken;
            final small = tok.isModifier;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: small ? 8 : 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF16A34A) : (isCurrent ? _accent : Colors.transparent),
                border: Border.all(color: contrast.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tok.displayChar,
                style: TextStyle(
                  fontSize: small ? 20 : 28,
                  fontWeight: FontWeight.bold,
                  color: (isDone || isCurrent) ? Colors.white : (hc ? Colors.white : contrast),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        if (currentIsSign || current.isMultiCell)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              [
                if (currentIsSign) _symbolName(current),
                if (current.isMultiCell) 'braille.two_pairs_hint'.tr(),
              ].join('  ·  '),
              textAlign: TextAlign.center,
              style: GameTypography.heading(context, contrast, 18),
            ),
          ),
        const SizedBox(height: 6),
        Text('braille.word_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 15)),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Semantics(
              label: 'braille.word_listen'.tr(),
              button: true,
              child: OutlinedButton.icon(
                onPressed: _repeatWord,
                icon: const Icon(Icons.volume_up_rounded),
                label: Text('braille.word_listen'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            Semantics(
              label: 'braille.action_reset'.tr(),
              button: true,
              child: OutlinedButton.icon(
                onPressed: _clearWordLetter,
                icon: const Icon(Icons.backspace_rounded),
                label: Text('braille.action_reset'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: CategoryVoiceCommandButton(
            options: [
              VoiceCategoryOption(
                keywords: [
                  'слушни го зборот', 'слушни', 'преслушај', 'повтори го зборот', 'зборот',
                  'listen to the word', 'listen', 'repeat the word', 'repeat', 'the word',
                  'dëgjo fjalën', 'degjo fjalen', 'dëgjo', 'degjo', 'fjalën',
                ],
                onSelected: _repeatWord,
              ),
              VoiceCategoryOption(keywords: _kwRemoveLetter, onSelected: _clearWordLetter),
              ..._categoryVoiceOptions(),
            ],
            onBack: _backToCategories,
            compact: true,
            background: _accent,
            trigger: _voiceTrigger,
          ),
        ),
        Expanded(
          child: Center(
            child: _dotPairsGrid(pairCount: current.cells.length, onTap: _tapWordDot, hits: _wordCorrectDotsHit),
          ),
        ),
        _buildExpressKeyboardHint(contrast, 'braille.word_keyboard_hint'),
      ],
    );
  }

  // --- Пишување: „Искажи ја својата мисла“ и „Пишувај реченици“ ---

  Widget _buildWritingDotGrid() {
    return SizedBox(
      height: 270,
      child: Center(
        child: _dotPairsGrid(
          pairCount: 2,
          onTap: _tapWritingDot,
          hits: _writingDots,
          dotSize: 56,
          dotPadding: 6,
        ),
      ),
    );
  }

  /// Ознаки за состојбата: режим за броеви (по знакот за број, до празно
  /// место), следната буква е голема.
  Widget _buildModeBadges(Color contrast) {
    final badges = <String>[
      if (_composer.numberMode) 'braille.badge_number_mode'.tr(),
      if (_composer.capitalNext) 'braille.badge_capital_next'.tr(),
    ];
    if (badges.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final b in badges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent, width: 1.5),
              ),
              child: Text(b, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: contrast)),
            ),
        ],
      ),
    );
  }

  /// Копчиња на екранот за истите дејства како А, : и П на тастатурата
  /// (за телефон/таблет без тастатура).
  Widget _buildWritingActions() {
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return Semantics(
        label: label,
        button: true,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 22),
          label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          action(Icons.record_voice_over_rounded, 'braille.action_confirm'.tr(), _onConfirmKey),
          action(Icons.undo_rounded, 'braille.action_remove_dot'.tr(), _removeLastWritingDot),
          action(Icons.backspace_rounded, 'braille.action_reset'.tr(), _onResetKey),
          action(Icons.menu_book_rounded, 'braille.action_reference'.tr(), () => _openReference(_view)),
        ],
      ),
    );
  }

  Widget _buildExpressThought(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildBackRow(contrast, onBack: _backToCategories),
          _buildExpressExplanationButton(contrast),
          if (_expressExplanationOpen) _buildExpressExplanationPanel(contrast),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('braille.express_title'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 18)),
          ),
          _buildModeBadges(contrast),
          _buildWritingDotGrid(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text('braille.express_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 13)),
          ),
          _buildWritingActions(),
          // Полето за пишување - ограничена висина, со скрол и расте нагоре
          // со секој нов ред.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 170),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: hc ? Colors.white : contrast.withOpacity(0.25), width: hc ? 2 : 1.5),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: _buildExpressComposedText(contrast),
                    ),
                  ),
                ),
                // Копчиња ДЕСНО од полето: зачувај ја реченицата и преглед
                // на веќе зачуваните реченици.
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 4, bottom: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'braille.express_save'.tr(),
                        button: true,
                        child: Material(
                          color: _accent,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _saveCurrentSentence,
                            child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.save_rounded, color: Colors.white, size: 24)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        label: 'braille.express_preview'.tr(),
                        button: true,
                        child: Material(
                          color: Colors.white,
                          shape: CircleBorder(side: BorderSide(color: _accent, width: 1.5)),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _openSavedSentences,
                            child: Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.list_alt_rounded, color: _accent, size: 24)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: CategoryVoiceCommandButton(
              options: [
                VoiceCategoryOption(
                  keywords: ['зачувај реченица', 'зачувај', 'save sentence', 'save', 'ruaj fjalinë', 'ruaj'],
                  onSelected: _saveCurrentSentence,
                ),
                VoiceCategoryOption(
                  keywords: ['прегледај реченици', 'прегледај', 'преглед', 'preview sentences', 'preview', 'shiko fjalitë', 'shiko'],
                  onSelected: _openSavedSentences,
                ),
                ..._writingVoiceOptions(),
                ..._categoryVoiceOptions(),
              ],
              onBack: _backToCategories,
              compact: true,
              background: _accent,
              trigger: _voiceTrigger,
            ),
          ),
          _buildExpressKeyboardHint(contrast, 'braille.express_keyboard_hint'),
        ],
      ),
    );
  }

  /// Знакот што е изговорен со прв А (чека потврда) - како ќе се појави.
  String? _pendingPreviewText() {
    final p = _preview;
    if (p == null) return _composer.pendingCells.isNotEmpty ? '…' : null;
    if (p.status == BrailleDecodeStatus.prefix) return '…';
    final s = p.symbol!;
    switch (s.kind) {
      case BrailleKind.space:
        return '␣';
      case BrailleKind.letter:
        return _composer.capitalNext ? BrailleData.upper(s.char) : s.char;
      default:
        return s.char;
    }
  }

  /// Го прикажува текстот составен до момент: завршените реченици, тековниот
  /// ред и - подвлечен/во бојата на акцентот - знакот што е изговорен со А,
  /// но сеуште не е потврден.
  Widget _buildExpressComposedText(Color contrast) {
    final baseStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: contrast, height: 1.4);
    final pendingStyle = baseStyle.copyWith(color: _accent, decoration: TextDecoration.underline, decorationColor: _accent, decorationThickness: 2);

    final pending = _pendingPreviewText();
    final current = _composer.currentLineText;
    if (_composer.lines.isEmpty && current.isEmpty && pending == null) {
      return Text('braille.express_empty'.tr(), style: baseStyle.copyWith(color: contrast.withOpacity(0.4)));
    }

    final buffer = StringBuffer();
    for (final line in _composer.lines) {
      buffer.writeln(line);
    }
    buffer.write(current);

    final spans = <InlineSpan>[TextSpan(text: buffer.toString(), style: baseStyle)];
    if (pending != null) spans.add(TextSpan(text: pending, style: pendingStyle));
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildExpressExplanationButton(Color contrast) {
    final label = _expressExplanationOpen ? 'braille.express_explanation_toggle_close'.tr() : 'braille.express_explanation_toggle_open'.tr();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        label: label,
        button: true,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _toggleExpressExplanation,
            icon: Icon(_expressExplanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded, size: 26),
            label: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _expressExplanationOpen ? AccessibilityUtils.getDisabledColor(context) : _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpressExplanationPanel(Color contrast) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_rounded, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('braille.express_explanation_title'.tr(), style: GameTypography.heading(context, contrast, 17)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (_view == _View.sentenceGame ? 'braille.sentence_explanation_text' : 'braille.express_explanation_text').tr(),
            style: GameTypography.body(context, contrast, 15),
          ),
          const SizedBox(height: 12),
          _buildVoiceCommandsBox(
            contrast,
            _view == _View.sentenceGame ? 'braille.voice_cmds_sentence' : 'braille.voice_cmds_express',
          ),
        ],
      ),
    );
  }

  /// Нагласен преглед на гласовните команди (се активираат со Г или со
  /// копчето за гласовна команда).
  Widget _buildVoiceCommandsBox(Color contrast, String textKey) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.record_voice_over_rounded, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${'braille.voice_cmds_title'.tr()} ', style: GameTypography.heading(context, contrast, 15)),
                  TextSpan(text: textKey.tr(), style: GameTypography.body(context, contrast, 15).copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpressKeyboardHint(Color contrast, String textKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        textKey.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: contrast.withOpacity(0.9)),
      ),
    );
  }

  // --- „Пишувај реченици“ ---

  /// Текст за секој симбол од реченицата (со големите букви), за приказ.
  List<String> _tokenDisplayList(List<BrailleSymbol> tokens) {
    final out = <String>[];
    var capital = false;
    for (final t in tokens) {
      switch (t.kind) {
        case BrailleKind.capitalSign:
          capital = true;
          out.add(t.displayChar);
          break;
        case BrailleKind.letter:
          out.add(capital ? BrailleData.upper(t.char) : t.char);
          capital = false;
          break;
        case BrailleKind.space:
          capital = false;
          out.add(t.displayChar);
          break;
        default:
          out.add(t.displayChar);
      }
    }
    return out;
  }

  Widget _buildSentenceTarget(Color contrast, bool hc) {
    final labels = _tokenDisplayList(_sentenceTokens);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Semantics(
        label: _sentence?.text ?? '',
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 6,
          children: List.generate(_sentenceTokens.length, (i) {
            final tok = _sentenceTokens[i];
            final isDone = i < _sentenceStep;
            final isCurrent = i == _sentenceStep;
            final small = tok.isModifier || tok.kind == BrailleKind.space;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF16A34A) : (isCurrent ? _accent : Colors.transparent),
                border: Border.all(color: contrast.withOpacity(isCurrent ? 0.9 : 0.3), width: isCurrent ? 2 : 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: small ? 16 : 22,
                  fontWeight: FontWeight.bold,
                  color: (isDone || isCurrent) ? Colors.white : (hc ? Colors.white : contrast),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSentenceGame(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    if (_sentenceFinished) return _sentenceDoneScreen(contrast);
    if (_sentence == null) return const SizedBox.shrink();
    final current = _sentenceStep < _sentenceTokens.length ? _sentenceTokens[_sentenceStep] : null;
    final currentIsSign = current != null && current.kind != BrailleKind.letter && current.kind != BrailleKind.digit;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildBackRow(contrast, onBack: _backToCategories),
          _buildExpressExplanationButton(contrast),
          if (_expressExplanationOpen) _buildExpressExplanationPanel(contrast),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              '${'braille.sentence_title'.tr()}  ·  ${_sentenceCount + 1}/$_sentenceSessionTarget  ·  ${'braille.sentence_mistakes'.tr()}: $_sentenceMistakes',
              textAlign: TextAlign.center,
              style: GameTypography.heading(context, contrast, 17),
            ),
          ),
          _buildSentenceTarget(contrast, hc),
          if (currentIsSign)
            Text(_symbolName(current!), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 17)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Semantics(
                  label: 'braille.sentence_listen'.tr(),
                  button: true,
                  child: OutlinedButton.icon(
                    onPressed: () => _playSentenceAudio(),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: Text('braille.sentence_listen'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                Semantics(
                  label: 'braille.sentence_hint'.tr(),
                  button: true,
                  child: OutlinedButton.icon(
                    onPressed: _playSentenceHint,
                    icon: const Icon(Icons.lightbulb_rounded),
                    label: Text('braille.sentence_hint'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          _buildModeBadges(contrast),
          _buildWritingDotGrid(),
          _buildWritingActions(),
          Center(
            child: CategoryVoiceCommandButton(
              options: [
                VoiceCategoryOption(
                  keywords: [
                    'што следи', 'што е следно', 'следно', 'помош',
                    'what next', "what's next", 'whats next', 'next', 'hint', 'help',
                    'çfarë vjen', 'cfare vjen', 'më pas', 'ndihmë', 'ndihme',
                  ],
                  onSelected: _playSentenceHint,
                ),
                VoiceCategoryOption(
                  keywords: [
                    'преслушај ја реченицата', 'преслушај', 'слушни ја реченицата', 'слушај', 'повтори ја реченицата', 'повтори',
                    'listen to the sentence', 'listen', 'repeat the sentence', 'repeat', 'again',
                    'dëgjo fjalinë', 'degjo fjaline', 'dëgjo', 'degjo', 'përsërit', 'perserit',
                  ],
                  onSelected: () => _playSentenceAudio(),
                ),
                ..._writingVoiceOptions(),
                ..._categoryVoiceOptions(),
              ],
              onBack: _backToCategories,
              compact: true,
              background: _accent,
              trigger: _voiceTrigger,
            ),
          ),
          _buildExpressKeyboardHint(contrast, 'braille.sentence_keyboard_hint'),
        ],
      ),
    );
  }

  Widget _sentenceDoneScreen(Color contrast) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 72, color: _accent),
            const SizedBox(height: 16),
            Text(
              'braille.sentence_done_text'.tr(args: ['$_sentenceCount', '$_sentenceMistakesTotal']),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startSentenceGame,
              icon: const Icon(Icons.replay_rounded),
              label: Text('braille.sentence_again'.tr()),
              style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _backToCategories,
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text('braille.back'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  // --- Референтна мрежа (потсетник) ---

  /// Страница со сите зачувани реченици (од „Искажи ја својата мисла"), секоја
  /// со свое копче за бришење; гласовната команда тука ги препознава
  /// „избриши реченица" (ја брише последната зачувана) и „назад".
  Widget _buildSavedSentences(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _closeSavedSentences, withVoiceBack: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('braille.express_preview'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 20)),
        ),
        const SizedBox(height: 8),
        Center(
          child: CategoryVoiceCommandButton(
            options: [
              VoiceCategoryOption(
                keywords: ['избриши реченица', 'избриши', 'delete sentence', 'delete', 'fshi fjalinë', 'fshi'],
                onSelected: _deleteLastSavedSentenceByVoice,
              ),
              ..._categoryVoiceOptions(),
            ],
            onBack: _closeSavedSentences,
            compact: true,
            background: _accent,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _savedSentences.isEmpty
              ? Center(
                  child: Text(
                    'braille.express_no_saved'.tr(),
                    textAlign: TextAlign.center,
                    style: GameTypography.body(context, contrast, 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _savedSentences.length,
                  itemBuilder: (context, index) {
                    final sentence = _savedSentences[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: hc ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: hc ? Colors.white : contrast.withOpacity(0.2), width: hc ? 2 : 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(sentence, style: GameTypography.body(context, contrast, 17))),
                          Semantics(
                            label: 'braille.express_delete'.tr(),
                            button: true,
                            child: IconButton(
                              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                              onPressed: () => _deleteSavedSentence(index),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReferenceGrid(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _closeReference, withVoiceBack: true),
        Center(
          child: Semantics(
            button: true,
            label: _referenceListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
            child: Material(
              color: (_referenceListening ? _accent.withValues(alpha: 0.6) : _accent),
              borderRadius: BorderRadius.circular(18),
              elevation: 4,
              child: InkWell(
                onTap: _referenceListening ? null : _onReferenceMicTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_referenceListening ? Icons.mic_rounded : Icons.record_voice_over_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        _referenceListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('braille.letters'.tr(), style: GameTypography.heading(context, contrast, 20)),
                const SizedBox(height: 12),
                _buildReferenceRow(BrailleData.lettersFor(_lang), contrast),
                const SizedBox(height: 24),
                Text('braille.numbers'.tr(), style: GameTypography.heading(context, contrast, 20)),
                const SizedBox(height: 12),
                _buildReferenceRow(BrailleData.numbers, contrast),
                const SizedBox(height: 24),
                Text('braille.group_punct'.tr(), style: GameTypography.heading(context, contrast, 20)),
                const SizedBox(height: 12),
                _buildReferenceRow(BrailleData.punctuationFor(_lang), contrast),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceRow(List<BrailleSymbol> items, Color contrast) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: items
          .map((s) => _ReferenceCell(
                character: s.displayChar,
                semanticName: _symbolName(s),
                cells: s.cells,
                contrastColor: contrast,
                highlighted: _referenceHighlightKey == s.key,
                highlightColor: _accent,
                // Сега изговара и буквата И точките (со истите мп3 за точки).
                onTap: () => _highlightAndPlayReferenceSymbol(s),
              ))
          .toList(),
    );
  }

  /// Ги свети/осветлува ќелијата на притиснатата/изговорената буква/број
  /// додека трае изговорот, потоа се гаси.
  Future<void> _highlightAndPlayReferenceSymbol(BrailleSymbol s) async {
    final myToken = ++_referenceHighlightToken;
    setState(() => _referenceHighlightKey = s.key);
    await _playCharExplanationSequence(s);
    if (!mounted || myToken != _referenceHighlightToken) return;
    setState(() => _referenceHighlightKey = null);
  }

  /// Именувани форми на бројки (0-9) на трите јазици, за случај STT-то да
  /// го препознае изговорениот број како збор ("пет") наместо како цифра
  /// ("5") - двете форми треба да се совпаднат со истиот симбол.
  static const Map<String, String> _spokenDigitWords = {
    // mk
    'нула': '0', 'еден': '1', 'една': '1', 'два': '2', 'две': '2', 'три': '3', 'четири': '4',
    'пет': '5', 'шест': '6', 'седум': '7', 'осум': '8', 'девет': '9',
    // en
    'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
    // sq
    'zero0': '0', 'një': '1', 'nje': '1', 'dy': '2', 'tre': '3', 'katër': '4', 'kater': '4', 'pesë': '5', 'pese': '5',
    'gjashtë': '6', 'gjashte': '6', 'shtatë': '7', 'shtate': '7', 'tetë': '8', 'tete': '8', 'nëntë': '9', 'nente': '9',
  };

  /// Гласовна команда во потсетникот: ако корисникот ja изговори буквата
  /// (или бројот), се пали таа ќелија и се изговара со истите мп3 (буква +
  /// точки), исто како кога се притисне.
  Future<void> _startReferenceVoiceListen() async {
    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    final langCode = _langCode;

    final transcript = await orchestrator.listenOnce();
    if (!mounted) return;
    if (transcript == null || transcript.trim().isEmpty) {
      await _playVoiceFeedbackClip('not_recognized', langCode, voiceAssistant);
      return;
    }

    var t = transcript.toLowerCase().trim();
    // Прво знаците: препознавањето на говор често го враќа САМИОТ знак („?“,
    // „,“, „@“) наместо зборот, па тоа се проверува пред сè друго; потоа
    // имиња на знаци („прашалник“, „знак за број“...) - пред да се отстранат
    // префиксите како „број “ / „number “.
    final sign = _matchLiteralSign(t) ?? _matchSpokenSign(t.replaceAll(RegExp(r'[.,!?„“”"]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());
    for (final prefix in ['буква ', 'letter ', 'shkronja ', 'број ', 'broj ', 'numri ', 'number ']) {
      if (t.startsWith(prefix)) t = t.substring(prefix.length).trim();
    }
    t = t.replaceAll(RegExp(r'[.,!?]'), '').trim();

    final all = [...BrailleData.lettersFor(_lang), ...BrailleData.digits];
    BrailleSymbol? match = sign;
    for (final s in match == null ? all : const <BrailleSymbol>[]) {
      final target = s.char.toLowerCase();
      if (t == target || t.split(' ').contains(target)) {
        match = s;
        break;
      }
    }
    if (match == null) {
      final asDigit = _spokenDigitWords[t];
      if (asDigit != null) {
        for (final s in BrailleData.digits) {
          if (s.char == asDigit) {
            match = s;
            break;
          }
        }
      }
    }

    if (match != null) {
      await _highlightAndPlayReferenceSymbol(match);
    } else {
      await _playVoiceFeedbackClip('not_recognized', langCode, voiceAssistant);
    }
  }

  /// Изговорени имиња на знаците (mk/en/sq) → клуч на симболот.
  static const Map<String, List<String>> _spokenSignNames = {
    'space': ['празно место', 'празно', 'простор', 'space', 'blank', 'hapësirë', 'hapesire', 'hapësira'],
    'capital': ['голема буква', 'знак за голема', 'capital', 'shkronjë e madhe', 'shkronje e madhe', 'e madhe'],
    'number_sign': ['знак за број', 'бројен знак', 'number sign', 'numeric indicator', 'shenja e numrit', 'shenja numerike'],
    'semicolon': ['точка запирка', 'точка и запирка', 'semicolon', 'pikëpresj', 'pikepresj'],
    'colon': ['две точки', 'colon', 'dy pika'],
    'period': ['точка', 'period', 'full stop', 'dot', 'pikë', 'pike'],
    'comma': ['запирка', 'comma', 'presje'],
    'question': ['прашалник', 'знак прашалник', 'question', 'pikëpyetj', 'pikepyetj'],
    'exclamation': ['извичник', 'узвичник', 'exclamation', 'pikëçudit', 'pikecudit'],
    'hyphen': ['цртичка', 'црта', 'hyphen', 'dash', 'vizë', 'vize'],
    'apostrophe': ['апостроф', 'apostrophe', 'apostrof'],
    'quote_open': ['отворени наводници', 'наводници', 'open quote', 'quotation', 'quote', 'thonjëza', 'thonjeza'],
    'quote_close': ['затворени наводници', 'close quote', 'closing quote', 'mbyll thonjëzat'],
    'slash': ['коса црта', 'slash', 'vijë e pjerrët', 'vije e pjerret'],
    'at': ['мајмунче', 'мајмун', 'at sign', 'at symbol', 'majmun', 'majmunçe', 'shenja et'],
  };

  /// Ако транскриптот е само знак (пр. „?“ или „ ? “), го враќа тој знак.
  BrailleSymbol? _matchLiteralSign(String t) {
    final compact = t.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return null;
    final signs = BrailleData.punctuationFor(_lang).where((s) => s.kind == BrailleKind.punctuation).toList();
    for (final s in signs) {
      if (compact == s.char) return s;
    }
    // Наводници во било која форма.
    if (RegExp(r'^["„“”«»]$').hasMatch(compact)) {
      return signs.firstWhere((s) => s.key == 'quote_open');
    }
    // Само еден знак, евентуално со точка на крај што ја додава STT (пр. „?.“).
    final stripped = compact.replaceAll(RegExp(r'\.+$'), '');
    for (final s in signs) {
      if (stripped.isNotEmpty && stripped == s.char) return s;
    }
    return null;
  }

  /// Бара изговорено име на знак. Подолгите фрази се проверуваат прво
  /// (пр. „точка запирка“ пред „точка“, „коса црта“ пред „црта“). Зборовите
  /// се споредуваат и по почеток, за да се фатат и облиците со член
  /// („прашалникот“, „запирката“, „pikëpyetja“).
  BrailleSymbol? _matchSpokenSign(String t) {
    final phrases = <(String, String)>[
      for (final e in _spokenSignNames.entries)
        for (final p in e.value) (p, e.key),
    ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    final words = t.split(' ');
    for (final (phrase, key) in phrases) {
      final bool hit;
      if (phrase.contains(' ')) {
        hit = t.contains(phrase);
      } else if (phrase.length >= 5) {
        hit = words.any((w) => w.startsWith(phrase));
      } else {
        hit = words.contains(phrase);
      }
      if (!hit) continue;
      for (final s in BrailleData.punctuationFor(_lang)) {
        if (s.key == key) return s;
      }
    }
    return null;
  }

  Future<void> _playVoiceFeedbackClip(String key, String langCode, VoiceAssistantService voiceAssistant) async {
    bool reachedPlaying = false;
    try {
      await _voicePlayer.stop();
      await _voicePlayer.play(AssetSource('audio/voice/$langCode/$key.mp3'));
      reachedPlaying = true;
    } catch (_) {
      reachedPlaying = false;
    }
    if (!reachedPlaying) {
      await voiceAssistant.speakWithLanguage('voice.$key'.tr(), langCode, vibrate: false);
    }
  }

  Widget _buildKeyboardHint(Color contrast) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'braille.keyboard_hint'.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: contrast.withOpacity(0.9)),
      ),
    );
  }

  /// Ред со копче назад. Со `withVoiceBack` или `voiceOptions` има и копче
  /// за гласовна команда („назад“ + дадените опции + имиња на други игри).
  Widget _buildBackRow(
    Color contrast, {
    required VoidCallback onBack,
    bool withVoiceBack = false,
    List<VoiceCategoryOption>? voiceOptions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Semantics(label: 'braille.back'.tr(), button: true, child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: contrast), onPressed: onBack)),
          if (withVoiceBack || voiceOptions != null) ...[
            const SizedBox(width: 8),
            // Покрај „назад“ и локалните опции: имињата на другите групи и
            // вежби во Брајовата азбука (пр. од „Состави“ директно „група 2“),
            // а преку копчето - и имињата на другите игри.
            CategoryVoiceCommandButton(
              options: [...?voiceOptions, ..._categoryVoiceOptions()],
              onBack: onBack,
              compact: true,
              background: _accent,
            ),
          ],
        ],
      ),
    );
  }
}

/// Лева/десна зона за навигација.
class _NavZone extends StatefulWidget {
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool highContrast;

  const _NavZone({required this.enabled, required this.icon, required this.onTap, required this.label, required this.highContrast});

  @override
  State<_NavZone> createState() => _NavZoneState();
}

class _NavZoneState extends State<_NavZone> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.enabled ? widget.onTap : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_pressed) Container(color: Colors.black.withOpacity(0.2)),
            Opacity(
              opacity: widget.enabled ? 1.0 : 0.25,
              child: Center(child: Icon(widget.icon, size: 72, color: widget.highContrast ? Colors.white : Colors.black.withOpacity(0.55))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceCell extends StatelessWidget {
  final String character;
  final String semanticName;
  final List<List<int>> cells;
  final Color contrastColor;
  final VoidCallback onTap;
  final bool highlighted;
  final Color? highlightColor;

  const _ReferenceCell({
    required this.character,
    required this.semanticName,
    required this.cells,
    required this.contrastColor,
    required this.onTap,
    this.highlighted = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final buttonSize = AccessibilityUtils.getButtonSize(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final accent = highlightColor ?? const Color(0xFF4F46E5);

    return Semantics(
      label: 'braille.cell'.tr(args: [semanticName]),
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: (cells.length > 1 ? 124 : 100) * buttonSize,
            padding: EdgeInsets.all(16 * buttonSize),
            decoration: BoxDecoration(
              color: highlighted ? accent.withValues(alpha: hc ? 0.25 : 0.18) : (hc ? Colors.transparent : Colors.white.withValues(alpha: 0.95)),
              border: Border.all(color: highlighted ? accent : contrastColor, width: highlighted ? 4 : (hc ? 2 : 2.5)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: hc
                  ? const <BoxShadow>[]
                  : (highlighted ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)] : AppStyle.cardShadow(false)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(character, style: TextStyle(fontSize: 30 * buttonSize, fontWeight: FontWeight.bold, color: contrastColor)),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < cells.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _ReferenceDots(dots: cells[i], contrastColor: contrastColor, size: 28),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceDots extends StatelessWidget {
  final List<int> dots;
  final Color contrastColor;
  final double size;

  const _ReferenceDots({required this.dots, required this.contrastColor, this.size = 24});

  bool _isRaised(int dot) => dots.contains(dot);

  @override
  Widget build(BuildContext context) {
    final dotSize = size * 0.32;
    final gap = size * 0.12;
    const layout = [
      [1, 4],
      [2, 5],
      [3, 6],
    ];

    return SizedBox(
      width: size,
      height: size * 1.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < 3; r++) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(raised: _isRaised(layout[r][0]), color: contrastColor, size: dotSize),
                SizedBox(width: gap),
                _Dot(raised: _isRaised(layout[r][1]), color: contrastColor, size: dotSize),
              ],
            ),
            if (r < 2) SizedBox(height: gap),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool raised;
  final Color color;
  final double size;

  const _Dot({required this.raised, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: raised ? color : color.withValues(alpha: 0.2), border: Border.all(color: color, width: raised ? 1.5 : 1)),
    );
  }
}