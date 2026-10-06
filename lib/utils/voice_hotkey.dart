import 'package:flutter/widgets.dart';

/// Копчето Г (физичкото G) на тастатура - гласовна команда низ целата
/// апликација. Глобалниот слушач во main.dart ја зголемува вредноста при
/// секој притисок; почетниот екран и копчињата за гласовна команда во
/// игрите слушаат и реагираат само ако нивниот екран е најгоре.
abstract final class VoiceHotkey {
  static final ValueNotifier<int> pressed = ValueNotifier<int>(0);
}

/// Копчето Е (физичкото E, на секој распоред - исто е и кирилично Е) -
/// отвора / затвора објаснување во која било игра. Глобалниот слушач во
/// main.dart ја зголемува вредноста; реагира само [ExplainHotkeyListener]
/// на екранот што е најгоре (последно прикажаниот).
abstract final class ExplainHotkey {
  static final ValueNotifier<int> pressed = ValueNotifier<int>(0);
}

/// Обвивка околу копче за објаснување: при притисок на Е се повикува
/// [onTrigger] - само кај едно копче, она на екранот што е најгоре.
class ExplainHotkeyListener extends StatefulWidget {
  const ExplainHotkeyListener({super.key, required this.onTrigger, required this.child});

  final VoidCallback? onTrigger;
  final Widget child;

  @override
  State<ExplainHotkeyListener> createState() => _ExplainHotkeyListenerState();
}

class _ExplainHotkeyListenerState extends State<ExplainHotkeyListener> {
  static final List<_ExplainHotkeyListenerState> _registry = [];
  static bool _hooked = false;

  static void _dispatch() {
    for (final s in _registry.reversed) {
      if (!s.mounted || s.widget.onTrigger == null) continue;
      final route = ModalRoute.of(s.context);
      if (route != null && !route.isCurrent) continue;
      s.widget.onTrigger!();
      return;
    }
  }

  @override
  void initState() {
    super.initState();
    _registry.add(this);
    if (!_hooked) {
      _hooked = true;
      ExplainHotkey.pressed.addListener(_dispatch);
    }
  }

  @override
  void dispose() {
    _registry.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Копчето С (физичкото S - на македонски распоред е С, на англиски S) -
/// „Старт“: го притиска копчето што почнува игра (старт, пушти звук,
/// играј повторно...) на екранот што е најгоре. Глобалниот слушач во
/// main.dart ја зголемува вредноста; реагира само еден
/// [StartHotkeyListener] - последниот прикажан со активно копче.
abstract final class StartHotkey {
  static final ValueNotifier<int> pressed = ValueNotifier<int>(0);
}

/// Обвивка околу копче што почнува игра: при притисок на С се повикува
/// [onTrigger]. Ако [onTrigger] е null (копчето е оневозможено), се
/// прескокнува и се бара следното.
class StartHotkeyListener extends StatefulWidget {
  const StartHotkeyListener({super.key, required this.onTrigger, required this.child});

  final VoidCallback? onTrigger;
  final Widget child;

  @override
  State<StartHotkeyListener> createState() => _StartHotkeyListenerState();
}

class _StartHotkeyListenerState extends State<StartHotkeyListener> {
  static final List<_StartHotkeyListenerState> _registry = [];
  static bool _hooked = false;

  static void _dispatch() {
    for (final s in _registry.reversed) {
      if (!s.mounted || s.widget.onTrigger == null) continue;
      final route = ModalRoute.of(s.context);
      if (route != null && !route.isCurrent) continue;
      // Невидливо копче (на пр. во друг таб) не се притиска.
      if (!TickerMode.of(s.context)) continue;
      s.widget.onTrigger!();
      return;
    }
  }

  @override
  void initState() {
    super.initState();
    _registry.add(this);
    if (!_hooked) {
      _hooked = true;
      StartHotkey.pressed.addListener(_dispatch);
    }
  }

  @override
  void dispose() {
    _registry.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}