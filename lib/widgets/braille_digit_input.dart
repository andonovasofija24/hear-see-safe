import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../braille/braille_data.dart';
import '../utils/accessibility_utils.dart';
import '../utils/input_mode.dart';
import '../utils/vibration_utils.dart';
import 'playful_ui.dart';

/// Множител за натписите (копчиња, преглед на цифрата). Точките и
/// ќелијата ја задржуваат својата геометрија.
const double _kBdText = 1.55;

/// За управување однадвор (пр. гласовни команди „потврди“ / „избриши“).
class BrailleDigitController {
  _BrailleDigitInputState? _state;

  /// Дали во клетката има започната цифра (точки или преглед).
  bool get hasPending {
    final s = _state;
    return s != null && (s._dots.isNotEmpty || s._preview != null);
  }

  /// „Потврди“ со глас: ако цифрата не е изговорена - прво се изговара, па
  /// веднаш се внесува (исто како А, А).
  Future<void> confirm() async {
    final s = _state;
    if (s == null) return;
    if (s._preview == null) {
      s._confirm();
      if (s._preview == null) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (_state != s || !s.mounted || s._preview == null) return;
    }
    s._confirm();
  }

  /// „Избриши“ со глас - ја брише клетката.
  void clear() => _state?._reset();
}

/// Внес на ЕДНА цифра со Брајово писмо - за вежбање на Брајовите вештини во
/// игрите со броеви. Исти правила како „Пишувај реченици“:
///
///  * точките 1-6 со допир (вклучи / исклучи) или со копчињата
///    F D S (точки 1 2 3) и J K L (точки 4 5 6) - секоја точка се изговара;
///  * А (или копчето „Изговори“) - се изговара цифрата; повторно А
///    („Потврди“) - цифрата се внесува;
///  * „.“ - ја брише последната точка; „;“ - ја брише целата клетка (ако е
///    празна - ја брише последната внесена цифра, преку [onBackspace]).
///
/// Пред клетката е нацртан ЗНАКОТ ЗА БРОЈ (точки 3-4-5-6) - во Брајово
/// писмо секој број почнува со него, па цифрите ги користат точките на
/// буквите а-ј.
class BrailleDigitInput extends StatefulWidget {
  const BrailleDigitInput({
    super.key,
    this.controller,
    required this.onDigit,
    this.onBackspace,
    this.enabled = true,
    this.allowZero = true,
    this.compact = false,
  });

  final BrailleDigitController? controller;

  /// Се повикува со потврдената цифра ('0'-'9').
  final ValueChanged<String> onDigit;
  final VoidCallback? onBackspace;
  final bool enabled;

  /// Судоку нема 0 - тогаш 0 се одбива како грешка.
  final bool allowZero;

  /// Помал изглед (кога има малку простор).
  final bool compact;

  @override
  State<BrailleDigitInput> createState() => _BrailleDigitInputState();
}

class _BrailleDigitInputState extends State<BrailleDigitInput> {
  static final Map<PhysicalKeyboardKey, int> _keyToDot = {
    PhysicalKeyboardKey.keyF: 1,
    PhysicalKeyboardKey.keyD: 2,
    PhysicalKeyboardKey.keyS: 3,
    PhysicalKeyboardKey.keyJ: 4,
    PhysicalKeyboardKey.keyK: 5,
    PhysicalKeyboardKey.keyL: 6,
  };
  static const Map<int, String> _dotKeyLetter = {1: 'F', 2: 'D', 3: 'S', 4: 'J', 5: 'K', 6: 'L'};

  final AudioPlayer _player = AudioPlayer();
  final Set<int> _dots = {};
  final List<int> _order = [];
  String? _preview;
  bool _error = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(covariant BrailleDigitInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) oldWidget.controller!._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _token++;
    _player.dispose();
    super.dispose();
  }

  String get _lang => context.locale.languageCode;

  // -------------------------------------------------------------------
  // Тастатура.
  // -------------------------------------------------------------------

  bool _onKey(KeyEvent event) {
    if (!mounted || !widget.enabled || event is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    // Додека се пишува во текстуално поле - буквите се за полето.
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null && focusCtx.findAncestorWidgetOfExactType<EditableText>() != null) return false;

    final key = event.physicalKey;
    final dot = _keyToDot[key];
    if (dot != null) {
      _addDot(dot);
      return true;
    }
    if (key == PhysicalKeyboardKey.keyA) {
      _confirm();
      return true;
    }
    if (key == PhysicalKeyboardKey.period) {
      _removeLastDot();
      return true;
    }
    if (key == PhysicalKeyboardKey.semicolon) {
      _reset();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Логика.
  // -------------------------------------------------------------------

  void _addDot(int dot) {
    if (!widget.enabled) return;
    setState(() {
      _preview = null;
      _error = false;
      if (_dots.add(dot)) _order.add(dot);
    });
    _vibrate(60);
    _play('dot_$dot');
  }

  /// Допир на точка на екранот: вклучи / исклучи.
  void _tapDot(int dot) {
    if (!widget.enabled) return;
    if (_dots.contains(dot)) {
      setState(() {
        _preview = null;
        _error = false;
        _dots.remove(dot);
        _order.remove(dot);
      });
      _vibrate(30);
    } else {
      _addDot(dot);
    }
  }

  void _removeLastDot() {
    if (!widget.enabled || _order.isEmpty) return;
    setState(() {
      _preview = null;
      _error = false;
      _dots.remove(_order.removeLast());
    });
    _vibrate(30);
  }

  void _reset() {
    if (!widget.enabled) return;
    if (_dots.isEmpty && _preview == null) {
      widget.onBackspace?.call();
      return;
    }
    setState(() {
      _dots.clear();
      _order.clear();
      _preview = null;
      _error = false;
    });
    _vibrate(30);
  }

  String? _decode() {
    for (final d in BrailleData.digits) {
      final pattern = d.dots.toSet();
      if (pattern.length == _dots.length && pattern.containsAll(_dots)) {
        if (d.char == '0' && !widget.allowZero) return null;
        return d.char;
      }
    }
    return null;
  }

  /// Прв пат: ја изговара цифрата (преглед). Втор пат: ја внесува.
  void _confirm() {
    if (!widget.enabled) return;
    final preview = _preview;
    if (preview != null) {
      setState(() {
        _dots.clear();
        _order.clear();
        _preview = null;
      });
      _vibrate(120);
      widget.onDigit(preview);
      return;
    }
    final digit = _decode();
    if (digit == null) {
      setState(() => _error = true);
      VibrationUtils.hasVibrator().then((ok) {
        if (ok) VibrationUtils.vibrate(pattern: const [0, 120, 100, 120]);
      });
      _playAsset('sounds/pong/miss.mp3');
      return;
    }
    setState(() => _preview = digit);
    _play('char_$digit');
  }

  void _vibrate(int ms) {
    VibrationUtils.hasVibrator().then((ok) {
      if (ok) VibrationUtils.vibrate(duration: ms);
    });
  }

  Future<void> _play(String clip) => _playAsset('audio/braille/$_lang/$clip.mp3');

  Future<void> _playAsset(String path) async {
    final token = ++_token;
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted || token != _token) return;
    try {
      await _player.play(AssetSource(path));
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // Изглед.
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    final dotSize = widget.compact ? 40.0 : 50.0;
    final gap = widget.compact ? 8.0 : 10.0;
    // Телефон / таблет без тастатура: нема ознаки за копчиња (F D S, A . ;)
    // и точките се распоредени како на Перкинс машина.
    final touch = InputMode.touchLayout(context);

    Widget cell = Container(
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _error ? const Color(0xFFDC2626) : (hc ? Colors.white : Playful.sun),
          width: _error ? 4 : 3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [for (final d in [1, 2, 3]) _dotButton(d, dotSize, gap, hc, showKey: !touch)]),
          SizedBox(width: gap),
          Column(mainAxisSize: MainAxisSize.min, children: [for (final d in [4, 5, 6]) _dotButton(d, dotSize, gap, hc, showKey: !touch)]),
        ],
      ),
    );

    final previewText = _preview ?? '?';

    // Знак за број - само за приказ (секогаш пред цифрата).
    final numberSign = Semantics(
      label: 'braille_input.number_sign'.tr(),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _staticCell(const {3, 4, 5, 6}, widget.compact ? 12 : 14, hc),
            const SizedBox(height: 4),
            Text('⠼', style: TextStyle(fontSize: 18 * 1.3, color: fg.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );

    // Преглед на цифрата (по првото А).
    final previewBubble = Semantics(
      liveRegion: true,
      label: _preview == null ? '' : _preview!,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.compact ? 72 : 88,
          height: widget.compact ? 72 : 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _preview != null ? (hc ? const Color(0xFFFFFF00) : Playful.sun) : (hc ? Colors.black : Colors.white.withValues(alpha: 0.1)),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                previewText,
                style: Playful.display((widget.compact ? 28 : 34) * 1.45, color: _preview != null ? Playful.ink : fg.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ),
    );

    final Widget board = touch
        ? _perkinsBoard(hc: hc, gap: gap, middle: [numberSign, SizedBox(height: gap), previewBubble])
        : Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 10,
            children: [numberSign, cell, previewBubble],
          );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.enabled ? 1 : 0.45,
      child: AbsorbPointer(
        absorbing: !widget.enabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            board,
            SizedBox(height: gap),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: _preview == null ? Icons.record_voice_over_rounded : Icons.check_rounded,
                  label: _preview == null ? 'braille_input.speak'.tr() : 'braille_input.confirm'.tr(),
                  keyLabel: touch ? null : 'A',
                  onTap: _confirm,
                  hc: hc,
                  primary: true,
                ),
                _actionButton(icon: Icons.backspace_outlined, label: 'braille_input.remove_dot'.tr(), keyLabel: touch ? null : '.', onTap: _removeLastDot, hc: hc),
                _actionButton(icon: Icons.clear_rounded, label: 'braille_input.clear'.tr(), keyLabel: touch ? null : ';', onTap: _reset, hc: hc),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dotButton(int dot, double size, double gap, bool hc, {bool showKey = true}) {
    final on = _dots.contains(dot);
    final label = 'braille_input.dot'.tr(args: [dot.toString()]);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap / 2),
      child: Semantics(
        label: label,
        button: true,
        toggled: on,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: () => _tapDot(dot),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? (hc ? const Color(0xFFFFFF00) : Playful.ink) : (hc ? Colors.black : const Color(0xFFE8E8F5)),
                border: Border.all(color: hc ? Colors.white : Playful.ink.withValues(alpha: on ? 1 : 0.35), width: 2),
                boxShadow: on && !hc ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.6), blurRadius: 10)] : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$dot', style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w900, color: on ? (hc ? Colors.black : Colors.white) : (hc ? Colors.white : Playful.ink))),
                  if (showKey)
                    Text(_dotKeyLetter[dot]!, style: TextStyle(fontSize: size * 0.2, fontWeight: FontWeight.w700, color: (on ? (hc ? Colors.black : Playful.sun) : (hc ? Colors.white70 : Playful.ink.withValues(alpha: 0.55))))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Перкинс распоред (само на допир): точките 1-2-3 во колона на левиот
  /// раб, 4-5-6 на десниот - за прстите на двете раце. Во средина:
  /// знакот за број и прегледот на цифрата. Висината е од големината на
  /// екранот (над ова секогаш има лизгање, па висината не е позната).
  Widget _perkinsBoard({required bool hc, required double gap, required List<Widget> middle}) {
    final screenH = MediaQuery.sizeOf(context).height;
    final dotH = (screenH * (widget.compact ? 0.075 : 0.095)).clamp(46.0, widget.compact ? 72.0 : 96.0);
    final boardH = dotH * 3 + gap * 2;
    return Container(
      padding: EdgeInsets.all(gap / 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: hc ? Colors.black : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: _error ? const Color(0xFFDC2626) : (hc ? Colors.white : Playful.sun),
          width: _error ? 4 : 3,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
          final colW = w * 0.33;
          Widget column(List<int> dots) => SizedBox(
                width: colW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < dots.length; i++) ...[
                      if (i > 0) SizedBox(height: gap),
                      _perkinsDot(dots[i], colW, dotH, hc),
                    ],
                  ],
                ),
              );
          return SizedBox(
            width: w,
            height: boardH,
            child: Row(
              children: [
                column(const [1, 2, 3]),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: middle),
                    ),
                  ),
                ),
                column(const [4, 5, 6]),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Голема точка за Перкинс распоредот - исти бои, звуци и ознаки како
  /// [_dotButton], само без буквата од тастатурата.
  Widget _perkinsDot(int dot, double width, double height, bool hc) {
    final on = _dots.contains(dot);
    final label = 'braille_input.dot'.tr(args: [dot.toString()]);
    return Semantics(
      label: label,
      button: true,
      toggled: on,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapDot(dot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              color: on ? (hc ? const Color(0xFFFFFF00) : Playful.ink) : (hc ? Colors.black : const Color(0xFFE8E8F5)),
              border: Border.all(color: hc ? Colors.white : Playful.ink.withValues(alpha: on ? 1 : 0.35), width: on ? 3 : 2),
              boxShadow: on && !hc ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.6), blurRadius: 10)] : null,
            ),
            child: Text(
              '$dot',
              style: TextStyle(fontSize: height * 0.45, fontWeight: FontWeight.w900, color: on ? (hc ? Colors.black : Colors.white) : (hc ? Colors.white : Playful.ink)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _staticCell(Set<int> dots, double dot, bool hc) {
    Widget d(int n) => Container(
          width: dot,
          height: dot,
          margin: EdgeInsets.all(dot * 0.22),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dots.contains(n) ? (hc ? const Color(0xFFFFFF00) : Playful.sun) : Colors.transparent,
            border: Border.all(color: (hc ? Colors.white : Colors.white.withValues(alpha: 0.6)), width: 1.5),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [d(1), d(2), d(3)]),
          Column(mainAxisSize: MainAxisSize.min, children: [d(4), d(5), d(6)]),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    String? keyLabel,
    required VoidCallback onTap,
    required bool hc,
    bool primary = false,
  }) {
    final bg = primary ? (hc ? const Color(0xFFFFFF00) : Playful.sun) : (hc ? Colors.black : Colors.white.withValues(alpha: 0.12));
    final fg = primary ? Playful.ink : (hc ? Colors.white : Colors.white);
    return Semantics(
      label: label,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.compact ? 8 : 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: primary ? 1 : 0.7), width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 26, color: fg),
                    const SizedBox(width: 8),
                    // Ограничена ширина: подолг натпис (mk/sq) оди во втор ред
                    // наместо да излезе надвор од копчето на тесен екран.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
                      child: Text(label, style: Playful.title(15 * _kBdText, color: fg)),
                    ),
                    if (keyLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary ? Playful.ink : Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(keyLabel, style: TextStyle(fontSize: 13 * _kBdText, fontWeight: FontWeight.w900, color: primary ? Playful.sun : Colors.white)),
                    ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}