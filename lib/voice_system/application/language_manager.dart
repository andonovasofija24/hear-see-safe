import 'package:flutter/foundation.dart';

import '../domain/entities/supported_voice_language.dart';
import '../domain/entities/transcription_result.dart';

/// Voice/STT language priority and UI language sync.
///
/// **Product rule:** Macedonian is always tried first for recognition unless the
/// user explicitly turns off [prioritizeMacedonianForStt] (advanced setting).
class LanguageManager extends ChangeNotifier {
  LanguageManager({
    this.prioritizeMacedonianForStt = true,
    String userUiLanguageCode = 'mk',
  }) : _userUiLanguageCode = userUiLanguageCode;

  /// When true, STT locale order always starts with Macedonian, then English, then Albanian.
  bool prioritizeMacedonianForStt;

  String _userUiLanguageCode;

  /// Last language detected by cloud STT or the LLM (hint for TTS feedback).
  SupportedVoiceLanguage? lastDetectedLanguage;

  String get userUiLanguageCode => _userUiLanguageCode;

  void setUserUiLanguageCode(String code) {
    if (_userUiLanguageCode == code) return;
    _userUiLanguageCode = code;
    notifyListeners();
  }

  void setPrioritizeMacedonianForStt(bool value) {
    if (prioritizeMacedonianForStt == value) return;
    prioritizeMacedonianForStt = value;
    notifyListeners();
  }

  void applyDetectionHint(TranscriptionResult? result) {
    if (result?.detectedLanguage != null) {
      lastDetectedLanguage = result!.detectedLanguage;
      notifyListeners();
    }
  }

  void applyIntentLanguage(SupportedVoiceLanguage? lang) {
    if (lang == null) return;
    lastDetectedLanguage = lang;
    notifyListeners();
  }

  /// `speech_to_text` locale IDs to try in order.
  ///
  /// ВАЖНО: само со тире (BCP-47, пр. 'mk-MK'), НЕ со долна црта ('mk_MK').
  /// Претходно листата ги содржеше двете форми за секој јазик - но
  /// платформата (Web Speech API / speech_to_text) не го препознава форматот
  /// со долна црта како важечки locale. Кога тоа е првиот обид во листата,
  /// препознавањето тивко паѓа назад на некој системски стандарден јазик
  /// (обично англиски), а тој обид сепак враќа НЕ-празен (но погрешен)
  /// препознаен текст - што ја прекинува целата постапка веднаш (бидејќи
  /// `listenOnce` запира штом добие кој било не-празен резултат), пред воопшто
  /// да стигне до вистинскиот 'mk-MK' обид. Ова беше причината зошто ПРВИОТ
  /// изговорен збор/категорија во речиси секоја игра не се препознаваше
  /// точно, додека следните обиди (веќе на точниот locale) работеа нормално.
  List<String> sttLocaleTryOrder() {
    const mk = ['mk-MK'];
    const en = ['en-US'];
    const sq = ['sq-AL'];

    if (prioritizeMacedonianForStt) {
      return [...mk, ...en, ...sq];
    }

    switch (_userUiLanguageCode.toLowerCase()) {
      case 'mk':
        return [...mk, ...en, ...sq];
      case 'sq':
        return [...sq, ...mk, ...en];
      case 'en':
      default:
        return [...en, ...mk, ...sq];
    }
  }

  SupportedVoiceLanguage feedbackLanguage() {
    return lastDetectedLanguage ??
        SupportedVoiceLanguage.fromUiLanguageCode(_userUiLanguageCode);
  }
}