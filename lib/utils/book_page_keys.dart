import 'package:flutter/services.dart';

/// Листање на сликовниците со тастатура: `<` / `>` (копчињата за запирка и
/// точка), посебното `<>` копче на европските тастатури (без Shift = назад,
/// со Shift = напред) и стрелките лево / десно.
///
/// Враќа -1 (претходна страница), 1 (следна) или 0 (не е копче за листање).
int bookPageDirection(KeyEvent event) {
  if (event is! KeyDownEvent) return 0;
  final key = event.physicalKey;
  if (key == PhysicalKeyboardKey.comma || key == PhysicalKeyboardKey.arrowLeft) return -1;
  if (key == PhysicalKeyboardKey.period || key == PhysicalKeyboardKey.arrowRight) return 1;
  if (key == PhysicalKeyboardKey.intlBackslash) {
    return HardwareKeyboard.instance.isShiftPressed ? 1 : -1;
  }
  return 0;
}