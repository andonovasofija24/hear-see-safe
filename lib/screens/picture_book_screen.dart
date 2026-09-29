import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

/// Мултимедијална сликовница за слабовиди/наглуви (модул „Учи и Слушај“).
/// Тек: категории -> мрежа од картички (по категорија) -> поединечна
/// сликовница по предмет -> назад ја означува картичката како прегледана ->
/// штом сите картички во категоријата се прегледани, автоматски почнува
/// мини-квиз.
class PictureBookScreen extends StatefulWidget {
  const PictureBookScreen({super.key});

  @override
  State<PictureBookScreen> createState() => _PictureBookScreenState();
}

enum _View { categorySelect, itemGrid, itemDetail, quiz, quizResult }

class _PictureBookScreenState extends State<PictureBookScreen> {
  late VoiceAssistantService _voiceAssistant;
  PageController? _itemPageController;
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final AudioPlayer _flipPlayer = AudioPlayer();
  final Random _random = Random();

  static const List<PictureBookCategory> _categories = [
    PictureBookCategory(
      id: 'animals',
      titleKey: 'picture_book.category_animals',
      icon: Icons.pets_rounded,
      color: Color(0xFF9333EA),
      items: [
        PictureBookItem(id: 'cat', nameKey: 'picture_book.cat', descriptionKey: 'picture_book.cat_desc', learnKey: 'picture_book.cat_learn', learn2Key: 'picture_book.cat_learn2', emoji: '🐱'),
        PictureBookItem(id: 'dog', nameKey: 'picture_book.dog', descriptionKey: 'picture_book.dog_desc', learnKey: 'picture_book.dog_learn', emoji: '🐶'),
        PictureBookItem(id: 'bird', nameKey: 'picture_book.bird', descriptionKey: 'picture_book.bird_desc', learnKey: 'picture_book.bird_learn', emoji: '🐦'),
        PictureBookItem(id: 'cow', nameKey: 'picture_book.cow', descriptionKey: 'picture_book.cow_desc', learnKey: 'picture_book.cow_learn', emoji: '🐄'),
      ],
    ),
    PictureBookCategory(
      id: 'nature',
      titleKey: 'picture_book.category_nature',
      icon: Icons.eco_rounded,
      color: Color(0xFF16A34A),
      items: [
        PictureBookItem(id: 'rain', nameKey: 'picture_book.rain', descriptionKey: 'picture_book.rain_desc', learnKey: 'picture_book.rain_learn', emoji: '🌧️'),
        PictureBookItem(id: 'sun', nameKey: 'picture_book.sun', descriptionKey: 'picture_book.sun_desc', learnKey: 'picture_book.sun_learn', emoji: '☀️', hasSound: false),
        PictureBookItem(id: 'tree', nameKey: 'picture_book.tree', descriptionKey: 'picture_book.tree_desc', learnKey: 'picture_book.tree_learn', emoji: '🌳'),
        PictureBookItem(id: 'water', nameKey: 'picture_book.water', descriptionKey: 'picture_book.water_desc', learnKey: 'picture_book.water_learn', learn2Key: 'picture_book.water_learn2', emoji: '💧'),
        PictureBookItem(id: 'fire', nameKey: 'picture_book.fire', descriptionKey: 'picture_book.fire_desc', learnKey: 'picture_book.fire_learn', learn2Key: 'picture_book.fire_learn2', emoji: '🔥'),
        PictureBookItem(id: 'wind', nameKey: 'picture_book.wind', descriptionKey: 'picture_book.wind_desc', learnKey: 'picture_book.wind_learn', emoji: '🌬️'),
      ],
    ),
    PictureBookCategory(
      id: 'objects',
      titleKey: 'picture_book.category_objects',
      icon: Icons.home_rounded,
      color: Color(0xFF2563EB),
      items: [
        PictureBookItem(id: 'car', nameKey: 'picture_book.car', descriptionKey: 'picture_book.car_desc', learnKey: 'picture_book.car_learn', emoji: '🚗'),
        PictureBookItem(id: 'bicycle', nameKey: 'picture_book.bicycle', descriptionKey: 'picture_book.bicycle_desc', learnKey: 'picture_book.bicycle_learn', emoji: '🚲'),
        PictureBookItem(id: 'book', nameKey: 'picture_book.book', descriptionKey: 'picture_book.book_desc', learnKey: 'picture_book.book_learn', emoji: '📖'),
        PictureBookItem(id: 'phone', nameKey: 'picture_book.phone', descriptionKey: 'picture_book.phone_desc', learnKey: 'picture_book.phone_learn', learn2Key: 'picture_book.phone_learn2', emoji: '📱'),
        PictureBookItem(id: 'clock', nameKey: 'picture_book.clock', descriptionKey: 'picture_book.clock_desc', learnKey: 'picture_book.clock_learn', emoji: '⏰'),
      ],
    ),
    PictureBookCategory(
      id: 'space',
      titleKey: 'picture_book.category_space',
      icon: Icons.rocket_launch_rounded,
      color: Color(0xFF4338CA),
      items: [
        PictureBookItem(id: 'star', nameKey: 'picture_book.star', descriptionKey: 'picture_book.star_desc', learnKey: 'picture_book.star_learn', emoji: '⭐', hasSound: false),
        PictureBookItem(id: 'moon', nameKey: 'picture_book.moon', descriptionKey: 'picture_book.moon_desc', learnKey: 'picture_book.moon_learn', emoji: '🌙', hasSound: false),
        PictureBookItem(id: 'rocket', nameKey: 'picture_book.rocket', descriptionKey: 'picture_book.rocket_desc', learnKey: 'picture_book.rocket_learn', emoji: '🚀'),
        PictureBookItem(id: 'planet', nameKey: 'picture_book.planet', descriptionKey: 'picture_book.planet_desc', learnKey: 'picture_book.planet_learn', emoji: '🪐', hasSound: false),
      ],
    ),
    PictureBookCategory(
      id: 'music',
      titleKey: 'picture_book.category_music',
      icon: Icons.music_note_rounded,
      color: Color(0xFFDB2777),
      items: [
        PictureBookItem(id: 'drum', nameKey: 'picture_book.drum', descriptionKey: 'picture_book.drum_desc', learnKey: 'picture_book.drum_learn', emoji: '🥁'),
        PictureBookItem(id: 'guitar', nameKey: 'picture_book.guitar', descriptionKey: 'picture_book.guitar_desc', learnKey: 'picture_book.guitar_learn', emoji: '🎸'),
        PictureBookItem(id: 'bell', nameKey: 'picture_book.bell', descriptionKey: 'picture_book.bell_desc', learnKey: 'picture_book.bell_learn', emoji: '🔔'),
      ],
    ),
  ];

  _View _view = _View.categorySelect;
  int _categoryIndex = 0;
  int _itemIndex = 0;
  bool _explanationOpen = false;
  /// Дали моментално свири звукот на предметот (за копчето play/pause).
  bool _itemSoundPlaying = false;

  /// Кои предмети (по id) се веќе прегледани, по категорија (по id).
  final Map<String, Set<String>> _visitedByCategory = {};

  /// Кои категории се веќе целосно завршени (прегледано + квиз) во оваа
  /// сесија - остануваат заклучени до следно вклучување на апликацијата.
  final Set<String> _completedCategories = {};

  /// Колку пати е притиснато "Обиди се повторно" по категорија - максимум 2,
  /// потоа категоријата останува трајно заклучена до следно вклучување.
  final Map<String, int> _quizRetriesUsed = {};
  static const int _maxQuizRetries = 2;

  /// Се зголемува секогаш кога почнува нова секвенца на говор - спречува
  /// преклопување ако детето брзо навигира/допира додека сè уште трае
  /// претходниот говор.
  int _narrationToken = 0;

  // Квиз состојба.
  List<_QuizQuestion> _quizQuestions = [];
  int _quizQuestionIndex = 0;
  int _quizScore = 0;
  PictureBookItem? _quizTarget;
  List<PictureBookItem> _quizChoices = [];
  bool _quizLocked = false;
  /// За визуелна повратна информација - кое копче е одбрано и дали е точно.
  PictureBookItem? _quizPicked;
  bool? _quizPickedCorrect;

  String get _langCode => context.locale.languageCode;
  PictureBookCategory get _category => _categories[_categoryIndex];
  PictureBookItem get _item => _category.items[_itemIndex];
  Set<String> get _visited => _visitedByCategory[_category.id] ?? const {};

  late final StreamSubscription<PlayerState> _effectsStateSub;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    // Никакво автоматско објаснување - целосно опционално, преку копчето
    // "Прикажи објаснување" на почетниот екран (исто како другите игри).

    // Го следи "play sound" копчето - кога звукот природно ќе заврши (или
    // ќе биде запрен од друго место), копчето се враќа на "play" икона.
    _effectsStateSub = _effectsPlayer.onPlayerStateChanged.listen((state) {
      if ((state == PlayerState.completed || state == PlayerState.stopped) && mounted) {
        setState(() => _itemSoundPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _flipPlayer.dispose();
    _itemPageController?.dispose();
    _effectsStateSub.cancel();
    super.dispose();
  }

  String _t(String key) => 'picture_book.$key'.tr();

  /// Пробува однапред снимена звучна датотека (твоја снимка, по јазик), а
  /// само ако не постои паѓа назад на системскиот text-to-speech. Го чека
  /// говорот РЕАЛНО да заврши пред да продолжи натамошниот тек.
  ///
  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -
  /// плеерот тивко „проголтува" грешка и никогаш не влегува во состојба
  /// "playing". Затоа не се потпираме само на тоа дали .play() фрлил
  /// исклучок - експлицитно чекаме потврда дека звукот навистина ПОЧНАЛ.
  Future<void> _speak(String key, String fallbackText, {bool allowTtsFallback = true}) async {
    if (!mounted) return;
    final relativePath = 'audio/picture_book/$_langCode/$key.mp3';
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
        // Ако заврши/запре пред воопшто да влезе во "playing" (многу кратки
        // датотеки), сепак сметај го стартот како разрешен.
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
      // Прво: дали навистина ПОЧНА да свири (краток рок - ова е локален
      // асет, треба да е речиси мигновено ако е валиден).
      await startedCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      if (reachedPlaying) {
        // Реално почна - сега чекај го целосното завршување.
        await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
      }
    }
    await stateSub.cancel();

    if (!mounted) return;
    final actuallyPlayed = playCallSucceeded && reachedPlaying;
    if (!actuallyPlayed && allowTtsFallback) {
      await _voiceAssistant.speakWithLanguage(fallbackText, _langCode, vibrate: false);
    }
  }

  /// Пресликување од id на предметот кон името на датотеката во
  /// assets/sounds/sound_identification/ - повеќето се веќе таму (се
  /// преупотребуваат од Идентификација на звук), некои ги додаваш нови таму
  /// со истото име како id-то на предметот.
  static const Map<String, String> _soundFileById = {
    'cat': 'meow',
    'dog': 'bark',
    // Сите останати го користат сопственото id како име на датотека:
    // rain, bird, water, wind, car, cow, tree, fire, bicycle, book, phone,
    // clock, rocket, drum, guitar, bell.
  };

  Future<void> _playEffect(String itemId) async {
    final fileName = _soundFileById[itemId] ?? itemId;
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/sound_identification/$fileName.mp3'));
    } catch (_) {}
  }

  // =====================================================================
  // Категории -> мрежа од картички.
  // =====================================================================

  void _onLockedCategoryTap() {
    VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: 60);
    });
  }

  void _enterCategory(int index) {
    _narrationToken++;
    _visitedByCategory.putIfAbsent(_categories[index].id, () => {});
    setState(() {
      _categoryIndex = index;
      _view = _View.itemGrid;
    });
  }

  void _backToCategories() {
    _narrationToken++;
    _voiceAssistant.stop();
    _voicePlayer.stop();
    setState(() => _view = _View.categorySelect);
  }

  // =====================================================================
  // Поединечна сликовница по предмет.
  // =====================================================================

  void _openItem(int index) {
    _narrationToken++;
    _itemPageController?.dispose();
    _itemPageController = PageController(initialPage: index);
    setState(() {
      _itemIndex = index;
      _view = _View.itemDetail;
    });
    _announceItem();
  }

  Future<void> _announceItem() async {
    final myToken = ++_narrationToken;
    final item = _item;
    final fallback = '${item.nameKey.tr()}. ${item.descriptionKey.tr()}. ${item.learnKey.tr()}';
    await _speak('${item.id}_explanation', fallback);
    if (!mounted || myToken != _narrationToken) return;
  }

  Future<void> _repeatItem() async {
    _narrationToken++;
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 100);
    }
    final item = _item;
    final fallback = '${item.nameKey.tr()}. ${item.descriptionKey.tr()}. ${item.learnKey.tr()}';
    await _speak('${item.id}_explanation', fallback);
    if (item.learn2Key != null) {
      final remember = _t('remember');
      final learn2 = item.learn2Key!.tr();
      await _speak('${item.id}_extra', '$remember $learn2');
    }
  }

  /// Го пушта звукот на предметот - се повикува ИСКЛУЧИВО од кружното
  /// копче-звучник, никогаш од допир на самата сликовница.
  /// Копчето сега е play/pause - ако звукот веќе свири, ново притискање го
  /// запира веднаш (некои звуци траат ~10 секунди, детето можеби не сака
  /// да ги слуша до крај).
  Future<void> _playItemSound() async {
    if (_itemSoundPlaying) {
      await _effectsPlayer.stop(); // слушателот на состојба ќе го ресетира _itemSoundPlaying
      return;
    }
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 150);
    }
    setState(() => _itemSoundPlaying = true);
    await _playEffect(_item.id);
  }

  /// Звук на прелистување страница - при секој премин од една сликовница
  /// на друга, без разлика дали е со лизгање или со стрелка.
  Future<void> _playFlipSound() async {
    try {
      await _flipPlayer.stop();
    } catch (_) {}
    try {
      await _flipPlayer.play(AssetSource('sounds/picture_book/flip.mp3'));
    } catch (_) {}
  }

  bool get _hasPrevItem => _itemIndex > 0;
  bool get _hasNextItem => _itemIndex < _category.items.length - 1;

  /// Го означува тековниот предмет како прегледан (без да се враќа во
  /// мрежата). Веќе НЕ го стартува квизот автоматски - наместо тоа, копче
  /// "Оди на квиз" се појавува на секоја сликовница штом сите ќе бидат
  /// прегледани (без разлика на редоследот).
  void _markCurrentVisitedAndMaybeQuiz() {
    final catId = _category.id;
    _visitedByCategory.putIfAbsent(catId, () => {}).add(_item.id);
  }

  /// Единствена точка низ која поминува секој премин меѓу сликовници - без
  /// разлика дали е предизвикан со лизгање (PageView) или со стрелка
  /// (_goToNextItem/_goToPrevItem), за да не се дуплира логиката.
  void _onItemPageChanged(int newIndex) {
    if (newIndex == _itemIndex) return;
    _narrationToken++;
    _voiceAssistant.stop();
    _voicePlayer.stop();
    _effectsPlayer.stop();
    _markCurrentVisitedAndMaybeQuiz(); // го означува ПРЕДМЕТОТ ШТО ГО НАПУШТАМЕ
    _playFlipSound();
    setState(() => _itemIndex = newIndex);
    _announceItem();
  }

  void _goToNextItem() {
    if (!_hasNextItem || _itemPageController == null) return;
    _itemPageController!.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  void _goToPrevItem() {
    if (!_hasPrevItem || _itemPageController == null) return;
    _itemPageController!.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  /// Затворање на сликовницата за предметот - се означува како прегледано.
  /// Ако сите предмети од категоријата сега се прегледани, автоматски
  /// почнува квизот.
  void _closeItemDetail() {
    _narrationToken++;
    // Веднаш прекини секаков говор/звук за предметот - не смее да продолжи
    // да се слуша откако веќе си излегол од сликовницата.
    _voiceAssistant.stop();
    _voicePlayer.stop();
    _effectsPlayer.stop();

    _markCurrentVisitedAndMaybeQuiz();
    setState(() => _view = _View.itemGrid);
  }

  void _toggleExplanation() {
    final opening = !_explanationOpen;
    setState(() => _explanationOpen = opening);
    if (opening) {
      _speak('explanation', _t('intro'));
    } else {
      _voiceAssistant.stop();
      _voicePlayer.stop();
    }
  }

  // =====================================================================
  // Мини-квиз (се активира кога сите картички од категоријата се прегледани).
  // =====================================================================

  /// "Обиди се повторно" - дозволено најмногу _maxQuizRetries пати по
  /// категорија. Категоријата останува заклучена во меѓувреме и понатаму.
  void _retryQuiz() {
    final used = _quizRetriesUsed[_category.id] ?? 0;
    if (used >= _maxQuizRetries) return;
    _quizRetriesUsed[_category.id] = used + 1;
    _startQuiz();
  }

  void _startQuiz() {
    _narrationToken++;
    final items = List<PictureBookItem>.from(_category.items);

    // БАРЕМ ДВЕ РАЗЛИЧНИ прашања за секој предмет од категоријата:
    // предметите СО звук добиваат звучно + описно прашање; предметите БЕЗ
    // звук добиваат описно + факт-за-учење прашање (две навистина
    // различни траги, никогаш исто прашање двапати).
    final questions = <_QuizQuestion>[];
    for (final i in items) {
      if (i.hasSound) {
        questions.add(_QuizQuestion(i, _ClueType.sound));
        questions.add(_QuizQuestion(i, _ClueType.description));
      } else {
        questions.add(_QuizQuestion(i, _ClueType.description));
        questions.add(_QuizQuestion(i, _ClueType.learnFact));
      }
    }
    questions.shuffle(_random);

    setState(() {
      _quizQuestions = questions;
      _quizQuestionIndex = 0;
      _quizScore = 0;
      _view = _View.quiz;
    });
    _prepareQuizQuestion();
  }

  void _prepareQuizQuestion() {
    final q = _quizQuestions[_quizQuestionIndex];
    // Сите предмети од категоријата се опции за одговор - за да го исполнат
    // екранот и играта да биде подизвикувачка.
    final choices = List<PictureBookItem>.from(_category.items)..shuffle(_random);
    setState(() {
      _quizTarget = q.item;
      _quizChoices = choices;
      _quizLocked = false;
      _quizPicked = null;
      _quizPickedCorrect = null;
    });
    // Насловот на прашањето ("Погоди го звукот!" / "Погоди за кој предмет
    // важи следново!") - исклучиво снимка, БЕЗ TTS-резерва.
    final introKey = q.isSound ? 'quiz_intro' : 'quiz_intro_info';
    _speak(introKey, '', allowTtsFallback: false);
    // Ниту звукот ниту особината повеќе не се пуштаат автоматски - детето
    // мора самo да го притисне копчето-звучник кога е спремно.
  }

  /// Ја пушта веќе постојната снимка за објаснување на предметот
  /// (<item>_explanation.mp3, истата како во сликовницата) - за информативни
  /// прашања, само на барање преку копчето-звучник. Исклучиво снимка, БЕЗ
  /// TTS-резерва.
  Future<void> _speakClue() async {
    if (_quizTarget == null) return;
    await _speak('${_quizTarget!.id}_explanation', '', allowTtsFallback: false);
  }

  /// hit.mp3 / miss.mp3 од Гласовен Понг (assets/sounds/pong/) - истите
  /// датотеки, без потреба од нови снимки.
  Future<void> _playPongEffect(String fileName) async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
    try {
      await _effectsPlayer.play(AssetSource('sounds/pong/$fileName'));
    } catch (_) {}
  }

  Future<void> _answerQuiz(PictureBookItem chosen) async {
    if (_quizLocked) return;
    // Веднаш прекини го звукот на поимот (ако сè уште свири) штом ќе се
    // одговори прашањето.
    _effectsPlayer.stop();
    _voiceAssistant.stop();
    final correct = chosen.id == _quizTarget!.id;
    setState(() {
      _quizLocked = true;
      _quizPicked = chosen;
      _quizPickedCorrect = correct;
    });

    if (correct) {
      setState(() => _quizScore++);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 200);
      }
      await _playPongEffect('hit.mp3');
    } else {
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      }
      await _playPongEffect('miss.mp3');
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final nextIndex = _quizQuestionIndex + 1;
    if (nextIndex >= _quizQuestions.length) {
      final isPerfect = _quizScore >= _quizQuestions.length;
      final retriesUsed = _quizRetriesUsed[_category.id] ?? 0;
      final noRetriesLeft = retriesUsed >= _maxQuizRetries;
      setState(() {
        _view = _View.quizResult;
        // Категоријата се заклучува само ако е совршен резултат ИЛИ ако веќе
        // се искористени сите дозволени обиди - инаку останува "прегледана,
        // но не заклучена", и квизот сепак може повторно да се пробa.
        if (isPerfect || noRetriesLeft) {
          _completedCategories.add(_category.id);
        }
      });
      await _speak('quiz_done', '', allowTtsFallback: false);
    } else {
      setState(() => _quizQuestionIndex = nextIndex);
      _prepareQuizQuestion();
    }
  }

  // =====================================================================
  // Build.
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return GameScreenChrome(
      accent: const Color(0xFF2563EB),
      title: _t('title').isNotEmpty ? _t('title') : 'features.picture_book'.tr(),
      child: SafeArea(
        child: Builder(
          builder: (context) {
            switch (_view) {
              case _View.categorySelect:
                return _buildCategorySelect(context);
              case _View.itemGrid:
                return _buildItemGrid(context);
              case _View.itemDetail:
                return _buildItemDetail(context);
              case _View.quiz:
                return _buildQuiz(context);
              case _View.quizResult:
                return _buildQuizResult(context);
            }
          },
        ),
      ),
    );
  }

  // --- Категории ---

  Widget _buildCategorySelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildExplanationButton(contrast),
        if (_explanationOpen) _buildExplanationPanel(contrast, _t('intro')),
        const SizedBox(height: 12),
        Text(
          _t('choose_category'),
          textAlign: TextAlign.center,
          style: GameTypography.heading(context, contrast, 20),
        ),
        const SizedBox(height: 20),
        for (final cat in _categories) ...[
          _categoryCard(context, cat, contrast, hc),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _buildExplanationButton(Color contrast) {
    final label = _explanationOpen
        ? 'picture_book.explanation_toggle_close'.tr()
        : 'picture_book.explanation_toggle_open'.tr();
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _toggleExplanation,
          icon: Icon(_explanationOpen ? Icons.expand_less_rounded : Icons.menu_book_rounded, size: 26),
          label: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _explanationOpen
                ? AccessibilityUtils.getDisabledColor(context)
                : const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 3,
          ),
        ),
      ),
    );
  }

  Widget _categoryCard(BuildContext context, PictureBookCategory cat, Color contrast, bool hc) {
    final index = _categories.indexOf(cat);
    final visitedCount = (_visitedByCategory[cat.id] ?? const {}).length;
    final locked = _completedCategories.contains(cat.id);
    return Semantics(
      label: locked
          ? '${cat.titleKey.tr()}. ${_t('category_locked')}.'
          : '${cat.titleKey.tr()}. ${cat.items.length} ${_t('items_count')}. $visitedCount ${_t('seen')}.',
      button: !locked,
      child: Opacity(
        opacity: locked ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: locked ? _onLockedCategoryTap : () => _enterCategory(index),
            child: Container(
              padding: const EdgeInsets.all(28),
              constraints: const BoxConstraints(minHeight: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: hc
                    ? null
                    : LinearGradient(
                        colors: [cat.color, Color.lerp(cat.color, Colors.white, 0.3)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: hc ? Colors.black : null,
                border: Border.all(color: hc ? Colors.white : cat.color, width: hc ? 3 : 0),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(hc ? 0.1 : 0.25),
                    ),
                    child: Icon(cat.icon, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 48),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.titleKey.tr(),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: hc ? const Color(0xFFFFFF00) : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locked ? _t('category_locked') : '$visitedCount / ${cat.items.length} ${_t('seen')}',
                          style: TextStyle(
                            fontSize: 15,
                            color: (hc ? const Color(0xFFFFFF00) : Colors.white).withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    locked ? Icons.lock_rounded : Icons.arrow_forward_ios_rounded,
                    color: hc ? Colors.white : Colors.white.withOpacity(0.8),
                    size: locked ? 26 : 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Мрежа од картички ---

  Widget _buildItemGrid(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final cat = _category;
    final reviewedNotLocked = _visited.length >= cat.items.length && !_completedCategories.contains(cat.id);
    return Column(
      children: [
        _buildBackRow(contrast, onBack: _backToCategories),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cat.titleKey.tr(),
                  style: GameTypography.heading(context, contrast, 20),
                ),
              ),
              if (reviewedNotLocked)
                Semantics(
                  label: 'picture_book.go_to_quiz'.tr(),
                  button: true,
                  child: Material(
                    color: hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(16),
                    elevation: hc ? 0 : 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _startQuiz,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.quiz_rounded, size: 32, color: hc ? Colors.black : Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'picture_book.go_to_quiz'.tr(),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: hc ? Colors.black : Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cat.items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) => _itemCard(context, cat.items[index], index, contrast, hc),
          ),
        ),
      ],
    );
  }

  Widget _itemCard(BuildContext context, PictureBookItem item, int index, Color contrast, bool hc) {
    final visited = _visited.contains(item.id);
    return Semantics(
      label: '${item.nameKey.tr()}${visited ? '. ${_t('seen')}' : ''}',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openItem(index),
          child: Opacity(
            opacity: visited ? 0.55 : 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: hc ? Colors.black : Colors.white,
                border: Border.all(color: hc ? Colors.white : contrast.withOpacity(0.2), width: hc ? 2 : 1.5),
                boxShadow: hc ? const [] : AppStyle.cardShadow(false),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.emoji, style: const TextStyle(fontSize: 68)),
                        const SizedBox(height: 8),
                        Text(
                          item.nameKey.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: hc ? Colors.white : contrast),
                        ),
                      ],
                    ),
                  ),
                  if (visited)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF16A34A)),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Поединечна сликовница ---

  Widget _buildItemDetail(BuildContext context) {
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    return Column(
      children: [
        _buildBackRow(contrastColor, onBack: _closeItemDetail),
        _buildStorySegments(context),
        if (_item.hasSound) _buildPlaySoundButton(contrastColor),
        Expanded(
          child: PageView.builder(
            controller: _itemPageController,
            itemCount: _category.items.length,
            onPageChanged: _onItemPageChanged,
            itemBuilder: (context, index) => _build3DPage(context, contrastColor, _category.items[index], index),
          ),
        ),
      ],
    );
  }

  /// Сегментирана лента на прогрес на врвот - точно како кај сторија на
  /// Инстаграм: по едно сегментче за секоја сликовница во категоријата,
  /// исполнето до тековната позиција.
  Widget _buildStorySegments(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final total = _category.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List.generate(total, (i) {
          final filled = i <= _itemIndex;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: filled
                    ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF2563EB))
                    : AccessibilityUtils.getDisabledColor(context).withOpacity(0.35),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Сликовница поделена на 3 зони со непрекината омбре позадина:
  /// лева (стрелка претходна) - централна (икона + текст + копче повтори)
  /// - десна (стрелка следна). Допир било каде во лева/десна зона исто така
  /// навигира.
  /// Ги завиткува сликовниците во лесна 3Д ротациска трансформација,
  /// заснована на позицијата на PageController - страниците навистина
  /// изгледаат како да се вртат во просторот при прелистување, не само
  /// што лизгаат рамно.
  Widget _build3DPage(BuildContext context, Color contrastColor, PictureBookItem item, int index) {
    return AnimatedBuilder(
      animation: _itemPageController!,
      builder: (context, child) {
        double page = index.toDouble();
        if (_itemPageController!.position.haveDimensions) {
          page = _itemPageController!.page ?? _itemIndex.toDouble();
        }
        final delta = (page - index).clamp(-1.0, 1.0);
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateY(delta * 0.9);
        final scale = 1.0 - delta.abs() * 0.12;
        return Transform(
          alignment: delta >= 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: matrix..scale(scale, scale),
          child: Opacity(opacity: 1.0 - delta.abs() * 0.35, child: child),
        );
      },
      child: _itemDetailCard(context, contrastColor, item, index),
    );
  }

  Widget _itemDetailCard(BuildContext context, Color contrastColor, PictureBookItem item, int index) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final catColor = _category.color;
    final hasPrev = index > 0;
    final hasNext = index < _category.items.length - 1;

    final gradientColors = hc
        ? const [Colors.black, Colors.black, Colors.black]
        : [
            Color.lerp(catColor, Colors.white, 0.72)!,
            Color.lerp(catColor, Colors.white, 0.28)!,
            Color.lerp(catColor, Colors.white, 0.72)!,
          ];

    final name = item.nameKey.tr();
    final description = item.descriptionKey.tr();
    final learn = item.learnKey.tr();

    return Container(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: hc ? Colors.white : contrastColor, width: 3),
        gradient: LinearGradient(
          colors: gradientColors,
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Лева зона: стрелка претходна ---
          Expanded(
            flex: 2,
            child: _NavZone(
              enabled: hasPrev,
              icon: Icons.chevron_left_rounded,
              onTap: _goToPrevItem,
              label: 'picture_book.previous_item'.tr(),
              highContrast: hc,
            ),
          ),
          // --- Централна зона: икона, текст, копче повтори ---
          Expanded(
            flex: 5,
            child: GestureDetector(
              onTap: _repeatItem,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                label: '$name. $description. $learn. ${_t('hint_tap')}',
                button: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final h = constraints.maxHeight;
                    final w = constraints.maxWidth;
                    final emojiSize = (h * 0.22).clamp(90.0, 170.0);
                    final titleSize = (w * 0.19).clamp(25.0, 36.0);
                    final descSize = (w * 0.10).clamp(16.0, 21.0);
                    final learnSize = (w * 0.088).clamp(15.0, 19.0);
                    final textColor = hc ? Colors.white : contrastColor;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item.emoji, style: TextStyle(fontSize: emojiSize)),
                          const SizedBox(height: 14),
                          Text(
                            name,
                            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold, color: textColor),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: TextStyle(fontSize: descSize, color: textColor.withOpacity(0.85)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            learn,
                            style: TextStyle(fontSize: learnSize, color: textColor.withOpacity(0.75), fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            label: 'picture_book.repeat_explanation'.tr(),
                            button: true,
                            child: Material(
                              color: hc ? Colors.black : const Color(0xFF2563EB),
                              shape: const CircleBorder(),
                              elevation: 3,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _repeatItem,
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Icon(Icons.replay_rounded, size: 40, color: hc ? Colors.white : Colors.white),
                                ),
                              ),
                            ),
                          ),
                          if (_visited.length >= _category.items.length) ...[
                            const SizedBox(height: 18),
                            Semantics(
                              label: 'picture_book.go_to_quiz'.tr(),
                              button: true,
                              child: Material(
                                color: hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A),
                                shape: const CircleBorder(),
                                elevation: hc ? 0 : 4,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _startQuiz,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Icon(Icons.quiz_rounded, size: 34, color: hc ? Colors.black : Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // --- Десна зона: стрелка следна ---
          Expanded(
            flex: 2,
            child: _NavZone(
              enabled: hasNext,
              icon: Icons.chevron_right_rounded,
              onTap: _goToNextItem,
              label: 'picture_book.next_item'.tr(),
              highContrast: hc,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaySoundButton(Color contrast) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Center(
        child: Semantics(
          label: _itemSoundPlaying ? 'picture_book.pause_sound'.tr() : 'picture_book.play_sound'.tr(),
          button: true,
          child: Material(
            color: _itemSoundPlaying ? const Color(0xFFD97706) : const Color(0xFF16A34A),
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _playItemSound,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Icon(_itemSoundPlaying ? Icons.pause_rounded : Icons.volume_up_rounded, size: 40, color: Colors.white),
              ),
            ),
          ),
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
            label: _t('back_to_categories'),
            button: true,
            child: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: contrast),
              onPressed: onBack,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationPanel(Color contrast, String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.35), width: 1.5),
      ),
      child: Text(text, style: GameTypography.body(context, contrast, 15)),
    );
  }

  // --- Квиз ---

  Widget _buildQuiz(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    if (_quizTarget == null) return const SizedBox.shrink();
    final isSoundQuestion = _quizQuestions[_quizQuestionIndex].isSound;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          children: [
            Text(
              'picture_book.quiz_progress'.tr(args: [(_quizQuestionIndex + 1).toString(), _quizQuestions.length.toString()]),
              style: GameTypography.heading(context, contrast, 28),
            ),
            const SizedBox(height: 8),
            Text(
              _t(isSoundQuestion ? 'quiz_intro' : 'quiz_intro_info'),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 20),
            ),
            const SizedBox(height: 20),
            if (!isSoundQuestion)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3), width: 1.5),
                ),
                child: Text(
                  (_quizQuestions[_quizQuestionIndex].clueType == _ClueType.learnFact ? _quizTarget!.learnKey : _quizTarget!.descriptionKey).tr(),
                  textAlign: TextAlign.center,
                  style: GameTypography.body(context, contrast, 21),
                ),
              ),
            // Единствен извор на звук/особина во квизот - само на притискање.
            Semantics(
              label: isSoundQuestion ? _t('quiz_replay') : 'picture_book.play_sound'.tr(),
              button: true,
              child: Material(
                color: const Color(0xFF2563EB),
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isSoundQuestion ? () => _playEffect(_quizTarget!.id) : _speakClue,
                  child: const Padding(
                    padding: EdgeInsets.all(28),
                    child: Icon(Icons.volume_up_rounded, size: 52, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: _quizChoices.length,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _quizAnswerButton(context, _quizChoices[i], contrast, hc),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Правоаголно, малку повисоко копче со иконата на поимот + името - со
  /// псевдо-3Д изглед (градиент + сенка) за да наликува на физичко копче.
  Widget _quizAnswerButton(BuildContext context, PictureBookItem choice, Color contrast, bool hc) {
    final isPicked = _quizPicked?.id == choice.id;
    Color bg = AccessibilityUtils.getPrimaryButtonBackground(context);
    Color fg = AccessibilityUtils.getPrimaryButtonForeground(context);
    if (isPicked && _quizPickedCorrect != null) {
      if (_quizPickedCorrect!) {
        bg = hc ? const Color(0xFFFFFF00) : const Color(0xFF16A34A);
        fg = hc ? Colors.black : Colors.white;
      } else {
        bg = hc ? const Color(0xFF3A3A3A) : const Color(0xFF6B7280);
        fg = Colors.white;
      }
    }
    // Го блокираме допирот со AbsorbPointer наместо onPressed: null - на тој
    // начин копчето секогаш останува во "вклучена" визуелна состојба, и
    // нашата boja секогаш се применува (некои Flutter верзии не ја
    // применуваат disabledBackgroundColor правилно).
    const tileSize = 84.0;
    return AbsorbPointer(
      absorbing: _quizLocked,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        elevation: hc ? 0 : 6,
        shadowColor: Colors.black.withOpacity(0.45),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _answerQuiz(choice),
          child: Container(
            height: tileSize,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: hc
                  ? Border.all(color: contrast, width: 2)
                  : Border.all(color: Colors.white.withOpacity(0.35), width: 1),
              gradient: hc
                  ? null
                  : LinearGradient(
                      colors: [Color.lerp(bg, Colors.white, 0.18)!, bg],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
            ),
            child: Row(
              children: [
                // Иконата ја исполнува сопствената квадратна зона ~70%.
                SizedBox(
                  width: tileSize - 14,
                  height: tileSize - 14,
                  child: Center(
                    child: Text(choice.emoji, style: TextStyle(fontSize: (tileSize - 14) * 0.7)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    choice.nameKey.tr(),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizResult(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final isPerfect = _quizScore >= _quizQuestions.length;
    final retriesUsed = _quizRetriesUsed[_category.id] ?? 0;
    final retriesLeft = isPerfect ? 0 : (_maxQuizRetries - retriesUsed);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: Color(0xFF2563EB)),
            const SizedBox(height: 16),
            Text(
              'picture_book.quiz_result'.tr(args: [_quizScore.toString(), _quizQuestions.length.toString()]),
              textAlign: TextAlign.center,
              style: GameTypography.body(context, contrast, 18),
            ),
            const SizedBox(height: 20),
            if (retriesLeft > 0) ...[
              Text(
                'picture_book.retries_left'.tr(args: [retriesLeft.toString()]),
                textAlign: TextAlign.center,
                style: GameTypography.body(context, contrast, 14),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _retryQuiz,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t('retry_quiz')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _backToCategories,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text(_t('back_to_categories')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
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

class PictureBookCategory {
  final String id;
  final String titleKey;
  final IconData icon;
  final Color color;
  final List<PictureBookItem> items;

  const PictureBookCategory({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class PictureBookItem {
  final String id;
  final String nameKey;
  final String descriptionKey;
  final String learnKey;
  final String? learn2Key;
  final String emoji;
  /// false за предмети без вистински звук (сонце, месечина, ѕвезда,
  /// планета) - за нив квизот секогаш поставува информативно прашање.
  final bool hasSound;

  const PictureBookItem({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.learnKey,
    this.learn2Key,
    required this.emoji,
    this.hasSound = true,
  });
}

enum _ClueType { sound, description, learnFact }

/// Едно прашање во квизот: кој предмет се прашува и од каде доаѓа
/// трагата - звук, опис (descriptionKey) или факт за учење (learnKey).
/// Двете информативни трагов се РАЗЛИЧНИ, за предметите без звук да
/// добијат две вистински различни прашања, не исто прашање двапати.
class _QuizQuestion {
  final PictureBookItem item;
  final _ClueType clueType;
  const _QuizQuestion(this.item, this.clueType);
  bool get isSound => clueType == _ClueType.sound;
}

/// Лева/десна зона за навигација на сликовницата - цела зона е допирлива,
/// со голема стрелка, и се засенува веднаш штом прстот ја допре (не само
/// на пуштање), за јасна визуелна потврда на притискањето.
class _NavZone extends StatefulWidget {
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool highContrast;

  const _NavZone({
    required this.enabled,
    required this.icon,
    required this.onTap,
    required this.label,
    required this.highContrast,
  });

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
            // Засенчување при притискање - секогаш видливо, без разлика на
            // бојата на позадината зад него.
            if (_pressed) Container(color: Colors.black.withOpacity(0.2)),
            Opacity(
              opacity: widget.enabled ? 1.0 : 0.25,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 72,
                  color: widget.highContrast ? Colors.white : Colors.black.withOpacity(0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}