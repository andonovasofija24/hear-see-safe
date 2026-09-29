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
    for (final label in labels) {
      final key = _matchLabel(label.label.toLowerCase(), dictionary);
      if (key != null) {
        if (label.confidence < ImageRecognitionService.defaultConfidenceThreshold) {
          return RecognitionResult(labelKey: 'camera.uncertain', confidence: label.confidence, mode: mode);
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
          labelKey: key,
          secondaryLabelKey: secondaryKey,
          confidence: label.confidence,
          mode: mode,
        );
      }
    }

    // Ништо од листата не се совпаѓа со нашиот речник - несигурно, не
    // погодено (никогаш не читаме сурово англиско име наместо ова).
    final bestScore = labels.isEmpty ? 0.0 : labels.first.confidence;
    return RecognitionResult(labelKey: 'camera.uncertain', confidence: bestScore, mode: mode);
  }

  /// Бара точно совпаѓање или совпаѓање-подниза во речникот (ML Kit
  /// понекогаш враќа поопшти зборови како "fruit" наместо "apple" - овде
  /// пробуваме прво точно совпаѓање, па потоа дали клучен збор од речникот
  /// се содржи во описот).
  String? _matchLabel(String description, Map<String, String> dictionary) {
    if (dictionary.containsKey(description)) return dictionary[description];
    for (final entry in dictionary.entries) {
      if (description.contains(entry.key)) return entry.value;
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

  /// Совпаѓа просечна RGB боја со најблиската од шесте веќе преведени бои
  /// во апликацијата (camera.color_*), преку Евклидово растојание во
  /// RGB-просторот. Намерно ограничено на веќе постоечките преводи - не се
  /// потребни нови клучеви за овој режим.
  String _nearestNamedColorKey(double r, double g, double b) {
    const palette = <String, (double, double, double)>{
      'camera.color_red': (220, 38, 38),
      'camera.color_blue': (37, 99, 235),
      'camera.color_green': (22, 163, 74),
      'camera.color_yellow': (234, 179, 8),
      'camera.color_black': (20, 20, 20),
      'camera.color_white': (245, 245, 245),
    };
    String bestKey = palette.keys.first;
    double bestDist = double.infinity;
    palette.forEach((key, rgb) {
      final dr = r - rgb.$1;
      final dg = g - rgb.$2;
      final db = b - rgb.$3;
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        bestKey = key;
      }
    });
    return bestKey;
  }

  @override
  void dispose() => _labeler.close();
}

// ===========================================================================
// Речници: сурово (англиско) име од ML Kit -> клуч за превод во апп-ов.
// Ова НЕ е конечна/исцрпна листа - секој нов запис бара и нов ред во трите
// JSON-датотеки за превод (mk/en/sq).
// ===========================================================================

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
  'pencil': 'camera.object_pencil',
  'backpack': 'camera.object_backpack',
  'bag': 'camera.object_bag',
  'flower': 'camera.object_flower',
  'plant': 'camera.object_plant',
  'tree': 'camera.object_tree',
  'dog': 'camera.object_dog',
  'cat': 'camera.object_cat',
  'bird': 'camera.object_bird',
  'toy': 'camera.object_toy',
  'ball point pen': 'camera.object_pen',
  'plate': 'camera.object_plate',
  'spoon': 'camera.object_spoon',
  'fork': 'camera.object_fork',
  'knife': 'camera.object_knife',
  'shoe': 'camera.object_shoe',
  'umbrella': 'camera.object_umbrella',
};

const Map<String, String> _clothingTypeToKey = {
  't-shirt': 'camera.clothing_type_shirt',
  'shirt': 'camera.clothing_type_shirt',
  'dress shirt': 'camera.clothing_type_shirt',
  'trousers': 'camera.clothing_type_pants',
  'pants': 'camera.clothing_type_pants',
  'jeans': 'camera.clothing_type_jeans',
  'shorts': 'camera.clothing_type_shorts',
  'skirt': 'camera.clothing_type_skirt',
  'dress': 'camera.clothing_type_dress',
  'jacket': 'camera.clothing_type_jacket',
  'coat': 'camera.clothing_type_coat',
  'sweater': 'camera.clothing_type_sweater',
  'hoodie': 'camera.clothing_type_hoodie',
  'hat': 'camera.clothing_type_hat',
  'cap': 'camera.clothing_type_hat',
  'sock': 'camera.clothing_type_sock',
  'shoe': 'camera.clothing_type_shoe',
  'sneakers': 'camera.clothing_type_shoe',
  'scarf': 'camera.clothing_type_scarf',
  'glove': 'camera.clothing_type_glove',
};