import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/accessibility_utils.dart';
import '../utils/voice_hotkey.dart';
import 'playful_ui.dart';

/// Множител за читливиот текст во картичката на избраниот остров.
const double _kIslandText = 1.55;

/// Еден остров (категорија) во [IslandCarousel].
class IslandItem {
  const IslandItem({
    required this.label,
    this.description = '',
    required this.icon,
    required this.color,
    this.state,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;

  /// null = обичен; true = точен одговор (зелено ✓); false = погрешен (црвено ✗).
  final bool? state;
}

/// За управување однадвор (пр. гласовно „следен“ / „претходен“).
class IslandCarouselController {
  _IslandCarouselState? _state;

  void next() => _state?._step(1, user: true);
  void previous() => _state?._step(-1, user: true);

  /// Индексот на островот што е моментално најгоре.
  int get selected => _state?._selected ?? 0;
}

/// Острови што се вртат во круг околу златен штит среде морето. Островот
/// најгоре е избраниот (светол, поголем); останатите се засенчени.
///
///  * со влечење лево/десно, со стрелките на екранот или со ← → на
///    тастатурата се врти кругот;
///  * допир на засенчен остров го носи најгоре; допир на горниот (или
///    „Влези“, Enter, празно место) ја отвора категоријата;
///  * додека корисникот не почне да врти, кругот сам се поместува на
///    секои неколку секунди (освен ако е исклучена анимацијата).
class IslandCarousel extends StatefulWidget {
  const IslandCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.controller,
    this.openLabel,
    this.openIcon = Icons.sailing_rounded,
    this.enabled = true,
    this.autoRotate = true,
    this.centerIcon = Icons.shield_rounded,
    this.bigIcons = false,
    this.showNumbers = true,
  });

  final List<IslandItem> items;
  final ValueChanged<int> onOpen;
  final IslandCarouselController? controller;

  /// Текст на копчето за влез (стандардно „Плови до островот“ од преводите).
  final String? openLabel;
  final IconData openIcon;

  /// false = кругот може да се врти, но изборот (отворање) е заклучен.
  final bool enabled;

  /// Сам да се врти додека корисникот не почне (во игрите - исклучено).
  final bool autoRotate;
  final IconData centerIcon;

  /// Поголеми икони и посветли засенчени острови (кога иконите се одговор).
  final bool bigIcons;
  final bool showNumbers;

  @override
  State<IslandCarousel> createState() => _IslandCarouselState();
}

class _IslandCarouselState extends State<IslandCarousel> with TickerProviderStateMixin {
  /// Непрекината „позиција“ на кругот: 0 = првиот остров горе, 1 = вториот...
  double _rotation = 0;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  Animation<double>? _spinAnim;
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  Timer? _autoTimer;
  bool _userTouched = false;

  int get _n => widget.items.length;
  int get _selected => (_rotation.round() % _n + _n) % _n;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _spin.addListener(() {
      final a = _spinAnim;
      if (a != null) setState(() => _rotation = a.value);
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !widget.autoRotate || _userTouched || _spin.isAnimating) return;
      if (Playful.reduceMotion(context)) return;
      // Со читач на екран (TalkBack/VoiceOver) не се врти само - liveRegion
      // би најавувал нов остров на секои 6 секунди.
      if (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false) return;
      _step(1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant IslandCarousel oldWidget) {
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
    _autoTimer?.cancel();
    _spin.dispose();
    _bob.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Вртење.
  // -------------------------------------------------------------------

  /// Каде кругот оди (или стои).
  double _target = 0;

  void _animateTo(double target) {
    _target = target;
    _spinAnim = Tween<double>(begin: _rotation, end: target).animate(
      CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic),
    );
    _spin
      ..stop()
      ..value = 0
      ..forward();
  }

  void _step(int delta, {bool user = false}) {
    if (user) _userTouched = true;
    final from = _spin.isAnimating ? _target : _rotation.roundToDouble();
    _animateTo(from + delta);
    HapticFeedback.selectionClick();
  }

  /// Островот [index] да дојде најгоре - по пократкиот пат.
  void _bringToTop(int index) {
    _userTouched = true;
    final current = (_spin.isAnimating ? _target : _rotation).round();
    var diff = (index - current) % _n;
    if (diff > _n / 2) diff -= _n;
    _animateTo((current + diff).toDouble());
    HapticFeedback.selectionClick();
  }

  void _open() {
    _userTouched = true;
    if (!widget.enabled) return;
    widget.onOpen(_selected);
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null && focusCtx.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    final key = event.physicalKey;
    if (key == PhysicalKeyboardKey.arrowRight) {
      _step(1, user: true);
      return true;
    }
    if (key == PhysicalKeyboardKey.arrowLeft) {
      _step(-1, user: true);
      return true;
    }
    if (key == PhysicalKeyboardKey.enter || key == PhysicalKeyboardKey.numpadEnter || key == PhysicalKeyboardKey.space) {
      // Ако е фокусирано некое копче (Tab), Enter/Space му припаѓаат нему.
      final pf = FocusManager.instance.primaryFocus;
      if (pf != null && pf is! FocusScopeNode) return false;
      _open();
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Изглед.
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => StartHotkeyListener(onTrigger: _open, child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    final selected = _selected;
    final item = widget.items[selected];

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 560.0);
        final height = size * 0.92;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {
                _userTouched = true;
                _spin.stop();
              },
              onHorizontalDragUpdate: (d) {
                setState(() => _rotation -= d.delta.dx / (size * 0.55));
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                var target = _rotation.roundToDouble();
                if (v.abs() > 500) target = (_rotation - v.sign * 0.5).roundToDouble();
                _animateTo(target);
              },
              child: SizedBox(
                width: size,
                height: height,
                child: AnimatedBuilder(
                  animation: _bob,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: CustomPaint(painter: _SeaPainter(highContrast: hc, t: _bob.value))),
                      // Штит (кибер заштита) во средина.
                      Align(
                        alignment: const Alignment(0, 0.08),
                        child: ExcludeSemantics(
                          child: Icon(widget.centerIcon, size: size * 0.13, color: hc ? Colors.white : Playful.sun),
                        ),
                      ),
                      ..._islands(size, height, hc),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Стрелки за вртење + влез.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundButton(Icons.rotate_right_rounded, 'islands.previous'.tr(), () => _step(-1, user: true), hc),
                const SizedBox(width: 18),
                _roundButton(Icons.rotate_left_rounded, 'islands.next'.tr(), () => _step(1, user: true), hc),
              ],
            ),
            const SizedBox(height: 14),
            // Картичка за избраниот остров.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Container(
                key: ValueKey(selected),
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: hc ? Colors.white : item.color.withValues(alpha: 0.9), width: 3),
                  boxShadow: hc ? null : [BoxShadow(color: item.color.withValues(alpha: 0.45), blurRadius: 22)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      header: true,
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: widget.showNumbers
                                ? FittedBox(fit: BoxFit.scaleDown, child: Text('${selected + 1}', style: const TextStyle(fontSize: 20 * _kIslandText, fontWeight: FontWeight.w900, color: Playful.ink)))
                                : Icon(item.icon, size: 32, color: Playful.ink),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item.label, style: Playful.display(25 * _kIslandText, color: fg))),
                        ],
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(item.description, style: Playful.body(16.5 * _kIslandText, color: fg.withValues(alpha: 0.95))),
                    ],
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      enabled: widget.enabled,
                      label: '${widget.openLabel ?? 'islands.open'.tr()}: ${item.label}',
                      child: ExcludeSemantics(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: widget.enabled ? 1 : 0.45,
                          child: PressableScale(
                          enabled: widget.enabled,
                          child: Material(
                            color: hc ? Colors.black : Playful.sun,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _open,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white, width: hc ? 2 : 3),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(widget.openIcon, size: 36, color: hc ? Colors.white : Playful.ink),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        widget.openLabel ?? 'islands.open'.tr(),
                                        style: Playful.title(21 * _kIslandText, color: hc ? Colors.white : Playful.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Островите по елипса; горниот е најголем и светол, другите засенчени.
  /// Се цртаат од најдалечниот кон најблискиот (горниот - последен).
  List<Widget> _islands(double size, double height, bool hc) {
    final cx = size / 2;
    final cy = height * 0.5;
    // Повеќе острови - поширок круг и помали острови.
    final many = _n > 4;
    final rx = size * (many ? 0.37 : 0.34);
    final ry = height * (many ? 0.36 : 0.33);
    final islandW = size * (_n <= 4 ? 0.3 : (_n <= 6 ? 0.26 : 0.23));
    final entries = <(double, Widget)>[];
    for (var i = 0; i < _n; i++) {
      final theta = -math.pi / 2 + (i - _rotation) * 2 * math.pi / _n;
      final closeness = math.cos(theta + math.pi / 2); // 1 = горе
      final focus = math.pow(math.max(0.0, closeness), 6).toDouble();
      final scale = 0.66 + 0.34 * math.max(0.0, closeness);
      final bob = Playful.reduceMotion(context) ? 0.0 : math.sin((_bob.value + i * 0.25) * 2 * math.pi) * 4;
      final x = cx + rx * math.cos(theta);
      final y = cy + ry * math.sin(theta) + bob;
      final w = islandW * scale;
      final isTop = i == _selected;
      entries.add((
        closeness,
        Positioned(
          left: x - w / 2,
          top: y - w * 0.45,
          width: w,
          height: w * 0.9,
          child: Semantics(
            button: true,
            selected: isTop,
            label: widget.showNumbers ? '${i + 1}. ${widget.items[i].label}' : widget.items[i].label,
            child: GestureDetector(
              onTap: () => isTop ? _open() : _bringToTop(i),
              child: ExcludeSemantics(
                child: _Island(
                  item: widget.items[i],
                  number: i + 1,
                  focus: focus,
                  highContrast: hc,
                  bigIcon: widget.bigIcons,
                  showNumber: widget.showNumbers,
                ),
              ),
            ),
          ),
        ),
      ));
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final e in entries) e.$2];
  }

  Widget _roundButton(IconData icon, String label, VoidCallback onTap, bool hc) {
    return Semantics(
      label: label,
      button: true,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: hc ? Colors.black : Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.75), width: 2.5),
                ),
                child: Icon(icon, size: 32, color: hc ? Colors.white : Playful.sun),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Еден остров: песок, зелен рид во бојата на категоријата, икона во бел
/// круг и златен реден број. [focus] 1 = горе (светол), 0 = засенчен.
class _Island extends StatelessWidget {
  const _Island({
    required this.item,
    required this.number,
    required this.focus,
    required this.highContrast,
    this.bigIcon = false,
    this.showNumber = true,
  });

  final IslandItem item;
  final int number;
  final double focus;
  final bool highContrast;
  final bool bigIcon;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final hc = highContrast;
        // Колку е засенчен (кај големите икони - помалку, за да се гледаат).
        final dim = (1 - focus) * (bigIcon ? 0.55 : 1.0);
        final state = item.state;
        final baseColor = state == null ? item.color : (state ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
        final hill = Color.lerp(baseColor, const Color(0xFF0B1030), dim * 0.6)!;
        final sand = Color.lerp(const Color(0xFFF4D58D), const Color(0xFF3A3550), dim * 0.7)!;
        final island = Stack(
          clipBehavior: Clip.none,
          children: [
            // Бранови околу островот.
            Positioned(
              left: -w * 0.06,
              right: -w * 0.06,
              bottom: 0,
              height: h * 0.34,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(w, h * 0.34)),
                  color: hc ? Colors.transparent : Colors.white.withValues(alpha: 0.12 + 0.14 * focus),
                  border: Border.all(color: Colors.white.withValues(alpha: hc ? 1 : 0.35 + 0.4 * focus), width: hc ? 2 : 1.5),
                ),
              ),
            ),
            // Песок.
            Positioned(
              left: w * 0.04,
              right: w * 0.04,
              bottom: h * 0.06,
              height: h * 0.3,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(w, h * 0.3)),
                  color: hc ? Colors.black : sand,
                  border: hc ? Border.all(color: Colors.white, width: 2) : null,
                ),
              ),
            ),
            // Рид со иконата.
            Positioned(
              left: w * (bigIcon ? 0.1 : 0.16),
              right: w * (bigIcon ? 0.1 : 0.16),
              bottom: h * 0.16,
              height: h * (bigIcon ? 0.8 : 0.72),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hc ? Colors.black : null,
                  gradient: hc
                      ? null
                      : RadialGradient(
                          center: const Alignment(-0.3, -0.4),
                          colors: [Color.lerp(hill, Colors.white, 0.25)!, hill, Color.lerp(hill, Colors.black, 0.35)!],
                          stops: const [0.0, 0.6, 1.0],
                        ),
                  border: Border.all(
                    color: hc ? (focus > 0.5 || state != null ? const Color(0xFFFFFF00) : Colors.white) : Colors.white.withValues(alpha: 0.5 + 0.5 * focus),
                    width: focus > 0.5 || state != null ? 4 : 2,
                  ),
                  boxShadow: hc || (focus < 0.05 && state == null)
                      ? null
                      : [BoxShadow(color: baseColor.withValues(alpha: 0.7 * math.max(focus, state == null ? 0.0 : 0.8)), blurRadius: 30, spreadRadius: 4 * focus)],
                ),
                child: Center(
                  child: Container(
                    width: w * (bigIcon ? 0.52 : 0.36),
                    height: w * (bigIcon ? 0.52 : 0.36),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : Colors.white.withValues(alpha: 0.75 + 0.25 * focus),
                      border: hc ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: Icon(item.icon, size: w * (bigIcon ? 0.38 : 0.22), color: hc ? const Color(0xFFFFFF00) : Color.lerp(baseColor, Colors.black, 0.25)),
                  ),
                ),
              ),
            ),
            // Реден број, или ✓ / ✗ по одговорот.
            if (showNumber || state != null)
            Positioned(
              right: w * 0.1,
              top: h * 0.02,
              child: Container(
                width: w * (state != null && bigIcon ? 0.3 : 0.2),
                height: w * (state != null && bigIcon ? 0.3 : 0.2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state != null
                      ? Colors.white
                      : (hc ? const Color(0xFFFFFF00) : Color.lerp(Playful.sun, const Color(0xFF555070), dim * 0.6)),
                  border: Border.all(color: state != null ? baseColor : Colors.white, width: 2),
                ),
                child: state != null
                    ? FittedBox(child: Icon(state ? Icons.check_rounded : Icons.close_rounded, color: baseColor))
                    : FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w900, color: Playful.ink)),
                        ),
                      ),
              ),
            ),
          ],
        );
        // Засенчени острови - потемни (во висок контраст само поблед).
        final minOpacity = bigIcon ? 0.7 : (hc ? 0.55 : 0.45);
        return Opacity(opacity: state != null ? 1.0 : minOpacity + (1 - minOpacity) * focus, child: island);
      },
    );
  }
}

/// Море: темно сино коло со кругови-бранови што полека пулсираат.
class _SeaPainter extends CustomPainter {
  _SeaPainter({required this.highContrast, required this.t});

  final bool highContrast;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rx = size.width * 0.47;
    final ry = size.height * 0.46;
    final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    if (highContrast) {
      canvas.drawOval(rect, Paint()..color = Colors.black);
      canvas.drawOval(rect, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      return;
    }
    canvas.drawOval(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0E7490), Color(0xFF0B3B66), Color(0xFF0B1030)],
          stops: [0.0, 0.65, 1.0],
        ).createShader(rect),
    );
    // Бранови - кругови што полека растат.
    for (var k = 0; k < 3; k++) {
      final p = (t + k / 3) % 1.0;
      final r = Rect.fromCenter(center: c, width: rx * 2 * (0.2 + 0.8 * p), height: ry * 2 * (0.2 + 0.8 * p));
      canvas.drawOval(
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12 * (1 - p))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawOval(
      rect,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SeaPainter old) => old.t != t || old.highContrast != highContrast;
}