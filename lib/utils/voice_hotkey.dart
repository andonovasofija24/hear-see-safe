import 'package:flutter/widgets.dart';

/// Копчето Г (физичкото G) на тастатура - гласовна команда низ целата
/// апликација. Глобалниот слушач во main.dart ја зголемува вредноста при
/// секој притисок; почетниот екран и копчињата за гласовна команда во
/// игрите слушаат и реагираат само ако нивниот екран е најгоре.
abstract final class VoiceHotkey {
  static final ValueNotifier<int> pressed = ValueNotifier<int>(0);
}