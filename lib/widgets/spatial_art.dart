import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/accessibility_utils.dart';
import 'playful_ui.dart';

/// Уметност за „Просторна ориентација“ - заштитен знак „Навигаторска карта“:
///  * [SpatialMapBackdrop] - позадина: стара поморска карта (мрежа од
///    меридијани и паралели), голема роза на ветровите што полека се
///    врти, патека со стапалки и ѕвезди;
///  * [CompassRoseNeedle] - мала роза на ветровите со игла што покажува
///    кон насоката што моментално вибрира (среде крстот);
///  * [DirectionPips] - точки на копчињата: колку вибрации има насоката.

class SpatialMapBackdrop extends StatefulWidget {
  const SpatialMapBackdrop({super.key, required this.tint});

  final Color tint;

  @override
  State<SpatialMapBackdrop> createState() => _SpatialMapBackdropState();
}

class _SpatialMapBackdropState extends State<SpatialMapBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 90));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B1E3A), Color(0xFF12305A), Color(0xFF0A1730)],
            ),
          ),
          child: RepaintBoundary(
            child: CustomPaint(painter: _MapPainter(_c, widget.tint), child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.t, this.tint) : super(repaint: t);

  final Animation<double> t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final grid = Paint()
      ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Меридијани (благо заоблени) и паралели.
    for (var i = 1; i < 8; i++) {
      final x = w * i / 8;
      final p = Path()
        ..moveTo(x, 0)
        ..quadraticBezierTo(x + (i - 4) * 10, h / 2, x, h);
      canvas.drawPath(p, grid);
    }
    for (var y = 60.0; y < h; y += 90) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    // Ѕвезди.
    final rnd = math.Random(3);
    for (var i = 0; i < 40; i++) {
      final s = Offset(w * rnd.nextDouble(), h * rnd.nextDouble());
      final tw = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t.value * math.pi * 40 + i));
      canvas.drawCircle(s, 1 + rnd.nextDouble() * 1.4, Paint()..color = Colors.white.withValues(alpha: 0.18 * tw));
    }
    // Патека со точки и стапалки (од долу лево кон горе десно).
    final route = Path()
      ..moveTo(w * 0.05, h * 0.92)
      ..cubicTo(w * 0.35, h * 0.75, w * 0.15, h * 0.45, w * 0.5, h * 0.4)
      ..cubicTo(w * 0.8, h * 0.35, w * 0.7, h * 0.12, w * 0.95, h * 0.06);
    final metric = route.computeMetrics().first;
    final dot = Paint()..color = const Color(0xFFFFC93C).withValues(alpha: 0.18);
    final shift = (t.value * 600) % 28;
    for (var d = shift; d < metric.length; d += 28) {
      final tan = metric.getTangentForOffset(d);
      if (tan == null) continue;
      canvas.drawCircle(tan.position, 3, dot);
    }
    // Крст „X“ на крајот на патеката - целта.
    final end = Offset(w * 0.95, h * 0.06);
    final x = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.3)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(end + const Offset(-10, -10), end + const Offset(10, 10), x);
    canvas.drawLine(end + const Offset(10, -10), end + const Offset(-10, 10), x);
    // Голема роза на ветровите во долниот десен агол.
    final rc = Offset(w * 0.86, h * 0.8);
    final rr = math.min(w, h) * 0.32;
    canvas.save();
    canvas.translate(rc.dx, rc.dy);
    canvas.rotate(t.value * math.pi * 2);
    _rose(canvas, rr, Colors.white.withValues(alpha: 0.07), tint.withValues(alpha: 0.12));
    canvas.restore();
    // Сјај во бојата на модулот.
    canvas.drawCircle(Offset(w * 0.1, h * 0.15), math.min(w, h) * 0.6, Paint()
      ..shader = RadialGradient(colors: [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: Offset(w * 0.1, h * 0.15), radius: math.min(w, h) * 0.6)));
  }

  void _rose(Canvas canvas, double r, Color line, Color fill) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset.zero, r, stroke);
    canvas.drawCircle(Offset.zero, r * 0.82, stroke);
    for (var k = 0; k < 32; k++) {
      final a = k * math.pi / 16;
      final inner = k.isEven ? r * 0.88 : r * 0.92;
      canvas.drawLine(Offset(math.cos(a), math.sin(a)) * inner, Offset(math.cos(a), math.sin(a)) * r, stroke);
    }
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4 - math.pi / 2;
      final len = k.isEven ? r * 0.78 : r * 0.45;
      final side = r * 0.09;
      final tip = Offset(math.cos(a), math.sin(a)) * len;
      final l = Offset(math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)) * side;
      final p = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(l.dx, l.dy)
        ..lineTo(-l.dx, -l.dy)
        ..close();
      canvas.drawPath(p, Paint()..color = fill);
      canvas.drawPath(p, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.tint != tint;
}

/// Мала роза на ветровите со игла. [dir] = 'up' | 'down' | 'left' |
/// 'right' | null (иглата мирува горе, бледо).
class CompassRoseNeedle extends StatelessWidget {
  const CompassRoseNeedle({super.key, required this.dir, required this.active, this.size = 92});

  final String? dir;
  final bool active;
  final double size;

  static const Map<String, double> _angles = {'up': 0, 'right': math.pi / 2, 'down': math.pi, 'left': -math.pi / 2};

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final reduce = Playful.reduceMotion(context);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _angles[dir] ?? 0),
        duration: Duration(milliseconds: reduce ? 0 : 380),
        curve: Curves.easeOutBack,
        builder: (context, a, _) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _NeedlePainter(angle: a, lit: dir != null, active: active, hc: hc)),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter({required this.angle, required this.lit, required this.active, required this.hc});

  final double angle;
  final bool lit;
  final bool active;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final gold = hc ? Colors.white : Playful.sun;
    // Тело: метален прстен и темен бројчаник.
    canvas.drawCircle(c, r, Paint()
      ..shader = (hc
              ? const RadialGradient(colors: [Colors.black, Colors.black])
              : const RadialGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0B1E3A)]))
          .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = gold.withValues(alpha: active ? 1 : 0.6));
    // Ознаки за четирите насоки (точки = број на вибрации).
    const dirs = [('up', 0.0, 2), ('right', math.pi / 2, 3), ('down', math.pi, 4), ('left', -math.pi / 2, 1)];
    for (final (_, a, n) in dirs) {
      final dirV = Offset(math.sin(a), -math.cos(a));
      final perp = Offset(-dirV.dy, dirV.dx);
      for (var i = 0; i < n; i++) {
        final p = c + dirV * (r * 0.78) + perp * ((i - (n - 1) / 2) * 6);
        canvas.drawCircle(p, 2.2, Paint()..color = Colors.white.withValues(alpha: 0.75));
      }
    }
    // Иглата.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final len = r * 0.62;
    final wid = r * 0.16;
    final north = Path()
      ..moveTo(0, -len)
      ..lineTo(wid, 0)
      ..lineTo(-wid, 0)
      ..close();
    final south = Path()
      ..moveTo(0, len * 0.6)
      ..lineTo(wid, 0)
      ..lineTo(-wid, 0)
      ..close();
    canvas.drawPath(north, Paint()..color = hc ? const Color(0xFFFFFF00) : (lit ? const Color(0xFFEF4444) : const Color(0xFFEF4444).withValues(alpha: 0.55)));
    canvas.drawPath(south, Paint()..color = hc ? Colors.white : Colors.white.withValues(alpha: 0.8));
    canvas.restore();
    canvas.drawCircle(c, r * 0.1, Paint()..color = gold);
    if (lit && !hc) {
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Playful.sun.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter old) =>
      old.angle != angle || old.lit != lit || old.active != active || old.hc != hc;
}

/// Точки во аголот на копчето за насока: колку пати вибрира.
class DirectionPips extends StatelessWidget {
  const DirectionPips({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: hc ? Colors.black : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.7), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hc ? const Color(0xFFFFFF00) : Playful.sun,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
