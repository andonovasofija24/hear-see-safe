import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Дали се користи тастатура или само допир.
///
/// На компјутер (Windows, Linux, macOS, Chrome на компјутер) секогаш се
/// прикажуваат ознаките за копчињата (F D S, 7 8 9, ESC...). На телефон и
/// таблет (Android, iOS - и како апликација и во прелистувач) тие се
/// скриени и упатствата се за допир - СÈ ДОДЕКА не се притисне копче на
/// вистинска тастатура (Bluetooth / USB). Тогаш ознаките се појавуваат.
abstract final class InputMode {
  /// Се поставува на true при првото копче од вистинска тастатура.
  static final ValueNotifier<bool> keyboardSeen = ValueNotifier<bool>(false);

  static bool get _touchPlatform =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Дали да се прикажат ознаките и упатствата за тастатура. Екранот што
  /// ја повикува се обновува сам кога ќе се поврзе тастатура.
  static bool showKeys(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<InputModeScope>();
    return !_touchPlatform || keyboardSeen.value;
  }

  /// Распоред за допир (телефон / таблет без тастатура).
  static bool touchLayout(BuildContext context) => !showKeys(context);

  /// Истото како [showKeys], но без [BuildContext] - за повици надвор од
  /// build (на пр. кога се пушта звук по притисок на копче).
  static bool get keysVisible => !_touchPlatform || keyboardSeen.value;

  static Set<String>? _assets;

  /// Снимка за допир: на телефон без тастатура, ако постои снимка со
  /// наставка `_touch` (пр. `audio/number_games/mk/explanation_sudoku_touch.mp3`),
  /// се пушта таа; инаку обичната. [relPath] е патеката без `assets/`.
  static Future<String> touchClip(String relPath) async {
    if (keysVisible) return relPath;
    final dot = relPath.lastIndexOf('.');
    if (dot < 0) return relPath;
    final touch = '${relPath.substring(0, dot)}_touch${relPath.substring(dot)}';
    try {
      _assets ??= (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().toSet();
      if (_assets!.contains('assets/$touch')) return touch;
    } catch (_) {}
    return relPath;
  }

  /// Се повикува од глобалниот слушач за тастатура (main.dart). Се броат
  /// само букви, бројки и стрелки надвор од текстуално поле - системското
  /// „назад“ и копчињата од екранската тастатура (бришење, Enter) не.
  static void noteKeyEvent(KeyEvent event) {
    if (keyboardSeen.value || event is! KeyDownEvent) return;
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null && focusCtx.findAncestorWidgetOfExactType<EditableText>() != null) return;
    final k = event.logicalKey;
    final isArrow = k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight;
    final ch = event.character;
    final isPrintable = ch != null && ch.trim().isNotEmpty;
    if (isArrow || isPrintable) keyboardSeen.value = true;
  }
}

/// Го става [InputMode.keyboardSeen] во дрвото, за екраните да се обноват
/// кога ќе се поврзе тастатура.
class InputModeScope extends InheritedNotifier<ValueNotifier<bool>> {
  InputModeScope({super.key, required super.child}) : super(notifier: InputMode.keyboardSeen);
}