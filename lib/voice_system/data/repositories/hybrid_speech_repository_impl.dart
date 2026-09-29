import '../../domain/entities/transcription_result.dart';
import '../../domain/repositories/speech_to_text_repository.dart';

/// Tries cloud STT first (when configured), then on-device recognition.
class HybridSpeechRepositoryImpl implements SpeechToTextRepository {
  HybridSpeechRepositoryImpl({
    required SpeechToTextRepository cloud,
    required SpeechToTextRepository device,
  })  : _cloud = cloud,
        _device = device;

  final SpeechToTextRepository _cloud;
  final SpeechToTextRepository _device;

  @override
  Future<TranscriptionResult?> listenOnce({Duration? timeout}) async {
    final cloud = await _cloud.listenOnce(timeout: timeout);
    if (cloud != null && !cloud.isEmpty) return cloud;
    return _device.listenOnce(timeout: timeout);
  }

  @override
  Stream<TranscriptionResult> listenStreaming({Duration? maxDuration}) {
    return _device.listenStreaming(maxDuration: maxDuration);
  }

  @override
  Future<void> stop() async {
    await _cloud.stop();
    await _device.stop();
  }
}