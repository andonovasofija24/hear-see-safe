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
import 'package:hear_and_see_safe/widgets/picture_book_scenes/scene_contract.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/nature_tree_scene.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/objects_belt_scene.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/orbit_scenes.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/nutrition_pyramid_scene.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/world_cultures_scene.dart';
import 'package:hear_and_see_safe/widgets/picture_book_scenes/institutions_square_scene.dart';

/// Колку пати поголем текст (како на почетниот екран).
const double _kPbText = 1.6;

/// Мултимедијална сликовница за слабовиди/наглуви (модул „Учи и Слушај“).
/// Тек: категории -> сцена на категоријата (дрво, лента, планета, уво, лав)
/// со 10 поими и стрелки ← → -> поединечна сликовница по поим -> назад се
/// враќа на сцената со истиот поим избран. Квизот е СЕКОГАШ достапен (дел
/// од сцената, копче С).
class PictureBookScreen extends StatefulWidget {
  const PictureBookScreen({super.key});

  @override
  State<PictureBookScreen> createState() => _PictureBookScreenState();
}

enum _View { categorySelect, stage, itemDetail, quiz, quizResult }

class _PictureBookScreenState extends State<PictureBookScreen> with TickerProviderStateMixin {
  late VoiceAssistantService _voiceAssistant;
  PageController? _itemPageController;
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  final AudioPlayer _flipPlayer = AudioPlayer();
  final Random _random = Random();

  static const List<PictureBookCategory> _categories = [
    PictureBookCategory(
      id: 'institutions',
      titleKey: 'picture_book.category_institutions',
      icon: Icons.account_balance_rounded,
      color: Color(0xFF2563EB),
      items: [
        PictureBookItem(id: 'institution_city_hall', nameKey: 'picture_book.institution_city_hall', descriptionKey: 'picture_book.institution_city_hall_desc', learnKey: 'picture_book.institution_city_hall_learn', emoji: '🏛️', hasSound: false),
        PictureBookItem(id: 'institution_hospital', nameKey: 'picture_book.institution_hospital', descriptionKey: 'picture_book.institution_hospital_desc', learnKey: 'picture_book.institution_hospital_learn', emoji: '🏥', hasSound: false),
        PictureBookItem(id: 'institution_school', nameKey: 'picture_book.institution_school', descriptionKey: 'picture_book.institution_school_desc', learnKey: 'picture_book.institution_school_learn', emoji: '🏫', hasSound: false),
        PictureBookItem(id: 'institution_library', nameKey: 'picture_book.institution_library', descriptionKey: 'picture_book.institution_library_desc', learnKey: 'picture_book.institution_library_learn', emoji: '📚', hasSound: false),
        PictureBookItem(id: 'institution_police', nameKey: 'picture_book.institution_police', descriptionKey: 'picture_book.institution_police_desc', learnKey: 'picture_book.institution_police_learn', emoji: '🚓', hasSound: false),
        PictureBookItem(id: 'institution_fire_station', nameKey: 'picture_book.institution_fire_station', descriptionKey: 'picture_book.institution_fire_station_desc', learnKey: 'picture_book.institution_fire_station_learn', emoji: '🚒', hasSound: false),
        PictureBookItem(id: 'institution_post_office', nameKey: 'picture_book.institution_post_office', descriptionKey: 'picture_book.institution_post_office_desc', learnKey: 'picture_book.institution_post_office_learn', emoji: '📮', hasSound: false),
        PictureBookItem(id: 'institution_museum', nameKey: 'picture_book.institution_museum', descriptionKey: 'picture_book.institution_museum_desc', learnKey: 'picture_book.institution_museum_learn', emoji: '🖼️', hasSound: false),
      ],
    ),

    PictureBookCategory(
      id: 'cultures',
      titleKey: 'picture_book.category_cultures',
      icon: Icons.public_rounded,
      color: Color(0xFF0F766E),
      items: [
        PictureBookItem(id: 'culture_japan', nameKey: 'picture_book.culture_japan', descriptionKey: 'picture_book.culture_japan_desc', learnKey: 'picture_book.culture_japan_learn', emoji: '🌸', hasSound: false),
        PictureBookItem(id: 'culture_egypt', nameKey: 'picture_book.culture_egypt', descriptionKey: 'picture_book.culture_egypt_desc', learnKey: 'picture_book.culture_egypt_learn', emoji: '🏺', hasSound: false),
        PictureBookItem(id: 'culture_italy', nameKey: 'picture_book.culture_italy', descriptionKey: 'picture_book.culture_italy_desc', learnKey: 'picture_book.culture_italy_learn', emoji: '🏛️', hasSound: false),
        PictureBookItem(id: 'culture_mexico', nameKey: 'picture_book.culture_mexico', descriptionKey: 'picture_book.culture_mexico_desc', learnKey: 'picture_book.culture_mexico_learn', emoji: '🎨', hasSound: false),
        PictureBookItem(id: 'culture_france', nameKey: 'picture_book.culture_france', descriptionKey: 'picture_book.culture_france_desc', learnKey: 'picture_book.culture_france_learn', emoji: '🗼', hasSound: false),
        PictureBookItem(id: 'culture_greece', nameKey: 'picture_book.culture_greece', descriptionKey: 'picture_book.culture_greece_desc', learnKey: 'picture_book.culture_greece_learn', emoji: '🏺', hasSound: false),
        PictureBookItem(id: 'culture_china', nameKey: 'picture_book.culture_china', descriptionKey: 'picture_book.culture_china_desc', learnKey: 'picture_book.culture_china_learn', emoji: '🏮', hasSound: false),
        PictureBookItem(id: 'culture_india', nameKey: 'picture_book.culture_india', descriptionKey: 'picture_book.culture_india_desc', learnKey: 'picture_book.culture_india_learn', emoji: '🕌', hasSound: false),
        PictureBookItem(id: 'culture_kenya', nameKey: 'picture_book.culture_kenya', descriptionKey: 'picture_book.culture_kenya_desc', learnKey: 'picture_book.culture_kenya_learn', emoji: '🪘', hasSound: false),
        PictureBookItem(id: 'culture_turkey', nameKey: 'picture_book.culture_turkey', descriptionKey: 'picture_book.culture_turkey_desc', learnKey: 'picture_book.culture_turkey_learn', emoji: '🧿', hasSound: false),
      ],
    ),

    PictureBookCategory(
      id: 'nutrition',
      titleKey: 'picture_book.category_nutrition',
      icon: Icons.restaurant_rounded,
      color: Color(0xFFB45309),
      items: [
        PictureBookItem(id: 'food_sweets', nameKey: 'picture_book.food_sweets', descriptionKey: 'picture_book.food_sweets_desc', learnKey: 'picture_book.food_sweets_learn', emoji: '🍬', hasSound: false),
        PictureBookItem(id: 'food_dairy', nameKey: 'picture_book.food_dairy', descriptionKey: 'picture_book.food_dairy_desc', learnKey: 'picture_book.food_dairy_learn', emoji: '🥛', hasSound: false),
        PictureBookItem(id: 'food_meat', nameKey: 'picture_book.food_meat', descriptionKey: 'picture_book.food_meat_desc', learnKey: 'picture_book.food_meat_learn', emoji: '🍗', hasSound: false),
        PictureBookItem(id: 'food_fish', nameKey: 'picture_book.food_fish', descriptionKey: 'picture_book.food_fish_desc', learnKey: 'picture_book.food_fish_learn', emoji: '🐟', hasSound: false),
        PictureBookItem(id: 'food_fruit', nameKey: 'picture_book.food_fruit', descriptionKey: 'picture_book.food_fruit_desc', learnKey: 'picture_book.food_fruit_learn', emoji: '🍎', hasSound: false),
        PictureBookItem(id: 'food_vegetables', nameKey: 'picture_book.food_vegetables', descriptionKey: 'picture_book.food_vegetables_desc', learnKey: 'picture_book.food_vegetables_learn', emoji: '🥦', hasSound: false),
        PictureBookItem(id: 'food_grains', nameKey: 'picture_book.food_grains', descriptionKey: 'picture_book.food_grains_desc', learnKey: 'picture_book.food_grains_learn', emoji: '🍞', hasSound: false),
        PictureBookItem(id: 'food_legumes', nameKey: 'picture_book.food_legumes', descriptionKey: 'picture_book.food_legumes_desc', learnKey: 'picture_book.food_legumes_learn', emoji: '🫘', hasSound: false),
        PictureBookItem(id: 'food_nuts', nameKey: 'picture_book.food_nuts', descriptionKey: 'picture_book.food_nuts_desc', learnKey: 'picture_book.food_nuts_learn', emoji: '🥜', hasSound: false),
        PictureBookItem(id: 'food_water', nameKey: 'picture_book.food_water', descriptionKey: 'picture_book.food_water_desc', learnKey: 'picture_book.food_water_learn', emoji: '💧', hasSound: false),
      ],
    ),

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
        PictureBookItem(id: 'horse', nameKey: 'picture_book.horse', descriptionKey: 'picture_book.horse_desc', learnKey: 'picture_book.horse_learn', emoji: '🐴'),
        PictureBookItem(id: 'sheep', nameKey: 'picture_book.sheep', descriptionKey: 'picture_book.sheep_desc', learnKey: 'picture_book.sheep_learn', emoji: '🐑'),
        PictureBookItem(id: 'pig', nameKey: 'picture_book.pig', descriptionKey: 'picture_book.pig_desc', learnKey: 'picture_book.pig_learn', emoji: '🐷'),
        PictureBookItem(id: 'duck', nameKey: 'picture_book.duck', descriptionKey: 'picture_book.duck_desc', learnKey: 'picture_book.duck_learn', emoji: '🦆'),
        PictureBookItem(id: 'frog', nameKey: 'picture_book.frog', descriptionKey: 'picture_book.frog_desc', learnKey: 'picture_book.frog_learn', emoji: '🐸'),
        PictureBookItem(id: 'rooster', nameKey: 'picture_book.rooster', descriptionKey: 'picture_book.rooster_desc', learnKey: 'picture_book.rooster_learn', emoji: '🐓'),
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
        PictureBookItem(id: 'thunder', nameKey: 'picture_book.thunder', descriptionKey: 'picture_book.thunder_desc', learnKey: 'picture_book.thunder_learn', emoji: '⛈️'),
        PictureBookItem(id: 'snow', nameKey: 'picture_book.snow', descriptionKey: 'picture_book.snow_desc', learnKey: 'picture_book.snow_learn', emoji: '❄️', hasSound: false),
        PictureBookItem(id: 'flower', nameKey: 'picture_book.flower', descriptionKey: 'picture_book.flower_desc', learnKey: 'picture_book.flower_learn', emoji: '🌸', hasSound: false),
        PictureBookItem(id: 'sea', nameKey: 'picture_book.sea', descriptionKey: 'picture_book.sea_desc', learnKey: 'picture_book.sea_learn', learn2Key: 'picture_book.sea_learn2', emoji: '🌊'),
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
        PictureBookItem(id: 'door', nameKey: 'picture_book.door', descriptionKey: 'picture_book.door_desc', learnKey: 'picture_book.door_learn', learn2Key: 'picture_book.door_learn2', emoji: '🚪'),
        PictureBookItem(id: 'key', nameKey: 'picture_book.key', descriptionKey: 'picture_book.key_desc', learnKey: 'picture_book.key_learn', learn2Key: 'picture_book.key_learn2', emoji: '🔑'),
        PictureBookItem(id: 'scissors', nameKey: 'picture_book.scissors', descriptionKey: 'picture_book.scissors_desc', learnKey: 'picture_book.scissors_learn', learn2Key: 'picture_book.scissors_learn2', emoji: '✂️'),
        PictureBookItem(id: 'toothbrush', nameKey: 'picture_book.toothbrush', descriptionKey: 'picture_book.toothbrush_desc', learnKey: 'picture_book.toothbrush_learn', emoji: '🪥'),
        PictureBookItem(id: 'glass', nameKey: 'picture_book.glass', descriptionKey: 'picture_book.glass_desc', learnKey: 'picture_book.glass_learn', emoji: '🥛'),
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
        PictureBookItem(id: 'earth', nameKey: 'picture_book.earth', descriptionKey: 'picture_book.earth_desc', learnKey: 'picture_book.earth_learn', emoji: '🌍', hasSound: false),
        PictureBookItem(id: 'astronaut', nameKey: 'picture_book.astronaut', descriptionKey: 'picture_book.astronaut_desc', learnKey: 'picture_book.astronaut_learn', emoji: '🧑‍🚀', hasSound: false),
        PictureBookItem(id: 'comet', nameKey: 'picture_book.comet', descriptionKey: 'picture_book.comet_desc', learnKey: 'picture_book.comet_learn', emoji: '☄️', hasSound: false),
        PictureBookItem(id: 'satellite', nameKey: 'picture_book.satellite', descriptionKey: 'picture_book.satellite_desc', learnKey: 'picture_book.satellite_learn', emoji: '🛰️'),
        PictureBookItem(id: 'ufo', nameKey: 'picture_book.ufo', descriptionKey: 'picture_book.ufo_desc', learnKey: 'picture_book.ufo_learn', emoji: '🛸'),
        PictureBookItem(id: 'telescope', nameKey: 'picture_book.telescope', descriptionKey: 'picture_book.telescope_desc', learnKey: 'picture_book.telescope_learn', emoji: '🔭', hasSound: false),
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
        PictureBookItem(id: 'piano', nameKey: 'picture_book.piano', descriptionKey: 'picture_book.piano_desc', learnKey: 'picture_book.piano_learn', emoji: '🎹'),
        PictureBookItem(id: 'violin', nameKey: 'picture_book.violin', descriptionKey: 'picture_book.violin_desc', learnKey: 'picture_book.violin_learn', emoji: '🎻'),
        PictureBookItem(id: 'trumpet', nameKey: 'picture_book.trumpet', descriptionKey: 'picture_book.trumpet_desc', learnKey: 'picture_book.trumpet_learn', emoji: '🎺'),
        PictureBookItem(id: 'saxophone', nameKey: 'picture_book.saxophone', descriptionKey: 'picture_book.saxophone_desc', learnKey: 'picture_book.saxophone_learn', emoji: '🎷'),
        PictureBookItem(id: 'accordion', nameKey: 'picture_book.accordion', descriptionKey: 'picture_book.accordion_desc', learnKey: 'picture_book.accordion_learn', emoji: '🪗'),
        PictureBookItem(id: 'banjo', nameKey: 'picture_book.banjo', descriptionKey: 'picture_book.banjo_desc', learnKey: 'picture_book.banjo_learn', emoji: '🪕'),
        PictureBookItem(id: 'microphone', nameKey: 'picture_book.microphone', descriptionKey: 'picture_book.microphone_desc', learnKey: 'picture_book.microphone_learn', emoji: '🎤'),
      ],
    ),
  ];

  _View _view = _View.categorySelect;
  int _categoryIndex = 0;

  /// Отворената страница во менито-книга и насоката на прелистување.
  int _bookPage = 0;
  bool _bookForward = true;
  int _bookFrom = 0;
  bool _bookFlipping = false;
  late final AnimationController _flipCtl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  int _itemIndex = 0;
  bool _explanationOpen = false;
  /// Дали моментално свири звукот на предметот (за копчето play/pause).
  bool _itemSoundPlaying = false;

  /// Кои предмети (по id) се веќе прегледани, по категорија (по id).
  final Map<String, Set<String>> _visitedByCategory = {};

  /// Избраниот поим на сцената на категоријата (светнат, се отвора на
  /// допир / Enter). Се ресетира на 0 при влез во категорија.
  int _stageIndex = 0;

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
    _loadSoundAssets();
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
  /// На сцената на категоријата: ← / → (и < >) го менуваат избраниот поим,
  /// Enter / Space го отвораат.
  bool _onBookKey(KeyEvent event) {
    if (!mounted || (_view != _View.itemDetail && _view != _View.stage)) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_view == _View.stage) return _onStageKey(event);
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

  bool _onStageKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Додека се пишува во поле - копчињата се за полето.
    final focus = FocusManager.instance.primaryFocus;
    final focusCtx = focus?.context;
    if (focusCtx != null &&
        (focusCtx.widget is EditableText || focusCtx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final key = event.physicalKey;
    if (key == PhysicalKeyboardKey.arrowLeft || key == PhysicalKeyboardKey.comma) {
      _stageStep(-1);
      return true;
    }
    if (key == PhysicalKeyboardKey.arrowRight || key == PhysicalKeyboardKey.period) {
      _stageStep(1);
      return true;
    }
    if (event is KeyDownEvent &&
        (key == PhysicalKeyboardKey.enter || key == PhysicalKeyboardKey.numpadEnter || key == PhysicalKeyboardKey.space)) {
      // Ако е фокусирано конкретно копче (Tab), Enter / Space го притиска
      // него (на пр. стрелката или квизот) - не го отвораме поимот двапати.
      if (focus != null && focus is! FocusScopeNode) return false;
      _openStageItem();
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
    _flipCtl.dispose();
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
    // Сите останати го користат сопственото id како име на датотека
    // (rain, bird, horse, door, glass, satellite, piano, microphone...).
  };

  /// Кои звучни ефекти навистина постојат во апликацијата. Поим без своја
  /// датотека се однесува како „без звук“ (нема копче за звук и нема
  /// тивко прашање „Погоди го звукот“) додека не се додаде снимката.
  Set<String>? _soundAssets;

  Future<void> _loadSoundAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final set = manifest.listAssets().where((a) => a.startsWith('assets/sounds/sound_identification/')).toSet();
      if (mounted) setState(() => _soundAssets = set);
    } catch (_) {}
  }

  bool _hasSound(PictureBookItem item) {
    if (!item.hasSound) return false;
    final assets = _soundAssets;
    if (assets == null) return true; // уште се вчитува - како порано
    final file = _soundFileById[item.id] ?? item.id;
    return assets.contains('assets/sounds/sound_identification/$file.mp3');
  }

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
  // Категории -> сцена на категоријата.
  // =====================================================================

  void _enterCategory(int index) {
    _narrationToken++;
    _visitedByCategory.putIfAbsent(_categories[index].id, () => {});
    setState(() {
      _categoryIndex = index;
      _bookPage = index;
      _stageIndex = 0;
      _view = _View.stage;
    });
  }

  /// Избор на поим на сцената (допир на неизбран поим во сцената).
  void _selectStageItem(int index) {
    final n = _category.items.length;
    if (n == 0) return;
    final next = ((index % n) + n) % n;
    if (next == _stageIndex) return;
    setState(() => _stageIndex = next);
    HapticFeedback.selectionClick();
    _playFlipSound();
  }

  /// ← / → (стрелките под сцената и на тастатура) - кружно.
  void _stageStep(int delta) => _selectStageItem(_stageIndex + delta);

  /// Го отвора избраниот поим од сцената.
  void _openStageItem() {
    final n = _category.items.length;
    if (n == 0) return;
    _openItem(_stageIndex.clamp(0, n - 1));
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

  /// Од резултатот на квизот назад на сцената на категоријата.
  void _backToStage() {
    _narrationToken++;
    _voiceAssistant.stop();
    _voicePlayer.stop();
    setState(() => _view = _View.stage);
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

  // Претходно снимени имиња на знаменитости (без системски TTS).
  // Пример: assets/audio/picture_book/mk/culture_japan_landmark_1.mp3
  Future<void> _playCultureLandmark(String countryId, int number) async {
    if (_category.id != 'cultures') return;
    final key = 'picture_book.${countryId}_landmark_$number';
    await _speak('${countryId}_landmark_$number', key.tr(), allowTtsFallback: false);
  }

  Future<void> _playCultureLandmarksSequence(String countryId, int token) async {
    if (_category.id != 'cultures') return;
    for (var number = 1; number <= 3; number++) {
      if (!mounted || token != _narrationToken || _item.id != countryId) return;
      await _playCultureLandmark(countryId, number);
    }
  }

  Future<void> _announceItem() async {
    final myToken = ++_narrationToken;
    final item = _item;
    final fallback = '${item.nameKey.tr()}. ${item.descriptionKey.tr()}. ${item.learnKey.tr()}';
    await _speak('${item.id}_explanation', fallback);
    if (!mounted || myToken != _narrationToken) return;
    await _playCultureLandmarksSequence(item.id, myToken);
  }

  Future<void> _repeatItem() async {
    final myToken = ++_narrationToken;
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 100);
    }
    final item = _item;
    final fallback = '${item.nameKey.tr()}. ${item.descriptionKey.tr()}. ${item.learnKey.tr()}';
    await _speak('${item.id}_explanation', fallback);
    if (!mounted || myToken != _narrationToken) return;
    if (item.learn2Key != null) {
      final remember = _t('remember');
      final learn2 = item.learn2Key!.tr();
      await _speak('${item.id}_extra', '$remember $learn2');
    }
    if (!mounted || myToken != _narrationToken) return;
    await _playCultureLandmarksSequence(item.id, myToken);
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
    if (!mounted) return;
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

  /// Го означува тековниот предмет како прегледан. Квизот НЕ зависи од
  /// ова - секогаш е достапен (на сцената и на секоја сликовница).
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
    if (!_hasNextItem) return;
    if (_view == _View.itemDetail) {
      _onItemPageChanged(_itemIndex + 1);
      return;
    }
    _itemPageController!.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  void _goToPrevItem() {
    if (!_hasPrevItem) return;
    if (_view == _View.itemDetail) {
      _onItemPageChanged(_itemIndex - 1);
      return;
    }
    _itemPageController!.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
  }

  /// Затворање на сликовницата за предметот - се означува како прегледано и
  /// се враќа на сцената на категоријата.
  void _closeItemDetail() {
    _narrationToken++;
    // Веднаш прекини секаков говор/звук за предметот - не смее да продолжи
    // да се слуша откако веќе си излегол од сликовницата.
    _voiceAssistant.stop();
    _voicePlayer.stop();
    _effectsPlayer.stop();

    _markCurrentVisitedAndMaybeQuiz();
    // Назад на сцената - со истиот поим избран.
    setState(() {
      _stageIndex = _itemIndex;
      _view = _View.stage;
    });
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
  // Мини-квиз - СЕКОГАШ достапен (од сцената, од сликовницата, копче С),
  // без услов сите поими да се прегледани и без ограничување на обидите.
  // =====================================================================

  /// Најмногу толку понудени одговори по прашање (точниот + 3 од истата
  /// категорија) - со 10 поими, сите 10 како одговори би било премногу.
  static const int _kQuizChoices = 4;

  /// Се зголемува при секој нов квиз - одговор од претходен квиз (што сè
  /// уште чека) не смее да го помести новиот.
  int _quizSession = 0;

  void _startQuiz() {
    if (!mounted) return;
    _narrationToken++;
    _voiceAssistant.stop();
    _voicePlayer.stop();
    _effectsPlayer.stop();
    final items = List<PictureBookItem>.from(_category.items);
    if (items.isEmpty) return;

    // По едно прашање за секој поим (10 прашања): описно - само првата
    // реченица (<id>_quiz_desc / <id>_desc), без името - или, за поимите СО
    // звук, по случаен избор „погоди го звукот“. (Реченицата „Научи“ не се
    // користи - речиси секогаш го содржи името и го издава одговорот.)
    final questions = <_QuizQuestion>[
      for (final i in items)
        _QuizQuestion(i, _hasSound(i) && _random.nextBool() ? _ClueType.sound : _ClueType.description),
    ]..shuffle(_random);

    _quizSession++;
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
    // Точниот одговор + до 3 погрешни од истата категорија, измешани.
    final distractors = _category.items.where((i) => i.id != q.item.id).toList()..shuffle(_random);
    final choices = <PictureBookItem>[q.item, ...distractors.take(_kQuizChoices - 1)]..shuffle(_random);
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
      await _speak('${choice.id}_name', choice.nameKey.tr(), allowTtsFallback: false);
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
    'horse': ['коњ', 'коњот', 'коњче', 'horse', 'pony', 'kalë', 'kale', 'kali'],
    'sheep': ['овца', 'овцата', 'овче', 'јагне', 'sheep', 'lamb', 'dele', 'delja', 'qengj'],
    'pig': ['свиња', 'свињата', 'прасе', 'pig', 'piggy', 'derr', 'derri'],
    'duck': ['патка', 'патката', 'пајка', 'duck', 'rosë', 'rose', 'rosa'],
    'frog': ['жаба', 'жабата', 'жапче', 'frog', 'bretkosë', 'bretkose', 'bretkosa'],
    'rooster': ['петел', 'петелот', 'rooster', 'cock', 'gjel', 'gjeli', 'këndes', 'kendes'],
    'thunder': ['гром', 'громот', 'грмотевица', 'бура', 'thunder', 'storm', 'bubullimë', 'bubullime', 'stuhi'],
    'snow': ['снег', 'снегот', 'snow', 'borë', 'bore', 'bora'],
    'flower': ['цвет', 'цветот', 'цвеќе', 'flower', 'lule', 'lulja'],
    'sea': ['море', 'морето', 'sea', 'ocean', 'det', 'deti'],
    'door': ['врата', 'вратата', 'door', 'derë', 'dere', 'dera'],
    'key': ['клуч', 'клучот', 'key', 'çelës', 'celes', 'çelësi', 'celesi'],
    'scissors': ['ножици', 'ножиците', 'scissors', 'gërshërë', 'gershere', 'gërshërët'],
    'toothbrush': ['четка', 'четкичка', 'четката', 'toothbrush', 'brush', 'furçë', 'furce', 'furça'],
    'glass': ['чаша', 'чашата', 'glass', 'cup', 'gotë', 'gote', 'gota'],
    'earth': ['земја', 'земјата', 'earth', 'globe', 'tokë', 'toke', 'toka'],
    'astronaut': ['астронаут', 'космонаут', 'astronaut', 'astronauti'],
    'comet': ['комета', 'кометата', 'comet', 'kometë', 'komete', 'kometa'],
    'satellite': ['сателит', 'сателитот', 'satellite', 'satelit', 'sateliti'],
    'ufo': ['нло', 'летечка', 'ufo', 'nlo', 'spaceship'],
    'telescope': ['телескоп', 'телескопот', 'telescope', 'teleskop', 'teleskopi'],
    'piano': ['пијано', 'клавир', 'piano', 'pianoja'],
    'violin': ['виолина', 'виолината', 'violin', 'fiddle', 'violinë', 'violine', 'violina'],
    'trumpet': ['труба', 'трубата', 'trumpet', 'trumbë', 'trumbe', 'trumbeta'],
    'saxophone': ['саксофон', 'саксофонот', 'saxophone', 'sax', 'saksofon', 'saksofoni'],
    'accordion': ['хармоника', 'хармониката', 'harmonika', 'accordion', 'fizarmonikë', 'fizarmonike', 'fizarmonika'],
    'banjo': ['бенџо', 'банџо', 'banjo', 'banxho'],
    'microphone': ['микрофон', 'микрофонот', 'microphone', 'mic', 'mikrofon', 'mikrofoni'],
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
    final session = _quizSession;
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
    if (!mounted || _view != _View.quiz || session != _quizSession) return;

    final nextIndex = _quizQuestionIndex + 1;
    if (nextIndex >= _quizQuestions.length) {
      setState(() => _view = _View.quizResult);
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
      voiceOptions: _view == _View.stage ? _stageVoiceOptions() : _categoryVoiceOptions(),
      onVoiceBack: _backToCategories,
      child: SafeArea(
        child: Builder(
          builder: (context) {
            switch (_view) {
              case _View.categorySelect:
                return _buildCategorySelect(context);
              case _View.stage:
                return _buildStage(context);
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
            // Магична книга со обележувачи - една страница по категорија.
            _buildBook(context, width - side * 2, hc),
          ],
        );
      },
    );
  }

  /// Категориите со глас - во менито со категории, но и од внатре (горе
  /// десно / кај сликовницата), за директно префрлање меѓу категориите.
  List<VoiceCategoryOption> _categoryVoiceOptions() {
    int idx(String id) => _categories.indexWhere((c) => c.id == id);
    VoiceCategoryOption opt(String id, List<String> kws) =>
        VoiceCategoryOption(keywords: kws, onSelected: () => _selectCategoryByVoice(idx(id)));
    return [
      opt('institutions', const ['институции', 'институција', 'institutions', 'institution', 'institucionet', 'institucione']),
      opt('cultures', const ['култури', 'културите', 'култура', 'cultures', 'culture', 'kulturat', 'kultura']),
      opt('nutrition', const ['исхрана', 'храна', 'nutrition', 'food', 'ushqyerja', 'ushqimi', 'ushqim']),
      opt('animals', const ['животни', 'animals', 'kafshët', 'kafshet']),
      opt('nature', const ['природа', 'nature', 'natyra']),
      opt('objects', const ['секојдневни предмети', 'предмети', 'everyday objects', 'objects', 'objekte të përditshme', 'objekte te perditshme', 'objekte']),
      opt('space', const ['вселена', 'space', 'hapësira', 'hapesira']),
      opt('music', const ['музика', 'music', 'muzika']),
    ];
  }

  Widget _buildExplanationButton(Color contrast) {
    return PlayfulExplainButton(
      open: _explanationOpen,
      label: _explanationOpen
          ? 'picture_book.explanation_toggle_close'.tr()
          : 'picture_book.explanation_toggle_open'.tr(),
      onTap: _toggleExplanation,
    );
  }

  // ---------------------------------------------------------------------
  // Мени „Магична книга“: шарена детска книга со обележувачи. Секоја
  // категорија е една страница (на компјутер раширени два листа): лево
  // илустрација на светот, името и напредокот; десно поимите „искокнуваат“
  // како во расклоплива сликовница и големо копче „Влези“.
  // ---------------------------------------------------------------------

  void _turnBookPage(int index) {
    if (_bookFlipping || index < 0 || index >= _categories.length || index == _bookPage) return;
    _playFlipSound();
    if (Playful.reduceMotion(context)) {
      setState(() => _bookPage = index);
      return;
    }
    setState(() {
      _bookFrom = _bookPage;
      _bookForward = index > _bookPage;
      _bookPage = index;
      _bookFlipping = true;
    });
    _flipCtl.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _bookFlipping = false);
    });
  }

  Widget _buildBook(BuildContext context, double width, bool hc) {
    final reduce = Playful.reduceMotion(context);
    final page = _bookPage.clamp(0, _categories.length - 1);
    final cat = _categories[page];
    final wide = width >= 760;
    const yellow = Color(0xFFFFFF00);
    final cover = Color.lerp(cat.color, Colors.black, 0.35)!;

    // Обележувачите: шарени јазичиња што висат од горниот раб на книгата.
    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _categories.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                button: true,
                selected: i == page,
                label: _categories[i].titleKey.tr(),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: () => _turnBookPage(i),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: reduce ? 0 : 220),
                      width: i == page ? 66 : 54,
                      height: i == page ? 74 : 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hc ? Colors.black : _categories[i].color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        border: Border.all(
                          color: hc ? (i == page ? yellow : Colors.white) : Colors.white.withValues(alpha: i == page ? 1 : 0.6),
                          width: i == page ? 3 : 2,
                        ),
                        boxShadow: hc ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, -2))],
                      ),
                      child: Icon(_categories[i].icon, color: hc ? (i == page ? yellow : Colors.white) : Colors.white, size: i == page ? 36 : 28),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Телото на книгата: вистинско 3D прелистување (компјутер - раширена
    // книга; телефон - тефтер со спирала горе).
    // Телото на книгата: вистинско 3D прелистување (компјутер - раширена
    // книга; телефон - тефтер со спирала горе).
    final body = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Повлекување лево = следна страница, десно = претходна.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _turnBookPage(page + 1);
        if (v > 200) _turnBookPage(page - 1);
      },
      child: wide ? _bookSpread(hc, cover) : _notebook(hc, cover),
    );
    final coverEdge = Color.lerp(cover, Colors.black, 0.45)!;

    // Целата книга лежи малку навалена (горниот раб подалеку), а корицата
    // има видлива дебелина под себе - така изгледа како предмет на маса.
    final book = Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0008)
        ..rotateX(reduce ? 0 : -0.16),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduce ? 0 : 400),
        padding: EdgeInsets.fromLTRB(wide ? 18 : 14, wide ? 14 : 30, wide ? 18 : 14, wide ? 16 : 22),
        decoration: BoxDecoration(
          color: hc ? Colors.black : cover,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.85), width: 3),
          boxShadow: hc ? null : [
            // Дебелина на корицата (тврд картон).
            BoxShadow(color: coverEdge, offset: const Offset(0, 10)),
            const BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 24)),
            BoxShadow(color: cat.color.withValues(alpha: 0.4), blurRadius: 34),
          ],
        ),
        child: body,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabs,
        book,
        const SizedBox(height: 22),
        // Листање: претходна / следна страница.
        Row(
          children: [
            _bookArrow(Icons.arrow_back_rounded, 'picture_book.previous_item'.tr(), page > 0, () => _turnBookPage(page - 1), hc),
            Expanded(
              child: Text('${page + 1} / ${_categories.length}', textAlign: TextAlign.center,
                style: GoogleFonts.lexend(fontSize: 18 * _kPbText, fontWeight: FontWeight.w800,
                  color: hc ? yellow : Colors.white)),
            ),
            _bookArrow(Icons.arrow_forward_rounded, 'picture_book.next_item'.tr(), page < _categories.length - 1, () => _turnBookPage(page + 1), hc),
          ],
        ),
      ],
    );
  }

  /// Хартија за страница (сенка кон рбетот / спиралата).
  BoxDecoration _pageDeco(bool hc, {required bool left, bool top = false}) => BoxDecoration(
    color: hc ? Colors.black : null,
    gradient: hc ? null : LinearGradient(
      begin: top ? Alignment.topCenter : (left ? Alignment.centerRight : Alignment.centerLeft),
      end: top ? Alignment.bottomCenter : (left ? Alignment.centerLeft : Alignment.centerRight),
      colors: const [Color(0xFFD8CFBA), Color(0xFFFFFDF7), Color(0xFFFFFDF7), Color(0xFFF0E9DA)],
      stops: const [0.0, 0.13, 0.9, 1.0],
    ),
    border: Border.all(color: hc ? Colors.white : const Color(0xFFD9D0BC), width: hc ? 2 : 1),
  );

  /// Содржина со најмала висина [minH]: ако не собира, се смалува.
  Widget _fitPage(Widget child, double w, double minH) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: max(10.0, w),
      child: ConstrainedBox(constraints: BoxConstraints(minHeight: max(0.0, minH)), child: child),
    ),
  );

  /// Еден лист од раширената книга со фиксна големина.
  /// Десниот лист: поимите горе, „Влези“ најдолу.
  Widget _leafBox(PictureBookCategory c, bool hc, {required bool left, required double w, required double h, bool pop = true}) => Container(
    width: w,
    height: h,
    decoration: _pageDeco(hc, left: left),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    child: _fitPage(
      left
          ? _bookLeaf(c, hc, left: true, bare: true)
          : Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_leafItemsGrid(c, hc, pop: pop), const SizedBox(height: 16), _leafEnterButton(c, hc)],
            ),
      w - 32,
      h - 30,
    ),
  );

  /// Страница од тефтерот: светот горе, поимите под него, „Влези“ најдолу.
  Widget _notebookPage(PictureBookCategory c, bool hc, double w, double h, {bool pop = true}) => Container(
    width: w,
    height: h,
    decoration: _pageDeco(hc, left: false, top: true),
    padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
    child: _fitPage(
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _bookLeaf(c, hc, left: true, bare: true),
            const SizedBox(height: 16),
            _leafItemsGrid(c, hc, pop: pop),
          ]),
          const SizedBox(height: 16),
          _leafEnterButton(c, hc),
        ],
      ),
      w - 28,
      h - 38,
    ),
  );

  /// Задната страна на лист во тефтерот - празна хартија со линии.
  Widget _blankBack(bool hc, double w, double h) => Container(
    width: w,
    height: h,
    decoration: _pageDeco(hc, left: false, top: true),
    child: hc ? null : CustomPaint(painter: _RuledPaperPainter()),
  );

  static const double _flipPerspective = 0.0016;

  /// Куп листови под страницата - дебелината на книгата/тефтерот.
  /// [dx], [dy] - во која насока се гледаат рабовите.
  List<Widget> _pageStack(bool hc, int count, double w, double h, double x, double y, double dx, double dy) => [
    for (var i = count; i >= 1; i--)
      Positioned(
        left: x + dx * i,
        top: y + dy * i,
        width: w,
        height: h,
        child: DecoratedBox(decoration: BoxDecoration(
          color: hc ? Colors.black : Color.lerp(const Color(0xFFFFFDF7), const Color(0xFFBFB49C), i / (count + 1)),
          border: Border.all(color: hc ? Colors.white : const Color(0xFFB8AD95), width: 1),
        )),
      ),
  ];

  /// Лист што се врти: една цела (крута) страница што се крева кон
  /// гледачот околу рбетот/спиралата. Предната страна се гледа до 90°,
  /// потоа задната (огледално превртена за да се чита правилно).
  /// [vertical] = тефтер (оска горе); инаку книга (оска лево или десно).
  Widget _turningLeaf({
    required Widget front,
    required Widget back,
    required double angle,
    required bool vertical,
    bool hingeLeft = true,
  }) {
    final showBack = cos(angle) < 0;
    final face = showBack
        ? Transform(
            alignment: Alignment.center,
            transform: vertical ? Matrix4.rotationX(pi) : Matrix4.rotationY(pi),
            child: back,
          )
        : front;
    // Потемно кога листот е накосо, посветло кога е исправен кон нас.
    final dark = (1 - cos(angle).abs()) * 0.3;
    final m = Matrix4.identity()..setEntry(3, 2, _flipPerspective);
    if (vertical) {
      m.rotateX(angle);
    } else {
      m.rotateY(angle);
    }
    return Transform(
      alignment: vertical ? Alignment.topCenter : (hingeLeft ? Alignment.centerLeft : Alignment.centerRight),
      transform: m,
      child: Stack(fit: StackFit.expand, children: [
        face,
        IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: dark))),
      ]),
    );
  }

  /// Раширена книга: лист што се крева од рбетот кон нас и се превртува
  /// на другата страна (напред: десниот лист оди налево; назад: левиот
  /// оди надесно). Под листовите се гледа купот страници.
  Widget _bookSpread(bool hc, Color cover) {
    final cat = _categories[_bookPage.clamp(0, _categories.length - 1)];
    final from = _categories[_bookFrom.clamp(0, _categories.length - 1)];
    const h = 470.0;
    const spine = 14.0;
    final int leftPages = 2 + min<int>(4, _bookPage);
    final int rightPages = 2 + min<int>(4, _categories.length - 1 - _bookPage);
    return LayoutBuilder(builder: (context, cons) {
      const x0 = 10.0;
      final half = (cons.maxWidth - spine - x0 * 2) / 2;
      final xr = x0 + half + spine;
      return AnimatedBuilder(
        animation: _flipCtl,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_flipCtl.value);
          final flipping = _bookFlipping;
          final fwd = _bookForward;
          final staticLeft = !flipping ? cat : (fwd ? from : cat);
          final staticRight = !flipping ? cat : (fwd ? cat : from);
          // Сенката што листот ја фрла врз страниците под него.
          final shade = flipping ? sin(t * pi) * 0.3 : 0.0;
          Widget shaded(Widget child, double a) => Stack(children: [
            child,
            if (a > 0.005) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: a)))),
          ]);
          final children = <Widget>[
            // Купот страници: лево се гледаат кон лево-долу, десно кон десно-долу.
            ..._pageStack(hc, leftPages, half, h, x0, 0, -1.6, 1.4),
            ..._pageStack(hc, rightPages, half, h, xr, 0, 1.6, 1.4),
            Positioned(left: x0, top: 0, width: half, height: h,
              child: shaded(_leafBox(staticLeft, hc, left: true, w: half, h: h), fwd ? shade * (t > 0.5 ? 1 : 0.35) : shade)),
            Positioned(left: xr, top: 0, width: half, height: h,
              child: shaded(_leafBox(staticRight, hc, left: false, w: half, h: h), fwd ? shade : shade * (t > 0.5 ? 1 : 0.35))),
            // Рбетот: длабок жлеб меѓу листовите.
            Positioned(left: x0 + half, top: -4, width: spine, height: h + 8,
              child: DecoratedBox(decoration: BoxDecoration(
                color: hc ? Colors.white : null,
                borderRadius: BorderRadius.circular(4),
                gradient: hc ? null : LinearGradient(colors: [
                  const Color(0xFFBDB29A), Color.lerp(cover, Colors.black, 0.55)!, const Color(0xFFBDB29A),
                ]),
              ))),
          ];
          if (flipping) {
            // Позитивен z во Flutter е „навнатре“ во екранот, па листот
            // се врти кон гледачот (над страниците, не под нив).
            final angle = fwd ? pi * t : -pi * t;
            children.add(Positioned(
              left: fwd ? xr : x0,
              top: 0,
              width: half,
              height: h,
              child: _turningLeaf(
                front: _leafBox(from, hc, left: !fwd, w: half, h: h, pop: false),
                back: _leafBox(cat, hc, left: fwd, w: half, h: h, pop: false),
                angle: angle,
                vertical: false,
                hingeLeft: fwd,
              ),
            ));
          }
          return SizedBox(height: h + 10, child: Stack(clipBehavior: Clip.none, children: children));
        },
      );
    });
  }

  /// Тефтер (телефон): спирала горе, листот се крева кон нас, се свиткува
  /// и се превртува нагоре преку спиралата. Долу се гледа купот листови.
  Widget _notebook(bool hc, Color cover) {
    final cat = _categories[_bookPage.clamp(0, _categories.length - 1)];
    final from = _categories[_bookFrom.clamp(0, _categories.length - 1)];
    final int under = 2 + min<int>(4, _categories.length - 1 - _bookPage);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      const h = 680.0;
      return AnimatedBuilder(
        animation: _flipCtl,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_flipCtl.value);
          final flipping = _bookFlipping;
          final fwd = _bookForward;
          final bottom = !flipping ? cat : (fwd ? cat : from);
          final p = fwd ? t : 1 - t;
          final children = <Widget>[
            ..._pageStack(hc, under, w, h, 0, 0, 0, 1.8),
            Positioned(left: 0, top: 0, width: w, height: h, child: Stack(children: [
              _notebookPage(bottom, hc, w, h),
              if (flipping) Positioned.fill(child: IgnorePointer(child: ColoredBox(
                color: Colors.black.withValues(alpha: sin(p * pi) * 0.28)))),
            ])),
          ];
          if (flipping) {
            // Напред: тековниот лист се крева 0 → 180°; назад: претходниот
            // се враќа 180 → 0°. Негативен агол = кон гледачот.
            children.add(Positioned(
              left: 0,
              top: 0,
              width: w,
              height: h,
              child: _turningLeaf(
                front: _notebookPage(fwd ? from : cat, hc, w, h, pop: false),
                back: _blankBack(hc, w, h),
                angle: -pi * p,
                vertical: true,
              ),
            ));
          }
          // Спиралата горе (над страниците).
          children.add(Positioned(left: 0, right: 0, top: -24, height: 40,
            child: IgnorePointer(child: CustomPaint(painter: _SpiralPainter(hc)))));
          return SizedBox(height: h + 10, child: Stack(clipBehavior: Clip.none, children: children));
        },
      );
    });
  }

  /// Поимите на категоријата: два реда по пет, големи плочки.
  Widget _leafItemsGrid(PictureBookCategory cat, bool hc, {bool pop = true}) {
    final seen = _visitedByCategory[cat.id] ?? const <String>{};
    const perRow = 5;
    final rows = (cat.items.length / perRow).ceil();
    Widget tile(int i) {
      final isSeen = seen.contains(cat.items[i].id);
      final box = AspectRatio(
          aspectRatio: 1,
          child: Opacity(
            opacity: isSeen ? 1.0 : 0.55,
            child: Container(
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hc ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: hc ? Colors.white : (isSeen ? cat.color : const Color(0xFFD9D0BC)),
                  width: isSeen ? 3.5 : 2,
                ),
                boxShadow: hc ? null : const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(2, 5))],
              ),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(cat.items[i].emoji, style: const TextStyle(fontSize: 60, height: 1.0)),
              ),
            ),
          ),
        );
      // Листот што се врти е копија - без „искокнување“, за да нема
      // двојни/трепкави слики додека се листа.
      if (!pop) return box;
      return PopIn(key: ValueKey('pop-${cat.id}-$i'), index: i, stepMs: 55, child: box);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(children: [
            for (var c = 0; c < perRow; c++) ...[
              if (c > 0) const SizedBox(width: 10),
              Expanded(child: r * perRow + c < cat.items.length ? tile(r * perRow + c) : const SizedBox.shrink()),
            ],
          ]),
        ],
      ],
    );
  }

  /// Големото копче „Влези“ најдолу на страницата.
  Widget _leafEnterButton(PictureBookCategory cat, bool hc) {
    final index = _categories.indexOf(cat);
    final seen = _visitedByCategory[cat.id] ?? const <String>{};
    final total = cat.items.length;
    final visited = seen.length;
    const yellow = Color(0xFFFFFF00);
    return Semantics(
      button: true,
      label: '${'picture_book.enter_category'.tr()}: ${cat.titleKey.tr()}. $total ${_t('items_count')}. $visited ${_t('seen')}.',
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: hc ? Colors.black : cat.color,
            borderRadius: BorderRadius.circular(22),
            elevation: hc ? 0 : 6,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _enterCategory(index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: hc ? yellow : Colors.white, width: 3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_rounded, color: hc ? yellow : Colors.white, size: 38),
                    const SizedBox(width: 12),
                    Flexible(child: Text('picture_book.enter_category'.tr(), style: GoogleFonts.lexend(
                      fontSize: 24 * _kPbText, fontWeight: FontWeight.w900, color: hc ? yellow : Colors.white))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookArrow(IconData icon, String label, bool enabled, VoidCallback onTap, bool hc) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: ExcludeSemantics(
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: hc ? Colors.black : Colors.white,
          shape: CircleBorder(side: BorderSide(color: hc ? Colors.white : Playful.ink, width: 2.5)),
          elevation: hc ? 0 : 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(width: 64, height: 64, child: Icon(icon, size: 36, color: hc ? Colors.white : Playful.ink)),
          ),
        ),
      ),
    ),
  );

  /// Еден лист од книгата. Левиот: светот, името, напредокот и печатот.
  /// Десниот: поимите што искокнуваат + копчето „Влези“.
  Widget _bookLeaf(PictureBookCategory cat, bool hc, {required bool left, bool bare = false}) {
    final seen = _visitedByCategory[cat.id] ?? const <String>{};
    final total = cat.items.length;
    final visited = seen.length;
    final allSeen = total > 0 && visited >= total;
    const yellow = Color(0xFFFFFF00);
    final ink = hc ? Colors.white : Playful.ink;
    final paper = bare ? const BoxDecoration() : BoxDecoration(
      color: hc ? Colors.black : null,
      gradient: hc ? null : LinearGradient(
        begin: left ? Alignment.centerRight : Alignment.centerLeft,
        end: left ? Alignment.centerLeft : Alignment.centerRight,
        // Сенка кон рбетот, светло кон работ.
        colors: const [Color(0xFFE9E2D2), Color(0xFFFFFDF7), Color(0xFFFFFDF7)],
        stops: const [0.0, 0.12, 1.0],
      ),
      border: hc ? Border.all(color: Colors.white, width: 2) : null,
    );

    if (left) {
      return Container(
        decoration: paper,
        padding: bare ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Илустрација на светот во рамка.
            Container(
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: hc ? Colors.white : cat.color, width: 3),
                color: hc ? Colors.black : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(children: [
                  if (!hc) Positioned.fill(child: CustomPaint(painter: _WorldPainter(cat.id, cat.color))),
                  Center(child: Icon(cat.icon, size: 64, color: hc ? yellow : Colors.white.withValues(alpha: 0.0))),
                  // Печат „Прегледано“ кога сè е видено.
                  if (allSeen)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: hc ? Colors.black : Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: hc ? yellow : const Color(0xFFC62828), width: 3),
                          ),
                          child: Text(_t('seen').toUpperCase(), style: GoogleFonts.lexend(fontSize: 18,
                            fontWeight: FontWeight.w900, color: hc ? yellow : const Color(0xFFC62828))),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(shape: BoxShape.circle, color: hc ? Colors.black : cat.color,
                  border: Border.all(color: hc ? Colors.white : Colors.white, width: 2)),
                child: Icon(cat.icon, color: hc ? yellow : Colors.white, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(cat.titleKey.tr(), style: GoogleFonts.lexend(fontSize: 26 * _kPbText,
                fontWeight: FontWeight.w800, color: hc ? yellow : ink, height: 1.1))),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : visited / total,
                minHeight: 12,
                backgroundColor: hc ? Colors.white24 : const Color(0xFFE5DCC8),
                valueColor: AlwaysStoppedAnimation(hc ? yellow : cat.color),
              ),
            ),
            const SizedBox(height: 6),
            Text('$visited / $total ${_t('seen')}', style: GoogleFonts.lexend(fontSize: 16 * _kPbText,
              fontWeight: FontWeight.w700, color: hc ? Colors.white : const Color(0xFF5B5B6B))),
          ],
        ),
      );
    }

    // Десниот лист: поимите (два реда по пет) и „Влези“.
    return Container(
      decoration: paper,
      padding: bare ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _leafItemsGrid(cat, hc),
          const SizedBox(height: 18),
          _leafEnterButton(cat, hc),
        ],
      ),
    );
  }

  // --- Сцена на категоријата ---
  //
  // Горе: назад + насловот на категоријата. Во средина: тематската сцена
  // (дрво / лента / планета / уво / лав) со 10-те поими и копчето за квиз.
  // Долу: големи стрелки ← → и меѓу нив големата слика на избраниот поим
  // со името под неа (допир -> се отвора).

  /// Гласовни команди на сцената: „квиз“, името на кој било поим (го
  /// отвора), па категориите.
  List<VoiceCategoryOption> _stageVoiceOptions() => [
        VoiceCategoryOption(
          keywords: const ['квиз', 'quiz', 'kuiz'],
          onSelected: _startQuiz,
        ),
        for (var i = 0; i < _category.items.length; i++)
          VoiceCategoryOption(
            keywords: const [],
            matches: (t) => _saysItem(t, _category.items[i]),
            onSelected: () {
              if (!mounted || _view != _View.stage) return;
              setState(() => _stageIndex = i);
              _openItem(i);
            },
          ),
        ..._categoryVoiceOptions(),
      ];

  /// Тематската сцена според категоријата.
  Widget _sceneFor(PictureBookCategory cat, List<PbSceneItem> items, int selected, bool hc, bool reduce) {
    final quizLabel = 'picture_book.go_to_quiz'.tr();
    final key = ValueKey('pb-scene-${cat.id}');
    switch (cat.id) {
      case 'institutions':
        return InstitutionsSquareScene(
          key: key, items: items, selected: selected,
          onSelect: _selectStageItem, onOpen: _openStageItem,
          onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'cultures':
        return WorldCulturesScene(
          key: key, items: items, selected: selected,
          onSelect: _selectStageItem, onOpen: _openStageItem,
          onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'nutrition':
        return NutritionPyramidScene(
          key: key, items: items, selected: selected,
          onSelect: _selectStageItem, onOpen: _openStageItem,
          onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'nature':
        return NatureTreeScene(
          key: key,
          items: items,
          selected: selected,
          onSelect: _selectStageItem,
          onOpen: _openStageItem,
          onQuiz: _startQuiz,
          quizLabel: quizLabel,
          highContrast: hc,
          reduceMotion: reduce,
        );
      case 'objects':
        return ObjectsBeltScene(
          key: key,
          items: items,
          selected: selected,
          onSelect: _selectStageItem,
          onOpen: _openStageItem,
          onQuiz: _startQuiz,
          quizLabel: quizLabel,
          highContrast: hc,
          reduceMotion: reduce,
        );
      case 'space':
        return SpaceOrbitScene(
          key: key,
          items: items,
          selected: selected,
          onSelect: _selectStageItem,
          onOpen: _openStageItem,
          onQuiz: _startQuiz,
          quizLabel: quizLabel,
          highContrast: hc,
          reduceMotion: reduce,
        );
      case 'music':
        return MusicEarScene(
          key: key,
          items: items,
          selected: selected,
          onSelect: _selectStageItem,
          onOpen: _openStageItem,
          onQuiz: _startQuiz,
          quizLabel: quizLabel,
          highContrast: hc,
          reduceMotion: reduce,
        );
      case 'animals':
      default:
        return AnimalsLionScene(
          key: key,
          items: items,
          selected: selected,
          onSelect: _selectStageItem,
          onOpen: _openStageItem,
          onQuiz: _startQuiz,
          quizLabel: quizLabel,
          highContrast: hc,
          reduceMotion: reduce,
        );
    }
  }

  Widget _buildStage(BuildContext context) {
    final contrast = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);
    final reduce = Playful.reduceMotion(context);
    final cat = _category;
    final visited = _visited;
    final count = cat.items.length;
    final selected = count == 0 ? 0 : _stageIndex.clamp(0, count - 1);
    final sceneItems = [
      for (final i in cat.items) PbSceneItem(id: i.id, emoji: i.emoji, label: i.nameKey.tr(), visited: visited.contains(i.id)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Висина на сцената: колку ширината (300-520), но на низок екран
        // помалку, за стрелките и избраниот поим да се гледаат без лизгање.
        const reserved = 330.0; // заглавје + стрелки + избраниот поим
        final base = width.clamp(300.0, 520.0);
        final fit = constraints.maxHeight.isFinite ? constraints.maxHeight - reserved : base;
        final sceneH = min(base, max(260.0, fit));
        // Само вертикално лизгање - хоризонталните потези одат до сцената.
        return StartHotkeyListener(
          onTrigger: _startQuiz,
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: _buildBackRow(contrast, onBack: _backToCategories)),
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
                            Text('${visited.length} / $count ${_t('seen')}',
                                style: GameTypography.body(context, _onBg(hc, contrast).withValues(alpha: 0.9), 16 * _kPbText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0) ...[
                  SizedBox(
                    width: width,
                    height: sceneH,
                    child: _sceneFor(cat, sceneItems, selected, hc, reduce),
                  ),
                  const SizedBox(height: 10),
                  _stageControls(cat.items[selected], visited.contains(cat.items[selected].id), contrast, hc, reduce),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Под сцената: ← [голема слика на избраниот поим + име] →.
  Widget _stageControls(PictureBookItem item, bool seen, Color contrast, bool hc, bool reduce) {
    const yellow = Color(0xFFFFFF00);
    final cat = _category;
    final name = item.nameKey.tr();
    final glow = hc ? yellow : Color.lerp(cat.color, Colors.white, 0.35)!;
    final tile = Semantics(
      button: true,
      label: '$name${seen ? '. ${_t('seen')}' : ''}',
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openStageItem,
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduce ? 0 : 260),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                child: Stack(
                  key: ValueKey('pb-stage-tile-${item.id}'),
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 124,
                      height: 124,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc ? Colors.black : Colors.white,
                        border: Border.all(color: hc ? yellow : glow, width: hc ? 4 : 5),
                        boxShadow: hc
                            ? null
                            : [
                                BoxShadow(color: glow.withValues(alpha: 0.75), blurRadius: 28, spreadRadius: 4),
                                BoxShadow(color: cat.color.withValues(alpha: 0.5), blurRadius: 10),
                              ],
                      ),
                      child: Text(item.emoji, style: const TextStyle(fontSize: 76)),
                    ),
                    if (seen)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hc ? Colors.black : const Color(0xFF16A34A),
                            border: Border.all(color: hc ? yellow : Colors.white, width: 2),
                          ),
                          child: Icon(Icons.check_rounded, color: hc ? yellow : Colors.white, size: 22),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stageArrow(Icons.arrow_back_rounded, 'picture_book.previous_item'.tr(), () => _stageStep(-1), hc),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile,
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: GameTypography.heading(context, _onBg(hc, contrast), 24 * _kPbText),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _stageArrow(Icons.arrow_forward_rounded, 'picture_book.next_item'.tr(), () => _stageStep(1), hc),
        ],
      ),
    );
  }

  /// Голема тркалезна стрелка (68 px) под сцената.
  Widget _stageArrow(IconData icon, String label, VoidCallback onTap, bool hc) {
    const yellow = Color(0xFFFFFF00);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: hc ? Colors.black : Playful.sun,
            shape: CircleBorder(side: BorderSide(color: hc ? yellow : Colors.white, width: 3)),
            elevation: hc ? 0 : 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(icon, size: 40, color: hc ? yellow : Playful.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Поединечна сликовница ---

  /// Деталниот приказ ја користи ИСТАТА сцена како категоријата.
  /// Нема второ копче за квиз: оригиналното останува на сцената.
  Widget _buildItemDetail(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final contrast = AccessibilityUtils.getContrastColor(context);
    final item = _item;
    final visited = _visited;
    final sceneItems = [
      for (final i in _category.items)
        PbSceneItem(
          id: i.id,
          emoji: i.emoji,
          label: i.nameKey.tr(),
          visited: visited.contains(i.id),
        ),
    ];
    const yellow = Color(0xFFFFFF00);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          children: [
            Row(
              children: [
                _buildBackRow(contrast, onBack: _closeItemDetail),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final isCultures = _category.id == 'cultures';
                  final sceneHeight = (constraints.maxHeight *
                          (isCultures ? (compact ? 0.48 : 0.53) : (compact ? 0.58 : 0.65)))
                      .clamp(isCultures ? 150.0 : 180.0, isCultures ? 380.0 : 460.0);
                  return Column(
                    children: [
                      SizedBox(
                        height: sceneHeight,
                        width: double.infinity,
                        child: ClipRect(
                          child: AnimatedScale(
                            // Зум на постојната сцена, без заменување на
                            // дрвото, лентата, планетата, увото или лавот.
                            scale: isCultures ? 0.90 : 1.08,
                            duration: Duration(
                              milliseconds: Playful.reduceMotion(context) ? 0 : 350,
                            ),
                            child: _detailScene(
                              sceneItems,
                              hc,
                              Playful.reduceMotion(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: hc ? Colors.black : Color.lerp(_category.color, Colors.black, 0.70),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: hc ? yellow : _category.color.withValues(alpha: 0.95),
                              width: 2.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: _objectsExplanation(
                                  item.nameKey.tr(),
                                  item.descriptionKey.tr(),
                                  item.learnKey.tr(),
                                  hc,
                                  const Color(0xFF071A43),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _objectsArrow(
                                    Icons.arrow_back_rounded,
                                    'picture_book.previous_item'.tr(),
                                    hc,
                                    _goToPrevItem,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _objectsActionButton(
                                      Icons.volume_up_rounded,
                                      'Повтори',
                                      _category.color,
                                      hc ? yellow : Colors.white,
                                      hc,
                                      _repeatItem,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _objectsArrow(
                                    Icons.arrow_forward_rounded,
                                    'picture_book.next_item'.tr(),
                                    hc,
                                    _goToNextItem,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Деталната сцена ги користи оригиналните widget-и и нивните анимации.
  /// Изборот на нов поим го ажурира деталниот приказ, не stage екранот.
  Widget _detailScene(List<PbSceneItem> items, bool hc, bool reduce) {
    final selected = _itemIndex;
    final quizLabel = 'picture_book.go_to_quiz'.tr();
    void select(int index) {
      if (index != _itemIndex) _onItemPageChanged(index);
    }
    switch (_category.id) {
      case 'institutions':
        return InstitutionsSquareScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce, focusMode: true,
        );
      case 'cultures':
        return WorldCulturesScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'nutrition':
        return NutritionPyramidScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'nature':
        return NatureTreeScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'objects':
        return ObjectsBeltScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce, focusMode: true,
        );
      case 'space':
        return SpaceOrbitScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'music':
        return MusicEarScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
      case 'animals':
      default:
        return AnimalsLionScene(
          items: items, selected: selected, onSelect: select,
          onOpen: _repeatItem, onQuiz: _startQuiz, quizLabel: quizLabel,
          highContrast: hc, reduceMotion: reduce,
        );
    }
  }

  Widget _objectsExplanation(
    String name,
    String description,
    String learn,
    bool hc,
    Color navy,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_category.id == 'cultures') ...[
              Builder(builder: (context) {
                const ids = ['culture_japan', 'culture_egypt', 'culture_italy',
                  'culture_mexico', 'culture_france', 'culture_greece',
                  'culture_china', 'culture_india', 'culture_kenya', 'culture_turkey'];
                const flags = ['🇯🇵', '🇪🇬', '🇮🇹', '🇲🇽', '🇫🇷', '🇬🇷', '🇨🇳', '🇮🇳', '🇰🇪', '🇹🇷'];
                final i = ids.indexOf(_item.id);
                if (i < 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Text(flags[i], style: const TextStyle(fontSize: 54)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name,
                      style: GoogleFonts.lexend(fontSize: 27,
                        fontWeight: FontWeight.w900, color: Colors.white))),
                  ]),
                );
              }),
            ],
            Text(
              description,
              style: GoogleFonts.lexend(
                fontSize: 28,
                height: 1.16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              learn,
              style: GoogleFonts.lexend(
                fontSize: 25,
                height: 1.16,
                fontWeight: FontWeight.w700,
                color: hc ? const Color(0xFFFFFF00) : const Color(0xFFFFE18A),
              ),
            ),
            if (_category.id == 'cultures') ...[
              const SizedBox(height: 18),
              Text('picture_book.culture_landmarks_title'.tr(),
                style: GoogleFonts.lexend(fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: hc ? const Color(0xFFFFFF00) : Colors.white)),
              const SizedBox(height: 10),
              ...List.generate(3, (index) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Semantics(
                  button: true,
                  label: 'picture_book.${_item.id}_landmark_${index + 1}'.tr(),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        _narrationToken++;
                        _playCultureLandmark(_item.id, index + 1);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: hc ? const Color(0xFFFFFF00) : const Color(0xFFFFE18A))),
                        child: Row(children: [
                          const Icon(Icons.volume_up_rounded, color: Colors.white, size: 25),
                          const SizedBox(width: 10),
                          Expanded(child: Text('picture_book.${_item.id}_landmark_${index + 1}'.tr(),
                            style: GoogleFonts.lexend(fontSize: 22,
                              fontWeight: FontWeight.w700, color: Colors.white))),
                        ]),
                      ),
                    ),
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _objectsFocusedItem(
    String emoji,
    String itemId,
    bool hc,
    Color accent,
    double fontSize,
  ) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Container(
          key: ValueKey(itemId),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hc ? Colors.black : const Color(0xFFFFD56A),
            border: Border.all(
              color: hc ? const Color(0xFFFFFF00) : Colors.white,
              width: hc ? 4 : 5,
            ),
            boxShadow: hc
                ? null
                : [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.9),
                      blurRadius: 26,
                      spreadRadius: 4,
                    ),
                    const BoxShadow(
                      color: Color(0xAAFFD76A),
                      blurRadius: 42,
                      spreadRadius: 10,
                    ),
                  ],
          ),
          child: Text(emoji, style: TextStyle(fontSize: fontSize)),
        ),
      ),
    );
  }

  Widget _objectsNeighbour(int offset, bool hc, Color accent) {
    final items = _category.items;
    if (items.length < 2) return const SizedBox.shrink();
    final index = (_itemIndex + offset + items.length) % items.length;
    final item = items[index];
    return Opacity(
      opacity: hc ? 1 : 0.65,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: hc ? Colors.black : const Color(0xFF203D70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hc ? Colors.white : accent.withValues(alpha: 0.8),
              width: 2,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(item.emoji, style: const TextStyle(fontSize: 42)),
          ),
        ),
      ),
    );
  }

  Widget _objectsArrow(
    IconData icon,
    String label,
    bool hc,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: hc ? Colors.black : const Color(0xFF1769E8),
        shape: CircleBorder(
          side: BorderSide(
            color: hc ? const Color(0xFFFFFF00) : Colors.white,
            width: 3,
          ),
        ),
        elevation: hc ? 0 : 5,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 29, color: hc ? const Color(0xFFFFFF00) : Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _objectsActionButton(
    IconData icon,
    String label,
    Color color,
    Color foreground,
    bool hc,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      label: label.replaceAll('\\n', ' '),
      child: Material(
        color: hc ? Colors.black : color,
        borderRadius: BorderRadius.circular(20),
        elevation: hc ? 0 : 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hc ? const Color(0xFFFFFF00) : Colors.white,
                width: hc ? 3 : 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: foreground),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lexend(
                    fontSize: 19,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
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
    final culture = _category.id == 'cultures';
    final cultureIndex = const ['culture_japan','culture_egypt','culture_italy','culture_mexico','culture_france','culture_greece','culture_china','culture_india','culture_kenya','culture_turkey'].indexOf(item.id);
    const cultureFlags = ['🇯🇵','🇪🇬','🇮🇹','🇲🇽','🇫🇷','🇬🇷','🇨🇳','🇮🇳','🇰🇪','🇹🇷'];

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
                                child: Text(culture && cultureIndex >= 0 ? cultureFlags[cultureIndex] : item.emoji, style: TextStyle(fontSize: emojiSize)),
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
                            if (culture && cultureIndex >= 0) ...[
                              const SizedBox(height: 18),
                              Text('picture_book.culture_landmarks_title'.tr(),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.lexend(fontSize: 25, fontWeight: FontWeight.w800,
                                  color: hc ? yellow : catDeep)),
                              const SizedBox(height: 12),
                              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
                                children: List.generate(3, (landmark) => Semantics(
                                  button: true,
                                  label: 'picture_book.${item.id}_landmark_${landmark + 1}'.tr(),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {
                                        _narrationToken++;
                                        _playCultureLandmark(item.id, landmark + 1);
                                      },
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 125, maxWidth: 260),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: hc ? Colors.black : Colors.white,
                                          border: Border.all(color: hc ? yellow : catColor, width: 2),
                                          borderRadius: BorderRadius.circular(14)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.volume_up_rounded, size: 22, color: hc ? yellow : catDeep),
                                          const SizedBox(width: 8),
                                          Flexible(child: Text('picture_book.${item.id}_landmark_${landmark + 1}'.tr(),
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.lexend(fontSize: 20, fontWeight: FontWeight.w700,
                                              color: hc ? Colors.white : Playful.ink))),
                                        ]),
                                      ),
                                    ),
                                  ),
                                )),
                              ),
                            ],
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
                                // Квизот е секогаш достапен (без услов).
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
          if (_hasSound(item))
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
            // Нов квиз - секогаш, без ограничување на обидите.
            StartHotkeyListener(
              onTrigger: _startQuiz,
              child: _resultButton(icon: Icons.refresh_rounded, label: _t('retry_quiz'), color: _quizGreen, onTap: _startQuiz),
            ),
            const SizedBox(height: 12),
            _resultButton(icon: Icons.auto_stories_rounded, label: _t('back_to_items'), color: _category.color, onTap: _backToStage),
            const SizedBox(height: 12),
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

/// Мал насликан предел за секоја категорија (позадина на станицата).
class _WorldPainter extends CustomPainter {
  _WorldPainter(this.id, this.color);
  final String id;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final night = id == 'space';
    // Небо.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night
              ? const [Color(0xFF0B1033), Color(0xFF2B2A6B)]
              : [Color.lerp(color, const Color(0xFF9FD8FF), 0.55)!, const Color(0xFFE8F6FF)],
        ).createShader(rect),
    );
    final rnd = Random(id.hashCode);
    if (night) {
      for (var i = 0; i < 40; i++) {
        canvas.drawCircle(Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * 0.6), 1 + rnd.nextDouble() * 1.6,
          Paint()..color = Colors.white.withValues(alpha: 0.5 + rnd.nextDouble() * 0.5));
      }
      canvas.drawCircle(Offset(w * 0.82, h * 0.22), h * 0.08, Paint()..color = const Color(0xFFFFF3C4));
    } else {
      canvas.drawCircle(Offset(w * 0.86, h * 0.2), h * 0.08, Paint()..color = const Color(0xFFFFE082));
      // Облачиња.
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
      for (final c in [Offset(w * 0.18, h * 0.24), Offset(w * 0.55, h * 0.16)]) {
        canvas.drawCircle(c, h * 0.05, cloud);
        canvas.drawCircle(c + Offset(h * 0.06, h * 0.01), h * 0.04, cloud);
        canvas.drawCircle(c - Offset(h * 0.06, -h * 0.01), h * 0.035, cloud);
      }
    }
    // Ридови / тло.
    final groundTop = h * 0.58;
    final groundColor = switch (id) {
      'space' => const Color(0xFF4B4F6B),
      'institutions' || 'objects' => const Color(0xFFC9BFAE),
      'cultures' => const Color(0xFFE7D3A1),
      'nutrition' => const Color(0xFF8BC34A),
      'music' => const Color(0xFF9CCC65),
      _ => const Color(0xFF66BB6A),
    };
    final hills = Path()
      ..moveTo(0, groundTop + h * 0.06)
      ..quadraticBezierTo(w * 0.25, groundTop - h * 0.06, w * 0.5, groundTop + h * 0.02)
      ..quadraticBezierTo(w * 0.78, groundTop + h * 0.08, w, groundTop - h * 0.02)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hills, Paint()..color = groundColor);
    canvas.drawPath(hills, Paint()..color = Colors.black.withValues(alpha: 0.12)..style = PaintingStyle.stroke..strokeWidth = 2);

    final ink = Paint()..color = Colors.black.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    void tree(Offset base, double s) {
      canvas.drawRect(Rect.fromCenter(center: base + Offset(0, -s * 0.4), width: s * 0.18, height: s * 0.8), Paint()..color = const Color(0xFF795548));
      canvas.drawCircle(base + Offset(0, -s * 1.0), s * 0.55, Paint()..color = const Color(0xFF2E7D32));
      canvas.drawCircle(base + Offset(-s * 0.2, -s * 1.15), s * 0.3, Paint()..color = const Color(0xFF43A047));
    }
    void house(Offset base, double s, Color wall, Color roof) {
      final body = Rect.fromLTWH(base.dx - s / 2, base.dy - s * 0.7, s, s * 0.7);
      canvas.drawRect(body, Paint()..color = wall);
      canvas.drawRect(body, ink);
      final r = Path()
        ..moveTo(body.left - s * 0.08, body.top)
        ..lineTo(body.center.dx, body.top - s * 0.45)
        ..lineTo(body.right + s * 0.08, body.top)
        ..close();
      canvas.drawPath(r, Paint()..color = roof);
      canvas.drawRect(Rect.fromLTWH(body.center.dx - s * 0.1, body.bottom - s * 0.32, s * 0.2, s * 0.32), Paint()..color = const Color(0xFF6D4C41));
    }

    final gy = groundTop + h * 0.04;
    switch (id) {
      case 'institutions':
        // Мал град со купола.
        house(Offset(w * 0.18, gy), h * 0.2, const Color(0xFFF5E6CC), const Color(0xFFC0503A));
        house(Offset(w * 0.36, gy - 2), h * 0.24, const Color(0xFFE3F2FD), const Color(0xFF1E5AA8));
        canvas.drawRect(Rect.fromLTWH(w * 0.5, gy - h * 0.26, w * 0.16, h * 0.26), Paint()..color = const Color(0xFFEDE3CF));
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.58, gy - h * 0.26), width: w * 0.1, height: h * 0.16), pi, pi, true, Paint()..color = const Color(0xFF7FA6A0));
        house(Offset(w * 0.78, gy), h * 0.22, const Color(0xFFFFF3E0), const Color(0xFFB7322C));
        break;
      case 'cultures':
        // Пристаниште: море, брод, светилник.
        canvas.drawRect(Rect.fromLTWH(0, groundTop + h * 0.02, w * 0.45, h * 0.2), Paint()..color = const Color(0xFF4FA3D9));
        final hull = Path()
          ..moveTo(w * 0.08, gy - h * 0.02)
          ..lineTo(w * 0.36, gy - h * 0.02)
          ..lineTo(w * 0.32, gy + h * 0.05)
          ..lineTo(w * 0.12, gy + h * 0.05)
          ..close();
        canvas.drawPath(hull, Paint()..color = const Color(0xFF8D4E2A));
        canvas.drawLine(Offset(w * 0.22, gy - h * 0.02), Offset(w * 0.22, gy - h * 0.3), Paint()..color = const Color(0xFF5D4037)..strokeWidth = 3);
        canvas.drawPath(Path()..moveTo(w * 0.22, gy - h * 0.28)..lineTo(w * 0.34, gy - h * 0.06)..lineTo(w * 0.22, gy - h * 0.06)..close(), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(w * 0.7, gy - h * 0.34, w * 0.06, h * 0.34), Paint()..color = Colors.white);
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(Rect.fromLTWH(w * 0.7, gy - h * 0.3 + i * h * 0.1, w * 0.06, h * 0.04), Paint()..color = const Color(0xFFD62828));
        }
        canvas.drawCircle(Offset(w * 0.6, gy - h * 0.1), h * 0.09, Paint()..color = const Color(0xFF64B5F6));
        canvas.drawCircle(Offset(w * 0.6, gy - h * 0.1), h * 0.09, ink);
        break;
      case 'nutrition':
        // Фарма: ниви со редови, овошка и амбар.
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(Offset(w * (0.05 + i * 0.06), h), Offset(w * (0.2 + i * 0.05), gy), Paint()..color = const Color(0xFF558B2F)..strokeWidth = 3);
        }
        house(Offset(w * 0.62, gy), h * 0.26, const Color(0xFFC62828), const Color(0xFF6D1B1B));
        tree(Offset(w * 0.84, gy), h * 0.22);
        for (final p in [Offset(w * 0.8, gy - h * 0.24), Offset(w * 0.88, gy - h * 0.2), Offset(w * 0.84, gy - h * 0.3)]) {
          canvas.drawCircle(p, h * 0.02, Paint()..color = const Color(0xFFE53935));
        }
        break;
      case 'animals':
        // Ливада со ограда.
        for (var x = w * 0.05; x < w * 0.95; x += w * 0.08) {
          canvas.drawLine(Offset(x, gy - h * 0.08), Offset(x, gy + h * 0.02), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 4);
        }
        canvas.drawLine(Offset(w * 0.05, gy - h * 0.06), Offset(w * 0.95, gy - h * 0.06), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 3);
        canvas.drawLine(Offset(w * 0.05, gy - h * 0.02), Offset(w * 0.95, gy - h * 0.02), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 3);
        tree(Offset(w * 0.85, gy - h * 0.06), h * 0.22);
        break;
      case 'nature':
        // Шума со река.
        final river = Path()
          ..moveTo(w * 0.42, gy)
          ..quadraticBezierTo(w * 0.5, h * 0.8, w * 0.38, h);
        canvas.drawPath(river, Paint()..color = const Color(0xFF4FC3F7)..style = PaintingStyle.stroke..strokeWidth = 18..strokeCap = StrokeCap.round);
        for (final x in [0.1, 0.22, 0.62, 0.74, 0.88]) {
          tree(Offset(w * x, gy + (x * 37 % 1) * 6), h * (0.18 + (x * 13 % 1) * 0.08));
        }
        break;
      case 'objects':
        // Улица со работилница и лента.
        house(Offset(w * 0.22, gy), h * 0.26, const Color(0xFFFFE0B2), const Color(0xFF8D6E63));
        canvas.drawRect(Rect.fromLTWH(w * 0.42, gy - h * 0.06, w * 0.46, h * 0.06), Paint()..color = const Color(0xFF455A64));
        for (var x = w * 0.44; x < w * 0.88; x += w * 0.05) {
          canvas.drawCircle(Offset(x, gy - h * 0.03), h * 0.018, Paint()..color = const Color(0xFF90A4AE));
        }
        canvas.drawRect(Rect.fromLTWH(w * 0.72, gy - h * 0.34, w * 0.05, h * 0.28), Paint()..color = const Color(0xFF8D6E63));
        break;
      case 'space':
        // Опсерваторија на рид.
        canvas.drawRect(Rect.fromLTWH(w * 0.55, gy - h * 0.16, w * 0.18, h * 0.16), Paint()..color = const Color(0xFFCFD8DC));
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.64, gy - h * 0.16), width: w * 0.18, height: h * 0.2), pi, pi, true, Paint()..color = const Color(0xFFB0BEC5));
        canvas.drawLine(Offset(w * 0.66, gy - h * 0.22), Offset(w * 0.76, gy - h * 0.34), Paint()..color = const Color(0xFF37474F)..strokeWidth = 6);
        break;
      case 'music':
        // Летна сцена (амфитеатар) со ноти.
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, gy), width: w * 0.5, height: h * 0.4), pi, pi, true, Paint()..color = const Color(0xFFEDE7F6));
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, gy), width: w * 0.5, height: h * 0.4), pi, pi, false, ink);
        final note = TextPainter(
          text: const TextSpan(text: '♪ ♫ ♪', style: TextStyle(fontSize: 26, color: Color(0xFF5E35B1), fontWeight: FontWeight.w900)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        note.paint(canvas, Offset(w * 0.5 - note.width / 2, gy - h * 0.34));
        break;
      default:
        tree(Offset(w * 0.8, gy), h * 0.22);
    }
    // Мала патека низ пределот (продолжение на големиот пат).
    final trail = Path()
      ..moveTo(w * 0.5, h)
      ..quadraticBezierTo(w * 0.45, h * 0.86, w * 0.5, gy + h * 0.02);
    canvas.drawPath(trail, Paint()..color = const Color(0x99D9B27C)..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _WorldPainter old) => old.id != id || old.color != color;
}

/// Линии на празна хартија (задна страна на лист од тефтерот).
class _RuledPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x334A90C2)
      ..strokeWidth = 1.2;
    for (var y = 48.0; y < size.height; y += 30) {
      canvas.drawLine(Offset(16, y), Offset(size.width - 16, y), line);
    }
    canvas.drawLine(const Offset(46, 0), Offset(46, size.height), Paint()..color = const Color(0x44E53935)..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _RuledPaperPainter oldDelegate) => false;
}

/// Метална спирала на горниот раб на тефтерот.
class _SpiralPainter extends CustomPainter {
  _SpiralPainter(this.hc);
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 26.0;
    final count = ((size.width - 20) / step).floor();
    final start = (size.width - (count - 1) * step) / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final x = start + i * step;
      // Дупка во хартијата.
      canvas.drawCircle(Offset(x, size.height - 6), 4, Paint()..color = hc ? Colors.white : const Color(0xFF3E3A36));
      // Прстен.
      final r = Rect.fromCenter(center: Offset(x, size.height * 0.45), width: 12, height: size.height * 0.9);
      if (hc) {
        ring.color = Colors.white;
      } else {
        ring.shader = const LinearGradient(colors: [Color(0xFF8C8C8C), Color(0xFFF2F2F2), Color(0xFF7A7A7A)])
            .createShader(r);
      }
      canvas.drawArc(r, -pi / 2, pi, false, ring);
      canvas.drawArc(r, pi / 2, pi * 0.6, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _SpiralPainter oldDelegate) => oldDelegate.hc != hc;
}