import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../domain/entities/supported_voice_language.dart';
import '../../domain/entities/transcription_result.dart';
import '../../domain/repositories/speech_to_text_repository.dart';
import '../../voice_system_config.dart';
import '../google_cloud/google_speech_rest_client.dart';
import '../io/read_file_bytes.dart';

/// Google Cloud Speech-to-Text (sync REST). Short utterances; see [VoiceSystemConfig].
///
/// On **web**, recording bytes differ per browser — this implementation returns
/// `null` so [HybridSpeechRepositoryImpl] falls back to on-device STT.
class GoogleCloudSpeechRepositoryImpl implements SpeechToTextRepository {
  GoogleCloudSpeechRepositoryImpl({
    required VoiceSystemConfig config,
    GoogleSpeechRestClient? client,
    AudioRecorder? recorder,
  })  : _config = config,
        _client = client ?? GoogleSpeechRestClient(apiKey: config.googleApiKey),
        _recorder = recorder ?? AudioRecorder();

  final VoiceSystemConfig _config;
  final GoogleSpeechRestClient _client;
  final AudioRecorder _recorder;

  @override
  Future<TranscriptionResult?> listenOnce({Duration? timeout}) async {
    if (kIsWeb || !_config.hasGoogleKey) return null;

    final status = await Permission.microphone.request();
    if (!status.isGranted) return null;

    if (!await _recorder.hasPermission()) return null;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/hss_stt_${DateTime.now().millisecondsSinceEpoch}.flac';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.flac,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    final ms = (timeout ?? _config.commandListenTimeout)
        .inMilliseconds
        .clamp(2000, 8000);
    await Future<void>.delayed(Duration(milliseconds: ms));
    final stoppedPath = await _recorder.stop();
    final bytes = await readFileBytes(stoppedPath ?? path);
    if (bytes == null || bytes.isEmpty) return null;

    final primary = SupportedVoiceLanguage.macedonian.bcp47;
    final alts = [
      SupportedVoiceLanguage.english.bcp47,
      SupportedVoiceLanguage.albanian.bcp47,
    ];

    GoogleRecognizeResult? best = await _client.recognize(
      audioBytes: bytes,
      encoding: 'FLAC',
      sampleRateHertz: 16000,
      languageCode: primary,
      alternativeLanguageCodes: alts,
    );

    if (_shouldRetryEnglish(best)) {
      best = await _client.recognize(
        audioBytes: bytes,
        encoding: 'FLAC',
        sampleRateHertz: 16000,
        languageCode: SupportedVoiceLanguage.english.bcp47,
        alternativeLanguageCodes: const [],
      );
    }

    if (best == null || best.transcript.isEmpty) return null;

    return TranscriptionResult(
      transcript: best.transcript,
      confidence: best.confidence,
      detectedLanguage:
          SupportedVoiceLanguage.tryParseBcp47(best.detectedBcp47),
      source: TranscriptionSource.googleCloud,
    );
  }

  @override
  Stream<TranscriptionResult> listenStreaming({Duration? maxDuration}) async* {
    final r = await listenOnce(timeout: maxDuration);
    if (r != null && !r.isEmpty) yield r;
  }

  bool _shouldRetryEnglish(GoogleRecognizeResult? r) {
    if (r == null) return true;
    if (r.transcript.isEmpty) return true;
    final c = r.confidence;
    if (c == null) return false;
    return c < _config.sttMinConfidenceFallback;
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  void dispose() => _client.close();
}