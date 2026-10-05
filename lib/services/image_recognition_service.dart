import 'dart:math';

import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;

import 'package:hear_and_see_safe/models/recognition_result.dart';

/// Се фрла кога препознавањето не можело да заврши (нечитлива слика, модел
/// не успеал да се вчита итн). Екранот го фаќа ова и покажува соодветна
/// порака (најчесто 'camera.error').
class RecognitionException implements Exception {
  final String messageKey;
  const RecognitionException(this.messageKey);
}

/// Апстракција за "кој и да е" backend за препознавање, за да логиката во
/// екранот никогаш директно не зависи од конкретен API/модел. Ако утре се
/// смени провајдерот, се менува само имплементацијата тука - екранот
/// останува ист.
abstract class ImageRecognitionService {
  /// Праг под кој резултатот се смета за "несигурен" (се јавува
  /// 'camera.uncertain' наместо резултатот). Ова е ПОЧЕТНА вредност за
  /// тестирање - можеби ќе треба да се прилагоди по вистинско тестирање на
  /// телефон.
  static const double defaultConfidenceThreshold = 0.65;

  Future<RecognitionResult> recognize({
    required XFile image,
    required String mode,
  });

  /// Се повикува кога екранот се уништува, за да се ослободат ресурсите на
  /// моделот (на пр. затворање на ML Kit labeler-от).
  void dispose();
}

/// Имплементација преку Google ML Kit "Image Labeling" - модел кој работи
/// ЛОКАЛНО НА УРЕДОТ (on-device), за режимите "предмети" и "облека", плус
/// локална (офлајн) детекција на доминантна боја за режимот "бои".
///
/// Клучни предности во однос на облак-базиран API (пр. Cloud Vision):
/// - Бесплатно засекогаш, без API клуч, без квота, без ризик од изложен
///   клуч кај корисникот.
/// - Работи целосно ОФЛАЈН - важно за деца/пристапност, апликацијата не
///   зависи од интернет врска за да препознае предмет.
/// - Побрзо, нема мрежен round-trip.
///
/// ⚠️ ВАЖНО ОГРАНИЧУВАЊЕ: google_mlkit_image_labeling работи САМО на
/// Android и iOS (нативни модели преку platform channels). Пакетот НЕМА
/// имплементација за веб, па овој сервис НЕ работи со
/// `flutter run -d chrome` - при обид да се препознае нешто на веб ќе
/// фрли грешка (MissingPluginException однадвор фатена и претворена во
/// 'camera.error_unsupported_platform'). За тестирање на препознавањето
/// мора да се користи вистински телефон или Android/iOS емулатор
/// (`flutter run` без `-d chrome`, со поврзан уред/емулатор).
class MlKitRecognitionService implements ImageRecognitionService {
  final ImageLabeler _labeler;

  MlKitRecognitionService()
      : _labeler = ImageLabeler(
          options: ImageLabelerOptions(confidenceThreshold: 0.5),
        );

  @override
  Future<RecognitionResult> recognize({
    required XFile image,
    required String mode,
  }) async {
    if (mode == 'color') {
      // Бојата се пресметува локално - без модел, без мрежа.
      return _recognizeDominantColor(image);
    }
    return _recognizeViaMlKit(image: image, mode: mode);
  }

  // ---------------------------------------------------------------------
  // Предмети / облека - Google ML Kit Image Labeling (on-device).
  // ---------------------------------------------------------------------

  Future<RecognitionResult> _recognizeViaMlKit({
    required XFile image,
    required String mode,
  }) async {
    List<ImageLabel> labels;
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      labels = await _labeler.processImage(inputImage);
    } on RecognitionException {
      rethrow;
    } catch (e) {
      // Најчеста причина за грешка тука е обид за употреба на веб (пакетот
      // нема веб-имплементација) - платформски исклучок кој ML Kit не го
      // фаќа сам, па го препознаваме овде преку текстот на грешката.
      final message = e.toString().toLowerCase();
      if (message.contains('missingplugin') || message.contains('not implemented')) {
        throw const RecognitionException('camera.error_unsupported_platform');
      }
      throw const RecognitionException('camera.error');
    }

    // Сортирано опаѓачки по доверба - ML Kit не гарантира редослед сам.
    labels.sort((a, b) => b.confidence.compareTo(a.confidence));

    final dictionary = mode == 'clothing' ? _clothingTypeToKey : _objectToKey;

    // Прво се бара конкретен предмет (пр. „куче“, „топка“); општите ознаки
    // („човек“, „рака“, „храна“, „соба“...) се земаат само ако нема ништо
    // поконкретно - ML Kit честопати ги става нив најгоре.
    ({String key, double confidence})? specific;
    ({String key, double confidence})? generic;
    for (final label in labels) {
      final key = _matchLabel(label.label.toLowerCase(), dictionary);
      if (key == null) continue;
      if (_genericKeys.contains(key)) {
        generic ??= (key: key, confidence: label.confidence);
      } else {
        specific ??= (key: key, confidence: label.confidence);
      }
      if (specific != null) break;
    }

    // Конкретниот се зема ако е доволно сигурен; инаку општиот (ако тој е
    // сигурен); инаку - несигурно.
    final threshold = ImageRecognitionService.defaultConfidenceThreshold;
    final ({String key, double confidence})? pick =
        (specific != null && specific.confidence >= threshold)
            ? specific
            : ((generic != null && generic.confidence >= threshold) ? generic : null);

    if (pick == null) {
      // Ништо сигурно од нашиот речник (никогаш не читаме сурово англиско
      // име наместо ова).
      final best = specific?.confidence ?? generic?.confidence ?? (labels.isEmpty ? 0.0 : labels.first.confidence);
      return RecognitionResult(labelKey: 'camera.uncertain', confidence: best, mode: mode);
    }

    String? secondaryKey;
    if (mode == 'clothing') {
      // За облека, дополнително ја пресметуваме доминантната боја од
      // истата слика (иста локална логика како за режимот "бои") -
      // изговорена ОДДЕЛНО од типот на облеката, за да не мора да
      // склопуваме родово-зависна фраза (пр. "сина маица" наспроти
      // "сини панталони") што лесно се пишува погрешно граматички.
      final colorResult = await _recognizeDominantColor(image);
      secondaryKey = colorResult.labelKey;
    }
    return RecognitionResult(
      labelKey: pick.key,
      secondaryLabelKey: secondaryKey,
      confidence: pick.confidence,
      mode: mode,
    );
  }

  /// Бара точно совпаѓање, па совпаѓање на ЦЕЛ збор/фраза во описот (ML
  /// Kit понекогаш враќа подолги имиња, пр. „stuffed toy“). Само цели
  /// зборови - „cat“ НЕ смее да се најде во „cattle“, ниту „cap“ во
  /// „cappuccino“.
  String? _matchLabel(String description, Map<String, String> dictionary) {
    final exact = dictionary[description];
    if (exact != null) return exact;
    for (final entry in dictionary.entries) {
      final pattern = RegExp('(^|[^a-z])${RegExp.escape(entry.key)}([^a-z]|\$)');
      if (pattern.hasMatch(description)) return entry.value;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Бои - локална детекција на доминантна боја (без мрежа, без модел).
  // ---------------------------------------------------------------------

  Future<RecognitionResult> _recognizeDominantColor(XFile image) async {
    final bytes = await image.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const RecognitionException('camera.error');
    }

    // Земаме примерок од централниот квадрат на сликата (тука обично стои
    // предметот кон кој е насочена камерата), не од целата слика - работ
    // на кадарот честопати е позадина, не самиот предмет/боја.
    final cropSize = (min(decoded.width, decoded.height) * 0.5).round().clamp(1, min(decoded.width, decoded.height));
    final left = ((decoded.width - cropSize) / 2).round();
    final top = ((decoded.height - cropSize) / 2).round();

    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    const step = 4; // прескокнуваме пиксели за брзина - доволно е за просек.
    for (var y = top; y < top + cropSize; y += step) {
      for (var x = left; x < left + cropSize; x += step) {
        final pixel = decoded.getPixel(x, y);
        rSum += pixel.r.toInt();
        gSum += pixel.g.toInt();
        bSum += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) {
      throw const RecognitionException('camera.error');
    }

    final avg = (r: rSum / count, g: gSum / count, b: bSum / count);
    final key = _nearestNamedColorKey(avg.r, avg.g, avg.b);
    return RecognitionResult(labelKey: key, confidence: 1.0, mode: 'color');
  }

  /// Ја именува просечната боја преку нијанса / заситеност / осветленост
  /// (HSV) - посигурно од „најблиска RGB точка“, и со повеќе бои: црвена,
  /// портокалова, жолта, светлозелена, зелена, темнозелена, тиркизна,
  /// светлосина, сина, темносина, виолетова, розова, кафеава, беж, сива,
  /// црна, бела.
  String _nearestNamedColorKey(double r, double g, double b) {
    final rn = r / 255, gn = g / 255, bn = b / 255;
    final maxC = max(rn, max(gn, bn));
    final minC = min(rn, min(gn, bn));
    final delta = maxC - minC;
    final v = maxC;
    final s = maxC == 0 ? 0.0 : delta / maxC;
    double h = 0;
    if (delta > 0) {
      if (maxC == rn) {
        h = 60 * (((gn - bn) / delta) % 6);
      } else if (maxC == gn) {
        h = 60 * (((bn - rn) / delta) + 2);
      } else {
        h = 60 * (((rn - gn) / delta) + 4);
      }
    }
    if (h < 0) h += 360;

    if (v < 0.18) return 'camera.color_black';
    if (s < 0.16) {
      if (v > 0.82) return 'camera.color_white';
      if (v < 0.3) return 'camera.color_black';
      return 'camera.color_gray';
    }
    // Бледи топли тонови - беж.
    if (h >= 20 && h < 55 && s < 0.4 && v > 0.65) return 'camera.color_beige';

    if (h < 12 || h >= 345) {
      if (s < 0.5 && v > 0.7) return 'camera.color_pink';
      if (v < 0.45) return 'camera.color_brown';
      return 'camera.color_red';
    }
    if (h < 40) return v < 0.62 ? 'camera.color_brown' : 'camera.color_orange';
    if (h < 68) return v < 0.5 ? 'camera.color_brown' : 'camera.color_yellow';
    if (h < 90) return 'camera.color_light_green';
    if (h < 160) {
      if (v < 0.4) return 'camera.color_dark_green';
      if (v > 0.75 && s < 0.5) return 'camera.color_light_green';
      return 'camera.color_green';
    }
    if (h < 195) return 'camera.color_turquoise';
    if (h < 255) {
      if (v < 0.42) return 'camera.color_dark_blue';
      if (v > 0.75 && s < 0.5) return 'camera.color_light_blue';
      return 'camera.color_blue';
    }
    if (h < 295) return 'camera.color_purple';
    return 'camera.color_pink';
  }

  @override
  void dispose() => _labeler.close();
}

// ===========================================================================
// Речници: сурово (англиско) име од ML Kit -> клуч за превод во апп-ов.
// Имињата се од официјалната листа ознаки на ML Kit (основниот модел) плус
// неколку чести синоними. Секој нов клуч бара и нов ред во трите JSON-
// датотеки за превод (mk/en/sq), во делот "camera".
// ===========================================================================

/// Режим „Предмети“.
const Map<String, String> _objectToKey = {
  'apple': 'camera.object_apple',
  'banana': 'camera.object_banana',
  'orange': 'camera.object_orange_fruit',
  'grape': 'camera.object_grape',
  'lemon': 'camera.object_lemon',
  'bread': 'camera.object_bread',
  'cup': 'camera.object_cup',
  'mug': 'camera.object_cup',
  'glass': 'camera.object_glass',
  'bottle': 'camera.object_bottle',
  'book': 'camera.object_book',
  'chair': 'camera.object_chair',
  'table': 'camera.object_table',
  'ball': 'camera.object_ball',
  'phone': 'camera.object_phone',
  'mobile phone': 'camera.object_phone',
  'laptop': 'camera.object_laptop',
  'clock': 'camera.object_clock',
  'watch': 'camera.object_watch',
  'key': 'camera.object_key',
  'scissors': 'camera.object_scissors',
  'pen': 'camera.object_pen',
  'ball point pen': 'camera.object_pen',
  'pencil': 'camera.object_pencil',
  'backpack': 'camera.object_backpack',
  'bag': 'camera.object_bag',
  'flower': 'camera.object_flower',
  'petal': 'camera.object_flower',
  'plant': 'camera.object_plant',
  'flora': 'camera.object_plant',
  'tree': 'camera.object_tree',
  'dog': 'camera.object_dog',
  'cat': 'camera.object_cat',
  'bird': 'camera.object_bird',
  'toy': 'camera.object_toy',
  'plate': 'camera.object_plate',
  'saucer': 'camera.object_plate',
  'spoon': 'camera.object_spoon',
  'fork': 'camera.object_fork',
  'knife': 'camera.object_knife',
  'shoe': 'camera.object_shoe',
  'sneakers': 'camera.object_shoe',
  'umbrella': 'camera.object_umbrella',
  'stuffed toy': 'camera.object_teddy',
  'plush': 'camera.object_teddy',
  'teddy bear': 'camera.object_teddy',
  'horse': 'camera.object_horse',
  'duck': 'camera.object_duck',
  'waterfowl': 'camera.object_duck',
  'bear': 'camera.object_bear',
  'butterfly': 'camera.object_butterfly',
  'insect': 'camera.object_insect',
  'larva': 'camera.object_insect',
  'turtle': 'camera.object_turtle',
  'crocodile': 'camera.object_crocodile',
  'penguin': 'camera.object_penguin',
  'cattle': 'camera.object_cow',
  'cow': 'camera.object_cow',
  'bull': 'camera.object_bull',
  'seal': 'camera.object_seal',
  'dinosaur': 'camera.object_dinosaur',
  'fish': 'camera.object_fish',
  'pomacentridae': 'camera.object_fish',
  'gerbil': 'camera.object_mouse',
  'hamster': 'camera.object_mouse',
  'mouse': 'camera.object_mouse',
  'shetland sheepdog': 'camera.object_dog',
  'dalmatian': 'camera.object_dog',
  'cairn terrier': 'camera.object_dog',
  'basset hound': 'camera.object_dog',
  'shikoku': 'camera.object_dog',
  'cavalier': 'camera.object_dog',
  'puppy': 'camera.object_dog',
  'himalayan': 'camera.object_cat',
  'ragdoll': 'camera.object_cat',
  'sphynx': 'camera.object_cat',
  'pixie-bob': 'camera.object_cat',
  'kitten': 'camera.object_cat',
  'food': 'camera.object_food',
  'meal': 'camera.object_food',
  'lunch': 'camera.object_food',
  'supper': 'camera.object_food',
  'cuisine': 'camera.object_food',
  'fast food': 'camera.object_food',
  'fruit': 'camera.object_fruit',
  'vegetable': 'camera.object_vegetable',
  'cake': 'camera.object_cake',
  'icing': 'camera.object_cake',
  'cookie': 'camera.object_cookie',
  'pizza': 'camera.object_pizza',
  'hot dog': 'camera.object_hot_dog',
  'cheeseburger': 'camera.object_burger',
  'hamburger': 'camera.object_burger',
  'juice': 'camera.object_juice',
  'coffee': 'camera.object_coffee',
  'cappuccino': 'camera.object_coffee',
  'cola': 'camera.object_soda',
  'gelato': 'camera.object_ice_cream',
  'ice cream': 'camera.object_ice_cream',
  'pie': 'camera.object_pie',
  'sushi': 'camera.object_sushi',
  'couch': 'camera.object_sofa',
  'loveseat': 'camera.object_sofa',
  'sofa': 'camera.object_sofa',
  'bench': 'camera.object_bench',
  'desk': 'camera.object_desk',
  'shelf': 'camera.object_shelf',
  'drawer': 'camera.object_drawer',
  'cabinetry': 'camera.object_cupboard',
  'curtain': 'camera.object_curtain',
  'cushion': 'camera.object_pillow',
  'pillow': 'camera.object_pillow',
  'bunk bed': 'camera.object_bed',
  'bed': 'camera.object_bed',
  'lampshade': 'camera.object_lamp',
  'lamp': 'camera.object_lamp',
  'sink': 'camera.object_sink',
  'television': 'camera.object_tv',
  'computer': 'camera.object_computer',
  'tableware': 'camera.object_dishes',
  'cutlery': 'camera.object_cutlery',
  'cookware and bakeware': 'camera.object_pot',
  'flowerpot': 'camera.object_flowerpot',
  'tablecloth': 'camera.object_tablecloth',
  'placemat': 'camera.object_tablecloth',
  'whiteboard': 'camera.object_board',
  'blackboard': 'camera.object_board',
  'paper': 'camera.object_paper',
  'newspaper': 'camera.object_newspaper',
  'poster': 'camera.object_poster',
  'comics': 'camera.object_comic',
  'piano': 'camera.object_piano',
  'musical instrument': 'camera.object_instrument',
  'balloon': 'camera.object_balloon',
  'flag': 'camera.object_flag',
  'handbag': 'camera.object_handbag',
  'glasses': 'camera.object_glasses',
  'sunglasses': 'camera.object_sunglasses',
  'goggles': 'camera.object_glasses',
  'helmet': 'camera.object_helmet',
  'ring': 'camera.object_ring',
  'necklace': 'camera.object_necklace',
  'bracelet': 'camera.object_bracelet',
  'bangle': 'camera.object_bracelet',
  'money': 'camera.object_money',
  'lego': 'camera.object_lego',
  'skateboard': 'camera.object_skateboard',
  'longboard': 'camera.object_skateboard',
  'bicycle': 'camera.object_bicycle',
  'car': 'camera.object_car',
  'bus': 'camera.object_bus',
  'train': 'camera.object_train',
  'airplane': 'camera.object_airplane',
  'airliner': 'camera.object_airplane',
  'aircraft': 'camera.object_airplane',
  'helicopter': 'camera.object_helicopter',
  'boat': 'camera.object_boat',
  'sailboat': 'camera.object_boat',
  'speedboat': 'camera.object_boat',
  'canoe': 'camera.object_boat',
  'kayak': 'camera.object_boat',
  'motorcycle': 'camera.object_motorcycle',
  'tractor': 'camera.object_tractor',
  'van': 'camera.object_van',
  'rocket': 'camera.object_rocket',
  'wheel': 'camera.object_wheel',
  'tire': 'camera.object_tire',
  'swing': 'camera.object_swing',
  'playground': 'camera.object_playground',
  'pool': 'camera.object_pool',
  'branch': 'camera.object_branch',
  'twig': 'camera.object_branch',
  'rock': 'camera.object_rock',
  'sand': 'camera.object_sand',
  'star': 'camera.object_star',
  'moon': 'camera.object_moon',
  'sky': 'camera.object_sky',
  'rainbow': 'camera.object_rainbow',
  'fire': 'camera.object_fire',
  'bonfire': 'camera.object_fire',
  'ice': 'camera.object_ice',
  'icicle': 'camera.object_ice',
  'mountain': 'camera.object_mountain',
  'beach': 'camera.object_beach',
  'river': 'camera.object_river',
  'lake': 'camera.object_lake',
  'waterfall': 'camera.object_waterfall',
  'forest': 'camera.object_forest',
  'jungle': 'camera.object_forest',
  'garden': 'camera.object_garden',
  'park': 'camera.object_park',
  'road': 'camera.object_road',
  'bridge': 'camera.object_bridge',
  'building': 'camera.object_building',
  'skyscraper': 'camera.object_building',
  'castle': 'camera.object_castle',
  'palace': 'camera.object_castle',
  'church': 'camera.object_church',
  'cathedral': 'camera.object_church',
  'mosque': 'camera.object_mosque',
  'room': 'camera.object_room',
  'bedroom': 'camera.object_bedroom',
  'kitchen': 'camera.object_kitchen',
  'bathroom': 'camera.object_bathroom',
  'stairs': 'camera.object_stairs',
  'wall': 'camera.object_wall',
  'roof': 'camera.object_roof',
  'statue': 'camera.object_statue',
  'christmas': 'camera.object_christmas',
  'hand': 'camera.object_hand',
  'foot': 'camera.object_foot',
  'toe': 'camera.object_foot',
  'ear': 'camera.object_ear',
  'mouth': 'camera.object_mouth',
  'hair': 'camera.object_hair',
  'baby': 'camera.object_baby',
  'person': 'camera.object_person',
};

/// Општи предмети - се земаат само ако нема ништо поконкретно на сликата.
const Set<String> _genericKeys = {
  'camera.object_person',
  'camera.object_hand',
  'camera.object_foot',
  'camera.object_ear',
  'camera.object_mouth',
  'camera.object_hair',
  'camera.object_food',
  'camera.object_fruit',
  'camera.object_vegetable',
  'camera.object_plant',
  'camera.object_room',
  'camera.object_sky',
  'camera.object_wall',
  'camera.object_building',
  'camera.object_toy',
  'camera.object_bag',
  'camera.object_paper',
};

/// Режим „Облека“.
const Map<String, String> _clothingTypeToKey = {
  't-shirt': 'camera.clothing_type_shirt',
  'shirt': 'camera.clothing_type_shirt',
  'dress shirt': 'camera.clothing_type_shirt',
  'polo': 'camera.clothing_type_shirt',
  'top': 'camera.clothing_type_shirt',
  'trousers': 'camera.clothing_type_pants',
  'pants': 'camera.clothing_type_pants',
  'jeans': 'camera.clothing_type_jeans',
  'denim': 'camera.clothing_type_jeans',
  'shorts': 'camera.clothing_type_shorts',
  'skirt': 'camera.clothing_type_skirt',
  'dress': 'camera.clothing_type_dress',
  'gown': 'camera.clothing_type_dress',
  'jacket': 'camera.clothing_type_jacket',
  'outerwear': 'camera.clothing_type_jacket',
  'coat': 'camera.clothing_type_coat',
  'sweater': 'camera.clothing_type_sweater',
  'cardigan': 'camera.clothing_type_sweater',
  'hoodie': 'camera.clothing_type_hoodie',
  'hat': 'camera.clothing_type_hat',
  'cap': 'camera.clothing_type_hat',
  'beanie': 'camera.clothing_type_hat',
  'sock': 'camera.clothing_type_sock',
  'shoe': 'camera.clothing_type_shoe',
  'sneakers': 'camera.clothing_type_sneakers',
  'boot': 'camera.clothing_type_boot',
  'sandal': 'camera.clothing_type_sandal',
  'scarf': 'camera.clothing_type_scarf',
  'glove': 'camera.clothing_type_glove',
  'mitten': 'camera.clothing_type_glove',
  'blazer': 'camera.clothing_type_blazer',
  'tights': 'camera.clothing_type_tights',
  'leggings': 'camera.clothing_type_leggings',
  'tie': 'camera.clothing_type_tie',
  'jersey': 'camera.clothing_type_jersey',
  'swimwear': 'camera.clothing_type_swimsuit',
  'wetsuit': 'camera.clothing_type_swimsuit',
  'tuxedo': 'camera.clothing_type_suit',
  'suit': 'camera.clothing_type_suit',
  'vest': 'camera.clothing_type_vest',
  'pajamas': 'camera.clothing_type_pajamas',
  'glasses': 'camera.clothing_type_glasses',
  'goggles': 'camera.clothing_type_glasses',
  'sunglasses': 'camera.clothing_type_sunglasses',
  'helmet': 'camera.clothing_type_helmet',
  'handbag': 'camera.clothing_type_bag',
  'bag': 'camera.clothing_type_bag',
  'backpack': 'camera.clothing_type_bag',
  'necklace': 'camera.clothing_type_jewellery',
  'bracelet': 'camera.clothing_type_jewellery',
  'bangle': 'camera.clothing_type_jewellery',
  'ring': 'camera.clothing_type_jewellery',
  'jewellery': 'camera.clothing_type_jewellery',
  'belt': 'camera.clothing_type_belt',
  'uniform': 'camera.clothing_type_uniform',
  'strap': 'camera.clothing_type_belt',
};