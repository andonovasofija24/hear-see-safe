import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Една ознака од Google Cloud Vision: англиското име (мали букви) и
/// довербата (0-1, како кај ML Kit).
typedef CloudLabel = ({String label, double confidence});

/// Дополнително, ОНЛАЈН препознавање преку Google Cloud Vision
/// (LABEL_DETECTION + OBJECT_LOCALIZATION).
///
/// ML Kit останува главниот, офлајн модел; ова само додава поими што ML Kit
/// ги нема (куќа, прозорец, море, четка за заби...). Клучот се задава при
/// компајлирање:
///
/// ```
/// flutter build apk --release --dart-define=GOOGLE_VISION_API_KEY=...
/// ```
///
/// (резерва: `GOOGLE_API_KEY`). Без клуч - исклучено, апликацијата работи
/// исто како порано. Секоја грешка (нема интернет, тајмаут, одбиен клуч,
/// квота...) тивко враќа празна листа - НИКОГАШ не се покажува грешка.
/// Види docs/cloud_vision_setup.md.
class CloudVisionService {
  CloudVisionService({String? apiKey}) : _apiKey = apiKey ?? configuredApiKey;

  static const String _visionKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const String _googleKey = String.fromEnvironment('GOOGLE_API_KEY');

  /// Клучот од `--dart-define` (празно = исклучено).
  static const String configuredApiKey = _visionKey != '' ? _visionKey : _googleKey;

  /// SHA-1 на клучот со кој е потпишана апликацијата - потребен кога API
  /// клучот е ограничен на Android апликации (заглавие `X-Android-Cert`).
  static const String _androidCertRaw = String.fromEnvironment('GOOGLE_VISION_ANDROID_CERT');

  /// Име на пакетот (заглавие `X-Android-Package`).
  static const String androidPackage = 'com.example.hear_and_see_safe';

  static const Duration _timeout = Duration(seconds: 5);
  static const int _maxSide = 640;
  static const int _jpegQuality = 80;

  final String _apiKey;
  http.Client? _client;
  bool _disposed = false;

  /// Дали онлајн препознавањето е вклучено (има клуч, не е веб).
  /// На веб никогаш - клучот не смее да заврши во прелистувач.
  bool get isEnabled => !kIsWeb && !_disposed && _apiKey.isNotEmpty;

  /// Ознаки за сликата. Никогаш не фрла: при каква било грешка или по
  /// [_timeout] (вкупно, со подготовката на сликата) враќа празна листа.
  Future<List<CloudLabel>> labels(Future<Uint8List> Function() readBytes) async {
    if (!isEnabled) return const [];
    try {
      return await _labels(readBytes).timeout(_timeout, onTimeout: () => const <CloudLabel>[]);
    } catch (_) {
      return const [];
    }
  }

  Future<List<CloudLabel>> _labels(Future<Uint8List> Function() readBytes) async {
    final bytes = await readBytes();
    if (!isEnabled) return const [];
    // Намалување (најмногу 640 px) + JPEG ~80 во посебен isolate.
    final jpeg = await compute(_prepareJpeg, bytes);
    if (jpeg == null || !isEnabled) return const [];

    final body = jsonEncode({
      'requests': [
        {
          'image': {'content': base64Encode(jpeg)},
          'features': [
            {'type': 'LABEL_DETECTION', 'maxResults': 25},
            {'type': 'OBJECT_LOCALIZATION', 'maxResults': 10},
          ],
        },
      ],
    });
    final headers = <String, String>{'Content-Type': 'application/json; charset=utf-8'};
    final cert = _androidCertRaw.replaceAll(':', '').replaceAll(' ', '').toUpperCase();
    if (defaultTargetPlatform == TargetPlatform.android && cert.isNotEmpty) {
      headers['X-Android-Package'] = androidPackage;
      headers['X-Android-Cert'] = cert;
    }
    final uri = Uri.https('vision.googleapis.com', '/v1/images:annotate', {'key': _apiKey});
    final client = _client ??= http.Client();
    final response = await client.post(uri, headers: headers, body: body);
    if (response.statusCode != 200 || !isEnabled) return const [];
    return _parse(response.body);
  }

  /// labelAnnotations[].description/score + localizedObjectAnnotations[].name/score.
  static List<CloudLabel> _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final responses = decoded['responses'];
    if (responses is! List || responses.isEmpty) return const [];
    final first = responses.first;
    if (first is! Map) return const [];
    final out = <CloudLabel>[];
    void add(Object? list, String field) {
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final name = item[field];
        final score = item['score'];
        if (name is! String || score is! num) continue;
        final label = name.trim().toLowerCase();
        if (label.isEmpty) continue;
        final s = score.toDouble();
        out.add((label: label, confidence: s < 0 ? 0.0 : (s > 1 ? 1.0 : s)));
      }
    }

    add(first['labelAnnotations'], 'description');
    add(first['localizedObjectAnnotations'], 'name');
    return out;
  }

  void dispose() {
    _disposed = true;
    _client?.close();
    _client = null;
  }
}

/// Декодира, ја исправа ориентацијата (EXIF), намалува на најмногу
/// [CloudVisionService._maxSide] px по подолгата страна и враќа JPEG.
/// Top-level функција - се извршува преку [compute].
Uint8List? _prepareJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longSide = max(image.width, image.height);
  if (longSide > CloudVisionService._maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: CloudVisionService._maxSide, interpolation: img.Interpolation.linear)
        : img.copyResize(image, height: CloudVisionService._maxSide, interpolation: img.Interpolation.linear);
  }
  return img.encodeJpg(image, quality: CloudVisionService._jpegQuality);
}