import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Говор за екранот „Препознавање преку камера“ - ИСКЛУЧИВО однапред
/// снимени mp3 клипови (без системски TTS).
///
/// Датотеките се во `assets/audio/camera/<јазик>/<клуч>.mp3`
/// (јазик = mk / en / sq). Ако некој клип недостасува, тој дел едноставно
/// се прескокнува (тишина) - НЕМА резерва преку синтетички глас.
///
/// Секвенци: шаблоните се составуваат од повеќе клипови по ред, пр.
/// `['tpl_found', 'obj_dog']` = „Пронајдов:“ + „Куче“. Секоја нова секвенца
/// (или [stop] / [dispose]) ја прекинува претходната преку бројач (token).
/// Целосна листа на клипови: docs/camera_snimki.md.
class CameraClipPlayer {
  CameraClipPlayer({bool Function()? isEnabled}) : _isEnabled = isEnabled;

  final AudioPlayer _player = AudioPlayer();
  final bool Function()? _isEnabled;
  int _token = 0;
  bool _disposed = false;

  /// Сите средства (assets) во апликацијата - за брзо да знаеме дали клипот
  /// постои, без да чекаме тајмаут кога датотеката ја нема.
  static Set<String>? _assets;
  static bool _manifestFailed = false;

  /// Пауза меѓу два клипа во секвенца.
  static const Duration _gap = Duration(milliseconds: 140);

  /// Посебен „клуч“ во секвенца што значи подолга пауза (не е датотека).
  static const String pause = '_pause';
  static const Duration _pauseDuration = Duration(milliseconds: 350);

  // -------------------------------------------------------------------------
  // Клучеви на клиповите
  // -------------------------------------------------------------------------

  /// Шаблон пред предмет / облека: „Пронајдов:“.
  static const String tplFound = 'tpl_found';

  /// Шаблон пред боја: „Бојата е“.
  static const String tplColorIs = 'tpl_color_is';

  /// Име на клипот за режимот (се пушта при промена на режим).
  static String modeKey(String mode) => 'mode_$mode';

  /// Клуч за превод (пр. 'camera.object_dog') -> клуч на клип (пр.
  /// 'obj_dog'). Стабилни ASCII snake_case имиња, изведени од клучевите
  /// во речникот на [ImageRecognitionService]:
  ///  * camera.object_X        -> obj_X
  ///  * camera.color_X         -> color_X
  ///  * camera.clothing_type_X -> cloth_X
  ///  * camera.<друго>         -> msg_<друго> (ready, analyzing, uncertain,
  ///    error, error_timeout ...)
  static String clipKeyFor(String translationKey) {
    var k = translationKey;
    if (k.startsWith('camera.')) k = k.substring('camera.'.length);
    if (k.startsWith('object_')) return 'obj_${k.substring('object_'.length)}';
    if (k.startsWith('clothing_type_')) {
      return 'cloth_${k.substring('clothing_type_'.length)}';
    }
    if (k.startsWith('color_')) return k;
    return 'msg_$k';
  }

  // -------------------------------------------------------------------------
  // Репродукција
  // -------------------------------------------------------------------------

  /// Го прекинува тековниот говор (ако има).
  Future<void> stop() async {
    _token++;
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Пушта еден клип (ја прекинува претходната секвенца).
  Future<void> play(String lang, String key) => playSequence(lang, [key]);

  /// Пушта клипови по ред. Се враќа кога ќе заврши последниот, или веднаш
  /// штом почне нова секвенца / се повика [stop] / [dispose].
  Future<void> playSequence(String lang, List<String> keys) async {
    if (_disposed) return;
    final token = ++_token;
    try {
      await _player.stop();
    } catch (_) {}
    final isEnabled = _isEnabled;
    if (isEnabled != null && !isEnabled()) return;

    var first = true;
    for (final key in keys) {
      if (_disposed || token != _token) return;
      if (key == pause) {
        await Future.delayed(_pauseDuration);
        continue;
      }
      final path = 'audio/camera/$lang/$key.mp3';
      if (!await _exists(path)) continue; // нема снимка -> тишина
      if (_disposed || token != _token) return;
      if (!first) {
        await Future.delayed(_gap);
        if (_disposed || token != _token) return;
      }
      first = false;
      await _playOne(path, token);
    }
  }

  /// Ги ослободува ресурсите; по ова плеерот не пушта ништо.
  Future<void> dispose() async {
    _disposed = true;
    _token++;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
  }

  Future<bool> _exists(String relPath) async {
    if (_manifestFailed) return true; // не знаеме - пробај (тајмаут подолу)
    try {
      _assets ??= (await AssetManifest.loadFromAssetBundle(rootBundle))
          .listAssets()
          .toSet();
    } catch (_) {
      _manifestFailed = true;
      return true;
    }
    return _assets!.contains('assets/$relPath');
  }

  /// Пушта еден клип и чека да заврши. На некои платформи (веб) грешка при
  /// пуштање не фрла исклучок, па чекаме потврда дека навистина почнал; ако
  /// не почне за 4 секунди - продолжуваме (тишина).
  Future<void> _playOne(String relPath, int token) async {
    bool reached = false;
    final started = Completer<void>();
    final finished = Completer<void>();
    late final StreamSubscription<PlayerState> sub;
    sub = _player.onPlayerStateChanged.listen((st) {
      if (st == PlayerState.playing) {
        reached = true;
        if (!started.isCompleted) started.complete();
      }
      if (st == PlayerState.completed ||
          (st == PlayerState.stopped && reached) ||
          st == PlayerState.disposed) {
        if (!started.isCompleted) started.complete();
        if (!finished.isCompleted) finished.complete();
      }
    });

    try {
      bool ok = false;
      try {
        await _player.play(AssetSource(relPath));
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!ok || _disposed || token != _token) return;
      await started.future
          .timeout(const Duration(seconds: 4), onTimeout: () {});
      if (reached && !_disposed && token == _token) {
        await finished.future
            .timeout(const Duration(seconds: 15), onTimeout: () {});
      }
    } finally {
      await sub.cancel();
    }
  }
}