import '../../domain/entities/supported_voice_language.dart';
import '../../domain/entities/voice_intent.dart';
import '../../domain/repositories/voice_intent_repository.dart';
import '../../voice_system_config.dart';
import '../openai/open_ai_intent_client.dart';

/// LLM layer: multilingual utterances → unified JSON intent (OpenAI Chat Completions).
class OpenAiVoiceIntentRepository implements VoiceIntentRepository {
  OpenAiVoiceIntentRepository({
    required VoiceSystemConfig config,
    OpenAiIntentClient? client,
  })  : _config = config,
        _client = client ??
            OpenAiIntentClient(
              apiKey: config.openAiApiKey,
              model: config.openAiModel,
            );

  final VoiceSystemConfig _config;
  final OpenAiIntentClient _client;

  static const _systemPrompt = '''
You are a voice command normalizer for a children's accessibility app (blind/low-vision users).
The user may speak Macedonian (preferred), English, or Albanian.

Detect the source language and return ONE JSON object with this shape:
{
  "action": "<action_id>",
  "params": { "<key>": "<value>" },
  "detected_language": "mk-MK" | "en-US" | "sq-AL",
  "confidence": 0.0-1.0,
  "requires_confirmation": true/false
}

Rules:
- Always prefer interpreting ambiguous phrases as Macedonian if plausible.
- Map semantically equivalent phrases in any language to the same action_id.
- Use requires_confirmation: true for destructive/system actions (Wi‑Fi, data, purchases, logout, delete).

Valid action_id values:
- open_settings
- change_language  (open the language selection screen, e.g. "промени јазик", "change language", "ndrysho gjuhën")
- set_language  (params: lang = mk | en | sq; when a specific language is named, e.g. "англиски", "switch to Albanian")
- navigate_braille
- navigate_picture_book
- navigate_number_games
- navigate_camera_recognition
- navigate_spatial_orientation
- navigate_sound_identification
- navigate_cyber_safety
- navigate_sound_memory
- navigate_voice_pong
- navigate_melody_memory
- navigate_rhythm_tap
- navigate_story_choices
- system_wifi  (params: state = enable | disable)
- unknown  (if no match)

Examples:
User (MK): "Отвори подесувања и исклучи WiFi"
→ {"action":"system_wifi","params":{"state":"disable"},"detected_language":"mk-MK","confidence":0.95,"requires_confirmation":true}

User (EN): "Open settings and turn off WiFi"
→ {"action":"system_wifi","params":{"state":"disable"},"detected_language":"en-US","confidence":0.95,"requires_confirmation":true}

User (SQ): "Hap cilësimet dhe fik WiFi"
→ {"action":"system_wifi","params":{"state":"disable"},"detected_language":"sq-AL","confidence":0.95,"requires_confirmation":true}

Also merge legacy flat keys into params if the user uses shorthand, e.g.
{"action":"open_settings","wifi":"disable"} should become
{"action":"system_wifi","params":{"state":"disable"},...}
''';

  @override
  Future<VoiceIntent> resolveIntent({
    required String transcript,
    SupportedVoiceLanguage? uiLanguageHint,
  }) async {
    if (!_config.hasOpenAiKey) {
      return VoiceIntent(
        action: 'unknown',
        params: {'transcript': transcript},
      );
    }

    final user = StringBuffer()
      ..writeln('Transcript: $transcript')
      ..writeln(
        'UI language hint (BCP-47 base): ${uiLanguageHint?.bcp47 ?? 'none'}',
      );

    final raw = await _client.completeJson(
      systemPrompt: _systemPrompt,
      userContent: user.toString(),
    );

    if (raw == null || raw.isEmpty) {
      return VoiceIntent(action: 'unknown', params: {'transcript': transcript});
    }

    final parsed = VoiceIntent.tryParse(raw);
    if (parsed != null) {
      return VoiceIntent(
        action: parsed.action,
        params: parsed.params,
        detectedLanguage: parsed.detectedLanguage,
        confidence: parsed.confidence,
        requiresConfirmation: parsed.requiresConfirmation,
        rawModelJson: raw,
      );
    }

    return VoiceIntent(
      action: 'unknown',
      params: {'transcript': transcript, 'raw': raw},
    );
  }

  void dispose() => _client.close();
}