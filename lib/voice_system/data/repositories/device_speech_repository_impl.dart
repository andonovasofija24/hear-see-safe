import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../application/language_manager.dart';
import '../../domain/entities/transcription_result.dart';
import '../../domain/repositories/speech_to_text_repository.dart';

/// On-device STT via `speech_to_text` (Web Speech API / OS engine).
class DeviceSpeechRepositoryImpl implements SpeechToTextRepository {
  DeviceSpeechRepositoryImpl({
    required LanguageManager languageManager,
    SpeechToText? speech,
  })  : _languageManager = languageManager,
        _speech = speech ?? SpeechToText();

  final LanguageManager _languageManager;
  final SpeechToText _speech;
  bool _initialized = false;

  Future<bool> _ensureInit() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  @override
  Future<TranscriptionResult?> listenOnce({Duration? timeout}) async {
    if (!await _ensureInit()) return null;
    final t = timeout ?? const Duration(seconds: 8);
    for (final localeId in _languageManager.sttLocaleTryOrder()) {
      final text = await _listenSingleLocale(localeId, t);
      if (text != null && text.trim().isNotEmpty) {
        return TranscriptionResult(
          transcript: text.trim(),
          source: TranscriptionSource.device,
        );
      }
    }
    return null;
  }

  Future<String?> _listenSingleLocale(String localeId, Duration timeout) async {
    if (_speech.isListening) await _speech.stop();
    final completer = Completer<String?>();
    String? lastFinal;

    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          lastFinal = r.recognizedWords.trim();
          if (!completer.isCompleted) completer.complete(lastFinal);
        }
      },
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.confirmation,
      ),
    );

    Future<void>.delayed(timeout, () {
      if (!completer.isCompleted) {
        if (_speech.isListening) _speech.stop();
        completer.complete(lastFinal);
      }
    });

    return completer.future;
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