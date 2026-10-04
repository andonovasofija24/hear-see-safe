import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../application/language_manager.dart';
import '../../domain/entities/transcription_result.dart';
import '../../domain/repositories/speech_to_text_repository.dart';

/// On-device STT via `speech_to_text` (Web Speech API / OS engine).
///
/// Поправки за веб (Chrome):
///  - пред ПРВОТО слушање се бара дозвола за микрофон и се чека одговорот -
///    порано прозорецот за дозвола се појавуваше ДОДЕКА веќе течеше времето
///    за слушање, па првиот обид секогаш пропаѓаше;
///  - на веб „конечниот“ резултат стигнува дури неколку секунди по крајот на
///    говорот; затоа се враќа и последниот делумен резултат штом слушањето
///    заврши или истече времето (порано тоа што е кажано се губеше);
///  - грешка при стартување (пр. претходното слушање уште не е затворено)
///    повеќе не го „крши“ тивко целиот тек - се прекинува и се пробува уште еднаш.
class DeviceSpeechRepositoryImpl implements SpeechToTextRepository {
  DeviceSpeechRepositoryImpl({
    required LanguageManager languageManager,
    SpeechToText? speech,
  })  : _languageManager = languageManager,
        _speech = speech ?? SpeechToText();

  final LanguageManager _languageManager;
  final SpeechToText _speech;
  bool _initialized = false;
  bool _permissionAsked = false;
  bool _permissionDenied = false;

  /// Тековно слушање - за statusListener/errorListener од initialize.
  Completer<String?>? _active;
  String? _activePartial;

  Future<bool> _ensureInit() async {
    if (!_permissionAsked) {
      _permissionAsked = true;
      if (kIsWeb) {
        try {
          final status = await Permission.microphone.request();
          _permissionDenied = status.isDenied || status.isPermanentlyDenied;
        } catch (_) {
          // Ако проверката не е поддржана - продолжи; прелистувачот сам ќе прашa.
        }
      }
    }
    if (_permissionDenied) return false;
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    return _initialized;
  }

  void _onStatus(String status) {
    // Слушањето заврши (пауза / крај) - врати го она што е чуено, иако
    // „конечниот“ резултат на веб сеуште не стигнал.
    if ((status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) &&
        _activePartial != null &&
        _active != null &&
        !_active!.isCompleted) {
      _active!.complete(_activePartial);
    }
  }

  void _onError(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    if (msg.contains('not-allowed') || msg.contains('service-not-allowed') || msg.contains('permission')) {
      _permissionDenied = true;
    }
    if (_active != null && !_active!.isCompleted && (error.permanent || _permissionDenied)) {
      _active!.complete(_activePartial);
    }
  }

  @override
  Future<TranscriptionResult?> listenOnce({Duration? timeout}) async {
    if (!await _ensureInit()) return null;
    final t = timeout ?? const Duration(seconds: 8);
    for (final localeId in _languageManager.sttLocaleTryOrder()) {
      final text = await _listenSingleLocale(localeId, t);
      if (_permissionDenied) return null;
      if (text != null && text.trim().isNotEmpty) {
        return TranscriptionResult(
          transcript: text.trim(),
          source: TranscriptionSource.device,
        );
      }
    }
    return null;
  }

  Future<void> _safeStart(String localeId, Duration timeout, void Function(SpeechRecognitionResult) onResult) async {
    Future<void> start() => _speech.listen(
          onResult: onResult,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 3),
          localeId: localeId,
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.confirmation,
          ),
        );
    try {
      await start();
    } catch (_) {
      // Најчесто: претходното слушање сеуште не е затворено. Откажи и пробај пак.
      try {
        await _speech.cancel();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        await start();
      } catch (_) {
        if (_active != null && !_active!.isCompleted) _active!.complete(null);
      }
    }
  }

  Future<String?> _listenSingleLocale(String localeId, Duration timeout) async {
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
    final completer = Completer<String?>();
    _active = completer;
    _activePartial = null;
    String? lastFinal;

    await _safeStart(localeId, timeout, (SpeechRecognitionResult r) {
      final words = r.recognizedWords.trim();
      if (words.isEmpty) return;
      _activePartial = words;
      if (r.finalResult) {
        lastFinal = words;
        if (!completer.isCompleted) completer.complete(lastFinal);
      }
    });

    // Мала резерва над `listenFor`, за да стигне и крајот на сесијата.
    Future<void>.delayed(timeout + const Duration(milliseconds: 800), () {
      if (!completer.isCompleted) {
        if (_speech.isListening) _speech.stop();
        completer.complete(lastFinal ?? _activePartial);
      }
    });

    final result = await completer.future;
    if (identical(_active, completer)) _active = null;
    return result;
  }

  @override
  Stream<TranscriptionResult> listenStreaming({Duration? maxDuration}) async* {
    if (!await _ensureInit()) return;
    if (_speech.isListening) await _speech.stop();

    final localeId = _languageManager.sttLocaleTryOrder().first;
    final listenFor = maxDuration ?? const Duration(seconds: 30);

    final controller = StreamController<TranscriptionResult>();

    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (r.recognizedWords.trim().isEmpty) return;
        controller.add(
          TranscriptionResult(
            transcript: r.recognizedWords.trim(),
            isFinal: r.finalResult,
            confidence: r.hasConfidenceRating ? r.confidence : null,
            source: TranscriptionSource.device,
          ),
        );
      },
      listenFor: listenFor,
      pauseFor: const Duration(seconds: 2),
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );

    Future<void>.delayed(listenFor, () async {
      if (_speech.isListening) await _speech.stop();
      await controller.close();
    });

    yield* controller.stream;
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }
}