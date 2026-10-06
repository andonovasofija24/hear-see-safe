import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/utils/voice_level.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/utils/book_page_keys.dart';
import 'package:flutter/services.dart';

/// Колку пати поголем текст (како на почетниот екран).
const double _kPbText = 1.6;

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

  /// Тек на прашањето (како кај квизот во Кибер безбедност): трагата е
  /// слушната, колку одговори се веќе изговорени (и достапни), кој се чита.
  bool _quizClueDone = false;
  bool _quizCluePlaying = false;
  int _quizUnlocked = 0;
  int? _quizReadingIndex;
  /// Точно/неточно по прашање - за патеката со резултати горе.
  final List<bool> _quizResults = [];
  /// Колку од особината е изговорено (за текстот што светнува збор по збор).
  final ValueNotifier<double> _clueProgress = ValueNotifier<double>(0);

  String get _langCode => context.locale.languageCode;
  PictureBookCategory get _category => _categories[_categoryIndex];
  PictureBookItem get _item => _category.items[_itemIndex];
  Set<String> get _visited => _visitedByCategory[_category.id] ?? const {};

  late final StreamSubscription<PlayerState> _effectsStateSub;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onBookKey);
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

  /// < > (и стрелките) за листање кога е отворена страница од сликовницата.
  bool _onBookKey(KeyEvent event) {
    if (!mounted || _view != _View.itemDetail) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final dir = bookPageDirection(event);
    if (dir < 0) {
      _goToPrevItem();
      return true;
    }
    if (dir > 0) {
      _goToNextItem();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onBookKey);
    _voiceAssistant.stop();
    _voicePlayer.dispose();
    _effectsPlayer.dispose();
    _flipPlayer.dispose();
    _itemPageController?.dispose();
    _effectsStateSub.cancel();
    _clueProgress.dispose();
    VoiceLevel.speaking.value = false;
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

  /// Избор на категорија со глас (од `CategoryVoiceCommandButton`) - сите
  /// категории се секогаш достапни, нема повеќе заклучување.
  void _selectCategoryByVoice(int index) {
    // Може да се повика и од сликовницата / квизот - прво стопирај звук.
    _voiceAssistant.stop();
    _voicePlayer.stop();
    _enterCategory(index);
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

    // Секој предмет добива описно прашање - само првата реченица од
    // сликовницата (<id>_desc), која никаде не го спомнува името. Предметите
    // СО звук добиваат и прашање „погоди го звукот“. (Реченицата „Научи“ не
    // се користи - речиси секогаш го содржи името и го издава одговорот.)
    final questions = <_QuizQuestion>[];
    for (final i in items) {
      if (i.hasSound) questions.add(_QuizQuestion(i, _ClueType.sound));
      questions.add(_QuizQuestion(i, _ClueType.description));
    }
    questions.shuffle(_random);

    setState(() {
      _quizQuestions = questions;
      _quizQuestionIndex = 0;
      _quizScore = 0;
      _quizResults.clear();
      _view = _View.quiz;
    });
    _prepareQuizQuestion();
  }

  void _prepareQuizQuestion() {
    final q = _quizQuestions[_quizQuestionIndex];
    // Сите предмети од категоријата се опции за одговор.
    final choices = List<PictureBookItem>.from(_category.items)..shuffle(_random);
    setState(() {
      _quizTarget = q.item;
      _quizChoices = choices;
      _quizLocked = false;
      _quizPicked = null;
      _quizPickedCorrect = null;
      _quizClueDone = false;
      _quizCluePlaying = false;
      _quizUnlocked = 0;
      _quizReadingIndex = null;
    });
    _clueProgress.value = 0;
    _runQuizSequence(withIntro: true);
  }

  /// Текстот на трагата за описните прашања (`<id>_quiz_desc`) - посебен
  /// кус опис само за квизот, без името на поимот.
  String _clueKey(_QuizQuestion q) => 'picture_book.${q.item.id}_quiz_desc';

  /// Снимката за трагата: assets/audio/picture_book/<јазик>/<id>_desc.mp3 -
  /// САМО првата реченица (описот).
  String _clueClip(_QuizQuestion q) => '${q.item.id}_desc';

  /// Како квизот во Кибер безбедност: воведна порака → трагата (звукот или
  /// особината) → понудените одговори еден по еден (секое копче станува
  /// достапно штом ќе се изговори неговото име). Повторувањето (`withIntro:
  /// false`) не ги заклучува веќе слушнатите одговори.
  Future<void> _runQuizSequence({required bool withIntro}) async {
    final myToken = ++_narrationToken;
    bool alive() => mounted && myToken == _narrationToken && _view == _View.quiz && !_quizLocked;
    final q = _quizQuestions[_quizQuestionIndex];
    try {
      await _effectsPlayer.stop();
    } catch (_) {}

    if (withIntro) {
      // Насловот - исклучиво снимка, без TTS-резерва (како досега).
      await _speak(q.isSound ? 'quiz_intro' : 'quiz_intro_info', '', allowTtsFallback: false);
      if (!alive()) return;
      await Future.delayed(const Duration(milliseconds: 250));
      if (!alive()) return;
    }

    // Трагата.
    if (!mounted || myToken != _narrationToken) return;
    setState(() => _quizCluePlaying = true);
    if (q.isSound) {
      VoiceLevel.speaking.value = true;
      await _playEffectAndWait(q.item.id);
      VoiceLevel.speaking.value = false;
    } else {
      await _speakWithProgress(_clueClip(q), _clueKey(q).tr(), _clueProgress);
    }
    if (!mounted || myToken != _narrationToken) return;
    setState(() {
      _quizCluePlaying = false;
      _quizClueDone = true;
    });
    if (!alive()) return;

    // Одговорите, еден по еден.
    for (var i = 0; i < _quizChoices.length; i++) {
      await Future.delayed(const Duration(milliseconds: 280));
      if (!alive()) return;
      setState(() => _quizReadingIndex = i);
      final choice = _quizChoices[i];
      await _speak('${choice.id}_name', choice.nameKey.tr());
      if (!mounted || myToken != _narrationToken) return;
      setState(() {
        _quizReadingIndex = null;
        if (_quizUnlocked < i + 1) _quizUnlocked = i + 1;
      });
    }
  }

  /// Како `_speak`, но додека снимката свири го пополнува `progress` (0..1)
  /// - текстот на трагата светнува збор по збор (караоке). Без снимка:
  /// системски глас и проценето време.
  Future<void> _speakWithProgress(String key, String text, ValueNotifier<double> progress) async {
    progress.value = 0;
    Duration? total;
    final posSub = _voicePlayer.onPositionChanged.listen((pos) async {
      total ??= await _voicePlayer.getDuration();
      final ms = total?.inMilliseconds ?? 0;
      if (ms > 0 && mounted) progress.value = (pos.inMilliseconds / ms).clamp(0.0, 1.0);
    });
    // Резерва за системски глас: тече по проценето време, ако позицијата
    // не стигнува (нема снимка).
    final sw = Stopwatch()..start();
    final estimateMs = 70 * text.length + 400;
    final ticker = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted && total == null && sw.elapsedMilliseconds > 600) {
        progress.value = (sw.elapsedMilliseconds / estimateMs).clamp(0.0, 0.98);
      }
    });
    VoiceLevel.speaking.value = true;
    try {
      await _speak(key, text);
    } finally {
      ticker.cancel();
      await posSub.cancel();
      VoiceLevel.speaking.value = false;
      if (mounted) progress.value = 1;
    }
  }

  /// Го пушта звукот на поимот и чека да заврши (најмногу 10 секунди).
  Future<void> _playEffectAndWait(String itemId) async {
    final done = Completer<void>();
    var seenPlaying = false;
    final sub = _effectsPlayer.onPlayerStateChanged.listen((st) {
      if (st == PlayerState.playing) seenPlaying = true;
      if (st == PlayerState.completed || (st == PlayerState.stopped && seenPlaying)) {
        if (!done.isCompleted) done.complete();
      }
    });
    try {
      await _playEffect(itemId);
      // Ако не почне за 3 секунди (нема звук), продолжи.
      await Future.any([
        done.future,
        Future.delayed(const Duration(seconds: 3)).then((_) {
          if (!seenPlaying && !done.isCompleted) done.complete();
          return done.future;
        }),
      ]).timeout(const Duration(seconds: 10), onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  /// Повтори: трагата и одговорите повторно (без воведот).
  void _replayQuizClue() {
    if (_quizLocked) return;
    setState(() => _quizReadingIndex = null);
    _runQuizSequence(withIntro: false);
  }

  /// Штом почне гласовната команда: запри го говорот (за микрофонот да не
  /// го слуша) и отклучи ги сите одговори - детето сака да одговори со глас.
  void _onQuizVoiceStart() {
    _narrationToken++;
    VoiceLevel.speaking.value = false;
    _voicePlayer.stop();
    _effectsPlayer.stop();
    _voiceAssistant.stop();
    if (!mounted) return;
    setState(() {
      _quizReadingIndex = null;
      _quizCluePlaying = false;
      _quizClueDone = true;
      _quizUnlocked = _quizChoices.length;
    });
    _clueProgress.value = 1;
  }

  /// Одговор со глас: името на поимот на кој било од трите јазици.
  void _answerQuizByVoice(PictureBookItem choice) {
    if (_quizLocked || !_quizClueDone) return;
    _answerQuiz(choice);
  }

  /// Имињата (со најчестите облици) на трите јазици - за гласовен одговор.
  static const Map<String, List<String>> _voiceNames = {
    'cat': ['мачка', 'маче', 'cat', 'kitty', 'mace', 'maçe'],
    'dog': ['куче', 'кучe', 'dog', 'puppy', 'qen', 'qeni'],
    'bird': ['птица', 'птичка', 'bird', 'zog', 'zogu'],
    'cow': ['крава', 'cow', 'lopë', 'lope', 'lopa'],
    'rain': ['дожд', 'rain', 'shi', 'shiu'],
    'sun': ['сонце', 'sun', 'diell', 'dielli'],
    'tree': ['дрво', 'tree', 'pemë', 'peme', 'pema'],
    'water': ['вода', 'water', 'ujë', 'uje', 'uji'],
    'fire': ['оган', 'огнот', 'огин', 'fire', 'zjarr', 'zjarri'],
    'wind': ['ветар', 'ветер', 'ветрот', 'wind', 'erë', 'ere', 'era'],
    'car': ['автомобил', 'кола', 'car', 'makinë', 'makine', 'makina'],
    'bicycle': ['велосипед', 'точак', 'bicycle', 'bike', 'bicikletë', 'biciklete', 'biçikletë'],
    'book': ['книга', 'book', 'libër', 'liber', 'libri'],
    'phone': ['телефон', 'phone', 'telephone', 'telefon', 'telefoni'],
    'clock': ['часовник', 'саат', 'clock', 'watch', 'orë', 'ore', 'ora'],
    'star': ['ѕвезда', 'звезда', 'star', 'yll', 'ylli'],
    'moon': ['месечина', 'месечината', 'moon', 'hënë', 'hëna', 'hena', 'hene'],
    'rocket': ['ракета', 'rocket', 'raketë', 'rakete', 'raketa'],
    'planet': ['планета', 'planet', 'planeti'],
    'drum': ['тапан', 'тапанот', 'drum', 'daulle', 'daullja', 'daulja'],
    'guitar': ['гитара', 'guitar', 'kitarë', 'kitare', 'kitara'],
    'bell': ['ѕвонче', 'звонче', 'ѕвоно', 'звоно', 'bell', 'zile', 'zilja'],
  };

  /// Дали транскриптот го содржи името (како посебен збор, со дозволени
  /// наставки: „кучето“, „мачката“, „qeni“...). Кратките зборови (до 3
  /// букви, пр. „shi“, „yll“) мора да се речиси точни.
  static bool _saysItem(String transcript, PictureBookItem item) {
    final names = _voiceNames[item.id] ?? [item.id];
    final words = transcript.toLowerCase().split(RegExp(r'[\s,.!?]+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      for (final n in names) {
        if (w == n) return true;
        final extra = n.length <= 3 ? 1 : 4;
        if (w.startsWith(n) && w.length - n.length <= extra) return true;
      }
    }
    return false;
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
    // Веднаш прекини го звукот / читањето штом ќе се одговори.
    _narrationToken++;
    VoiceLevel.speaking.value = false;
    _voicePlayer.stop();
    _effectsPlayer.stop();
    _voiceAssistant.stop();
    final correct = chosen.id == _quizTarget!.id;
    setState(() {
      _quizLocked = true;
      _quizPicked = chosen;
      _quizPickedCorrect = correct;
      _quizReadingIndex = null;
      _quizCluePlaying = false;
      _quizResults.add(correct);
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

    // Подолго кај погрешен одговор - да се види кој бил точниот.
    await Future.delayed(Duration(milliseconds: correct ? 1100 : 1900));
    if (!mounted || _view != _View.quiz) return;

    final nextIndex = _quizQuestionIndex + 1;
    if (nextIndex >= _quizQuestions.length) {
      final isPerfect = _quizScore >= _quizQuestions.length;
      final retriesUsed = _quizRetriesUsed[_category.id] ?? 0;
      final noRetriesLeft = retriesUsed >= _maxQuizRetries;
      setState(() {
        _view = _View.quizResult;
        // Категоријата се заклучува само ако е совршен резултат ИЛИ ако веќе
        // се искористени сите дозволени обиди.
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
      // Темна позадина со сликите што лебдат: во менито - од сите
      // категории, внатре во категорија - од таа категорија, во нејзината боја.
      bodyBackground: _view == _View.categorySelect
          ? EmojiBackdrop(
              key: const ValueKey('pb-bg-all'),
              emojis: [for (final c in _categories) c.items.first.emoji, for (final c in _categories) c.items.last.emoji],
              tint: const Color(0xFF2563EB),
            )
          : EmojiBackdrop(
              key: ValueKey('pb-bg-${_category.id}'),
              emojis: [for (final i in _category.items) i.emoji],
              tint: _category.color,
            ),
      // Менито со категории, сликовницата и квизот имаат свое копче.
      voiceCommand: _view != _View.categorySelect && _view != _View.itemDetail && _view != _View.quiz,
      voiceOptions: _categoryVoiceOptions(),
      onVoiceBack: _backToCategories,
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
  //
  // Изглед (ист распоред како досега, нова визуелност): темна позадина со
  // сликите што лебдат, бел текст, полно обоени картички за категориите,
  // бели картички за сликовниците и темни „сцени“ за самите сликовници.

  /// Боја на текстот врз темната позадина.
  Color _onBg(bool hc, Color contrast) => hc ? contrast : Colors.white;

  Widget _buildCategorySelect(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    // Низ целиот екран (лизгачот е скроз десно); категориите се по една во
    // ред, во средина, до 980 широки.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final side = ((width - 980) / 2).clamp(20.0, double.infinity);
        const gap = 18.0;
        final compact = width - side * 2 < 560;
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 20, side, 28),
          children: [
            _buildExplanationButton(contrast),
            if (_explanationOpen) _buildExplanationPanel(contrast, _t('intro')),
            const SizedBox(height: 18),
            PopIn(
              index: 0,
              child: Text(
                _t('choose_category'),
                textAlign: TextAlign.center,
                style: GameTypography.heading(context, _onBg(hc, contrast), 28 * _kPbText),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: CategoryVoiceCommandButton(
                options: _categoryVoiceOptions(),
                onBack: () => Navigator.of(context).pop(),
                background: hc ? null : Playful.sun,
                foreground: hc ? null : Playful.ink,
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < _categories.length; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              PopIn(index: 1 + i, child: _categoryCard(context, _categories[i], contrast, hc, compact: compact)),
            ],
          ],
        );
      },
    );
  }

  /// Категориите со глас - во менито со категории, но и од внатре (горе
  /// десно / кај сликовницата), за директно префрлање меѓу категориите.
  List<VoiceCategoryOption> _categoryVoiceOptions() => [
      VoiceCategoryOption(
        keywords: const ['животни', 'animals', 'kafshët', 'kafshet'],
        onSelected: () => _selectCategoryByVoice(0),
      ),
      VoiceCategoryOption(
        keywords: const ['природа', 'nature', 'natyra'],
        onSelected: () => _selectCategoryByVoice(1),
      ),
      VoiceCategoryOption(
        keywords: const [
          'секојдневни предмети',
          'предмети',
          'everyday objects',
          'objects',
          'objekte të përditshme',
          'objekte te perditshme',
          'objekte',
        ],
        onSelected: () => _selectCategoryByVoice(2),
      ),
      VoiceCategoryOption(
        keywords: const ['вселена', 'space', 'hapësira', 'hapesira'],
        onSelected: () => _selectCategoryByVoice(3),
      ),
      VoiceCategoryOption(
        keywords: const ['музика', 'music', 'muzika'],
        onSelected: () => _selectCategoryByVoice(4),
      ),
    ];

  Widget _buildExplanationButton(Color contrast) {
    return PlayfulExplainButton(
      open: _explanationOpen,
      label: _explanationOpen
          ? 'picture_book.explanation_toggle_close'.tr()
          : 'picture_book.explanation_toggle_open'.tr(),
      onTap: _toggleExplanation,
    );
  }

  Widget _categoryCard(BuildContext context, PictureBookCategory cat, Color contrast, bool hc, {bool compact = false}) {
    final index = _categories.indexOf(cat);
    final seen = _visitedByCategory[cat.id] ?? const <String>{};
    final visitedCount = seen.length;
    final total = cat.items.length;
    final allSeen = visitedCount >= total;
    final deep = Color.lerp(cat.color, Colors.black, 0.35)!;
    final fg = hc ? const Color(0xFFFFFF00) : Colors.white;
    final iconBox = compact ? 72.0 : 100.0;
    final catIcon = Container(
      width: iconBox,
      height: iconBox,
      decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? Colors.black : Colors.white),
      child: Icon(cat.icon, color: hc ? const Color(0xFFFFFF00) : deep, size: compact ? 42 : 58),
    );
    final arrowBox = compact ? 52.0 : 60.0;
    final arrow = Container(
      width: arrowBox,
      height: arrowBox,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: allSeen ? const Color(0xFF16A34A) : Colors.white.withValues(alpha: hc ? 0.1 : 0.22),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(allSeen ? Icons.check_rounded : Icons.arrow_forward_rounded, color: Colors.white, size: 36),
    );
    final details = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cat.titleKey.tr(), style: GoogleFonts.lexend(fontSize: 30 * _kPbText, fontWeight: FontWeight.w800, color: fg, height: 1.15)),
          const SizedBox(height: 12),
          // Сликовниците од категоријата - прегледаните светат.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in cat.items)
                Opacity(
                  opacity: seen.contains(item.id) ? 1.0 : 0.45,
                  child: Text(item.emoji, style: const TextStyle(fontSize: 32)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : visitedCount / total,
              minHeight: 11,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(hc ? const Color(0xFFFFFF00) : Playful.sun),
            ),
          ),
          const SizedBox(height: 8),
          Text('$visitedCount / $total ${_t('seen')}',
              style: GoogleFonts.lexend(fontSize: 16 * _kPbText, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
    // Категориите НЕ се заклучуваат - секогаш достапни за допир; прогресот
    // (прегледано) се прикажува само визуелно.
    return Semantics(
      label: '${cat.titleKey.tr()}. $total ${_t('items_count')}. $visitedCount ${_t('seen')}.',
      button: true,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _enterCategory(index),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: hc ? null : LinearGradient(colors: [cat.color, deep], begin: Alignment.topLeft, end: Alignment.bottomRight),
                color: hc ? Colors.black : null,
                border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.85), width: 3),
                boxShadow: hc ? null : [BoxShadow(color: cat.color.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    // Голема бледа слика во аголот - украс.
                    Positioned(
                      right: -10,
                      bottom: -24,
                      child: ExcludeSemantics(
                        child: Opacity(opacity: hc ? 0 : 0.18, child: Text(cat.items.first.emoji, style: const TextStyle(fontSize: 150))),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(compact ? 18 : 22),
                      child: compact
                          // Телефон: иконата и стрелката горе, текстот под нив
                          // во цела ширина (големите букви да собере).
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    catIcon,
                                    const Spacer(),
                                    arrow,
                                  ],
                                ),
                                const SizedBox(height: 14),
                                details,
                              ],
                            )
                          : Row(
                              children: [
                                catIcon,
                                const SizedBox(width: 22),
                                Expanded(child: details),
                                const SizedBox(width: 12),
                                arrow,
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
    );
  }

  // --- Мрежа од картички ---

  Widget _buildItemGrid(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final cat = _category;
    final reviewedNotLocked = _visited.length >= cat.items.length && !_completedCategories.contains(cat.id);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Низ целиот екран: мрежа од сликички (2 колони на телефон, 3 на
        // широк екран - помалку колони, за поголеми картички и букви).
        final width = constraints.maxWidth;
        final columns = width >= 1000 ? 3 : 2;
        return Column(
          children: [
            _buildBackRow(contrast, onBack: _backToCategories),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? Colors.black : cat.color, border: Border.all(color: Colors.white, width: 2)),
                    child: Icon(cat.icon, color: hc ? const Color(0xFFFFFF00) : Colors.white, size: 36),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.titleKey.tr(), style: GameTypography.heading(context, _onBg(hc, contrast), 26 * _kPbText)),
                        Text('${_visited.length} / ${cat.items.length} ${_t('seen')}',
                            style: GameTypography.body(context, _onBg(hc, contrast).withValues(alpha: 0.9), 16 * _kPbText)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (reviewedNotLocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Center(
                  child: StartHotkeyListener(onTrigger: _startQuiz, child: Semantics(
                    label: 'picture_book.go_to_quiz'.tr(),
                    button: true,
                    child: RippleRings(
                      color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                      spread: 12,
                      child: PressableScale(
                        child: Material(
                          color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                          borderRadius: BorderRadius.circular(20),
                          elevation: hc ? 0 : 4,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _startQuiz,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.quiz_rounded, size: 38, color: Playful.ink),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'picture_book.go_to_quiz'.tr(),
                                      textAlign: TextAlign.center,
                                      style: Playful.title(17 * _kPbText, color: Playful.ink),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: cat.items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) => PopIn(index: index, child: _itemCard(context, cat.items[index], index, contrast, hc)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _itemCard(BuildContext context, PictureBookItem item, int index, Color contrast, bool hc) {
    final visited = _visited.contains(item.id);
    final catColor = _category.color;
    return Semantics(
      label: '${item.nameKey.tr()}${visited ? '. ${_t('seen')}' : ''}',
      button: true,
      child: PressableScale(
        child: _GlassItemCard(
          tint: catColor,
          highContrast: hc,
          onTap: () => _openItem(index),
          emoji: item.emoji,
          name: item.nameKey.tr(),
          visited: visited,
        ),
      ),
    );
  }

  // --- Поединечна сликовница ---

  Widget _buildItemDetail(BuildContext context) {
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: [
            Row(
              children: [
                _buildBackRow(contrastColor, onBack: _closeItemDetail),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 16),
                  child: CategoryVoiceCommandButton(
                    compact: true,
                    background: hc ? null : Playful.sun,
                    foreground: hc ? null : Playful.ink,
                    options: [
                      VoiceCategoryOption(
                        keywords: const ['квиз', 'quiz', 'kuiz'],
                        onSelected: _startQuiz,
                      ),
                      ..._categoryVoiceOptions(),
                    ],
                    onBack: _backToCategories,
                  ),
                ),
              ],
            ),
            _buildStorySegments(context),
            // Отворена книга: лево и десно високи ленти за листање (секогаш
            // на исто место), во средина страницата со 3Д прелистување.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stripW = constraints.maxWidth < 480 ? 56.0 : 64.0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: stripW,
                          child: _NavZone(
                            enabled: _hasPrevItem,
                            icon: Icons.chevron_left_rounded,
                            onTap: _goToPrevItem,
                            label: 'picture_book.previous_item'.tr(),
                            highContrast: hc,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: PageView.builder(
                            controller: _itemPageController,
                            itemCount: _category.items.length,
                            onPageChanged: _onItemPageChanged,
                            itemBuilder: (context, index) => _build3DPage(context, contrastColor, _category.items[index], index),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: stripW,
                          child: _NavZone(
                            enabled: _hasNextItem,
                            icon: Icons.chevron_right_rounded,
                            onTap: _goToNextItem,
                            label: 'picture_book.next_item'.tr(),
                            highContrast: hc,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Сегментирана лента на прогрес на врвот - како кај сторија на Инстаграм:
  /// по едно сегментче за секоја сликовница во категоријата.
  Widget _buildStorySegments(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final total = _category.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(total, (i) {
          final filled = i <= _itemIndex;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
              height: i == _itemIndex ? 10 : 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: filled
                    ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
                    : (hc ? AccessibilityUtils.getDisabledColor(context) : Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Ги завиткува сликовниците во лесна 3Д ротација при прелистување.
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

  /// Страница од отворена сликовница: хартија во крем боја со повез лево,
  /// копчето за звук секогаш горе десно, во средина слика + име + опис +
  /// „научи“ + повтори. Листањето е со лентите лево/десно (надвор од
  /// страницата) или со лизгање.
  Widget _itemDetailCard(BuildContext context, Color contrastColor, PictureBookItem item, int index) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final catColor = _category.color;
    final catDeep = Color.lerp(catColor, Colors.black, 0.3)!;
    const yellow = Color(0xFFFFFF00);
    const paper = Color(0xFFFFF8E7);
    const bindingW = 16.0;

    final name = item.nameKey.tr();
    final description = item.descriptionKey.tr();
    final learn = item.learnKey.tr();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: hc ? Colors.black : paper,
        border: Border.all(color: hc ? Colors.white : const Color(0xFFE9D8B4), width: hc ? 3 : 2),
        boxShadow: hc
            ? null
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 12)),
              ],
      ),
      child: Stack(
        children: [
          // Повез (лево) - во HC рамна жолта линија.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: hc ? 8 : bindingW,
            child: ExcludeSemantics(
              child: Container(
                decoration: BoxDecoration(
                  color: hc ? yellow : null,
                  gradient: hc
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF6B3E16), Color(0xFFC08A2E), Color(0xFF8A5520)],
                          stops: [0.0, 0.55, 1.0],
                        ),
                ),
              ),
            ),
          ),
          // Сенка од повезот врз хартијата.
          if (!hc)
            Positioned(
              left: bindingW,
              top: 0,
              bottom: 0,
              width: 26,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withValues(alpha: 0.16), Colors.black.withValues(alpha: 0.0)],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            left: hc ? 8 : bindingW,
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
                    final emojiSize = min((h * 0.2).clamp(72.0, 150.0), w * 0.55);
                    // Текстот ~1.6 пати поголем (тесна страница - малку
                    // помалку, за подолгите зборови да се соберат).
                    final titleSize = (w * 0.15).clamp(32.0, 40.0 * _kPbText);
                    final descSize = (w * 0.085).clamp(24.0, 23.0 * _kPbText);
                    final learnSize = (w * 0.08).clamp(23.0, 21.0 * _kPbText);
                    // На тесна страница содржината почнува под копчето за
                    // звук (горе десно), за да не се преклопуваат.
                    final topPad = w < 520 ? 92.0 : 24.0;

                    return SingleChildScrollView(
                      primary: false,
                      padding: EdgeInsets.fromLTRB(14, topPad, 14, 24),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Сликата во круг со бранови.
                            RippleRings(
                              color: hc ? Colors.white : catColor,
                              active: _itemSoundPlaying && index == _itemIndex,
                              spread: 18,
                              child: Container(
                                padding: EdgeInsets.all(emojiSize * 0.18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hc ? Colors.black : Colors.white,
                                  border: Border.all(color: hc ? Colors.white : catColor.withValues(alpha: 0.35), width: hc ? 2 : 3),
                                ),
                                child: Text(item.emoji, style: TextStyle(fontSize: emojiSize)),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              name,
                              style: GoogleFonts.lexend(fontSize: titleSize, fontWeight: FontWeight.w800, color: hc ? yellow : catDeep, height: 1.1),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              description,
                              style: GoogleFonts.lexend(fontSize: descSize, fontWeight: FontWeight.w600, color: hc ? Colors.white : Playful.ink, height: 1.35),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            // „Научи“ - во балонче во бојата на категоријата.
                            Material(
                              color: hc ? Colors.black : Color.lerp(catColor, Colors.white, 0.86)!,
                              shape: SpeechBubbleBorder(
                                radius: 22,
                                tail: 14,
                                side: hc ? const BorderSide(color: Colors.white, width: 2) : BorderSide(color: catColor.withValues(alpha: 0.45), width: 2),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14 + 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.lightbulb_rounded, color: hc ? yellow : catDeep, size: 34),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        learn,
                                        style: GoogleFonts.lexend(fontSize: learnSize, fontWeight: FontWeight.w600, color: hc ? Colors.white : Playful.ink, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 20,
                              runSpacing: 14,
                              children: [
                                Semantics(
                                  label: 'picture_book.repeat_explanation'.tr(),
                                  button: true,
                                  child: PressableScale(
                                    child: _neonRoundButton(
                                      icon: Icons.replay_rounded,
                                      onTap: _repeatItem,
                                      hc: hc,
                                      neon: const Color(0xFF22D3EE),
                                    ),
                                  ),
                                ),
                                if (_visited.length >= _category.items.length)
                                  StartHotkeyListener(onTrigger: _startQuiz, child: Semantics(
                                    label: 'picture_book.go_to_quiz'.tr(),
                                    button: true,
                                    child: PressableScale(
                                      child: Material(
                                        color: hc ? yellow : const Color(0xFF16A34A),
                                        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                                        elevation: hc ? 0 : 4,
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: _startQuiz,
                                          child: SizedBox(
                                            width: 68,
                                            height: 68,
                                            child: Icon(Icons.quiz_rounded, size: 36, color: hc ? Colors.black : Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )),
                              ],
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
          // Копчето за звук - СЕКОГАШ горе десно на страницата.
          if (item.hasSound)
            Positioned(
              top: 12,
              right: 12,
              child: _buildPlaySoundButton(index),
            ),
        ],
      ),
    );
  }

  /// Тркалезно „неонско“ копче (повтори) - светлечки прстен; во HC рамно
  /// црно со бел раб.
  Widget _neonRoundButton({required IconData icon, required VoidCallback onTap, required bool hc, required Color neon}) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? Colors.black : Playful.night,
        border: Border.all(color: hc ? Colors.white : neon, width: 3),
        boxShadow: hc
            ? null
            : [
                BoxShadow(color: neon.withValues(alpha: 0.65), blurRadius: 18, spreadRadius: 1),
                BoxShadow(color: neon.withValues(alpha: 0.35), blurRadius: 6),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(icon, size: 36, color: hc ? Colors.white : neon),
          ),
        ),
      ),
    );
  }

  /// Големото жолто копче за звук (play/pause) - горе десно на страницата.
  /// Дејствува само на тековната страница (звукот е на тековниот предмет).
  Widget _buildPlaySoundButton(int index) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final playing = _itemSoundPlaying && index == _itemIndex;
    final color = playing ? const Color(0xFFF97316) : (hc ? Colors.black : Playful.sun);
    return Semantics(
      label: playing ? 'picture_book.pause_sound'.tr() : 'picture_book.play_sound'.tr(),
      button: true,
      child: RippleRings(
        color: hc ? Colors.white : Playful.sun,
        active: playing,
        spread: 12,
        child: PressableScale(
          child: Material(
            color: color,
            shape: CircleBorder(side: BorderSide(color: hc ? Colors.white : Playful.ink, width: hc ? 2 : 3)),
            elevation: hc ? 0 : 6,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: index == _itemIndex ? _playItemSound : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: playing
                    ? const SizedBox(width: 40, height: 40, child: Center(child: SoundWave(color: Colors.white, bars: 5, height: 30, barWidth: 5)))
                    : Icon(Icons.volume_up_rounded, size: 40, color: hc ? Colors.white : Playful.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackRow(Color contrast, {required VoidCallback onBack}) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: _t('back_to_categories'),
            button: true,
            child: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: hc ? contrast : Colors.white, size: 30),
              style: IconButton.styleFrom(
                backgroundColor: hc ? null : Colors.white.withValues(alpha: 0.15),
                side: hc ? null : BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
              onPressed: onBack,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationPanel(Color contrast, String text) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hc ? Colors.white : Playful.sun, width: 3),
      ),
      child: Text(text, style: GoogleFonts.lexend(fontSize: 18 * _kPbText, fontWeight: FontWeight.w500, height: 1.5, color: hc ? Colors.white : Playful.ink)),
    );
  }

  // --- Квиз ---
  //
  // Изглед: горе патека со прашањата (точно / неточно / тековно), темна
  // „сцена“ со трагата (звучен круг со бранови или балонче со особината што
  // светнува збор по збор), под неа големи плочки со одговорите. Плочката
  // што се чита свети жолто; додека не се изговори, плочката е бледа и не
  // може да се избере.

  static const Color _quizGreen = Color(0xFF16A34A);
  static const Color _quizRed = Color(0xFFDC2626);

  List<VoiceCategoryOption> _quizVoiceOptions() => [
        for (final choice in _quizChoices)
          VoiceCategoryOption(
            keywords: const [],
            matches: (t) => _saysItem(t, choice),
            onSelected: () => _answerQuizByVoice(choice),
          ),
        ..._categoryVoiceOptions(),
      ];

  /// Боја на текстот врз темната позадина на квизот.
  Color _onQuizBg(bool hc, Color contrast) => hc ? contrast : Colors.white;

  Widget _buildQuiz(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    if (_quizTarget == null) return const SizedBox.shrink();
    // Листата е широка колку екранот (лизгачот е скроз десно), а
    // содржината е во средина, до 980 широка.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 980) / 2).clamp(20.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 32),
          children: [
            _quizTrail(contrast, hc),
            const SizedBox(height: 16),
            _quizStage(contrast, hc),
            const SizedBox(height: 16),
            _quizStatus(contrast, hc),
            const SizedBox(height: 16),
            // Одговорите - еден под друг, како порано.
            for (var i = 0; i < _quizChoices.length; i++) ...[
              _quizAnswerTile(_quizChoices[i], i, contrast, hc),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  /// Патека со прашањата: ✓ точно, ✗ неточно, тековното е поголемо.
  Widget _quizTrail(Color contrast, bool hc) {
    final accent = hc ? AccessibilityUtils.getAccentColor(context) : _category.color;
    final total = _quizQuestions.length;
    return Semantics(
      label: 'picture_book.quiz_progress'.tr(args: ['${_quizQuestionIndex + 1}', '$total']),
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              'picture_book.quiz_progress'.tr(args: ['${_quizQuestionIndex + 1}', '$total']),
              style: GameTypography.heading(context, _onQuizBg(hc, contrast), 24 * _kPbText),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < total; i++)
                  Builder(builder: (context) {
                    final done = i < _quizResults.length;
                    final current = i == _quizQuestionIndex && !done;
                    final size = current ? 48.0 : 38.0;
                    Color bg;
                    Widget inner;
                    if (done) {
                      bg = _quizResults[i] ? _quizGreen : _quizRed;
                      inner = Icon(_quizResults[i] ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 24);
                    } else if (current) {
                      bg = accent;
                      inner = Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22));
                    } else {
                      bg = Colors.transparent;
                      inner = Text('${i + 1}', style: TextStyle(color: _onQuizBg(hc, contrast).withValues(alpha: 0.75), fontWeight: FontWeight.w700, fontSize: 17));
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: size,
                      height: size,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: done || current ? Colors.white : _onQuizBg(hc, contrast).withValues(alpha: 0.45), width: 2),
                        boxShadow: current && !hc ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 10)] : null,
                      ),
                      child: inner,
                    );
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Темната „сцена“ со трагата.
  Widget _quizStage(Color contrast, bool hc) {
    final q = _quizQuestions[_quizQuestionIndex];
    final isSound = q.isSound;
    final title = _t(isSound ? 'quiz_intro' : 'quiz_intro_info');
    final sun = hc ? const Color(0xFFFFFF00) : Playful.sun;

    final Widget clue;
    if (isSound) {
      clue = Semantics(
        button: true,
        label: _t('quiz_replay'),
        child: GestureDetector(
          onTap: _replayQuizClue,
          child: Column(
            children: [
              const SizedBox(height: 8),
              RippleRings(
                color: sun,
                active: _quizCluePlaying,
                spread: 28,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  scale: _quizCluePlaying ? 1.08 : 1.0,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(color: sun, shape: BoxShape.circle),
                    child: Icon(
                      _quizCluePlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                      size: 64,
                      color: Playful.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 36,
                child: _quizCluePlaying
                    ? SoundWave(color: sun, bars: 11, height: 36, barWidth: 6)
                    : null,
              ),
            ],
          ),
        ),
      );
    } else {
      clue = Semantics(
        label: _clueKey(q).tr(),
        child: Material(
          color: Colors.white,
          shape: const SpeechBubbleBorder(radius: 24, tail: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20 + 16),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 12),
                    child: Icon(Icons.format_quote_rounded, size: 44, color: _category.color),
                  ),
                  Expanded(
                    child: KaraokeText(
                      text: _clueKey(q).tr(),
                      progress: _clueProgress,
                      style: GoogleFonts.lexend(fontSize: 24 * _kPbText, fontWeight: FontWeight.w700, height: 1.35),
                      activeColor: const Color(0xFF4338CA),
                      idleColor: const Color(0xFF6B7280),
                      doneColor: Playful.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final replay = Semantics(
      button: true,
      label: _t('quiz_replay_all'),
      child: PressableScale(
        enabled: !_quizLocked,
        child: Material(
          color: sun,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _quizLocked ? null : _replayQuizClue,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.replay_rounded, color: Playful.ink, size: 34),
                  const SizedBox(width: 10),
                  Flexible(child: Text(_t('quiz_replay_all'), textAlign: TextAlign.center, style: Playful.title(17 * _kPbText, color: Playful.ink))),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final voice = CategoryVoiceCommandButton(
      options: _quizVoiceOptions(),
      onBack: _backToCategories,
      onListenStart: _onQuizVoiceStart,
      respondToHotkey: true,
      compact: true,
      background: Colors.white,
      foreground: Playful.ink,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        // Во бојата на категоријата (затемнета за бел текст), со бел раб
        // и сјај - се издвојува од темната позадина.
        gradient: hc
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(_category.color, Playful.night, 0.3)!, Color.lerp(_category.color, Playful.night, 0.62)!],
              ),
        color: hc ? Colors.black : null,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: hc ? 1 : 0.85), width: hc ? 2 : 3),
        boxShadow: hc ? null : [BoxShadow(color: _category.color.withValues(alpha: 0.55), blurRadius: 30, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(isSound ? Icons.hearing_rounded : Icons.lightbulb_rounded, color: sun, size: 39),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Playful.title(22 * _kPbText))),
            ],
          ),
          const SizedBox(height: 18),
          Center(child: clue),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [replay, voice],
          ),
        ],
      ),
    );
  }

  /// Што се случува сега: слушај / слушај ги одговорите / одговори.
  Widget _quizStatus(Color contrast, bool hc) {
    IconData icon;
    String text;
    Color color = _onQuizBg(hc, contrast);
    if (_quizLocked && _quizPickedCorrect != null) {
      final ok = _quizPickedCorrect!;
      icon = ok ? Icons.celebration_rounded : Icons.sentiment_dissatisfied_rounded;
      text = _t(ok ? 'quiz_correct' : 'quiz_incorrect');
      color = hc ? contrast : (ok ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5));
    } else if (!_quizClueDone) {
      icon = Icons.hearing_rounded;
      text = _t('quiz_listen');
    } else if (_quizUnlocked < _quizChoices.length) {
      icon = Icons.record_voice_over_rounded;
      text = _t('quiz_listen_answers');
    } else {
      icon = Icons.touch_app_rounded;
      text = _t('quiz_answer_now');
    }
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(text),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Flexible(
                child: Text(text, textAlign: TextAlign.center, style: GameTypography.heading(context, color, 22 * _kPbText)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Голем тактилен 3Д одговор (еден под друг): лево слика во круг, името,
  /// десно голем златен број / бран (се чита) / ✓ ✗.
  /// Состојби: бледо (сè уште не е изговорен), златен раб + малку поголемо
  /// (се чита), зелено и притиснато (точно), црвено и тресење (погрешно).
  Widget _quizAnswerTile(PictureBookItem choice, int index, Color contrast, bool hc) {
    final isPicked = _quizPicked?.id == choice.id;
    final isCorrectAnswer = choice.id == _quizTarget!.id;
    final unlocked = index < _quizUnlocked;
    final reading = _quizReadingIndex == index;
    final revealCorrect = _quizLocked && isCorrectAnswer && !isPicked;
    final pickedOk = isPicked && _quizPickedCorrect == true;
    final pickedWrong = isPicked && _quizPickedCorrect == false;
    final reduce = Playful.reduceMotion(context);
    const yellow = Color(0xFFFFFF00);

    // Лице, долен раб, текст и рамка на копчето.
    Color face;
    Color edge;
    Color fg;
    Color border;
    double borderW;
    if (hc) {
      face = AccessibilityUtils.getPrimaryButtonBackground(context);
      fg = AccessibilityUtils.getPrimaryButtonForeground(context);
      edge = contrast;
      border = contrast;
      borderW = 2;
    } else {
      face = const Color(0xFFF1F2FF);
      fg = Playful.ink;
      edge = Color.lerp(_category.color, Colors.black, 0.3)!;
      border = Colors.white;
      borderW = 2;
    }
    if (pickedOk) {
      face = hc ? yellow : _quizGreen;
      fg = hc ? Colors.black : Colors.white;
      edge = hc ? Colors.white : const Color(0xFF0E6B31);
      border = Colors.white;
      borderW = 4;
    } else if (pickedWrong) {
      face = hc ? const Color(0xFF3A3A3A) : _quizRed;
      fg = Colors.white;
      edge = hc ? Colors.white : const Color(0xFF8F1717);
      border = Colors.white;
      borderW = 4;
    } else if (revealCorrect) {
      face = hc ? Colors.black : const Color(0xFFDCFCE7);
      fg = hc ? Colors.white : const Color(0xFF14532D);
      edge = hc ? yellow : const Color(0xFF15803D);
      border = hc ? yellow : const Color(0xFF4ADE80);
      borderW = 5;
    } else if (reading) {
      // Караоке: посветло лице, златен раб.
      face = hc ? Colors.black : const Color(0xFFFFF6D1);
      fg = hc ? Colors.white : Playful.ink;
      edge = hc ? yellow : const Color(0xFFB7860B);
      border = hc ? yellow : Playful.sun;
      borderW = 4;
    }

    final dimmed = !unlocked && !reading && !_quizLocked;
    final circle = hc ? Colors.black : (pickedOk || pickedWrong ? Colors.white.withValues(alpha: 0.25) : _category.color.withValues(alpha: 0.15));

    // Десно: бројот на одговорот, бран додека се чита, или ✓ / ✗.
    Widget trailing;
    if (pickedOk || revealCorrect) {
      trailing = _roundBadge(Icons.check_rounded, pickedOk ? Colors.white : _quizGreen, pickedOk ? _quizGreen : Colors.white);
    } else if (pickedWrong) {
      trailing = _roundBadge(Icons.close_rounded, Colors.white, _quizRed);
    } else if (reading) {
      trailing = SizedBox(
        width: 58,
        height: 58,
        child: Center(child: SoundWave(color: hc ? Colors.white : Playful.ink, bars: 5, height: 30, barWidth: 5)),
      );
    } else {
      trailing = _quizNumberBadge(index + 1, hc);
    }

    final content = Row(
      children: [
        Container(
          width: 80,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
          child: Text(choice.emoji, style: const TextStyle(fontSize: 48)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: Duration(milliseconds: reduce ? 0 : 200),
                style: GoogleFonts.lexend(fontSize: (reading && !reduce ? 31 : 28) * _kPbText, fontWeight: FontWeight.w800, color: fg),
                child: Text(choice.nameKey.tr(), maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        trailing,
      ],
    );

    final tile = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: dimmed ? 0.4 : 1.0,
      child: _TactileAnswerButton(
        // Нова состојба за секое прашање (без пренесено тресење/притиснато).
        key: ValueKey('answer-$_quizQuestionIndex-${choice.id}'),
        face: face,
        edge: edge,
        borderColor: border,
        borderWidth: borderW,
        sunk: pickedOk,
        shake: pickedWrong,
        highlight: reading,
        highContrast: hc,
        onTap: () => _answerQuiz(choice),
        child: content,
      ),
    );

    return Semantics(
      button: unlocked && !_quizLocked,
      label: '${index + 1}. ${choice.nameKey.tr()}',
      child: AbsorbPointer(
        absorbing: _quizLocked || !unlocked,
        child: tile,
      ),
    );
  }

  /// Голем златен број на одговорот (1-4), како копче од тастатура.
  Widget _quizNumberBadge(int number, bool hc) {
    final bg = hc ? const Color(0xFFFFFF00) : Playful.sun;
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: hc ? Colors.white : Playful.ink, width: hc ? 3 : 2.5),
        boxShadow: hc ? null : [BoxShadow(color: Color.lerp(Playful.sun, Colors.black, 0.4)!, offset: const Offset(0, 4), blurRadius: 0)],
      ),
      child: Text('$number', style: Playful.display(30, color: hc ? Colors.black : Playful.ink)),
    );
  }

  Widget _roundBadge(IconData icon, Color fg, Color bg) => Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
        child: Icon(icon, color: fg, size: 36),
      );

  Widget _buildQuizResult(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = _onQuizBg(hc, AccessibilityUtils.getContrastColor(context));
    final isPerfect = _quizScore >= _quizQuestions.length;
    final retriesUsed = _quizRetriesUsed[_category.id] ?? 0;
    final retriesLeft = isPerfect ? 0 : (_maxQuizRetries - retriesUsed);
    final sun = hc ? const Color(0xFFFFFF00) : Playful.sun;
    // Широка колку екранот (лизгачот скроз десно), содржината во средина.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 760) / 2).clamp(24.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 40, side, 32),
          children: [
            PopIn(
              index: 0,
              child: Center(
                child: RippleRings(
                  color: _category.color,
                  spread: 24,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Playful.night,
                      shape: BoxShape.circle,
                      border: Border.all(color: sun, width: 5),
                    ),
                    child: Icon(isPerfect ? Icons.emoji_events_rounded : Icons.star_rounded, size: 76, color: sun),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            PopIn(
              index: 1,
              child: Text(
                'picture_book.quiz_result'.tr(args: [_quizScore.toString(), _quizQuestions.length.toString()]),
                textAlign: TextAlign.center,
                style: GameTypography.heading(context, contrast, 28 * _kPbText),
              ),
            ),
            const SizedBox(height: 16),
            // По една ѕвезда за секое прашање: полна = точно.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _quizResults.length; i++)
                  PopIn(
                    index: 2 + i,
                    stepMs: 90,
                    child: Icon(
                      _quizResults[i] ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 40,
                      color: _quizResults[i] ? (hc ? sun : const Color(0xFFF59E0B)) : contrast.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            if (retriesLeft > 0) ...[
              Text(
                'picture_book.retries_left'.tr(args: [retriesLeft.toString()]),
                textAlign: TextAlign.center,
                style: GameTypography.body(context, contrast, 17 * _kPbText),
              ),
              const SizedBox(height: 12),
              StartHotkeyListener(
                onTrigger: _retryQuiz,
                child: _resultButton(icon: Icons.refresh_rounded, label: _t('retry_quiz'), color: _quizGreen, onTap: _retryQuiz),
              ),
              const SizedBox(height: 12),
            ],
            _resultButton(icon: Icons.grid_view_rounded, label: _t('back_to_categories'), color: const Color(0xFF2563EB), onTap: _backToCategories),
          ],
        );
      },
    );
  }

  Widget _resultButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return PressableScale(
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Flexible(child: Text(label, textAlign: TextAlign.center, style: Playful.title(20 * _kPbText))),
              ],
            ),
          ),
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
  bool _hovered = false;

  void _setPressed(bool value) {
    // Отпуштањето секогаш се прифаќа (лентата е иста за сите страници).
    if (!widget.enabled && value) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.highContrast;
    const yellow = Color(0xFFFFFF00);
    // Висока заоблена лента: проѕирна со бел раб, златна при допир/лебдење.
    final active = widget.enabled && (_pressed || _hovered);
    final Color bg;
    final Color borderColor;
    final Color iconColor;
    if (hc) {
      bg = active ? yellow : Colors.black;
      borderColor = active ? yellow : Colors.white;
      iconColor = active ? Colors.black : Colors.white;
    } else {
      bg = active ? Playful.sun.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.12);
      borderColor = active ? Playful.sun : Colors.white.withValues(alpha: 0.75);
      iconColor = active ? Playful.ink : Colors.white;
    }
    return Semantics(
      label: widget.label,
      button: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.enabled ? widget.onTap : null,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.3,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor, width: hc ? 3 : 2),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 52, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Стаклена картичка за предмет во мрежата: проѕирна нијанса во бојата на
/// категоријата, бел раб, замаглена позадина. Сликата малку се зголемува и
/// еднаш се „заниша“ при лебдење / фокус / допир. Во HC: рамна, црна, бел раб.
class _GlassItemCard extends StatefulWidget {
  final Color tint;
  final bool highContrast;
  final VoidCallback onTap;
  final String emoji;
  final String name;
  final bool visited;

  const _GlassItemCard({
    required this.tint,
    required this.highContrast,
    required this.onTap,
    required this.emoji,
    required this.name,
    required this.visited,
  });

  @override
  State<_GlassItemCard> createState() => _GlassItemCardState();
}

class _GlassItemCardState extends State<_GlassItemCard> with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;
  late final AnimationController _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  bool get _active => _hover || _focus || _pressed;

  void _update({bool? hover, bool? focus, bool? pressed}) {
    if (!mounted) return;
    final wasActive = _active;
    setState(() {
      if (hover != null) _hover = hover;
      if (focus != null) _focus = focus;
      if (pressed != null) _pressed = pressed;
    });
    if (!wasActive && _active && !Playful.reduceMotion(context)) {
      _wiggle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.highContrast;
    final reduce = Playful.reduceMotion(context);
    final radius = BorderRadius.circular(24);
    final active = _active;

    final icon = AnimatedScale(
      scale: active && !reduce ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedBuilder(
        animation: _wiggle,
        builder: (context, child) => Transform.rotate(
          angle: sin(_wiggle.value * pi * 2) * 0.06,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hc ? Colors.black : Colors.white.withValues(alpha: 0.16),
            border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.4), width: hc ? 2 : 1.5),
          ),
          child: FittedBox(child: Text(widget.emoji, style: const TextStyle(fontSize: 70))),
        ),
      ),
    );

    final content = Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: icon),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(fontSize: 22 * _kPbText, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.visited)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF16A34A), border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
            ),
          ),
      ],
    );

    final face = Color.alphaBlend(Colors.white.withValues(alpha: 0.08), widget.tint.withValues(alpha: 0.18));
    final card = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap,
        onHover: (v) => _update(hover: v),
        onFocusChange: (v) => _update(focus: v),
        onHighlightChanged: (v) => _update(pressed: v),
        child: Ink(
          decoration: BoxDecoration(
            color: hc ? Colors.black : face,
            borderRadius: radius,
            border: Border.all(
              color: hc ? (active ? const Color(0xFFFFFF00) : Colors.white) : Colors.white.withValues(alpha: active ? 0.85 : 0.5),
              width: hc ? 2 : 1.75,
            ),
          ),
          child: content,
        ),
      ),
    );

    if (hc) {
      return ClipRRect(borderRadius: radius, child: card);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: card,
      ),
    );
  }
}

/// Големо „тактилно“ 3Д копче за одговор во квизот: полна боја со дебел
/// потемнет долен раб што потонува при притискање. Точниот одговор
/// останува притиснат (`sunk`), погрешниот еднаш се тресе (`shake`), а
/// одговорот што се чита моментално малку се зголемува (`highlight`).
/// Самото дејство (`onTap`) се повикува точно еднаш, преку InkWell.
class _TactileAnswerButton extends StatefulWidget {
  final Widget child;
  final Color face;
  final Color edge;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback onTap;
  final bool sunk;
  final bool shake;
  final bool highlight;
  final bool highContrast;

  const _TactileAnswerButton({
    super.key,
    required this.child,
    required this.face,
    required this.edge,
    required this.borderColor,
    required this.borderWidth,
    required this.onTap,
    required this.sunk,
    required this.shake,
    required this.highlight,
    required this.highContrast,
  });

  @override
  State<_TactileAnswerButton> createState() => _TactileAnswerButtonState();
}

class _TactileAnswerButtonState extends State<_TactileAnswerButton> with SingleTickerProviderStateMixin {
  static const double _depth = 8;
  static const double _sink = 6;
  bool _down = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void didUpdateWidget(covariant _TactileAnswerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !oldWidget.shake && !Playful.reduceMotion(context)) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = Playful.reduceMotion(context);
    final hc = widget.highContrast;
    final down = widget.sunk || _down;
    final drop = down ? _sink : 0.0;
    final radius = BorderRadius.circular(24);

    Widget button = AnimatedPadding(
      duration: Duration(milliseconds: reduce ? 0 : 110),
      curve: Curves.easeOut,
      // Вкупната висина е секогаш иста - се поместува само лицето.
      padding: EdgeInsets.only(top: drop, bottom: _depth - drop),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduce ? 0 : 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: widget.face,
          borderRadius: radius,
          border: Border.all(color: widget.borderColor, width: widget.borderWidth),
          boxShadow: [
            // Дебелиот долен раб (без замаглување) - се смалува кога е притиснато.
            BoxShadow(color: widget.edge, offset: Offset(0, _depth - drop), blurRadius: 0),
            if (widget.highlight && !hc) BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: 22, spreadRadius: 1),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onHighlightChanged: (v) {
              if (mounted && _down != v) setState(() => _down = v);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    button = AnimatedScale(
      duration: Duration(milliseconds: reduce ? 0 : 220),
      curve: Curves.easeOutBack,
      scale: widget.highlight && !reduce ? 1.04 : 1.0,
      child: button,
    );

    // Погрешен одговор - копчето кратко „одмавнува“ (±10px).
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final v = _shake.value;
        final dx = sin(v * pi * 6) * 10 * (1 - v);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: button,
    );
  }
}