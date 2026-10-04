import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// „Звук што се гледа“: колку гласно некој зборува додека апликацијата слуша
/// (0..1), и дали апликацијата моментално зборува. Позадината и копчињата
/// за глас го цртаат ова како бранови / светкање.
///
/// На телефон нивото доаѓа директно од препознавањето говор (јачина на
/// звукот). Во прелистувач тоа не е достапно - таму секој препознаен збор
/// дава кратко „светкање“.
abstract final class VoiceLevel {
  /// Јачина на гласот додека се слуша (0 = тишина, 1 = гласно).
  static final ValueNotifier<double> level = ValueNotifier<double>(0);

  /// Дали апликацијата моментално слуша.
  static final ValueNotifier<bool> listening = ValueNotifier<bool>(false);

  /// Дали апликацијата моментално зборува (пушта снимка).
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  static Timer? _decay;
  static double? _minRaw;
  static double? _maxRaw;

  static void setListening(bool v) {
    listening.value = v;
    if (!v) {
      _decay?.cancel();
      level.value = 0;
    }
  }

  /// Сурова вредност од speech_to_text (различен опсег на Android / iOS) -
  /// се нормализира според досега видените минимум/максимум.
  static void soundLevel(double raw) {
    _minRaw = math.min(_minRaw ?? raw, raw);
    _maxRaw = math.max(_maxRaw ?? raw + 10, raw);
    final span = math.max(_maxRaw! - _minRaw!, 1.0);
    final v = ((raw - _minRaw!) / span).clamp(0.0, 1.0);
    // Мало измазнување за да не трепери.
    level.value = level.value * 0.4 + v * 0.6;
  }

  /// Препознаен е збор - кратко светкање што полека се гаси.
  static void pulse([double strength = 0.9]) {
    level.value = math.max(level.value, strength);
    _decay?.cancel();
    _decay = Timer.periodic(const Duration(milliseconds: 60), (t) {
      level.value *= 0.86;
      if (level.value < 0.03) {
        level.value = 0;
        t.cancel();
      }
    });
  }
}