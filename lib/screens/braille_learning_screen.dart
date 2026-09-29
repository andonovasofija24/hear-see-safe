import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

/// Едно писмо/број во Брајовата азбука.
/// `key` е ФИКСЕН, рачно определен ASCII-безбеден идентификатор за име на
/// мп3 датотека (audio/braille/<јазик>/char_<key>.mp3) - НЕ се пресметува
/// од `char` во моментот на извршување (без regex/Unicode ризик).
class BrailleSymbol {
  final String char;
  final String key;
  final List<int> dots;
  const BrailleSymbol(this.char, this.key, this.dots);
}

class BrailleGroup {
  final String titleKey;
  final List<BrailleSymbol> symbols;
  const BrailleGroup(this.titleKey, this.symbols);
}

enum BrailleLang { mk, sq, en }

/// Извор: македонски и албански Брајов код според Wikipedia „Yugoslav
/// Braille“ / „Albanian Braille“ (базирано на UNESCO „World Braille
/// Usage“, 2013). Англискиот е стандарден Grade 1 Брај. Секоја листа е
/// подредена по АЗБУЧЕН РЕД (се користи и за потсетникот и како основа за
/// групирање).
class BrailleData {
  static const List<BrailleSymbol> _mk = [
    BrailleSymbol('а', 'а', [1]), BrailleSymbol('б', 'б', [1, 2]), BrailleSymbol('в', 'в', [1, 2, 3, 6]),
    BrailleSymbol('г', 'г', [1, 2, 4, 5]), BrailleSymbol('д', 'д', [1, 4, 5]), BrailleSymbol('ѓ', 'ѓ', [3, 4, 5]),
    BrailleSymbol('е', 'е', [1, 5]), BrailleSymbol('ж', 'ж', [2, 3, 4, 6]), BrailleSymbol('з', 'з', [1, 3, 5, 6]),
    BrailleSymbol('ѕ', 'ѕ', [1, 2, 5, 6]), BrailleSymbol('и', 'и', [2, 4]), BrailleSymbol('ј', 'ј', [2, 4, 5]),
    BrailleSymbol('к', 'к', [1, 3]), BrailleSymbol('л', 'л', [1, 2, 3]), BrailleSymbol('љ', 'љ', [1, 2, 6]),
    BrailleSymbol('м', 'м', [1, 3, 4]), BrailleSymbol('н', 'н', [1, 3, 4, 5]), BrailleSymbol('њ', 'њ', [1, 2, 4, 6]),
    BrailleSymbol('о', 'о', [1, 3, 5]), BrailleSymbol('п', 'п', [1, 2, 3, 4]), BrailleSymbol('р', 'р', [1, 2, 3, 5]),
    BrailleSymbol('с', 'с', [2, 3, 4]), BrailleSymbol('т', 'т', [2, 3, 4, 5]), BrailleSymbol('ќ', 'ќ', [3, 4]),
    BrailleSymbol('у', 'у', [1, 3, 6]), BrailleSymbol('ф', 'ф', [1, 2, 4]), BrailleSymbol('х', 'х', [1, 2, 5]),
    BrailleSymbol('ц', 'ц', [1, 4]), BrailleSymbol('ч', 'ч', [1, 6]), BrailleSymbol('џ', 'џ', [1, 2, 4, 5, 6]),
    BrailleSymbol('ш', 'ш', [1, 5, 6]),
  ];

  /// Букви кои немаат едноставен латиничен еквивалент од само една буква
  /// (бараат дигрaф/дијакритик) - специфични за македонскиот.
  static const Set<String> _mkSpecial = {'ѓ', 'ѕ', 'љ', 'њ', 'ќ', 'џ'};

  static const List<BrailleSymbol> _sq = [
    BrailleSymbol('a', 'a', [1]), BrailleSymbol('b', 'b', [1, 2]), BrailleSymbol('c', 'c', [1, 4]),
    BrailleSymbol('ç', 'ch', [1, 4, 6]), BrailleSymbol('d', 'd', [1, 4, 5]), BrailleSymbol('dh', 'dh', [1, 4, 5, 6]),
    BrailleSymbol('e', 'e', [1, 5]), BrailleSymbol('ë', 'ee', [1, 6]), BrailleSymbol('f', 'f', [1, 2, 4]),
    BrailleSymbol('g', 'g', [1, 2, 4, 5]), BrailleSymbol('gj', 'gj', [1, 2, 4, 5, 6]), BrailleSymbol('h', 'h', [1, 2, 5]),
    BrailleSymbol('i', 'i', [2, 4]), BrailleSymbol('j', 'j', [2, 4, 5]), BrailleSymbol('k', 'k', [1, 3]),
    BrailleSymbol('l', 'l', [1, 2, 3]), BrailleSymbol('ll', 'll', [1, 2, 3, 5, 6]), BrailleSymbol('m', 'm', [1, 3, 4]),
    BrailleSymbol('n', 'n', [1, 3, 4, 5]), BrailleSymbol('nj', 'nj', [1, 2, 4, 6]), BrailleSymbol('o', 'o', [1, 3, 5]),
    BrailleSymbol('p', 'p', [1, 2, 3, 4]), BrailleSymbol('q', 'q', [1, 2, 3, 4, 6]), BrailleSymbol('r', 'r', [1, 2, 3, 5]),
    BrailleSymbol('rr', 'rr', [1, 2, 3, 4, 5]), BrailleSymbol('s', 's', [2, 3, 4]), BrailleSymbol('sh', 'sh', [1, 5, 6]),
    BrailleSymbol('t', 't', [2, 3, 4, 5]), BrailleSymbol('th', 'th', [2, 3, 4, 5, 6]), BrailleSymbol('u', 'u', [1, 3, 6]),
    BrailleSymbol('v', 'v', [1, 2, 3, 6]), BrailleSymbol('x', 'x', [1, 3, 4, 6]), BrailleSymbol('xh', 'xh', [2, 3, 4, 6]),
    BrailleSymbol('y', 'y', [1, 3, 4, 5, 6]), BrailleSymbol('z', 'z', [1, 3, 5, 6]), BrailleSymbol('zh', 'zh', [1, 2, 5, 6]),
  ];

  /// Деветте дигрaфи на албанската азбука - секој е ЕДНО писмо со две
  /// латинични букви.
  static const Set<String> _sqSpecial = {'dh', 'gj', 'll', 'nj', 'rr', 'sh', 'th', 'xh', 'zh'};

  static const List<BrailleSymbol> _en = [
    BrailleSymbol('A', 'A', [1]), BrailleSymbol('B', 'B', [1, 2]), BrailleSymbol('C', 'C', [1, 4]),
    BrailleSymbol('D', 'D', [1, 4, 5]), BrailleSymbol('E', 'E', [1, 5]), BrailleSymbol('F', 'F', [1, 2, 4]),
    BrailleSymbol('G', 'G', [1, 2, 4, 5]), BrailleSymbol('H', 'H', [1, 2, 5]), BrailleSymbol('I', 'I', [2, 4]),
    BrailleSymbol('J', 'J', [2, 4, 5]), BrailleSymbol('K', 'K', [1, 3]), BrailleSymbol('L', 'L', [1, 2, 3]),
    BrailleSymbol('M', 'M', [1, 3, 4]), BrailleSymbol('N', 'N', [1, 3, 4, 5]), BrailleSymbol('O', 'O', [1, 3, 5]),
    BrailleSymbol('P', 'P', [1, 2, 3, 4]), BrailleSymbol('Q', 'Q', [1, 2, 3, 4, 5]), BrailleSymbol('R', 'R', [1, 2, 3, 5]),
    BrailleSymbol('S', 'S', [2, 3, 4]), BrailleSymbol('T', 'T', [2, 3, 4, 5]), BrailleSymbol('U', 'U', [1, 3, 6]),
    BrailleSymbol('V', 'V', [1, 2, 3, 6]), BrailleSymbol('W', 'W', [2, 4, 5, 6]), BrailleSymbol('X', 'X', [1, 3, 4, 6]),
    BrailleSymbol('Y', 'Y', [1, 3, 4, 5, 6]), BrailleSymbol('Z', 'Z', [1, 3, 5, 6]),
  ];

  static const Set<String> _enSpecial = {};

  static const List<BrailleSymbol> numbers = [
    BrailleSymbol('1', '1', [1]), BrailleSymbol('2', '2', [1, 2]), BrailleSymbol('3', '3', [1, 4]),
    BrailleSymbol('4', '4', [1, 4, 5]), BrailleSymbol('5', '5', [1, 5]), BrailleSymbol('6', '6', [1, 2, 4]),
    BrailleSymbol('7', '7', [1, 2, 4, 5]), BrailleSymbol('8', '8', [1, 2, 5]), BrailleSymbol('9', '9', [2, 4]),
    BrailleSymbol('0', '0', [2, 4, 5]),
  ];

  static List<BrailleSymbol> lettersFor(BrailleLang lang) {
    switch (lang) {
      case BrailleLang.mk:
        return _mk;
      case BrailleLang.sq:
        return _sq;
      case BrailleLang.en:
        return _en;
    }
  }

  static Set<String> _specialFor(BrailleLang lang) {
    switch (lang) {
      case BrailleLang.mk:
        return _mkSpecial;
      case BrailleLang.sq:
        return _sqSpecial;
      case BrailleLang.en:
        return _enSpecial;
    }
  }

  /// Групи: Ниво 1 = само точки {1,2,4,5}, Ниво 2 = +точка 3, Ниво 3 =
  /// +точка 6 (без специфичните знаци), потоа посебна група за
  /// специфичните знаци (ако ги има за тој јазик), па Броеви.
  static List<BrailleGroup> groupsFor(BrailleLang lang) {
    final letters = lettersFor(lang);
    final special = _specialFor(lang);
    final g1 = <BrailleSymbol>[], g2 = <BrailleSymbol>[], g3 = <BrailleSymbol>[], gSpecial = <BrailleSymbol>[];
    for (final s in letters) {
      if (special.contains(s.char)) {
        gSpecial.add(s);
        continue;
      }
      final set = s.dots.toSet();
      if (set.difference({1, 2, 4, 5}).isEmpty) {
        g1.add(s);
      } else if (!set.contains(6)) {
        g2.add(s);
      } else {
        g3.add(s);
      }
    }
    final result = [
      BrailleGroup('braille.group1', g1),
      BrailleGroup('braille.group2', g2),
      BrailleGroup('braille.group3', g3),
    ];
    if (gSpecial.isNotEmpty) result.add(BrailleGroup('braille.group_special', gSpecial));
    result.add(BrailleGroup('braille.group_numbers', numbers));
    return result;
  }

  /// ВАЖНО: секој збор мора да е во ИСТА големина на букви како симболите
  /// во листите погоре (_mk/_sq се мали букви, _en се големи) - со цел да
  /// не зависиме од .toLowerCase() за кирилица (ризично на некои
  /// платформи/веб). Дополни ги слободно, само чувај ја истата големина.
  static const Map<BrailleLang, List<String>> words = {
    BrailleLang.mk: [
      'баба', 'дедо', 'гајда', 'мама', 'татко', 'куќа', 'чаша',
      'вода', 'нога', 'рака', 'глава', 'лице', 'село', 'коса', 'риба',
    ],
    // Само еден потврден едноставен збор - albanски речник треба да се
    // прошири рачно (не сум сигурен во точноста на дополнителни зборови).
    BrailleLang.sq: ['baba'],
    BrailleLang.en: [
      'BAG', 'CAB', 'FED', 'ACE', 'CAGE', 'FACE', 'BEAD',
      'DOG', 'CAT', 'HAT', 'BED', 'EGG', 'ICE', 'JAM', 'KID',
    ],
  };

  /// Низи од бројки за играта со зборови - исти за сите јазици (бидејќи
  /// цифрите се исти без разлика на писмото).
  static const List<String> numberWords = [
    '12', '34', '56', '78', '90', '123', '456', '789',
    '321', '09', '21', '43', '65', '87', '10',
  ];
}

class BrailleLearningScreen extends StatefulWidget {
  const BrailleLearningScreen({super.key});

  @override
  State<BrailleLearningScreen> createState() => _BrailleLearningScreenState();
}

enum _View { categorySelect, explore, practiceModeSelect, practiceCompose, practiceRecognize, practiceWrite, wordRound, expressThought, reference }

class _BrailleLearningScreenState extends State<BrailleLearningScreen> {
  static const Color _accent = Color(0xFF4F46E5);

  late VoiceAssistantService _voiceAssistant;
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  PageController? _explorePageController;

  static final Map<LogicalKeyboardKey, int> _keyToDot = {
    LogicalKeyboardKey.keyF: 0,
    LogicalKeyboardKey.keyD: 1,
    LogicalKeyboardKey.keyS: 2,
    LogicalKeyboardKey.keyJ: 3,
    LogicalKeyboardKey.keyK: 4,
    LogicalKeyboardKey.keyL: 5,
  };

  static const List<String> _positionNames = [
    'braille.pos1', 'braille.pos2', 'braille.pos3', 'braille.pos4', 'braille.pos5', 'braille.pos6',
  ];

  static const List<String> _keyLetters = ['F', 'D', 'S', 'J', 'K', 'L'];

  _View _view = _View.categorySelect;
  /// Од каде е отворен потсетникот (_View.reference) - за да враќањето со
  /// назад-копчето оди точно таму (главно мени или „Искажи ја својата
  /// мисла"), а не секогаш кон главното мени.
  _View _viewBeforeReference = _View.categorySelect;
  int _groupIndex = 0;
  int _symbolIndex = 0;
  int _narrationToken = 0;

  /// Додека е true, категориите (групи/потсетник/игра со зборови) се
  /// заклучени - воведот самиот е СЕКОГАШ видлив, ова важи само за
  /// содржината подолу.
  bool _introLocked = true;

  final Set<String> _exploredKeys = {};

  BrailleSymbol? _practiceTarget;
  List<BrailleSymbol> _practicePool = [];
  int _practiceRound = 0;
  static const int _practiceRoundsTotal = 8;
  int _practiceScore = 0;
  bool _practiceFinished = false;
  final Set<int> _correctDotsHit = {};
  bool _writeFailed = false;
  List<BrailleSymbol> _recognizeChoices = [];
  String? _recognizePicked;
  bool _recognizeWasCorrect = false;

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  String? _currentWord;
  int _wordLetterIndex = 0;
  /// Точки веќе погодени за тековната буква во Играта со зборови - иста
  /// логика како Состави (точка-по-точка, без акорд).
  final Set<int> _wordCorrectDotsHit = {};

  // --- „Искажи ја својата мисла" (слободно пишување буква-по-буква) ---
  /// Веќе завршени редови (реченици) - секој ред е простор одделен низ
  /// зборови, се додава кога корисникот ќе притисне Х.
  final List<String> _expressLines = [];
  /// Зборови веќе затворени (со Г или Х) на тековниот, сеуште отворен ред.
  final List<String> _expressCurrentLineWords = [];
  /// Букви потврдени (со А/Г/Х) за зборот кој моментално се пишува.
  final List<String> _expressCurrentWordLetters = [];
  /// Точки притиснати за буквата која сеуште не е ниту прегледана ниту
  /// потврдена.
  final Set<int> _expressCurrentDots = {};
  /// Буквата која штотуку е изговорена со прв притисок на А, но сеуште не е
  /// потврдена (чека втор А / Г / Х, или „:" за поништување).
  BrailleSymbol? _expressPreviewedSymbol;
  bool _expressExplanationOpen = false;

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
  // јазикот (наместо секој пристап да прегради нови BrailleSymbol
  // инстанци, што ќе ги расипеше споредбите со идентитет како .remove()).
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

  Set<String> get _allExploredChars {
    final result = <String>{};
    for (var g = 0; g < _groups.length; g++) {
      for (final s in _groups[g].symbols) {
        if (_exploredKeys.contains('$g:${s.char}')) result.add(s.char);
      }
    }
    return result;
  }

  bool _isGroupFullyExplored(int index) {
    for (final s in _groups[index].symbols) {
      if (!_exploredKeys.contains('$index:${s.char}')) return false;
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
  /// не притисне на копчето „стоп" на дното на воведот, кое веднаш го
  /// прекинува звукот и ги отклучува категориите. Самиот вовед (текст +
  /// асоцијации) е СЕКОГАШ целосно видлив - заклучувањето важи само за
  /// категориите подолу.
  Future<void> _startIntroLockSequence() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _playClipAwaitingCompletion('game_name', timeout: const Duration(seconds: 8));
    if (!mounted) return;
    setState(() => _introLocked = false);
  }

  /// Рачно копче „стоп" - веднаш го прекинува звукот на воведот и ги
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
    super.dispose();
  }

  // =====================================================================
  // Звук - ИСКЛУЧИВО однапред снимени мп3 клипови. Ако клипот не постои,
  // не се пушта НИШТО (без TTS-резерва) - намерно, по барање.
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
    await _playClip('char_${s.key}');
  }

  /// Игра еден клип и ЧЕКА тој навистина да заврши (или да истече рокот)
  /// пред да се врати - потребно за секвенцијално пуштање.
  Future<void> _playClipAwaitingCompletion(String key, {Duration timeout = const Duration(seconds: 6)}) async {
    if (!mounted) return;
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
  }

  /// Составен звук: прво буквата (напр. "Буква Б"), потоа по ред звукот
  /// за секоја точка што ја сочинува. Ги користи ИСТИТЕ 6 датотеки за
  /// точки за сите букви.
  Future<void> _playCharExplanationSequence(BrailleSymbol s) async {
    final myToken = ++_narrationToken;
    await _playClipAwaitingCompletion('char_${s.key}');
    for (final d in s.dots) {
      if (myToken != _narrationToken || !mounted) return;
      await _playClipAwaitingCompletion('dot_$d');
    }
  }

  /// За вежбата „Препознај": апликацијата е за слепи лица кои не можат да
  /// ја видат сликата со точки (_bigDotDisplay), па наместо (или покрај)
  /// визуелниот приказ, по прашањето („recognize_prompt") по ред се
  /// пуштаат звуците за секоја точка што ја сочинува бараната буква/број
  /// (dot_1, dot_2 итн). Намерно НЕ се изговара самата буква - тоа би го
  /// издало точниот одговор пред корисникот да избере.
  Future<void> _playRecognizeDotsSequence(BrailleSymbol target) async {
    final myToken = ++_narrationToken;
    await _playClipAwaitingCompletion('recognize_prompt');
    for (final d in target.dots) {
      if (myToken != _narrationToken || !mounted) return;
      await _playClipAwaitingCompletion('dot_$d');
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

  /// Дали тековно отворената група е групата со броеви - користи се за да
  /// сликовницата зборува за „број", а не за „буква", кога се прикажуваат
  /// цифри.
  bool get _isNumberGroup => _group.titleKey == 'braille.group_numbers';

  String _explanationFor(BrailleSymbol s) {
    final dotList = s.dots.map((d) => '${'braille.dot'.tr()} $d ${_positionNames[d - 1].tr()}').join(', ');
    final templateKey = _isNumberGroup ? 'braille.explanation_template_number' : 'braille.explanation_template';
    return templateKey.tr(args: [s.char, dotList]);
  }

  // =====================================================================
  // Влез: тастатура.
  // =====================================================================

  /// Секое копче (F D S / J K L) веднаш регистрира "допир" на таа точка -
  /// исто однесување за Состави, Напиши и Игра со зборови (точка-по-точка,
  /// без чекање акорд).
  ///
  /// Во „Искажи ја својата мисла" (откако точките за буквата се веќе
  /// притиснати):
  ///  - А (прв пат) - ЈА ИЗГОВОРУВА буквата формирана од притиснатите точки
  ///    (преглед, сеуште не е потврдена);
  ///  - А (втор пат, веднаш по прегледот) - ја ПОТВРДУВА буквата како точна
  ///    и продолжува со следната буква од ИСТИОТ збор;
  ///  - Г (по прегледот со А) - ја потврдува буквата И го затвора зборот
  ///    (се додава празно место, продолжува нов збор на ИСТИОТ ред);
  ///  - Х (по прегледот со А) - ја потврдува буквата, го затвора зборот И
  ///    го затвора целиот ред/реченица (почнува НОВ РЕД);
  ///  - „:" - ја поништува тековната буква (која сеуште не е потврдена) за
  ///    да се внесат точките од почеток;
  ///  - П - го отвора потсетникот (азбука + бројки), достапен од оваа игра.
  static const LogicalKeyboardKey _expressPreviewKey = LogicalKeyboardKey.keyA;
  static const LogicalKeyboardKey _expressEndWordKey = LogicalKeyboardKey.keyG;
  static const LogicalKeyboardKey _expressEndLineKey = LogicalKeyboardKey.keyH;
  static const LogicalKeyboardKey _expressResetKey = LogicalKeyboardKey.semicolon;
  static const LogicalKeyboardKey _expressReferenceKey = LogicalKeyboardKey.keyP;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    // Во потсетникот: ако е отворен од „Искажи ja својата мисла", повторно
    // притискање на П враќа точно таму (напишаното останува зачувано).
    if (_view == _View.reference && key == _expressReferenceKey && _viewBeforeReference == _View.expressThought) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) {
          _closeReference();
        }
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_view == _View.expressThought &&
        (key == _expressPreviewKey ||
            key == _expressEndWordKey ||
            key == _expressEndLineKey ||
            key == _expressResetKey ||
            key == _expressReferenceKey)) {
      if (event is KeyDownEvent) {
        if (_pressedKeys.add(key)) {
          if (key == _expressPreviewKey) {
            _expressPreviewOrConfirmLetter();
          } else if (key == _expressEndWordKey) {
            _expressCommitLetter(endWord: true, endLine: false);
          } else if (key == _expressEndLineKey) {
            _expressCommitLetter(endWord: true, endLine: true);
          } else if (key == _expressResetKey) {
            _expressResetCurrentLetter();
          } else if (key == _expressReferenceKey) {
            _openReference(_View.expressThought);
          }
        }
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final dot = _keyToDot[key];
    if (dot == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (_pressedKeys.add(key)) {
        if (_view == _View.practiceCompose) {
          _tapComposeDot(dot);
        } else if (_view == _View.practiceWrite) {
          _tapWriteDot(dot);
        } else if (_view == _View.wordRound) {
          _tapWordDot(dot);
        } else if (_view == _View.expressThought) {
          _tapExpressDot(dot);
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

  /// Целосно ресетирање на состојбата на вежбање - се повикува секогаш
  /// кога се напушта екран за вежбање, за да не остане "заглавена"
  /// состојба (селектирани/погрешни точки) при следен влез.
  void _resetPracticeState() {
    _practiceTarget = null;
    _practiceFinished = false;
    _correctDotsHit.clear();
    _writeFailed = false;
    _recognizePicked = null;
    _practiceRound = 0;
  }

  void _backToCategories() {
    _narrationToken++;
    if (_view == _View.explore && _group.symbols.isNotEmpty) {
      _exploredKeys.add('$_groupIndex:${_group.symbols[_symbolIndex].char}');
    }
    _voiceAssistant.stop();
    _voicePlayer.stop();
    setState(() {
      _resetPracticeState();
      _currentWord = null;
      _expressLines.clear();
      _expressCurrentLineWords.clear();
      _expressCurrentWordLetters.clear();
      _expressCurrentDots.clear();
      _expressPreviewedSymbol = null;
      _expressExplanationOpen = false;
      _view = _View.categorySelect;
    });
  }

  /// Го отвора потсетникот, паметејќи од кој екран е повикан за назад-
  /// копчето да врати точно таму (пр. „Искажи ja својата мисла" го чува
  /// напишаното додека е во потсетникот).
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
    _exploredKeys.add('$_groupIndex:${_group.symbols[_symbolIndex].char}');
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
  // Фаза 2: Практика - избор на режим (+ Игра со зборови, ист мени).
  // =====================================================================

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
    _practicePool = List<BrailleSymbol>.from(_group.symbols)..shuffle(_random);
    _practiceScore = 0;
    setState(() => _view = mode);
    _nextPracticeRound();
  }

  /// Состави е вежбање без цел/број рунди - циклично поминува низ сите
  /// букви од групата, без резултат.
  void _nextPracticeRound() {
    final isCompose = _view == _View.practiceCompose;
    if (!isCompose && (_practiceRound >= _practiceRoundsTotal || _practiceRound >= _practicePool.length * 3)) {
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
      _correctDotsHit.clear();
      _writeFailed = false;
      _recognizePicked = null;
      if (_view == _View.practiceRecognize) {
        final others = List<BrailleSymbol>.from(_group.symbols)..remove(target);
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

  Future<void> _tapComposeDot(int dotIndex) async {
    if (_practiceTarget == null) return;
    final target = _practiceTarget!.dots.map((d) => d - 1).toSet();
    final isCorrect = target.contains(dotIndex);

    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(
        duration: isCorrect ? 150 : null,
        pattern: isCorrect ? null : const [0, 80, 60, 80],
      );
    }

    if (isCorrect) {
      setState(() => _correctDotsHit.add(dotIndex));
      await _playPongEffect('hit.mp3');
      if (_correctDotsHit.length == target.length) {
        setState(() => _practiceScore++);
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted || _view != _View.practiceCompose) return;
        setState(() => _practiceRound++);
        _nextPracticeRound();
      }
    } else {
      await _playPongEffect('miss.mp3');
    }
  }

  Future<void> _tapWriteDot(int dotIndex) async {
    if (_practiceTarget == null || _writeFailed) return;
    final target = _practiceTarget!.dots.map((d) => d - 1).toSet();
    final isCorrect = target.contains(dotIndex);

    if (isCorrect) {
      setState(() => _correctDotsHit.add(dotIndex));
      if (await VibrationUtils.hasVibrator()) await VibrationUtils.vibrate(duration: 150);
      if (_correctDotsHit.length == target.length) {
        setState(() => _practiceScore++);
        await _playPongEffect('hit.mp3');
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted || _view != _View.practiceWrite) return;
        setState(() => _practiceRound++);
        _nextPracticeRound();
      }
    } else {
      setState(() => _writeFailed = true);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
      await _playPongEffect('miss.mp3');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted || _view != _View.practiceWrite) return;
      setState(() => _practiceRound++);
      _nextPracticeRound();
    }
  }

  Future<void> _pickRecognizeAnswer(BrailleSymbol choice) async {
    if (_practiceTarget == null || _recognizePicked != null) return;
    final correct = choice.char == _practiceTarget!.char;
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(
        duration: correct ? 200 : null,
        pattern: correct ? null : const [0, 120, 100, 120],
      );
    }
    if (correct) setState(() => _practiceScore++);
    await _playPongEffect(correct ? 'hit.mp3' : 'miss.mp3');
    setState(() {
      _recognizePicked = choice.char;
      _recognizeWasCorrect = correct;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || _view != _View.practiceRecognize) return;
    setState(() => _practiceRound++);
    _nextPracticeRound();
  }

  // =====================================================================
  // Игра со зборови.
  // =====================================================================

  static const int _wordSessionTarget = 5;
  int _wordSessionCount = 0;

  /// Игра со зборови - секогаш достапна од главното мени, без разлика дали
  /// корисникот воопшто отворил некоја категорија (не бара претходно
  /// истражување). Секоја сесија бара 5 точно составени зборови/броеви по ред.
  void _startWordSession() {
    _narrationToken++;
    _wordSessionCount = 0;
    _pickNextWord();
  }

  List<String> _wordCandidates() {
    final letters = BrailleData.words[_lang] ?? [];
    final numbers = BrailleData.numberWords;
    return [...letters, ...numbers];
  }

  void _pickNextWord() {
    final candidates = _wordCandidates();
    if (candidates.isEmpty) {
      _playClip('word_round_unavailable');
      if (_view == _View.wordRound) setState(() => _view = _View.categorySelect);
      return;
    }
    setState(() {
      _currentWord = candidates[_random.nextInt(candidates.length)];
      _wordLetterIndex = 0;
      _wordCorrectDotsHit.clear();
      _view = _View.wordRound;
    });
    final s = _symbolForChar(_currentWord![0]);
    if (s != null) _playCharClip(s);
  }

  BrailleSymbol? _symbolForChar(String ch) {
    for (final g in _groups) {
      for (final s in g.symbols) {
        if (s.char == ch) return s;
      }
    }
    return null;
  }

  /// Точка-по-точка (исто како Состави): точна точка - светнува и останува
  /// селектирана; неточна - без визуелна промена (само звук+вибрација).
  /// Штом сите точни точки за тековната буква се селектирани, се преминува
  /// на следната буква, а по 5 зборови - сесијата завршува.
  Future<void> _tapWordDot(int dotIndex) async {
    if (_currentWord == null) return;
    final symbol = _symbolForChar(_currentWord![_wordLetterIndex]);
    if (symbol == null) return;
    final target = symbol.dots.map((d) => d - 1).toSet();
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

    setState(() => _wordCorrectDotsHit.add(dotIndex));
    await _playPongEffect('hit.mp3');
    if (_wordCorrectDotsHit.length < target.length) return;

    final wordDone = _wordLetterIndex + 1 >= _currentWord!.length;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted || _view != _View.wordRound) return;

    if (!wordDone) {
      setState(() {
        _wordLetterIndex++;
        _wordCorrectDotsHit.clear();
      });
      final next = _symbolForChar(_currentWord![_wordLetterIndex]);
      if (next != null) _playCharClip(next);
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
  // „Искажи ја својата мисла" - слободно пишување буква-по-буква, со
  // преглед пред потврда (наменето за слепи корисници кои не гледаат
  // видлива повратна информација). Достапно од главното мени.
  //
  // Контроли (по притискање на точките F D S J K L за буквата):
  //  - А (прв пат)  - ЈА ИЗГОВОРУВА буквата формирана од точките (преглед);
  //  - А (втор пат) - ја ПОТВРДУВА буквата, продолжува ИСТИОТ збор;
  //  - Г            - ја потврдува буквата И го затвора зборот (нов збор,
  //                   ИСТ ред);
  //  - Х            - ја потврдува буквата, го затвора зборот И редот
  //                   (нов ред - нова реченица);
  //  - „:"          - ја поништува тековната (сеуште непотврдена) буква;
  //  - П            - го отвора потсетникот.
  // =====================================================================

  void _startExpressThought() {
    _narrationToken++;
    _voicePlayer.stop();
    setState(() {
      _expressLines.clear();
      _expressCurrentLineWords.clear();
      _expressCurrentWordLetters.clear();
      _expressCurrentDots.clear();
      _expressPreviewedSymbol = null;
      _view = _View.expressThought;
    });
    _playClip('express_prompt');
  }

  /// Бара точно совпаѓање на притиснатите точки со некоја позната
  /// буква/број (низ сите групи на тековниот јазик) - слободно пишување,
  /// без однапред одреден "точен" одговор.
  BrailleSymbol? _symbolForDots(Set<int> dots0Based) {
    if (dots0Based.isEmpty) return null;
    final target = dots0Based.map((d) => d + 1).toSet();
    for (final g in _groups) {
      for (final s in g.symbols) {
        final sDots = s.dots.toSet();
        if (sDots.length == target.length && sDots.containsAll(target)) return s;
      }
    }
    return null;
  }

  /// Секое притискање регистрира точка (се стопира и се изговара веднаш).
  /// Ако веќе постои преглед (по А) кој сеуште не е потврден, притискање
  /// нова точка молчешкум го поништува тој преглед - корисникот очигледно
  /// сака да ja коригира буквата.
  Future<void> _tapExpressDot(int dotIndex) async {
    if (_view != _View.expressThought) return;
    setState(() {
      _expressPreviewedSymbol = null;
      _expressCurrentDots.add(dotIndex);
    });
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 90);
    }
    await _playClipAwaitingCompletion('dot_${dotIndex + 1}');
  }

  /// А: прв притисок - изговара преглед на буквата формирана од
  /// притиснатите точки (без да ja потврди). Втор притисок (додека
  /// прегледот е активен) - ja потврдува истата буква и продолжува со
  /// следната буква од ИСТИОТ збор.
  Future<void> _expressPreviewOrConfirmLetter() async {
    if (_expressPreviewedSymbol == null) {
      if (_expressCurrentDots.isEmpty) return;
      final symbol = _symbolForDots(_expressCurrentDots);
      if (symbol == null) {
        if (await VibrationUtils.hasVibrator()) {
          await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
        }
        await _playPongEffect('miss.mp3');
        return;
      }
      setState(() => _expressPreviewedSymbol = symbol);
      await _playCharClip(symbol);
    } else {
      await _expressCommitLetter(endWord: false, endLine: false);
    }
  }

  /// „:" - ja поништува буквата која чека потврда (или само притиснатите
  /// точки), за да се внесе повторно од почеток.
  void _expressResetCurrentLetter() {
    if (_expressCurrentDots.isEmpty && _expressPreviewedSymbol == null) return;
    setState(() {
      _expressCurrentDots.clear();
      _expressPreviewedSymbol = null;
    });
    _playPongEffect('miss.mp3');
  }

  /// Ja потврдува буквата која е веќе прегледана со А. Мора прво да има
  /// активен преглед - Г/Х пред А се игнорираат (со кус звук за грешка) за
  /// да не се потврди буква што never не е изговорена.
  Future<void> _expressCommitLetter({required bool endWord, required bool endLine}) async {
    final symbol = _expressPreviewedSymbol;
    if (symbol == null) {
      await _playPongEffect('miss.mp3');
      return;
    }
    setState(() {
      _expressCurrentWordLetters.add(symbol.char);
      _expressCurrentDots.clear();
      _expressPreviewedSymbol = null;
    });
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 150);
    }
    await _playPongEffect('hit.mp3');

    if (!endWord) return; // продолжува истата буква/збор - ништо повеќе.

    final word = _expressCurrentWordLetters.join();
    List<String>? finishedLineWords;
    setState(() {
      _expressCurrentLineWords.add(word);
      _expressCurrentWordLetters.clear();
      if (endLine) {
        finishedLineWords = List<String>.from(_expressCurrentLineWords);
        _expressLines.add(finishedLineWords!.join(' '));
        _expressCurrentLineWords.clear();
      }
    });

    if (endLine && finishedLineWords != null) {
      await _playLineReadback(finishedLineWords!);
    } else {
      await _playWordReadback(word);
    }
  }

  /// Го "прочитува" зборот исклучиво со веќе постоечките mp3-датотеки по
  /// буква (char_<key>) - секоја можна комбинација е составена динамички
  /// од фиксни снимки, без потреба од нови снимки или TTS.
  Future<void> _playWordReadback(String word) async {
    final myToken = ++_narrationToken;
    for (final ch in word.split('')) {
      if (myToken != _narrationToken || !mounted) return;
      final symbol = _symbolForChar(ch);
      if (symbol != null) {
        await _playClipAwaitingCompletion('char_${symbol.key}');
      }
    }
  }

  Future<void> _playLineReadback(List<String> words) async {
    final myToken = ++_narrationToken;
    for (final w in words) {
      if (myToken != _narrationToken || !mounted) return;
      await _playWordReadback(w);
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  void _toggleExpressExplanation() {
    final opening = !_expressExplanationOpen;
    setState(() => _expressExplanationOpen = opening);
    if (opening) {
      _playClip('express_explanation');
    } else {
      _voicePlayer.stop();
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
                case _View.reference:
                  return _buildReferenceGrid(context);
              }
            },
          ),
        ),
      ),
    );
  }

  // --- Избор на категорија ---

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
    final exploredCount = group.symbols.where((s) => _exploredKeys.contains('$index:${s.char}')).length;
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

  // --- Истражувај: 3-зонски дизајн исто како кај сликовницата ---

  Widget _buildExplore(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
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
                label: '${s.char}. ${_explanationFor(s)}',
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
                              _bigDotDisplay(s.dots, hc, scale: 2.0),
                              const SizedBox(height: 26),
                              Text(s.char, style: TextStyle(fontSize: 104, fontWeight: FontWeight.w900, color: textColor)),
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

  Widget _buildPracticeModeSelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_group.titleKey.tr(), style: GameTypography.heading(context, contrast, 20)),
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
        _buildBackRow(contrast, onBack: _openPracticeModeSelect),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_practiceTarget!.char, style: TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: contrast)),
        ),
        Expanded(child: Center(child: _interactiveDotGrid(onTap: _tapComposeDot, wrongVisual: false))),
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
        _buildBackRow(contrast, onBack: _openPracticeModeSelect),
        _practiceProgressLine(contrast),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_practiceTarget!.char, style: TextStyle(fontSize: 100, fontWeight: FontWeight.w900, color: contrast)),
        ),
        Expanded(
          child: Center(
            child: AbsorbPointer(absorbing: _writeFailed, child: _interactiveDotGrid(onTap: _tapWriteDot, wrongVisual: _writeFailed)),
          ),
        ),
        _buildKeyboardHint(contrast),
      ],
    );
  }

  /// Точна форма на Брајовата клетка: лева колона точки 1-2-3, десна
  /// колона точки 4-5-6.
  Widget _interactiveDotGrid({
    required void Function(int) onTap,
    required bool wrongVisual,
    Set<int>? hitDots,
    double dotSize = 150,
    double dotPadding = 14,
  }) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final hits = hitDots ?? _correctDotsHit;

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
        _buildBackRow(contrast, onBack: _openPracticeModeSelect),
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
                _bigDotDisplay(_practiceTarget!.dots, hc, scale: 1.5),
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
            children: _recognizeChoices.map((choice) {
              final isPicked = _recognizePicked == choice.char;
              final isCorrectAnswer = choice.char == _practiceTarget!.char;
              final showFeedback = _recognizePicked != null && (isPicked || isCorrectAnswer);
              final bg = !showFeedback
                  ? AccessibilityUtils.getPrimaryButtonBackground(context)
                  : (isCorrectAnswer ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 84,
                  child: ElevatedButton(
                    onPressed: () => _pickRecognizeAnswer(choice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bg,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(choice.char, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
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
    if (_currentWord == null) return const SizedBox.shrink();
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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: List.generate(_currentWord!.length, (i) {
            final isCurrent = i == _wordLetterIndex;
            final isDone = i < _wordLetterIndex;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF16A34A) : (isCurrent ? _accent : Colors.transparent),
                border: Border.all(color: contrast.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_currentWord![i], style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: (isDone || isCurrent) ? Colors.white : contrast)),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text('braille.word_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 15)),
        Expanded(
          child: Center(
            child: _interactiveDotGrid(onTap: _tapWordDot, wrongVisual: false, hitDots: _wordCorrectDotsHit),
          ),
        ),
        _buildKeyboardHint(contrast),
      ],
    );
  }

  // --- „Искажи ја својата мисла" ---

  Widget _buildExpressThought(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
        _buildExpressExplanationButton(contrast),
        if (_expressExplanationOpen) _buildExpressExplanationPanel(contrast),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('braille.express_title'.tr(), textAlign: TextAlign.center, style: GameTypography.heading(context, contrast, 18)),
        ),
        // Сликата со точки има ФИКСНА (помала) висина - никогаш не го
        // притиска/преклопува полето за пишување подолу, без разлика на
        // висината на екранот.
        SizedBox(
          height: 290,
          child: Center(
            child: _interactiveDotGrid(
              onTap: _tapExpressDot,
              wrongVisual: false,
              hitDots: _expressCurrentDots,
              dotSize: 76,
              dotPadding: 7,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text('braille.express_hint'.tr(), textAlign: TextAlign.center, style: GameTypography.body(context, contrast, 13)),
        ),
        // Полето за пишување - под сликата со точки, преку целата ширина на
        // екранот; ограничена (помала) висина за да не го зазема целиот
        // преостанат простор, со скрол и расте нагоре со секој нов ред.
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
          ),
        ),
        _buildExpressKeyboardHint(contrast),
      ],
    );
  }

  /// Го прикажува текстот составен до момент: веќе завршените редови,
  /// зборовите затворени на тековниот ред, буквите потврдени за тековниот
  /// збор, и - подвлечена/во бојата на акцентот - буквата која е штотуку
  /// прегледана со А, но сеуште не е потврдена.
  Widget _buildExpressComposedText(Color contrast) {
    final baseStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: contrast, height: 1.4);
    final pendingStyle = baseStyle.copyWith(color: _accent, decoration: TextDecoration.underline, decorationColor: _accent, decorationThickness: 2);

    final hasAnyContent = _expressLines.isNotEmpty ||
        _expressCurrentLineWords.isNotEmpty ||
        _expressCurrentWordLetters.isNotEmpty ||
        _expressPreviewedSymbol != null;
    if (!hasAnyContent) {
      return Text('braille.express_empty'.tr(), style: baseStyle.copyWith(color: contrast.withOpacity(0.4)));
    }

    final buffer = StringBuffer();
    for (final line in _expressLines) {
      buffer.writeln(line);
    }
    final currentLineParts = [..._expressCurrentLineWords];
    if (_expressCurrentWordLetters.isNotEmpty) currentLineParts.add(_expressCurrentWordLetters.join());
    if (currentLineParts.isNotEmpty) buffer.write(currentLineParts.join(' '));

    final spans = <InlineSpan>[TextSpan(text: buffer.toString(), style: baseStyle)];
    if (_expressPreviewedSymbol != null) {
      spans.add(TextSpan(text: _expressPreviewedSymbol!.char, style: pendingStyle));
    }
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
          Text('braille.express_explanation_text'.tr(), style: GameTypography.body(context, contrast, 15)),
        ],
      ),
    );
  }

  Widget _buildExpressKeyboardHint(Color contrast) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'braille.express_keyboard_hint'.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: contrast.withOpacity(0.9)),
      ),
    );
  }

  // --- Референтна мрежа (потсетник) ---

  Widget _buildReferenceGrid(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _closeReference),
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
                character: s.char,
                dots: s.dots,
                contrastColor: contrast,
                // Сега изговара и буквата И точките (со истите мп3 за точки).
                onTap: () => _playCharExplanationSequence(s),
              ))
          .toList(),
    );
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

  Widget _buildBackRow(Color contrast, {required VoidCallback onBack}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Semantics(label: 'braille.back'.tr(), button: true, child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: contrast), onPressed: onBack)),
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
  final List<int> dots;
  final Color contrastColor;
  final VoidCallback onTap;

  const _ReferenceCell({required this.character, required this.dots, required this.contrastColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final buttonSize = AccessibilityUtils.getButtonSize(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    return Semantics(
      label: 'braille.cell'.tr(args: [character]),
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 100 * buttonSize,
            padding: EdgeInsets.all(16 * buttonSize),
            decoration: BoxDecoration(
              color: hc ? Colors.transparent : Colors.white.withValues(alpha: 0.95),
              border: Border.all(color: contrastColor, width: hc ? 2 : 2.5),
              borderRadius: BorderRadius.circular(20),
              boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(character, style: TextStyle(fontSize: 30 * buttonSize, fontWeight: FontWeight.bold, color: contrastColor)),
                const SizedBox(height: 10),
                _ReferenceDots(dots: dots, contrastColor: contrastColor, size: 28),
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