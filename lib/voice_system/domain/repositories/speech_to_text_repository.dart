import '../entities/transcription_result.dart';

/// Abstraction over device STT, Google Cloud (sync / future streaming), or hybrid.
abstract class SpeechToTextRepository {
  /// One-shot listen (used when cloud key missing or as fallback).
  Future<TranscriptionResult?> listenOnce({
    Duration? timeout,
  });

  /// Optional: real-time partial transcripts. Default impl may delegate to [listenOnce].
  Stream<TranscriptionResult> listenStreaming({
    Duration? maxDuration,
  }) async* {
    final r = await listenOnce(timeout: maxDuration);
    if (r != null && !r.isEmpty) yield r;
  }

  Future<void> stop();
}