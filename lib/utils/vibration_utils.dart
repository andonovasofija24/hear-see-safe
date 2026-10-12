import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vibration/vibration.dart';
import 'package:hear_and_see_safe/utils/platform_utils.dart';

/// Platform-aware vibration utility. On web this is always a safe no-op
/// (browsers don't support the vibration package the same way); on mobile
/// it calls the real `vibration` plugin, with support for custom patterns
/// (e.g. [0, 80, 80, 80] = wait 0ms, buzz 80ms, pause 80ms, buzz 80ms).
class VibrationUtils {
  static Future<bool> hasVibrator() async {
    if (PlatformUtils.isWeb || kIsWeb) return false;
    try {
      final result = await Vibration.hasVibrator();
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Пробува прво со прилагодена шема (pattern) ако е дадена, инаку со
  /// едноставно траење (duration). Тивко не прави ништо ако вибрацијата
  /// не е достапна.
  /// [count] одделни удари (секој [onMs], пауза [offMs]) - секој удар е
  /// посебен повик, па бројот е ист на СЕКОЈ телефон (некои уреди не
  /// поддржуваат шеми и би вибрирале само еднаш). Чека да завршат сите.
  static Future<void> pulses(int count, {int onMs = 200, int offMs = 320}) async {
    if (PlatformUtils.isWeb || kIsWeb) return;
    for (var i = 0; i < count; i++) {
      await vibrate(duration: onMs);
      await Future.delayed(Duration(milliseconds: onMs + (i < count - 1 ? offMs : 0)));
    }
  }

  ///
  /// [amplitude] 1-255 (јачина) - на уредите што го поддржуваат; другите
  /// го игнорираат и вибрираат со стандардната јачина.
  static Future<void> vibrate({int? duration, List<int>? pattern, int? amplitude}) async {
    if (PlatformUtils.isWeb || kIsWeb) return;
    try {
      if (pattern != null && pattern.isNotEmpty) {
        final hasCustom = await Vibration.hasCustomVibrationsSupport();
        if (hasCustom == true) {
          await Vibration.vibrate(pattern: pattern);
          return;
        }
        // Уредот не поддржува прилагодени шеми - користи го првото
        // "траење" од шемата (обично најдолгото/најзначајното).
        final fallbackDuration = pattern.length > 1 ? pattern[1] : (duration ?? 100);
        await Vibration.vibrate(duration: fallbackDuration);
        return;
      }
      if (amplitude != null) {
        final canAmp = await Vibration.hasAmplitudeControl();
        if (canAmp == true) {
          await Vibration.vibrate(duration: duration ?? 100, amplitude: amplitude.clamp(1, 255).toInt());
          return;
        }
      }
      await Vibration.vibrate(duration: duration ?? 100);
    } catch (_) {
      // Тивко игнорирај - вибрацијата не е достапна на овој уред.
    }
  }
}