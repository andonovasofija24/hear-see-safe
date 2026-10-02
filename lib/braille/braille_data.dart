/// Податоци и логика за Брајовата азбука - БЕЗ Flutter зависности, за да
/// може да се тестира одделно (види test/braille_data_test.dart).
///
/// Содржи:
///  - [BrailleSymbol]  - една буква/број/знак (може да има ПОВЕЌЕ клетки, пр. @ и /)
///  - [BrailleData]    - табелите за mk/sq/en, групите, зборовите и речениците
///  - [BrailleData.tokenize] - претвора текст во низа Брајови симболи
///    (вклучувајќи знак за голема буква и знак за број каде што треба)
///  - [BrailleComposer] - "декодер" за слободно пишување: точки → симбол,
///    со режим за броеви (по знакот за број, до празно место) и голема буква.
library;

enum BrailleLang { mk, sq, en }

enum BrailleKind {
  letter,
  digit,
  punctuation,
  space,
  capitalSign,
  numberSign,
}

/// Една буква/број/знак во Брајовата азбука.
///
/// `key` е ФИКСЕН идентификатор за име на мп3 датотека:
/// `audio/braille/<јазик>/char_<key>.mp3` (за празно место: `char_space.mp3`,
/// а при објаснувањето по него и `dot_0.mp3` - „ниедна точка“).
class BrailleSymbol {
  /// Текстот што се запишува (за знаците без печатен еквивалент - знак за
  /// голема буква и знак за број - ова е само ознака за приказ).
  final String char;
  final String key;
  final BrailleKind kind;
  final List<int>? _single;
  final List<List<int>>? _multi;

  const BrailleSymbol(this.char, this.key, List<int> dots, {this.kind = BrailleKind.letter})
      : _single = dots,
        _multi = null;

  /// Знак составен од повеќе Брајови клетки (пр. @ = клетка 4, па клетка 1).
  const BrailleSymbol.multi(this.char, this.key, List<List<int>> cells, {this.kind = BrailleKind.punctuation})
      : _single = null,
        _multi = cells;

  /// Сите клетки по ред (најчесто само една).
  List<List<int>> get cells => _multi ?? [_single!];

  /// Точките на ПРВАТА клетка (за едноклеточни симболи - сите точки).
  List<int> get dots => cells.first;

  bool get isMultiCell => cells.length > 1;

  /// Мп3 клип (без наставка) за изговор на симболот.
  String get audioClip => 'char_$key';

  /// Знаците што означуваат крај на реченица во пишувањето.
  bool get endsSentence => kind == BrailleKind.punctuation && (char == '.' || char == '?' || char == '!');

  /// Дали е "вистински" знак/буква што се гледа во текстот (не модификатор).
  bool get isModifier => kind == BrailleKind.capitalSign || kind == BrailleKind.numberSign;

  /// Што да се прикаже голем на екранот.
  String get displayChar {
    switch (kind) {
      case BrailleKind.space:
        return '␣';
      default:
        return char;
    }
  }

  /// Клуч за превод на името на знакот (само за знаци, не за букви/бројки).
  String get nameKey => 'braille.sym_$key';

  @override
  String toString() => 'BrailleSymbol($char)';
}

class BrailleGroup {
  final String titleKey;
  final List<BrailleSymbol> symbols;
  const BrailleGroup(this.titleKey, this.symbols);
}

/// Збор за Играта со зборови. `key` е ASCII име за снимката
/// `audio/braille/<јазик>/word_<key>.mp3`.
class BrailleWord {
  final String text;
  final String key;
  const BrailleWord(this.text, this.key);
}

/// Реченица за играта Пишувај реченици. Снимка:
/// `audio/braille/<јазик>/sentence_<key>.mp3`.
class BrailleSentence {
  final String text;
  final String key;
  const BrailleSentence(this.text, this.key);
}

/// Извор: македонски и албански Брајов код според Wikipedia „Yugoslav
/// Braille“ / „Albanian Braille“ (базирано на UNESCO „World Braille
/// Usage“, 2013). Англискиот е стандарден Grade 1 Брај (UEB).
class BrailleData {
  // ---------------------------------------------------------------------
  // Букви.
  // ---------------------------------------------------------------------

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

  // ВНИМАНИЕ: клучевите за ç и ë се 'ç' и 'ë' - така се именувани
  // постоечките снимки (char_ç.mp3, char_ë.mp3). Порано беа 'ch'/'ee' и
  // затоа овие две букви воопшто не се слушаа.
  static const List<BrailleSymbol> _sq = [
    BrailleSymbol('a', 'a', [1]), BrailleSymbol('b', 'b', [1, 2]), BrailleSymbol('c', 'c', [1, 4]),
    BrailleSymbol('ç', 'ç', [1, 4, 6]), BrailleSymbol('d', 'd', [1, 4, 5]), BrailleSymbol('dh', 'dh', [1, 4, 5, 6]),
    BrailleSymbol('e', 'e', [1, 5]), BrailleSymbol('ë', 'ë', [1, 6]), BrailleSymbol('f', 'f', [1, 2, 4]),
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

  // Англиските букви се МАЛИ (големата буква сега се пишува со знакот за
  // голема буква, како во вистинскиот Брај). Клучевите (име на мп3) остануваат
  // големи букви - постоечките снимки се char_A.mp3 ... char_Z.mp3.
  static const List<BrailleSymbol> _en = [
    BrailleSymbol('a', 'A', [1]), BrailleSymbol('b', 'B', [1, 2]), BrailleSymbol('c', 'C', [1, 4]),
    BrailleSymbol('d', 'D', [1, 4, 5]), BrailleSymbol('e', 'E', [1, 5]), BrailleSymbol('f', 'F', [1, 2, 4]),
    BrailleSymbol('g', 'G', [1, 2, 4, 5]), BrailleSymbol('h', 'H', [1, 2, 5]), BrailleSymbol('i', 'I', [2, 4]),
    BrailleSymbol('j', 'J', [2, 4, 5]), BrailleSymbol('k', 'K', [1, 3]), BrailleSymbol('l', 'L', [1, 2, 3]),
    BrailleSymbol('m', 'M', [1, 3, 4]), BrailleSymbol('n', 'N', [1, 3, 4, 5]), BrailleSymbol('o', 'O', [1, 3, 5]),
    BrailleSymbol('p', 'P', [1, 2, 3, 4]), BrailleSymbol('q', 'Q', [1, 2, 3, 4, 5]), BrailleSymbol('r', 'R', [1, 2, 3, 5]),
    BrailleSymbol('s', 'S', [2, 3, 4]), BrailleSymbol('t', 'T', [2, 3, 4, 5]), BrailleSymbol('u', 'U', [1, 3, 6]),
    BrailleSymbol('v', 'V', [1, 2, 3, 6]), BrailleSymbol('w', 'W', [2, 4, 5, 6]), BrailleSymbol('x', 'X', [1, 3, 4, 6]),
    BrailleSymbol('y', 'Y', [1, 3, 4, 5, 6]), BrailleSymbol('z', 'Z', [1, 3, 5, 6]),
  ];

  static const Set<String> _enSpecial = {};

  // ---------------------------------------------------------------------
  // Броеви: прво ЗНАКОТ ЗА БРОЈ (точки 3-4-5-6), па цифрите. Цифрите ги
  // користат истите точки како буквите а-ј; по знакот за број точките се
  // толкуваат како цифри СЕ ДО празно место.
  // ---------------------------------------------------------------------

  static const BrailleSymbol numberSign = BrailleSymbol('#', 'number_sign', [3, 4, 5, 6], kind: BrailleKind.numberSign);

  static const List<BrailleSymbol> digits = [
    BrailleSymbol('1', '1', [1], kind: BrailleKind.digit), BrailleSymbol('2', '2', [1, 2], kind: BrailleKind.digit),
    BrailleSymbol('3', '3', [1, 4], kind: BrailleKind.digit), BrailleSymbol('4', '4', [1, 4, 5], kind: BrailleKind.digit),
    BrailleSymbol('5', '5', [1, 5], kind: BrailleKind.digit), BrailleSymbol('6', '6', [1, 2, 4], kind: BrailleKind.digit),
    BrailleSymbol('7', '7', [1, 2, 4, 5], kind: BrailleKind.digit), BrailleSymbol('8', '8', [1, 2, 5], kind: BrailleKind.digit),
    BrailleSymbol('9', '9', [2, 4], kind: BrailleKind.digit), BrailleSymbol('0', '0', [2, 4, 5], kind: BrailleKind.digit),
  ];

  /// Групата Броеви: знак за број + цифрите.
  static const List<BrailleSymbol> numbers = [numberSign, ...digits];

  // ---------------------------------------------------------------------
  // Знаци (интерпункција) + празно место + знак за голема буква.
  //
  // mk: Југословенски Брај; sq: Албански Брај; en: Unified English Braille.
  // ⚠️ @ и / немаат потврдена ознака во југословенскиот/албанскиот Брај на
  // Wikipedia - овде се земени двоклеточните знаци од англискиот Брај
  // (@ = 4 | 1, / = 4-5-6 | 3-4), кои не се судираат со ниту една буква.
  // Наводниците за mk се 2-3-6 / 3-5-6 (како во српскиот/хрватскиот Брај).
  // Ова е добро да се потврди со наставник/Сојуз на слепи.
  // ---------------------------------------------------------------------

  static const BrailleSymbol space = BrailleSymbol(' ', 'space', [], kind: BrailleKind.space);

  static const BrailleSymbol _capitalYu = BrailleSymbol('⇧', 'capital', [4, 6], kind: BrailleKind.capitalSign);
  static const BrailleSymbol _capitalEn = BrailleSymbol('⇧', 'capital', [6], kind: BrailleKind.capitalSign);

  static const BrailleSymbol _period = BrailleSymbol('.', 'period', [2, 5, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _comma = BrailleSymbol(',', 'comma', [2], kind: BrailleKind.punctuation);
  static const BrailleSymbol _questionYu = BrailleSymbol('?', 'question', [2, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _questionEn = BrailleSymbol('?', 'question', [2, 3, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _exclamation = BrailleSymbol('!', 'exclamation', [2, 3, 5], kind: BrailleKind.punctuation);
  static const BrailleSymbol _colon = BrailleSymbol(':', 'colon', [2, 5], kind: BrailleKind.punctuation);
  static const BrailleSymbol _semicolon = BrailleSymbol(';', 'semicolon', [2, 3], kind: BrailleKind.punctuation);
  static const BrailleSymbol _hyphen = BrailleSymbol('-', 'hyphen', [3, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _apostrophe = BrailleSymbol("'", 'apostrophe', [3], kind: BrailleKind.punctuation);
  static const BrailleSymbol _quoteOpenYu = BrailleSymbol('„', 'quote_open', [2, 3, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _quoteCloseYu = BrailleSymbol('“', 'quote_close', [3, 5, 6], kind: BrailleKind.punctuation);
  static const BrailleSymbol _quoteOpenEn = BrailleSymbol.multi('“', 'quote_open', [[4, 5], [2, 3, 6]]);
  static const BrailleSymbol _quoteCloseEn = BrailleSymbol.multi('”', 'quote_close', [[4, 5], [3, 5, 6]]);
  static const BrailleSymbol _slash = BrailleSymbol.multi('/', 'slash', [[4, 5, 6], [3, 4]]);
  static const BrailleSymbol _at = BrailleSymbol.multi('@', 'at', [[4], [1]]);

  static const List<BrailleSymbol> _punctYu = [
    space, _capitalYu, _period, _comma, _questionYu, _exclamation, _colon, _semicolon,
    _hyphen, _apostrophe, _quoteOpenYu, _quoteCloseYu, _slash, _at,
  ];

  static const List<BrailleSymbol> _punctEn = [
    space, _capitalEn, _period, _comma, _questionEn, _exclamation, _colon, _semicolon,
    _hyphen, _apostrophe, _quoteOpenEn, _quoteCloseEn, _slash, _at,
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

  /// Групата Знаци за дадениот јазик (празно место, голема буква, интерпункција).
  static List<BrailleSymbol> punctuationFor(BrailleLang lang) => lang == BrailleLang.en ? _punctEn : _punctYu;

  static BrailleSymbol capitalSignFor(BrailleLang lang) => lang == BrailleLang.en ? _capitalEn : _capitalYu;

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
  /// специфичните знаци (ако ги има за тој јазик), Броеви и Знаци.
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
    result.add(const BrailleGroup('braille.group_numbers', numbers));
    result.add(BrailleGroup('braille.group_punct', punctuationFor(lang)));
    return result;
  }

  /// Сите симболи што можат да се "прочитаат" од точки ВОН режимот за
  /// броеви (букви, знаци, знак за број). Цифрите се читаат само во режим
  /// за броеви.
  static List<BrailleSymbol> decodableFor(BrailleLang lang) => [
        ...lettersFor(lang),
        ...punctuationFor(lang).where((s) => s.kind != BrailleKind.space),
        numberSign,
      ];

  // ---------------------------------------------------------------------
  // Голема буква.
  // ---------------------------------------------------------------------

  /// Голема форма на буква (за дигрaфи само првата буква: sh → Sh).
  static String upper(String letter) {
    if (letter.isEmpty) return letter;
    return letter[0].toUpperCase() + letter.substring(1);
  }

  // ---------------------------------------------------------------------
  // Текст → Брајови симболи.
  // ---------------------------------------------------------------------

  /// Го претвора текстот во низа симболи онака како што се пишува на Брај:
  /// пред голема буква се додава знакот за голема буква, пред (првата)
  /// цифра знакот за број (важи до празно место). Враќа null ако текстот
  /// содржи знак што го нема во табелата за тој јазик.
  static List<BrailleSymbol>? tokenize(String text, BrailleLang lang) {
    final letters = lettersFor(lang);
    final lower = {for (final s in letters) s.char: s};
    final upperMap = {for (final s in letters) upper(s.char): s};
    final punct = {
      for (final s in punctuationFor(lang))
        if (s.kind == BrailleKind.punctuation) s.char: s,
    };
    final digitMap = {for (final d in digits) d.char: d};
    final capital = capitalSignFor(lang);

    final out = <BrailleSymbol>[];
    var numberMode = false;
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == ' ') {
        out.add(space);
        numberMode = false;
        i++;
        continue;
      }
      final digit = digitMap[ch];
      if (digit != null) {
        if (!numberMode) {
          out.add(numberSign);
          numberMode = true;
        }
        out.add(digit);
        i++;
        continue;
      }
      var matched = false;
      for (final len in const [2, 1]) {
        if (i + len > text.length) continue;
        final sub = text.substring(i, i + len);
        final low = lower[sub];
        if (low != null) {
          out.add(low);
          i += len;
          matched = true;
          break;
        }
        final up = upperMap[sub];
        if (up != null) {
          out.add(capital);
          out.add(up);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      final p = punct[ch];
      if (p != null) {
        out.add(p);
        i++;
        continue;
      }
      return null;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Игра со зборови - комбинации од СИТЕ категории: букви од сите групи,
  // специјални букви, зборови со голема буква, броеви и зборови со знак.
  // Секој збор прво се изговара (word_<key>.mp3), а ако снимката ја нема -
  // се спелува буква по буква со постоечките снимки.
  // ---------------------------------------------------------------------

  static const Map<BrailleLang, List<BrailleWord>> words = {
    BrailleLang.mk: [
      BrailleWord('баба', 'baba'), BrailleWord('дедо', 'dedo'), BrailleWord('мама', 'mama'),
      BrailleWord('татко', 'tatko'), BrailleWord('куќа', 'kukja'), BrailleWord('чаша', 'chasha'),
      BrailleWord('вода', 'voda'), BrailleWord('нога', 'noga'), BrailleWord('рака', 'raka'),
      BrailleWord('глава', 'glava'), BrailleWord('риба', 'riba'), BrailleWord('сонце', 'sonce'),
      BrailleWord('јаболко', 'jabolko'), BrailleWord('шума', 'shuma'), BrailleWord('цвет', 'cvet'),
      BrailleWord('леб', 'leb'), BrailleWord('жаба', 'zhaba'), BrailleWord('зајак', 'zajak'),
      BrailleWord('пчела', 'pchela'), BrailleWord('мачка', 'machka'), BrailleWord('куче', 'kuche'),
      BrailleWord('хартија', 'hartija'), BrailleWord('фудбал', 'fudbal'),
      BrailleWord('коњ', 'konj'), BrailleWord('љубов', 'ljubov'), BrailleWord('џемпер', 'dzhemper'),
      BrailleWord('ќерка', 'kjerka'), BrailleWord('ѕвезда', 'dzvezda'), BrailleWord('ѓеврек', 'gjevrek'),
      BrailleWord('Скопје', 'skopje'), BrailleWord('Охрид', 'ohrid'), BrailleWord('Ана', 'ana'),
      BrailleWord('Марко', 'marko'),
      BrailleWord('Здраво!', 'zdravo'), BrailleWord('Браво!', 'bravo'), BrailleWord('Ало?', 'alo'),
      BrailleWord('5', '5'), BrailleWord('12', '12'), BrailleWord('100', '100'), BrailleWord('2026', '2026'),
    ],
    BrailleLang.sq: [
      BrailleWord('baba', 'baba'), BrailleWord('mama', 'mama'), BrailleWord('nënë', 'nene'),
      BrailleWord('shtëpi', 'shtepi'), BrailleWord('ujë', 'uje'), BrailleWord('qen', 'qen'),
      BrailleWord('mace', 'mace'), BrailleWord('diell', 'diell'), BrailleWord('lule', 'lule'),
      BrailleWord('libër', 'liber'), BrailleWord('dorë', 'dore'), BrailleWord('këmbë', 'kembe'),
      BrailleWord('bukë', 'buke'), BrailleWord('zog', 'zog'), BrailleWord('yll', 'yll'),
      BrailleWord('dhi', 'dhi'), BrailleWord('gjel', 'gjel'), BrailleWord('rrugë', 'rruge'),
      BrailleWord('thikë', 'thike'), BrailleWord('xhep', 'xhep'), BrailleWord('zhurmë', 'zhurme'),
      BrailleWord('çantë', 'cante'),
      BrailleWord('Ana', 'ana'), BrailleWord('Tirana', 'tirana'), BrailleWord('Shkup', 'shkup'),
      BrailleWord('Tungjatjeta!', 'tungjatjeta'), BrailleWord('Bravo!', 'bravo'), BrailleWord('Ku?', 'ku'),
      BrailleWord('5', '5'), BrailleWord('12', '12'), BrailleWord('100', '100'), BrailleWord('2026', '2026'),
    ],
    BrailleLang.en: [
      BrailleWord('bag', 'bag'), BrailleWord('cab', 'cab'), BrailleWord('dog', 'dog'),
      BrailleWord('cat', 'cat'), BrailleWord('hat', 'hat'), BrailleWord('bed', 'bed'),
      BrailleWord('egg', 'egg'), BrailleWord('ice', 'ice'), BrailleWord('jam', 'jam'),
      BrailleWord('kid', 'kid'), BrailleWord('fox', 'fox'), BrailleWord('sun', 'sun'),
      BrailleWord('milk', 'milk'), BrailleWord('book', 'book'), BrailleWord('queen', 'queen'),
      BrailleWord('zebra', 'zebra'), BrailleWord('wolf', 'wolf'), BrailleWord('yes', 'yes'),
      BrailleWord('house', 'house'), BrailleWord('water', 'water'),
      BrailleWord('Ana', 'ana'), BrailleWord('Tom', 'tom'), BrailleWord('London', 'london'),
      BrailleWord('Hello!', 'hello'), BrailleWord('Why?', 'why'),
      BrailleWord('5', '5'), BrailleWord('12', '12'), BrailleWord('100', '100'), BrailleWord('2026', '2026'),
    ],
  };

  // ---------------------------------------------------------------------
  // Реченици за играта „Пишувај реченици“ (голема буква на почеток, знак
  // на крај, понекогаш број). Снимка: sentence_<key>.mp3; ако ја нема -
  // реченицата се спелува буква по буква.
  // ---------------------------------------------------------------------

  static const Map<BrailleLang, List<BrailleSentence>> sentences = {
    BrailleLang.mk: [
      BrailleSentence('Мама има куќа.', '1'),
      BrailleSentence('Јас сум Ана.', '2'),
      BrailleSentence('Каде е топката?', '3'),
      BrailleSentence('Браво, успеа!', '4'),
      BrailleSentence('Имам 5 јаболка.', '5'),
      BrailleSentence('Денес е убав ден.', '6'),
      BrailleSentence('Скопје е град.', '7'),
      BrailleSentence('Татко чита книга.', '8'),
      BrailleSentence('Колку години имаш?', '9'),
      BrailleSentence('Имам 7 години.', '10'),
    ],
    BrailleLang.sq: [
      BrailleSentence('Mama ka një shtëpi.', '1'),
      BrailleSentence('Unë jam Ana.', '2'),
      BrailleSentence('Ku është topi?', '3'),
      BrailleSentence('Bravo, ia dole!', '4'),
      BrailleSentence('Kam 5 mollë.', '5'),
      BrailleSentence('Sot është ditë e bukur.', '6'),
      BrailleSentence('Qeni vrapon shpejt.', '7'),
      BrailleSentence('Babai lexon një libër.', '8'),
      BrailleSentence('Sa vjeç je?', '9'),
      BrailleSentence('Jam 7 vjeç.', '10'),
    ],
    BrailleLang.en: [
      BrailleSentence('Mom has a house.', '1'),
      BrailleSentence('I am Ana.', '2'),
      BrailleSentence('Where is the ball?', '3'),
      BrailleSentence('Well done, you did it!', '4'),
      BrailleSentence('I have 5 apples.', '5'),
      BrailleSentence('Today is a nice day.', '6'),
      BrailleSentence('The dog can run.', '7'),
      BrailleSentence('Dad reads a book.', '8'),
      BrailleSentence('How old are you?', '9'),
      BrailleSentence('I am 7 years old.', '10'),
    ],
  };
}

// =========================================================================
// Декодирање: точки → симбол, со состојба (режим за броеви, голема буква,
// започнат повеќеклеточен знак).
// =========================================================================

enum BrailleDecodeStatus {
  /// Точките формираат цел симбол.
  complete,

  /// Точките се ПРВА (или наредна) клетка од повеќеклеточен знак - треба
  /// уште клетки.
  prefix,

  /// Нема таков симбол.
  invalid,
}

class BrailleDecodeResult {
  final BrailleDecodeStatus status;
  final BrailleSymbol? symbol;
  const BrailleDecodeResult(this.status, [this.symbol]);
}

/// Состојба на слободното пишување (Искажи ја својата мисла / Пишувај
/// реченици): веќе напишани редови, токените на тековниот ред и
/// започнатите клетки на повеќеклеточен знак.
///
/// Правила:
///  - празна клетка (ниедна точка) = празно место (крај на збор);
///  - по знакот за број, клетките што одговараат на цифра се толкуваат како
///    цифри СЕ ДО празно место;
///  - по знакот за голема буква, следната буква е голема;
///  - . ? ! го завршуваат редот (реченицата).
class BrailleComposer {
  BrailleComposer(this.lang);

  final BrailleLang lang;

  /// Завршени реченици (редови).
  final List<String> lines = [];

  /// Токени на тековниот (отворен) ред - вклучувајќи ги знаците за голема
  /// буква / број и празните места.
  final List<BrailleSymbol> lineTokens = [];

  /// Веќе потврдени клетки од повеќеклеточен знак што сеуште не е завршен.
  final List<List<int>> pendingCells = [];

  bool get numberMode => _replay().$1;
  bool get capitalNext => _replay().$2;

  (bool, bool) _replay() {
    var number = false;
    var capital = false;
    for (final t in lineTokens) {
      switch (t.kind) {
        case BrailleKind.numberSign:
          number = true;
          break;
        case BrailleKind.capitalSign:
          capital = true;
          break;
        case BrailleKind.space:
          number = false;
          capital = false;
          break;
        case BrailleKind.letter:
          capital = false;
          break;
        default:
          break;
      }
    }
    return (number, capital);
  }

  static bool _sameCell(List<int> a, Set<int> b) => a.length == b.length && b.containsAll(a);

  static bool _sameCells(List<int> a, List<int> b) => a.length == b.length && a.toSet().containsAll(b);

  /// Ги толкува точките (1-6) на тековната клетка во контекст на досегашното.
  BrailleDecodeResult decode(Set<int> dots) {
    if (dots.isEmpty) {
      return pendingCells.isEmpty
          ? const BrailleDecodeResult(BrailleDecodeStatus.complete, BrailleData.space)
          : const BrailleDecodeResult(BrailleDecodeStatus.invalid);
    }
    if (pendingCells.isEmpty && numberMode) {
      for (final d in BrailleData.digits) {
        if (_sameCell(d.dots, dots)) return BrailleDecodeResult(BrailleDecodeStatus.complete, d);
      }
    }
    final n = pendingCells.length;
    BrailleSymbol? complete;
    var hasLonger = false;
    for (final s in BrailleData.decodableFor(lang)) {
      final cells = s.cells;
      if (cells.length <= n) continue;
      var prefixOk = true;
      for (var i = 0; i < n; i++) {
        if (!_sameCells(cells[i], pendingCells[i])) {
          prefixOk = false;
          break;
        }
      }
      if (!prefixOk || !_sameCell(cells[n], dots)) continue;
      if (cells.length == n + 1) {
        complete ??= s;
      } else {
        hasLonger = true;
      }
    }
    if (complete != null) return BrailleDecodeResult(BrailleDecodeStatus.complete, complete);
    if (hasLonger) return const BrailleDecodeResult(BrailleDecodeStatus.prefix);
    return const BrailleDecodeResult(BrailleDecodeStatus.invalid);
  }

  /// Ги толкува двата пара точки одеднаш (пар 1 и пар 2). Ако вториот пар
  /// е празен - ист е како [decode] за еден пар; ако првиот пар е само
  /// почеток на двоклеточен знак (пр. точка 4 за @), враќа
  /// [BrailleDecodeStatus.prefix] - фали вториот пар.
  BrailleDecodeResult decodePairs(Set<int> first, Set<int> second) {
    if (second.isEmpty) return decode(first);
    if (first.isEmpty || pendingCells.isNotEmpty) return const BrailleDecodeResult(BrailleDecodeStatus.invalid);
    for (final s in BrailleData.decodableFor(lang)) {
      final cells = s.cells;
      if (cells.length == 2 && _sameCell(cells[0], first) && _sameCell(cells[1], second)) {
        return BrailleDecodeResult(BrailleDecodeStatus.complete, s);
      }
    }
    return const BrailleDecodeResult(BrailleDecodeStatus.invalid);
  }

  /// Додава потврдена клетка од повеќеклеточен знак.
  void pushPrefixCell(Set<int> dots) => pendingCells.add(dots.toList()..sort());

  /// Го запишува симболот. Ако е . ? ! - редот се затвора и се враќа
  /// неговиот текст (инаку null).
  String? commit(BrailleSymbol symbol) {
    pendingCells.clear();
    lineTokens.add(symbol);
    if (symbol.endsSentence) {
      final text = render(lineTokens).trim();
      lines.add(text);
      lineTokens.clear();
      return text;
    }
    return null;
  }

  /// Ги поништува започнатите клетки на повеќеклеточен знак.
  void clearPending() => pendingCells.clear();

  /// Го брише последниот запишан токен од тековниот ред (враќа го, или null).
  BrailleSymbol? backspace() {
    if (lineTokens.isEmpty) return null;
    return lineTokens.removeLast();
  }

  /// Токените на последниот збор (по последното празно место) во тековниот ред.
  List<BrailleSymbol> lastWordTokens() {
    var end = lineTokens.length;
    while (end > 0 && lineTokens[end - 1].kind == BrailleKind.space) {
      end--;
    }
    var start = end;
    while (start > 0 && lineTokens[start - 1].kind != BrailleKind.space) {
      start--;
    }
    return lineTokens.sublist(start, end);
  }

  String get currentLineText => render(lineTokens);

  void reset() {
    lines.clear();
    lineTokens.clear();
    pendingCells.clear();
  }

  /// Токени → текст (знакот за голема буква ја прави следната буква голема,
  /// знакот за број не се гледа).
  static String render(List<BrailleSymbol> tokens) {
    final b = StringBuffer();
    var capital = false;
    for (final t in tokens) {
      switch (t.kind) {
        case BrailleKind.capitalSign:
          capital = true;
          break;
        case BrailleKind.numberSign:
          break;
        case BrailleKind.space:
          b.write(' ');
          capital = false;
          break;
        case BrailleKind.letter:
          b.write(capital ? BrailleData.upper(t.char) : t.char);
          capital = false;
          break;
        default:
          b.write(t.char);
      }
    }
    return b.toString();
  }
}