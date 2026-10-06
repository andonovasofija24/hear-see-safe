import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../utils/accessibility_utils.dart';
import '../utils/voice_hotkey.dart';
import 'playful_ui.dart';

/// Множител за читливиот текст во картичката за предната категорија.
const double _kSphereText = 1.55;

/// Висина на натписот под топчињата на сферата (поголем натпис, ист ред).
const double _kSphereNodeLabelH = 27;

/// Една категорија на [SphereMenu].
class SphereItem {
  const SphereItem({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;
}

/// За управување однадвор (гласовно „следна“ / „претходна“).
class SphereMenuController {
  _SphereMenuState? _state;

  void next() => _state?._stepOrder(1);
  void previous() => _state?._stepOrder(-1);
  int get front => _state?._front ?? 0;
}

/// 3D глобус: категориите се распоредени по сфера што се врти во сите
/// правци (влечење со прст / глушец, со инерција).
///
///  * најпредната категорија е избрана - најголема и светла, со името
///    подолу и копче „Почни“; задните се помали и засенчени;
///  * допир на категорија ја носи напред; допир на предната ја отвора;
///  * ← → на тастатурата - следна / претходна, Enter - отвори;
///  * додека корисникот не ја допре, сферата полека сама се врти (освен
///    со исклучени анимации или читач на екран).
class SphereMenu extends StatefulWidget {
  const SphereMenu({
    super.key,
    required this.items,
    required this.onOpen,
    this.controller,
    this.openLabel,
    this.onHoldChanged,
  });

  /// true додека прстот е на топката - родителот може да го исклучи
  /// лизгањето на страницата за да може топката да се врти и нагоре/надолу.
  final ValueChanged<bool>? onHoldChanged;

  final List<SphereItem> items;
  final ValueChanged<int> onOpen;
  final SphereMenuController? controller;
  final String? openLabel;

  @override
  State<SphereMenu> createState() => _SphereMenuState();
}

class _SphereMenuState extends State<SphereMenu> with TickerProviderStateMixin {
  /// Вртење околу вертикалната (yaw) и хоризонталната (pitch) оска.
  double _yaw = 0.35;
  double _pitch = -0.25;

  late List<_P3> _points;
  late List<int> _order; // редослед за „следна / претходна“

  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  double _fromYaw = 0, _toYaw = 0, _fromPitch = 0, _toPitch = 0;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _vYaw = 0, _vPitch = 0; // инерција (радијани во секунда)
  bool _userTouched = false;
  bool _dragging = false;

  int _front = 0;
  int? _snapTarget; // каде оди тековното „snap“ вртење

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _buildPoints();
    _snap.addListener(() {
      final t = Curves.easeOutCubic.transform(_snap.value);
      setState(() {
        _yaw = _fromYaw + (_toYaw - _fromYaw) * t;
        _pitch = _fromPitch + (_toPitch - _fromPitch) * t;
      });
    });
    _ticker = createTicker(_onTick)..start();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(covariant SphereMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) _buildPoints();
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) oldWidget.controller!._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _snap.dispose();
    super.dispose();
  }

  /// Рамномерно по сферата („Фибоначиева“ сфера).
  void _buildPoints() {
    final n = widget.items.length;
    final golden = math.pi * (3 - math.sqrt(5));
    _points = [
      for (var i = 0; i < n; i++)
        () {
          // Малку „спуштени“ од половите (|y| <= 0.85) - подобро се гледаат,
          // а и pitch за да се донесат напред останува во границите (±1.45).
          final y = n == 1 ? 0.0 : (1 - (i / (n - 1)) * 2) * 0.85;
          final r = math.sqrt(math.max(0.0, 1 - y * y));
          final th = golden * i;
          return _P3(math.cos(th) * r, y, math.sin(th) * r).normalized();
        }(),
    ];
    final idx = List<int>.generate(n, (i) => i);
    idx.sort((a, b) {
      final la = math.atan2(_points[a].x, _points[a].z);
      final lb = math.atan2(_points[b].x, _points[b].z);
      return la.compareTo(lb);
    });
    _order = idx;
  }

  _P3 _rotate(_P3 p) {
    // Прво околу Y (yaw), па околу X (pitch).
    final cy = math.cos(_yaw), sy = math.sin(_yaw);
    final x1 = p.x * cy + p.z * sy;
    final z1 = -p.x * sy + p.z * cy;
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final y2 = p.y * cp - z1 * sp;
    final z2 = p.y * sp + z1 * cp;
    return _P3(x1, y2, z2);
  }

  bool get _calm =>
      Playful.reduceMotion(context) || (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false);

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    if (!mounted) return;
    if (_dragging || _snap.isAnimating) return;
    if (_vYaw.abs() > 0.02 || _vPitch.abs() > 0.02) {
      // Инерција по фрлање, со забавување - па се „заклучува“ напред.
      setState(() {
        _yaw += _vYaw * dt;
        _pitch = (_pitch + _vPitch * dt).clamp(-1.45, 1.45);
        final decay = math.pow(0.08, dt).toDouble();
        _vYaw *= decay;
        _vPitch *= decay;
      });
      if (_vYaw.abs() <= 0.02 && _vPitch.abs() <= 0.02) _snapToFront();
      return;
    }
    if (!_userTouched && !_calm) {
      setState(() => _yaw += 0.22 * dt); // полека само се врти
    } else {
      _ticker.stop(); // мирува - без празни рамки; _wake() го пали пак
    }
  }

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// Ја носи категоријата [i] точно напред (по пократкиот пат).
  void _bringToFront(int i) {
    final p = _points[i];
    var targetYaw = math.atan2(-p.x, p.z);
    final z1 = math.sqrt(p.x * p.x + p.z * p.z);
    final targetPitch = math.atan2(p.y, z1).clamp(-1.45, 1.45);
    // Најблиску до сегашното вртење (без цел круг непотребно).
    while (targetYaw - _yaw > math.pi) {
      targetYaw -= 2 * math.pi;
    }
    while (targetYaw - _yaw < -math.pi) {
      targetYaw += 2 * math.pi;
    }
    _fromYaw = _yaw;
    _fromPitch = _pitch;
    _toYaw = targetYaw;
    _toPitch = targetPitch;
    _snapTarget = i;
    _vYaw = 0;
    _vPitch = 0;
    _snap
      ..stop()
      ..value = 0
      ..forward();
    HapticFeedback.selectionClick();
  }

  void _snapToFront() {
    _vYaw = 0;
    _vPitch = 0;
    _bringToFront(_computeFront());
  }

  int _computeFront() {
    var best = 0;
    var bestZ = -2.0;
    for (var i = 0; i < _points.length; i++) {
      final z = _rotate(_points[i]).z;
      if (z > bestZ) {
        bestZ = z;
        best = i;
      }
    }
    return best;
  }

  void _stepOrder(int delta) {
    _userTouched = true;
    final from = _snap.isAnimating ? (_snapTarget ?? _front) : _front;
    final pos = _order.indexOf(from);
    final next = _order[(pos + delta) % _order.length];
    _bringToFront(next);
  }

  void _open() {
    _userTouched = true;
    widget.onOpen(_front);
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx != null && focusCtx.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    final key = event.physicalKey;
    if (key == PhysicalKeyboardKey.arrowRight) {
      _stepOrder(1);
      return true;
    }
    if (key == PhysicalKeyboardKey.arrowLeft) {
      _stepOrder(-1);
      return true;
    }
    if (key == PhysicalKeyboardKey.enter || key == PhysicalKeyboardKey.numpadEnter) {
      final pf = FocusManager.instance.primaryFocus;
      if (pf != null && pf is! FocusScopeNode) return false;
      _open();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => StartHotkeyListener(onTrigger: _open, child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    _front = _computeFront();
    final item = widget.items[_front];

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 520.0);
        final radius = size * 0.36;
        final base = (size * 0.2).clamp(58.0, 104.0);
        final projected = <(int, _P3)>[
          for (var i = 0; i < _points.length; i++) (i, _rotate(_points[i])),
        ]..sort((a, b) => a.$2.z.compareTo(b.$2.z)); // задните прво

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Listener(
              onPointerDown: (_) => widget.onHoldChanged?.call(true),
              onPointerUp: (_) => widget.onHoldChanged?.call(false),
              onPointerCancel: (_) => widget.onHoldChanged?.call(false),
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _userTouched = true;
                _dragging = true;
                _snap.stop();
                _vYaw = 0;
                _vPitch = 0;
              },
              onPanUpdate: (d) {
                setState(() {
                  _yaw += d.delta.dx / radius;
                  _pitch = (_pitch + d.delta.dy / radius).clamp(-1.45, 1.45);
                });
              },
              onPanEnd: (d) {
                _dragging = false;
                final v = d.velocity.pixelsPerSecond;
                _vYaw = v.dx / radius;
                _vPitch = v.dy / radius;
                if (_vYaw.abs() <= 0.02 && _vPitch.abs() <= 0.02) {
                  _snapToFront();
                } else {
                  _wake();
                }
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _GlobePainter(yaw: _yaw, pitch: _pitch, highContrast: hc, radius: radius)),
                    ),
                    for (final (i, p) in projected) _node(i, p, size, radius, base, hc),
                  ],
                ),
              ),
            ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundButton(Icons.chevron_left_rounded, 'sphere.previous'.tr(), () => _stepOrder(-1), hc),
                const SizedBox(width: 18),
                _roundButton(Icons.chevron_right_rounded, 'sphere.next'.tr(), () => _stepOrder(1), hc),
              ],
            ),
            const SizedBox(height: 14),
            // Предната категорија: име + „Почни“.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey(_front),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: hc ? Colors.white : item.color.withValues(alpha: 0.95), width: 3),
                  boxShadow: hc ? null : [BoxShadow(color: item.color.withValues(alpha: 0.45), blurRadius: 22)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hc ? Colors.black : Colors.white,
                              border: Border.all(color: hc ? Colors.white : item.color, width: 3),
                            ),
                            child: Icon(item.icon, color: hc ? const Color(0xFFFFFF00) : item.color, size: 32),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item.label, style: Playful.display(23 * _kSphereText, color: fg))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      button: true,
                      label: '${widget.openLabel ?? 'sphere.open'.tr()}: ${item.label}',
                      child: ExcludeSemantics(
                        child: PressableScale(
                          child: Material(
                            color: hc ? Colors.black : Playful.sun,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _open,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white, width: hc ? 2 : 3),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 38, color: hc ? Colors.white : Playful.ink),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        widget.openLabel ?? 'sphere.open'.tr(),
                                        style: Playful.title(21 * _kSphereText, color: hc ? Colors.white : Playful.ink),
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
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Една категорија на сферата: големина и светлина според длабочината.
  Widget _node(int i, _P3 p, double size, double radius, double base, bool hc) {
    final depth = (p.z + 1) / 2; // 0 = најназад, 1 = најнапред
    final isFront = i == _front;
    final scale = 0.45 + 0.55 * depth;
    final w = base * scale;
    final cx = size / 2 + p.x * radius;
    final cy = size / 2 - p.y * radius;
    final opacity = (0.22 + 0.78 * math.pow(depth, 1.6)).clamp(0.0, 1.0).toDouble();
    final it = widget.items[i];
    final showLabel = depth > 0.62;
    return Positioned(
      left: cx - w / 2,
      top: cy - w / 2,
      width: w,
      height: w + (showLabel ? _kSphereNodeLabelH : 0),
      child: Semantics(
        button: true,
        selected: isFront,
        label: '${i + 1}. ${it.label}',
        child: GestureDetector(
          onTap: () {
            _userTouched = true;
            if (isFront && !_snap.isAnimating) {
              _open();
            } else {
              _bringToFront(i);
            }
          },
          child: ExcludeSemantics(
            child: Opacity(
              opacity: opacity,
              child: Column(
                children: [
                  Container(
                    width: w,
                    height: w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : null,
                      gradient: hc
                          ? null
                          : RadialGradient(
                              center: const Alignment(-0.35, -0.4),
                              colors: [Color.lerp(it.color, Colors.white, 0.35)!, it.color, Color.lerp(it.color, Colors.black, 0.4)!],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                      border: Border.all(
                        color: isFront ? (hc ? const Color(0xFFFFFF00) : Playful.sun) : Colors.white.withValues(alpha: hc ? 1 : 0.8),
                        width: isFront ? 4 : 2,
                      ),
                      boxShadow: hc
                          ? null
                          : [
                              BoxShadow(
                                color: (isFront ? Playful.sun : it.color).withValues(alpha: isFront ? 0.7 : 0.35 * depth),
                                blurRadius: isFront ? 26 : 12,
                                spreadRadius: isFront ? 3 : 0,
                              ),
                            ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: Icon(it.icon, size: w * 0.5, color: hc ? const Color(0xFFFFFF00) : Colors.white)),
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: w * 0.32,
                            height: w * 0.32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: Playful.ink)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showLabel)
                    SizedBox(
                      height: _kSphereNodeLabelH,
                      width: w * 1.8,
                      child: OverflowBox(
                        maxWidth: w * 2.2,
                        child: Text(
                          it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Playful.title(12.5 * 1.4, color: hc ? Colors.white : Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.75), width: 2.5),
                ),
                child: Icon(icon, size: 34, color: hc ? Colors.white : Playful.sun),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _P3 {
  const _P3(this.x, this.y, this.z);
  final double x, y, z;

  _P3 normalized() {
    final l = math.sqrt(x * x + y * y + z * z);
    return l == 0 ? this : _P3(x / l, y / l, z / l);
  }
}

/// Глобусот: проѕирна топка со сјај, меридијани и паралели што се вртат
/// заедно со категориите.
class _GlobePainter extends CustomPainter {
  _GlobePainter({required this.yaw, required this.pitch, required this.highContrast, required this.radius});

  final double yaw;
  final double pitch;
  final bool highContrast;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = radius * 1.08;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (highContrast) {
      canvas.drawCircle(c, r, Paint()..color = Colors.black);
      canvas.drawCircle(c, r, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    } else {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.35, -0.4),
            colors: [Color(0xFF3B3A9C), Color(0xFF1C1A63), Color(0xFF0C0B33)],
            stops: [0.0, 0.6, 1.0],
          ).createShader(rect),
      );
      canvas.drawCircle(c, r * 1.03, Paint()
        ..color = const Color(0xFFFFC93C).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    final line = Paint()
      ..color = (highContrast ? Colors.white : Colors.white).withValues(alpha: highContrast ? 0.5 : 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    // Меридијани (се вртат со yaw).
    for (var k = 0; k < 6; k++) {
      final a = yaw + k * math.pi / 6;
      final w = (r * math.cos(a)).abs();
      canvas.drawOval(Rect.fromCenter(center: c, width: w * 2, height: r * 2), line);
    }
    // Паралели (се навалуваат со pitch).
    for (final lat in const [-0.6, -0.3, 0.0, 0.3, 0.6]) {
      final y = c.dy - r * math.sin(lat) * math.cos(pitch);
      final rw = r * math.cos(lat);
      final rh = (rw * math.sin(pitch)).abs();
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, y), width: rw * 2, height: math.max(1.0, rh * 2)), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) =>
      old.yaw != yaw || old.pitch != pitch || old.highContrast != highContrast || old.radius != radius;
}