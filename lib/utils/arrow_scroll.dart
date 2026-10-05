import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Лизгање низ целата апликација:
///  * секоја вертикална листа има видлив, дебел лизгач (бојата е во темата,
///    во main.dart - `appScrollbarTheme`);
///  * стрелките ↑ ↓ лизгаат малку, Page Up / Page Down - цел екран,
///    Home / End - на почеток / крај. Се лизга главната листа на екранот што
///    е најгоре (најголемата видлива).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Хоризонтални (пр. листање страници) - без лизгач.
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return child;
    final controller = details.controller;
    final bar = Scrollbar(controller: controller, child: child);
    if (controller == null) return bar;
    return _ArrowScrollTarget(controller: controller, child: bar);
  }
}

/// Тема за лизгачот: секогаш видлив, дебел, жолт врз темна патека - се
/// гледа и на светла и на темна позадина.
ScrollbarThemeData appScrollbarTheme({required bool highContrast}) {
  final thumb = highContrast ? const Color(0xFFFFFF00) : const Color(0xFFFFC93C);
  final thumbActive = highContrast ? Colors.white : const Color(0xFFFFA800);
  return ScrollbarThemeData(
    thumbVisibility: const WidgetStatePropertyAll(true),
    trackVisibility: const WidgetStatePropertyAll(true),
    interactive: true,
    thickness: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged) ? 20 : 14,
    ),
    radius: const Radius.circular(10),
    minThumbLength: 64,
    crossAxisMargin: 2,
    mainAxisMargin: 4,
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged) ? thumbActive : thumb,
    ),
    trackColor: WidgetStatePropertyAll(
      highContrast ? Colors.white.withValues(alpha: 0.25) : const Color(0xFF14134A).withValues(alpha: 0.35),
    ),
    trackBorderColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: highContrast ? 1.0 : 0.6)),
  );
}

/// Стрелките (↑ ↓ ← →) и Page Up/Down не прават ништо друго во апликацијата
/// (ниту преместуваат фокус) - лизгањето го прави [ArrowScroll.handleKey].
/// Полињата за пишување и понатаму ги користат стрелките за курсорот.
Map<ShortcutActivator, Intent> appShortcuts() => {
      ...WidgetsApp.defaultShortcuts,
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        // ← → не го местат фокусот - ги користат сликовниците (листање)
        // и судокуто (квадрати) преку HardwareKeyboard.
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ])
        SingleActivator(key): const DoNothingAndStopPropagationIntent(),
    };

class _ArrowScrollTarget extends StatefulWidget {
  const _ArrowScrollTarget({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_ArrowScrollTarget> createState() => _ArrowScrollTargetState();
}

class _ArrowScrollTargetState extends State<_ArrowScrollTarget> {
  @override
  void initState() {
    super.initState();
    ArrowScroll._targets.add(this);
  }

  @override
  void dispose() {
    ArrowScroll._targets.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

abstract final class ArrowScroll {
  static final List<_ArrowScrollTargetState> _targets = [];

  /// Екран што самиот ги користи стрелките (пр. судоку - премин меѓу
  /// квадратите) може да го исклучи лизгањето додека е активен.
  static bool Function()? suppressWhen;

  /// Глобален слушач за тастатура (main.dart). Враќа true ако излизгал.
  static bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (suppressWhen?.call() ?? false) return false;
    final key = event.logicalKey;
    // Не смее да биде `const` - LogicalKeyboardKey нема „примитивна“
    // еднаквост, па не може да биде во константно множество.
    final keys = {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    };
    if (!keys.contains(key)) return false;

    // Додека се пишува во поле - стрелките се за курсорот.
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null &&
        (focusCtx.widget is EditableText || focusCtx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }

    final position = _bestTarget();
    if (position == null) return false;

    final viewport = position.viewportDimension;
    double target;
    if (key == LogicalKeyboardKey.home) {
      target = position.minScrollExtent;
    } else if (key == LogicalKeyboardKey.end) {
      target = position.maxScrollExtent;
    } else {
      final step = (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown) ? viewport * 0.85 : 140.0;
      final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown;
      target = position.pixels + (down ? step : -step);
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return true;
    position.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    return true;
  }

  /// Главната листа на екранот што е најгоре: од оние што можат да се
  /// лизгаат, најголемата.
  static ScrollPosition? _bestTarget() {
    ScrollPosition? best;
    for (final t in _targets) {
      if (!t.mounted) continue;
      final route = ModalRoute.of(t.context);
      if (route != null && !route.isCurrent) continue;
      final c = t.widget.controller;
      if (!c.hasClients || c.positions.length != 1) continue;
      final p = c.position;
      if (!p.hasContentDimensions || p.maxScrollExtent <= p.minScrollExtent) continue;
      if (best == null || p.viewportDimension > best.viewportDimension) best = p;
    }
    return best;
  }
}