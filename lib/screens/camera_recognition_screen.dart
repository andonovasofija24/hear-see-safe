import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:hear_and_see_safe/models/recognition_result.dart';
import 'package:hear_and_see_safe/services/image_recognition_service.dart';
import 'package:hear_and_see_safe/providers/app_state_provider.dart';
import 'package:hear_and_see_safe/services/camera_clip_player.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';
import 'package:hear_and_see_safe/voice_system/application/voice_command_orchestrator.dart';

/// Множител за големината на текстот на овој екран (поголеми букви).
const double _kCamText = 1.6;

/// Фази на режимот „Барај“.
enum _SearchPhase { idle, searching, found, notFound, stopped }

/// Еден поим што може да се бара (предмет или облека). Поимите со исто име
/// на тековниот јазик (пр. „Чевел“ како предмет и како облека) се спојуваат
/// во еден - секој од нивните клучеви важи како „пронајдено“.
class _SearchConcept {
  _SearchConcept({required this.labelKey, required this.display});

  /// Главниот клуч за превод (за името и клипот).
  final String labelKey;

  /// Името на тековниот јазик (како што се прикажува).
  final String display;

  /// Сите клучеви за превод што значат ист поим.
  final List<String> keys = [];

  /// Нормализирани имиња за споредба со внесениот / изговорениот текст.
  final List<String> names = [];

  String get clipKey => CameraClipPlayer.clipKeyFor(labelKey);

  void addName(String n) {
    if (n.isNotEmpty && !names.contains(n)) names.add(n);
  }
}

/// Зборови што се фрлаат од барањето: „барај куче“, „најди ја топката“,
/// "find the ball", "kërko topin" -> куче / топката / ball / topin.
const Set<String> _kSearchStopWords = {
  // mk
  'барај', 'побарај', 'најди', 'пронајди', 'барам', 'сакам', 'да', 'го', 'ја', 'ги', 'ми', 'мојата', 'мојот', 'моите',
  'каде', 'е', 'ве', 'молам',
  // en
  'find', 'look', 'looking', 'for', 'search', 'the', 'a', 'an', 'my', 'me', 'please', 'i', 'want', 'to', 'where', 'is',
  // sq (без дијакритици - види _normSearch)
  'kerko', 'gjej', 'gjeje', 'gjeni', 'dua', 'te', 'ku', 'eshte', 'tim', 'time', 'tem', 'tende', 'ma',
};

/// Мали букви, без интерпункција и загради, ё/ѐ -> е, ѝ -> и, ë -> e, ç -> c
/// (за да „kerko“ и „kërko“ се исти), празни места собрани во едно.
String _normSearch(String s) {
  var t = s.toLowerCase();
  const swaps = <String, String>{
    'ё': 'е',
    'ѐ': 'е',
    'ѝ': 'и',
    'ë': 'e',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
  };
  for (final e in swaps.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  t = t.replaceAll(RegExp(r'\(.*?\)'), ' ');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return t.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Зборовите од барањето без глаголи/членови. Ако не остане ништо (пр.
/// детето штотуку почнало да пишува „a…“), се враќаат сите зборови.
List<String> _queryTokens(String raw) {
  final all = _normSearch(raw).split(' ').where((w) => w.isNotEmpty).toList();
  final kept = all.where((w) => !_kSearchStopWords.contains(w)).toList();
  return kept.isEmpty ? all : kept;
}

int _commonPrefix(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// Колку добро барањето [q] (зборови) одговара на поимот [c]: 100 точно,
/// 80 почеток на името, 70 почеток на збор, 65 името е збор во барањето,
/// 55 содржи, под 55 - иста основа (множина / член: „топката“, „кучиња“,
/// „topin“). 0 = не одговара.
int _scoreConcept(_SearchConcept c, List<String> q) {
  if (q.isEmpty) return 0;
  final query = q.join(' ');
  var best = 0;
  for (final name in c.names) {
    final words = name.split(' ');
    int s;
    if (name == query) {
      s = 100;
    } else if (name.startsWith(query)) {
      s = 80;
    } else if (words.any((w) => w.startsWith(query))) {
      s = 70;
    } else if (name.length >= 3 && ' $query '.contains(' $name ')) {
      s = 65;
    } else if (query.length >= 3 && name.contains(query)) {
      s = 55;
    } else {
      s = _stemScore(words, q);
    }
    if (s > best) best = s;
  }
  return best;
}

/// Споредба по основа: заеднички почеток од барем 4 букви, или целиот
/// збор од името (3+ букви, „qen“ во „qeni“), или сè освен последната
/// буква („куче“ / „кучиња“), или кај зборови од 5+ букви - сè освен
/// последните две („чевел“ / „чевли“, „liber“ / „librin“). Секој
/// дополнителен совпаднат збор +3; секој несовпаднат збор од името -1
/// (за „маси“ да е „Маса“, а не „Работна маса“).
int _stemScore(List<String> words, List<String> q) {
  var best = 0;
  var matched = 0;
  final hitWords = <int>{};
  for (final t in q) {
    var tokenBest = 0;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final p = _commonPrefix(t, w);
      final ok = p >= 4 ||
          (w.length >= 3 && p == w.length) ||
          (w.length >= 4 && p >= 3 && p == w.length - 1) ||
          (w.length >= 5 && p >= 3 && p >= w.length - 2);
      if (!ok) continue;
      hitWords.add(i);
      final s = 30 + (p > 9 ? 9 : p);
      if (s > tokenBest) tokenBest = s;
    }
    if (tokenBest > 0) matched++;
    if (tokenBest > best) best = tokenBest;
  }
  if (best == 0) return 0;
  final s = best + 3 * (matched - 1) - (words.length - hitWords.length);
  if (s > 50) return 50;
  return s < 1 ? 1 : s;
}

class CameraRecognitionScreen extends StatefulWidget {
  const CameraRecognitionScreen({super.key});

  @override
  State<CameraRecognitionScreen> createState() =>
      _CameraRecognitionScreenState();
}

class _CameraRecognitionScreenState extends State<CameraRecognitionScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _recognitionMode = 'object';

  /// Клуч за превод на грешка при иницијализација на камерата (permission
  /// одбиена, нема камера, платформата не поддржува итн). null = сè уредно,
  /// или сè уште не сме пробале.
  String? _cameraErrorKey;

  /// Последниот резултат од препознавање - го движи "живиот" панел со
  /// резултат (наместо статичен пример).
  RecognitionResult? _lastResult;

  /// Целиот говор на овој екран = однапред снимени клипови
  /// (assets/audio/camera/<јазик>/<клуч>.mp3), БЕЗ системски TTS. Види
  /// docs/camera_snimki.md за листата на сите снимки.
  late final CameraClipPlayer _clips;
  late final ImageRecognitionService _recognitionService;

  static const List<String> _modes = ['object', 'color', 'clothing', 'search'];

  // -------------------------------------------------------------------------
  // Режим „Барај“
  // -------------------------------------------------------------------------

  /// Колку најдолго трае едно барање.
  static const Duration _searchLimit = Duration(seconds: 40);

  /// Колку често се слика и препознава додека се бара.
  static const Duration _scanInterval = Duration(milliseconds: 1200);

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<_SearchConcept>? _conceptsCache;
  String? _conceptsLang;

  /// Што се бара (null = уште не е избрано).
  _SearchConcept? _target;
  _SearchPhase _searchPhase = _SearchPhase.idle;

  /// Бројач: секое ново барање / прекин го зголемува, па старите тајмери и
  /// сликања што уште траат знаат дека се застарени.
  int _searchSession = 0;
  Timer? _searchTicker;
  Timer? _scanTimer;
  final Stopwatch _searchWatch = Stopwatch();
  bool _scanBusy = false;
  int _scanErrors = 0;
  int _lastTickSecond = 0;

  /// Внесениот / изговорениот збор не е познат поим.
  bool _searchUnknown = false;

  /// Грешка што го запрела барањето (клуч за превод).
  String? _searchErrorKey;
  bool _voiceListening = false;

  /// Поим пронајден од горното копче за гласовна команда (Г).
  _SearchConcept? _pendingVoiceConcept;

  bool get _isSearching => _searchPhase == _SearchPhase.searching;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    _clips = CameraClipPlayer(isEnabled: () => appState.isVoiceAssistantEnabled);
    _recognitionService = MlKitRecognitionService();
    _initializeCamera();
  }

  String get _langCode => context.locale.languageCode;

  /// Пушта клипови по ред (ја прекинува претходната секвенца).
  Future<void> _say(List<String> clipKeys) {
    if (!mounted) return Future.value();
    return _clips.playSequence(_langCode, clipKeys);
  }

  /// Порака со клуч за превод (пр. 'camera.error_timeout') -> нејзиниот клип.
  Future<void> _sayMessage(String translationKey) =>
      _say([CameraClipPlayer.clipKeyFor(translationKey)]);

  Future<void> _initializeCamera() async {
    setState(() => _cameraErrorKey = null);
    // Препознавањето (Google ML Kit) работи само во апликацијата на
    // Android / iOS, не во прелистувач.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _failInit('camera.error_web'));
      return;
    }
    try {
      final status = await Permission.camera.request();

      if (!status.isGranted) {
        await _failInit('camera.error_permission');
        return;
      }

      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        await _failInit('camera.error_no_camera');
        return;
      }

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _cameraErrorKey = null;
      });

      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 100);
      }
      await _sayMessage('camera.ready');
    } catch (_) {
      await _failInit('camera.error_camera_unavailable');
    }
  }

  /// Заедничка логика кога иницијализацијата на камерата не успее - секогаш
  /// со видлива состојба (не бесконечен spinner), глас и посебен вибрациски
  /// шаблон за грешка.
  Future<void> _failInit(String errorKey) async {
    if (!mounted) return;
    setState(() {
      _isInitialized = false;
      _cameraErrorKey = errorKey;
    });
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
    }
    await _sayMessage(errorKey);
  }

  Future<void> _captureAndRecognize() async {
    final controller = _cameraController;

    // НИКОГАШ тивко - секое можно излегување без резултат добива глас +
    // вибрација + видлива порака, за корисникот секогаш да знае што се
    // случува (претходно тука имаше тивок `return` што личеше на "не
    // прави ништо" кога камерата не е подготвена).
    if (controller == null || !controller.value.isInitialized) {
      await _sayMessage('camera.error_not_ready');
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
      return;
    }
    // Барањето можеби уште ја довршува својата слика - не прави грешка.
    if (_isProcessing || controller.value.isTakingPicture) return;

    setState(() {
      _isProcessing = true;
      _lastResult = null;
    });

    XFile? shot;
    try {
      // Не чекаме да заврши - сликањето оди паралелно; резултатот (нова
      // секвенца) го прекинува ова ако уште трае.
      unawaited(_sayMessage('camera.analyzing'));
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 150);
      }

      final image = await controller.takePicture().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw const RecognitionException('camera.error_timeout'),
          );
      shot = image;

      if (!mounted) return;

      final result = await _recognitionService
          .recognize(image: image, mode: _recognitionMode)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw const RecognitionException('camera.error_timeout'),
          );

      if (!mounted) return;

      await _announceResult(result);

      setState(() => _lastResult = result);
      AccessibilityUtils.provideFeedback(context: context);
    } on RecognitionException catch (e) {
      if (!mounted) return;
      await _sayMessage(e.messageKey);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
    } catch (_) {
      if (!mounted) return;
      await _sayMessage('camera.error');
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
    } finally {
      _deleteTemp(shot);
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Ја брише привремената слика од takePicture (на телефон се снима во
  /// кеш-папката) - да не се трупаат датотеки при постојано сликање.
  void _deleteTemp(XFile? image) {
    if (image == null || kIsWeb) return;
    unawaited(() async {
      try {
        await File(image.path).delete();
      } catch (_) {}
    }());
  }

  /// Говор + вибрација прилагодени на исходот - различен шаблон за
  /// "несигурно" наспроти "пронајдено", за лицата со оштетен вид да можат
  /// да го разликуваат исходот и само преку допир, без да гледаат екран.
  Future<void> _announceResult(RecognitionResult result) async {
    if (result.confidence < ImageRecognitionService.defaultConfidenceThreshold ||
        result.labelKey == 'camera.uncertain') {
      await _sayMessage('camera.uncertain');
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 100, 80, 100]);
      }
      return;
    }

    await _say(_resultClips(result));
    if (!mounted) return;
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 250);
    }
  }

  /// Шаблон од клипови за сигурен резултат:
  ///  * бои:     „Бојата е“ + боја            -> [tpl_color_is, color_red]
  ///  * предмет: „Пронајдов:“ + предмет       -> [tpl_found, obj_dog]
  ///  * облека:  „Пронајдов:“ + облека, пауза, „Бојата е“ + боја
  ///             -> [tpl_found, cloth_shirt, _pause, tpl_color_is, color_blue]
  List<String> _resultClips(RecognitionResult result) {
    final main = CameraClipPlayer.clipKeyFor(result.labelKey);
    if (result.mode == 'color' || main.startsWith('color_')) {
      return [CameraClipPlayer.tplColorIs, main];
    }
    final keys = [CameraClipPlayer.tplFound, main];
    final secondary = result.secondaryLabelKey;
    if (secondary != null) {
      keys
        ..add(CameraClipPlayer.pause)
        ..add(CameraClipPlayer.tplColorIs)
        ..add(CameraClipPlayer.clipKeyFor(secondary));
    }
    return keys;
  }

  // -------------------------------------------------------------------------
  // Режим „Барај“ - избор на поим
  // -------------------------------------------------------------------------

  Future<void> _buzz({int? duration, List<int>? pattern}) async {
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: duration, pattern: pattern);
    }
  }

  /// Сите поими што може да се бараат (предмети + облека), со имиња на
  /// тековниот јазик. Се прави еднаш по јазик.
  List<_SearchConcept> _concepts() {
    final lang = _langCode;
    final cached = _conceptsCache;
    if (cached != null && _conceptsLang == lang) return cached;
    final byName = <String, _SearchConcept>{};
    final list = <_SearchConcept>[];
    for (final key in [...RecognitionVocabulary.objectKeys, ...RecognitionVocabulary.clothingKeys]) {
      final display = key.tr();
      final norm = _normSearch(display);
      if (norm.isEmpty) continue;
      var concept = byName[norm];
      if (concept == null) {
        concept = _SearchConcept(labelKey: key, display: display);
        byName[norm] = concept;
        list.add(concept);
      }
      concept.keys.add(key);
      concept.addName(norm);
      // „Кошула/маица“ -> и „кошула“ и „маица“.
      for (final part in display.split('/')) {
        concept.addName(_normSearch(part));
      }
      // На англиски - и имињата од ML Kit („puppy“, „kitten“, „sneakers“...).
      if (lang == 'en') {
        for (final raw in RecognitionVocabulary.rawLabelsFor(key)) {
          concept.addName(_normSearch(raw));
        }
      }
    }
    _conceptsCache = list;
    _conceptsLang = lang;
    return list;
  }

  /// Поими подредени по тоа колку одговараат на [text] (најдобрите прво).
  List<({_SearchConcept concept, int score})> _rankConcepts(String text) {
    final q = _queryTokens(text);
    if (q.isEmpty) return const [];
    final ranked = <({_SearchConcept concept, int score})>[];
    for (final c in _concepts()) {
      final score = _scoreConcept(c, q);
      if (score > 0) ranked.add((concept: c, score: score));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byLen = a.concept.display.length.compareTo(b.concept.display.length);
      if (byLen != 0) return byLen;
      return a.concept.display.compareTo(b.concept.display);
    });
    return ranked;
  }

  /// Предлози додека се пишува (најмногу 6).
  List<_SearchConcept> _suggestions() {
    final text = _searchCtrl.text;
    final target = _target;
    if (target != null && _normSearch(text) == _normSearch(target.display)) return const [];
    return [for (final r in _rankConcepts(text).take(6)) r.concept];
  }

  /// Најдобриот поим за [text] (внесено или изговорено), или null. Кога
  /// совпаѓањето е само по основа (под 55) и два различни поими се
  /// подеднакво добри - не погодуваме.
  _SearchConcept? _resolveQuery(String text) {
    final ranked = _rankConcepts(text);
    if (ranked.isEmpty) return null;
    final first = ranked.first;
    if (first.score < 55 && ranked.length > 1 && ranked[1].score == first.score) return null;
    return first.concept;
  }

  void _onQueryChanged(String text) {
    final target = _target;
    setState(() {
      _searchUnknown = false;
      _searchErrorKey = null;
      if (target != null && _normSearch(text) != _normSearch(target.display)) _target = null;
    });
  }

  void _clearQuery() {
    _searchCtrl.clear();
    setState(() {
      _target = null;
      _searchUnknown = false;
      _searchErrorKey = null;
      _searchPhase = _SearchPhase.idle;
    });
    _searchFocus.requestFocus();
  }

  void _selectTarget(_SearchConcept concept) {
    if (!mounted) return;
    if (_isSearching) _abortSearch();
    _searchCtrl.value = TextEditingValue(
      text: concept.display,
      selection: TextSelection.collapsed(offset: concept.display.length),
    );
    _searchFocus.unfocus();
    setState(() {
      _target = concept;
      _searchUnknown = false;
      _searchErrorKey = null;
      _searchPhase = _SearchPhase.idle;
    });
    // „Барам:“ + името на поимот.
    unawaited(_say([CameraClipPlayer.clipKeyFor('camera.search_target'), concept.clipKey]));
  }

  /// Enter во полето или изговорен текст.
  void _submitQuery(String text) {
    if (!mounted || _isSearching) return;
    final concept = _resolveQuery(text);
    if (concept == null) {
      setState(() {
        _target = null;
        _searchUnknown = text.trim().isNotEmpty;
      });
      if (text.trim().isEmpty) {
        unawaited(_sayMessage('camera.search_prompt'));
      } else {
        unawaited(_sayMessage('camera.search_unknown'));
        unawaited(_buzz(pattern: const [0, 100, 80, 100]));
      }
      return;
    }
    _selectTarget(concept);
  }

  /// Копчето со микрофон: слуша еднаш (истото препознавање на говор како
  /// гласовните команди во апликацијата, на тековниот јазик).
  Future<void> _listenForTarget() async {
    if (_voiceListening || _isSearching) return;
    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);
    // Да не го слуша сопствениот говор на екранот.
    await _clips.stop();
    if (!mounted) return;
    setState(() {
      _voiceListening = true;
      _searchUnknown = false;
      _searchErrorKey = null;
    });
    String? transcript;
    try {
      transcript = await orchestrator.listenOnce();
    } catch (_) {
      transcript = null;
    }
    if (!mounted) return;
    setState(() => _voiceListening = false);
    if (_isSearching) return;
    final heard = transcript?.trim() ?? '';
    if (heard.isEmpty) {
      // Ништо не е чуено - повторно прашањето.
      await _sayMessage('camera.search_prompt');
      return;
    }
    // Се покажува што е чуено (ако не се препознае, детето го гледа зборот).
    _searchCtrl.value = TextEditingValue(
      text: heard,
      selection: TextSelection.collapsed(offset: heard.length),
    );
    _submitQuery(heard);
  }

  /// Опции за горното копче за гласовна команда (и копчето Г) во режимот
  /// „Барај“: „стоп“ додека се бара, инаку - името на поимот.
  List<VoiceCategoryOption> _voiceOptions() {
    if (_recognitionMode != 'search') return const [];
    if (_isSearching) {
      return [
        VoiceCategoryOption(
          keywords: const ['стоп', 'запри', 'прекини', 'stop', 'ndalo', 'ndal'],
          beforeGlobal: true,
          onSelected: _stopSearch,
        ),
      ];
    }
    return [
      VoiceCategoryOption(
        keywords: const [],
        matches: (t) {
          _pendingVoiceConcept = _resolveQuery(t);
          return _pendingVoiceConcept != null;
        },
        onSelected: () {
          final c = _pendingVoiceConcept;
          _pendingVoiceConcept = null;
          if (c != null) _selectTarget(c);
        },
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Режим „Барај“ - самото барање
  // -------------------------------------------------------------------------

  bool _searchActive(int session) => mounted && session == _searchSession && _isSearching;

  Future<void> _startSearch() async {
    if (_isSearching || _voiceListening) return;
    final target = _target;
    if (target == null) {
      // Уште не е избрано што се бара.
      _searchFocus.requestFocus();
      await _sayMessage('camera.search_prompt');
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _sayMessage('camera.error_not_ready');
      await _buzz(pattern: const [0, 150, 100, 150]);
      return;
    }
    _searchFocus.unfocus();
    _cancelSearchTimers();
    final session = ++_searchSession;
    _scanErrors = 0;
    _lastTickSecond = 0;
    _scanBusy = false;
    _searchWatch
      ..reset()
      ..start();
    setState(() {
      _searchPhase = _SearchPhase.searching;
      _searchUnknown = false;
      _searchErrorKey = null;
      _lastResult = null;
    });
    _searchTicker = Timer.periodic(const Duration(milliseconds: 500), (_) => _onSearchTick(session));
    _scanTimer = Timer.periodic(_scanInterval, (_) => unawaited(_scanOnce(session)));
    // „Барам… врти го телефонот полека наоколу.“
    unawaited(_sayMessage('camera.searching'));
    unawaited(_buzz(duration: 120));
    unawaited(_scanOnce(session));
  }

  /// Секои пола секунда: одбројување на екранот, кратка вибрација на
  /// секои 3 секунди (детето знае дека барањето уште трае) и крај по 40 s.
  void _onSearchTick(int session) {
    if (!_searchActive(session)) return;
    final elapsed = _searchWatch.elapsed;
    if (elapsed >= _searchLimit) {
      unawaited(_finishSearch(_SearchPhase.notFound));
      return;
    }
    final sec = elapsed.inSeconds;
    if (sec > 0 && sec % 3 == 0 && sec != _lastTickSecond) {
      _lastTickSecond = sec;
      unawaited(_buzz(duration: 35));
    }
    setState(() {});
  }

  /// Една слика + препознавање. Ако претходното уште трае - се прескокнува.
  Future<void> _scanOnce(int session) async {
    if (_scanBusy || !_searchActive(session)) return;
    final controller = _cameraController;
    final target = _target;
    if (controller == null || !controller.value.isInitialized || target == null) return;
    if (controller.value.isTakingPicture) return;
    _scanBusy = true;
    XFile? image;
    try {
      image = await controller.takePicture().timeout(const Duration(seconds: 8));
      if (!_searchActive(session)) return;
      final concepts = await _recognitionService.recognizeConcepts(image: image).timeout(const Duration(seconds: 12));
      if (!_searchActive(session)) return;
      _scanErrors = 0;
      // Сите ознаки на сликата, не само најдобрата: доволно е еден од
      // клучевите на поимот да е над прагот.
      const threshold = ImageRecognitionService.defaultConfidenceThreshold;
      final hit = target.keys.any((k) => (concepts[k] ?? 0) >= threshold);
      if (hit) await _finishSearch(_SearchPhase.found);
    } on RecognitionException catch (e) {
      if (!_searchActive(session)) return;
      if (e.messageKey == 'camera.error_unsupported_platform' || ++_scanErrors >= 3) {
        await _failSearch(e.messageKey);
      }
    } catch (_) {
      // Една неуспешна слика не го прекинува барањето; три по ред - да.
      if (!_searchActive(session)) return;
      if (++_scanErrors >= 3) await _failSearch('camera.error');
    } finally {
      // Само ако сè уште е истото барање (новото има свој _scanBusy).
      if (session == _searchSession || !_isSearching) _scanBusy = false;
      _deleteTemp(image);
    }
  }

  void _cancelSearchTimers() {
    _searchTicker?.cancel();
    _searchTicker = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _searchWatch.stop();
  }

  /// Крај на барањето со глас и вибрација (пронајдено / време истече /
  /// прекинато од детето).
  Future<void> _finishSearch(_SearchPhase phase) async {
    if (!mounted || !_isSearching) return;
    _cancelSearchTimers();
    _searchSession++;
    _scanBusy = false;
    setState(() => _searchPhase = phase);
    final target = _target;
    if (phase == _SearchPhase.found) {
      // „Пронајдов го!“ + името; силна, долга вибрација.
      unawaited(_say([
        CameraClipPlayer.clipKeyFor('camera.search_found'),
        if (target != null) target.clipKey,
      ]));
      await _buzz(pattern: const [0, 300, 120, 300, 120, 600]);
    } else if (phase == _SearchPhase.notFound) {
      unawaited(_sayMessage('camera.search_not_found'));
      await _buzz(pattern: const [0, 150, 100, 150]);
    } else if (phase == _SearchPhase.stopped) {
      unawaited(_sayMessage('camera.search_stopped'));
      await _buzz(duration: 150);
    }
  }

  /// Барањето запира поради грешка на камерата / препознавањето.
  Future<void> _failSearch(String errorKey) async {
    if (!mounted || !_isSearching) return;
    _cancelSearchTimers();
    _searchSession++;
    _scanBusy = false;
    setState(() {
      _searchPhase = _SearchPhase.stopped;
      _searchErrorKey = errorKey;
    });
    unawaited(_sayMessage(errorKey));
    await _buzz(pattern: const [0, 150, 100, 150]);
  }

  /// Копчето „Стоп“ (и С / „стоп“ со глас).
  void _stopSearch() => unawaited(_finishSearch(_SearchPhase.stopped));

  /// Тивок прекин (промена на режим, апликацијата во позадина, излез).
  /// Не повикува setState - тоа го прави повикувачот ако треба.
  void _abortSearch({_SearchPhase to = _SearchPhase.idle}) {
    _cancelSearchTimers();
    _searchSession++;
    _scanBusy = false;
    if (_isSearching) _searchPhase = to;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && _isSearching) {
      _abortSearch(to: _SearchPhase.stopped);
      unawaited(_clips.stop());
      if (mounted) setState(() {});
    }
  }

  static const Color _accent = Color(0xFFEA580C);

  /// Икона и боја за секој режим.
  static const Map<String, IconData> _modeIcons = {
    'object': Icons.category_rounded,
    'color': Icons.palette_rounded,
    'clothing': Icons.checkroom_rounded,
    'search': Icons.travel_explore_rounded,
  };
  static const Map<String, Color> _modeColors = {
    'object': Color(0xFF2563EB),
    'color': Color(0xFFDB2777),
    'clothing': Color(0xFF9333EA),
    'search': Color(0xFF0D9488),
  };

  Widget _buildCameraPreview() {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized) {
      // Во средина, со својот однос на страни (без развлекување).
      return Center(child: CameraPreview(_cameraController!));
    }
    return _loading();
  }

  Widget _loading() {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Center(
      child: SizedBox(
        width: 54,
        height: 54,
        child: CircularProgressIndicator(strokeWidth: 5, color: hc ? Colors.white : Playful.sun),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abortSearch();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    unawaited(_clips.dispose());
    _cameraController?.dispose();
    _recognitionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);

    final modeLabels = {
      'object': 'camera.object'.tr(),
      'color': 'camera.color'.tr(),
      'clothing': 'camera.clothing'.tr(),
      'search': 'camera.search'.tr(),
    };
    final searchMode = _recognitionMode == 'search';

    return GameScreenChrome(
      accent: _accent,
      title: 'features.camera_recognition'.tr(),
      voiceOptions: _voiceOptions(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['📷', '🎨', '👕', '🔍', '✨', '🧸'],
        tint: _accent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
            final shortScreen = constraints.maxHeight < 620;
            // Четирите режими: 2 x 2 кога има доволно висина; на ниски
            // екрани - четири во ред, за визирот на камерата да не исчезне.
            final gridModes = constraints.maxHeight >= 700;
            // На ниски екрани текстот во резултатот расте помалку.
            final resultScale = shortScreen ? 1.3 : _kCamText;

            Widget tile(int i) => PopIn(
                  index: i,
                  child: _modeButton(_modes[i], modeLabels[_modes[i]]!, hc),
                );
            final modes = gridModes
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var r = 0; r < _modes.length; r += 2) ...[
                        if (r > 0) const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: tile(r)),
                            const SizedBox(width: 10),
                            Expanded(child: r + 1 < _modes.length ? tile(r + 1) : const SizedBox.shrink()),
                          ],
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _modes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: tile(i)),
                      ],
                    ],
                  );

            if (searchMode) {
              // „Барај“: полето, предлозите и копчињата не собираат под
              // визирот на мал телефон - целото се лизга, визирот има
              // фиксна висина.
              final viewfinderHeight = (constraints.maxHeight * 0.40).clamp(170.0, 440.0);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(side, 12, side, 16),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modes,
                    const SizedBox(height: 14),
                    SizedBox(height: viewfinderHeight, child: _buildViewfinder(hc)),
                    const SizedBox(height: 14),
                    _buildSearchPanel(hc, compact: shortScreen),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  modes,
                  const SizedBox(height: 14),
                  // Визир: камерата во рамка со златни агли; при анализа -
                  // златна линија што скенира.
                  Expanded(child: _buildViewfinder(hc)),
                  const SizedBox(height: 14),
                  if (_lastResult != null || _isProcessing) ...[
                    _buildResultPanel(hc, compact: shortScreen, textScale: resultScale),
                    const SizedBox(height: 12),
                  ],
                  Center(
                    child: SoundOrb(
                      icon: Icons.camera_alt_rounded,
                      label: _isProcessing ? 'camera.analyzing'.tr() : 'camera.capture'.tr(),
                      onTap: _isProcessing ? null : _captureAndRecognize,
                      active: _isProcessing,
                      size: shortScreen ? 76 : 96,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Визирот: камерата (или грешка), златните агли, линијата што скенира
  /// и - во режимот „Барај“ - големата ознака кога поимот е пронајден.
  Widget _buildViewfinder(bool hc) {
    final target = _target;
    final showFound = _recognitionMode == 'search' && _searchPhase == _SearchPhase.found && target != null;
    return Container(
      decoration: BoxDecoration(
        color: hc ? Colors.black : Playful.nightDeep,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white, width: hc ? 4 : 3),
        boxShadow: hc ? null : [BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 26)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cameraErrorKey != null
                ? _buildErrorState(hc)
                : (_isInitialized ? _buildCameraPreview() : _loading()),
            if (_cameraErrorKey == null)
              IgnorePointer(
                child: CustomPaint(painter: _ViewfinderPainter(highContrast: hc)),
              ),
            if ((_isProcessing || _isSearching) && !hc && !Playful.reduceMotion(context))
              const IgnorePointer(child: _ScanLine()),
            if (showFound && target != null)
              IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PopIn(
                      key: ValueKey('found_${target.labelKey}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: hc ? Colors.black : const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 48),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                target.display,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Playful.display(24 * _kCamText, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Режим „Барај“ - изглед
  // -------------------------------------------------------------------------

  Widget _buildSearchPanel(bool hc, {bool compact = false}) {
    final ink = hc ? Colors.white : Playful.ink;
    final searching = _isSearching;
    final suggestions = searching ? const <_SearchConcept>[] : _suggestions();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: hc ? Colors.white : _modeColors['search']!, width: 3),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: _submitQuery,
                  style: Playful.title(16 * _kCamText, color: ink),
                  cursorColor: ink,
                  decoration: InputDecoration(
                    hintText: 'camera.search_hint'.tr(),
                    hintMaxLines: 1,
                    hintStyle: Playful.body(13 * _kCamText, color: ink.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: hc ? Colors.black : Colors.white,
                    prefixIcon: Icon(Icons.search_rounded, size: 30, color: ink),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'camera.search_clear'.tr(),
                            iconSize: 30,
                            icon: Icon(Icons.close_rounded, color: ink),
                            onPressed: _clearQuery,
                          ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: hc ? const Color(0xFFFFFF00) : Playful.sun, width: 4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _searchMicButton(hc),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Semantics(
              container: true,
              label: 'camera.search_suggestions'.tr(),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final c in suggestions) _suggestionChip(c, hc)],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        _buildSearchStatus(hc, compact: compact),
        const SizedBox(height: 14),
        Center(
          child: searching
              ? _searchStopButton(hc)
              : SoundOrb(
                  icon: Icons.travel_explore_rounded,
                  label: 'camera.search_start'.tr(),
                  onTap: _voiceListening ? null : _startSearch,
                  size: compact ? 76 : 96,
                ),
        ),
      ],
    );
  }

  Widget _searchMicButton(bool hc) {
    final label = _voiceListening ? 'camera.search_listening'.tr() : 'camera.search_voice'.tr();
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: PressableScale(
          child: Material(
            color: hc ? Colors.black : (_voiceListening ? Playful.sun : _modeColors['search']!),
            shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _voiceListening ? null : _listenForTarget,
              child: SizedBox(
                width: 66,
                height: 66,
                child: Icon(
                  _voiceListening ? Icons.hearing_rounded : Icons.mic_rounded,
                  size: 36,
                  color: hc ? Colors.white : (_voiceListening ? Playful.ink : Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionChip(_SearchConcept c, bool hc) {
    final ink = hc ? Colors.white : Playful.ink;
    return Semantics(
      button: true,
      label: c.display,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: hc ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _selectTarget(c),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56, minWidth: 56),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: hc ? Colors.white : _modeColors['search']!, width: 3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 24, color: ink),
                    const SizedBox(width: 6),
                    Flexible(child: Text(c.display, style: Playful.title(15 * _kCamText, color: ink))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Големото црвено „Стоп“ додека се бара (и копчето С).
  Widget _searchStopButton(bool hc) {
    final label = 'camera.search_stop'.tr();
    return StartHotkeyListener(
      onTrigger: _stopSearch,
      child: Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: PressableScale(
            child: Material(
              color: hc ? Colors.black : const Color(0xFFDC2626),
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: _stopSearch,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 76, minWidth: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: hc ? null : [BoxShadow(color: const Color(0xFFDC2626).withValues(alpha: 0.5), blurRadius: 20)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_circle_rounded, size: 44, color: Colors.white),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(label, textAlign: TextAlign.center, style: Playful.display(20 * _kCamText, color: Colors.white)),
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

  /// Картичка со состојбата: што се бара, одбројување, пронајдено / не е
  /// пронајдено / прекинато / непознат збор.
  Widget _buildSearchStatus(bool hc, {bool compact = false}) {
    final ink = hc ? Colors.white : Playful.ink;
    final target = _target;
    final scale = compact ? 1.3 : _kCamText;

    final Color stateColor;
    final Widget leading;
    String? caption; // мал натпис горе
    String? headline; // големиот текст
    String? detail; // објаснување под него

    Widget circleIcon(IconData icon, Color color) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hc ? Colors.black : color,
            border: Border.all(color: hc ? Colors.white : color, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 36),
        );

    if (_isSearching) {
      stateColor = Playful.sun;
      final elapsed = _searchWatch.elapsed;
      final left = _searchLimit - elapsed;
      final secondsLeft = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
      final fraction = (left.inMilliseconds / _searchLimit.inMilliseconds).clamp(0.0, 1.0);
      leading = Semantics(
        label: 'camera.search_seconds'.tr(args: ['$secondsLeft']),
        child: ExcludeSemantics(
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 7,
                  color: hc ? Colors.white : const Color(0xFFD97706),
                  backgroundColor: hc ? Colors.white24 : Playful.sun.withValues(alpha: 0.3),
                ),
                Center(child: Text('$secondsLeft', style: Playful.display(24, color: ink))),
              ],
            ),
          ),
        ),
      );
      caption = 'camera.search_target'.tr();
      headline = target?.display;
      detail = 'camera.searching'.tr();
    } else if (_voiceListening) {
      stateColor = _modeColors['search']!;
      leading = circleIcon(Icons.hearing_rounded, stateColor);
      headline = 'camera.search_listening'.tr();
    } else if (_searchErrorKey != null) {
      stateColor = const Color(0xFFDC2626);
      leading = circleIcon(Icons.error_outline_rounded, stateColor);
      detail = _searchErrorKey!.tr();
    } else if (_searchUnknown) {
      stateColor = const Color(0xFFD97706);
      leading = circleIcon(Icons.help_outline_rounded, stateColor);
      detail = 'camera.search_unknown'.tr();
    } else if (_searchPhase == _SearchPhase.found && target != null) {
      stateColor = const Color(0xFF16A34A);
      leading = circleIcon(Icons.check_rounded, stateColor);
      caption = 'camera.search_found'.tr();
      headline = target.display;
    } else if (_searchPhase == _SearchPhase.notFound) {
      stateColor = const Color(0xFFD97706);
      leading = circleIcon(Icons.search_off_rounded, stateColor);
      caption = target == null ? null : 'camera.search_target'.tr();
      headline = target?.display;
      detail = 'camera.search_not_found'.tr();
    } else if (_searchPhase == _SearchPhase.stopped) {
      stateColor = const Color(0xFF64748B);
      leading = circleIcon(Icons.stop_rounded, stateColor);
      caption = target == null ? null : 'camera.search_target'.tr();
      headline = target?.display;
      detail = 'camera.search_stopped'.tr();
    } else if (target != null) {
      stateColor = _modeColors['search']!;
      leading = circleIcon(Icons.travel_explore_rounded, stateColor);
      caption = 'camera.search_target'.tr();
      headline = target.display;
      detail = 'camera.search_ready_hint'.tr();
    } else {
      stateColor = _modeColors['search']!;
      leading = circleIcon(Icons.lightbulb_outline_rounded, stateColor);
      detail = 'camera.search_prompt'.tr();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hc ? Colors.white : stateColor, width: 3),
        boxShadow: hc ? null : [BoxShadow(color: stateColor.withValues(alpha: 0.4), blurRadius: 16)],
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (caption != null)
                    Text(caption, style: Playful.body(14 * scale, color: ink.withValues(alpha: hc ? 1 : 0.75))),
                  if (headline != null)
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Playful.display((_searchPhase == _SearchPhase.found ? 26 : 22) * scale, color: ink),
                    ),
                  if (detail != null) ...[
                    if (caption != null || headline != null) const SizedBox(height: 4),
                    Text(detail, style: Playful.body(14 * scale, color: ink)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool hc) {
    return Container(
      color: hc ? Colors.black : Playful.nightRaised,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : const Color(0xFFDC2626),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.videocam_off_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 16),
            Text(
              _cameraErrorKey!.tr(),
              textAlign: TextAlign.center,
              style: Playful.title(19 * _kCamText, color: Colors.white),
            ),
            const SizedBox(height: 18),
            PressableScale(
              child: Material(
                color: hc ? Colors.black : Playful.sun,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _initializeCamera,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: hc ? 2 : 3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 32, color: hc ? Colors.white : Playful.ink),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'camera.retry'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.title(18 * _kCamText, color: hc ? Colors.white : Playful.ink),
                          ),
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
    );
  }

  /// „Жив“ резултат - бела картичка со златен раб: додека се анализира
  /// бранови, потоа зелена ✓ (пронајдено) или портокалово ? (несигурно).
  Widget _buildResultPanel(bool hc, {bool compact = false, double textScale = _kCamText}) {
    final result = _lastResult;
    final uncertain = result != null &&
        (result.confidence < ImageRecognitionService.defaultConfidenceThreshold ||
            result.labelKey == 'camera.uncertain');
    final stateColor = _isProcessing
        ? Playful.sun
        : (uncertain ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    final ink = hc ? Colors.white : Playful.ink;

    return PopIn(
      key: ValueKey(_isProcessing ? 'processing' : 'result_${result?.labelKey}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hc ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hc ? Colors.white : stateColor, width: 3),
          boxShadow: hc ? null : [BoxShadow(color: stateColor.withValues(alpha: 0.45), blurRadius: 18)],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : (_isProcessing ? Playful.night : stateColor),
                border: Border.all(color: hc ? Colors.white : stateColor, width: 2),
              ),
              child: Center(
                child: _isProcessing
                    ? (hc
                        ? const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 30)
                        : const SoundWave(color: Playful.sun, bars: 5, height: 24, barWidth: 4))
                    : Icon(
                        uncertain ? Icons.help_outline_rounded : Icons.check_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('camera.result_label'.tr(), style: Playful.body(14 * textScale, color: ink.withValues(alpha: 0.7))),
                    const SizedBox(height: 2),
                    if (_isProcessing)
                      Text(
                        'camera.analyzing'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.display((compact ? 20 : 22) * textScale, color: ink),
                      )
                    else if (result != null)
                      // maxLines: на 360x640 со голем текст (до 1.6x) долгите
                      // MK/SQ пораки инаку го туркаат визирот под 0 и Column-от
                      // прелева. Целиот текст е и понатаму во семантиката/говорот.
                      Text(
                        uncertain ? 'camera.uncertain'.tr() : result.labelKey.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.display((compact ? 22 : 26) * textScale, color: ink),
                      ),
                    if (!_isProcessing && result != null && !uncertain && result.secondaryLabelKey != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.secondaryLabelKey!.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.body(17 * textScale, color: ink),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плочка за режим - во својата боја; избраната е златна со бел раб.
  Widget _modeButton(String mode, String label, bool hc, {bool stacked = false}) {
    final isActive = _recognitionMode == mode;
    final color = _modeColors[mode] ?? _accent;
    final fg = isActive ? (hc ? Colors.black : Playful.ink) : Colors.white;

    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                // Секоја промена на режим тивко го прекинува барањето.
                final wasSearching = _isSearching;
                _abortSearch();
                setState(() {
                  _recognitionMode = mode;
                  _lastResult = null;
                  if (mode != 'search' || wasSearching) _searchPhase = _SearchPhase.idle;
                });
                if (mode != 'search') _searchFocus.unfocus();
                // Името на режимот (снимка) - и го прекинува претходниот говор.
                // „Барај“ - и прашањето „Што бараш? Напиши или кажи.“
                unawaited(_say(mode == 'search'
                    ? [CameraClipPlayer.modeKey(mode), CameraClipPlayer.pause, CameraClipPlayer.clipKeyFor('camera.search_prompt')]
                    : [CameraClipPlayer.modeKey(mode)]));
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: stacked ? 8 : 10, horizontal: stacked ? 18 : 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: hc ? (isActive ? const Color(0xFFFFFF00) : Colors.black) : (isActive ? Playful.sun : null),
                  gradient: hc || isActive
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(color, Colors.white, 0.05)!, Color.lerp(color, Colors.black, 0.35)!],
                        ),
                  border: Border.all(color: Colors.white, width: isActive ? 3 : 2),
                  boxShadow: hc
                      ? null
                      : [BoxShadow(color: (isActive ? Playful.sun : color).withValues(alpha: isActive ? 0.6 : 0.35), blurRadius: isActive ? 20 : 12)],
                ),
                child: stacked
                    // Еден под друг: икона + натпис во ред, на средина.
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_modeIcons[mode], size: 36, color: fg),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(label, textAlign: TextAlign.center, style: Playful.title(15 * _kCamText, color: fg)),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_modeIcons[mode], size: 34, color: fg),
                          const SizedBox(height: 4),
                          // Три во ред (низок екран) - натписот се смалува ако не собира.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, textAlign: TextAlign.center, style: Playful.title(15 * _kCamText, color: fg)),
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
}

/// Златни агли на визирот (како кај камера).
class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.highContrast});

  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = highContrast ? Colors.white : Playful.sun
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 18.0;
    final len = (size.shortestSide * 0.14).clamp(18.0, 48.0);
    final l = inset, t = inset, r = size.width - inset, b = size.height - inset;
    // горе-лево
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l, t + len), paint);
    // горе-десно
    canvas.drawLine(Offset(r, t), Offset(r - len, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // долу-лево
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - len), paint);
    // долу-десно
    canvas.drawLine(Offset(r, b), Offset(r - len, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) => old.highContrast != highContrast;
}

/// Златна линија што оди горе-долу низ визирот додека се анализира.
class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Align(
        alignment: Alignment(0, -0.9 + 1.8 * Curves.easeInOut.transform(_c.value)),
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Playful.sun,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: Playful.sun.withValues(alpha: 0.8), blurRadius: 16, spreadRadius: 3)],
          ),
        ),
      ),
    );
  }
}