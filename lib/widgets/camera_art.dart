import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/accessibility_utils.dart';
import 'playful_ui.dart';

/// Уметност за „Распознавање со камера“ - заштитен знак „Магичен објектив“:
///  * [CameraBokehBackdrop] - позадина од меки светла „боке“ (како кога
///    објективот не е изостриран) и сенка од бленда;
///  * [CameraBezel] - визирот како тело на фотоапарат: метален раб со
///    назабен прстен, шрафчиња и натпис;
///  * [LensOverlay] - во визирот: аглите што „дишат“ (изострување),
///    нишан во средина, REC светло, радар што кружи додека се бара,
///    одбројување по работ и аглите што се собираат кога е пронајдено;
///  * [ApertureShutterButton] - копче-бленда што се затвора и отвора.

class CameraBokehBackdrop extends StatefulWidget {
  const CameraBokehBackdrop({super.key, required this.tint});

  final Color tint;

  @override
  State<CameraBokehBackdrop> createState() => _CameraBokehBackdropState();
}

class _CameraBokehBackdropState extends State<CameraBokehBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40));

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
          decoration: const BoxDecoration(gradient: Playful.background),
          child: RepaintBoundary(
            child: CustomPaint(painter: _BokehPainter(_c, widget.tint), child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

class _BokehPainter extends CustomPainter {
  _BokehPainter(this.t, this.tint) : super(repaint: t);

  final Animation<double> t;
  final Color tint;

  static const _colors = [Color(0xFFFFC93C), Color(0xFFEA580C), Color(0xFF0D9488), Color(0xFF9333EA), Color(0xFF2563EB), Color(0xFFDB2777)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rnd = math.Random(5);
    // Меки кругови светлина што полека лебдат.
    for (var i = 0; i < 18; i++) {
      final bx = rnd.nextDouble(), by = rnd.nextDouble();
      final r = size.shortestSide * (0.05 + rnd.nextDouble() * 0.13);
      final phase = rnd.nextDouble() * math.pi * 2;
      final a = t.value * math.pi * 2 + phase;
      final c = Offset(size.width * bx + math.sin(a) * 26, size.height * by + math.cos(a * 0.7) * 20);
      final color = _colors[i % _colors.length];
      final alpha = 0.10 + 0.08 * (0.5 + 0.5 * math.sin(a * 1.3));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha * 1.6), color.withValues(alpha: alpha), color.withValues(alpha: 0)],
            stops: const [0.0, 0.7, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      // Тенок светол раб - како вистинско боке.
      canvas.drawCircle(c, r * 0.72, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: alpha * 0.6));
    }
    // Голема бленда во аголот (6 сечила), едвај видлива.
    final center = Offset(size.width * 0.92, size.height * 0.1);
    final radius = size.shortestSide * 0.42;
    final blade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(center, radius, blade);
    final rot = t.value * math.pi * 2 * 0.25;
    for (var k = 0; k < 6; k++) {
      final a = rot + k * math.pi / 3;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * radius;
      final p2 = center + Offset(math.cos(a + 2.1), math.sin(a + 2.1)) * radius * 0.45;
      canvas.drawLine(p1, p2, blade);
    }
    canvas.drawCircle(Offset(size.width * 0.12, size.height * 0.85), size.shortestSide * 0.6, Paint()
      ..shader = RadialGradient(colors: [tint.withValues(alpha: 0.25), tint.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: Offset(size.width * 0.12, size.height * 0.85), radius: size.shortestSide * 0.6)));
  }

  @override
  bool shouldRepaint(covariant _BokehPainter old) => old.tint != tint;
}

/// Визирот како тело на фотоапарат: метален раб, назабен прстен, шрафчиња
/// и мала плочка горе со името на режимот.
class CameraBezel extends StatelessWidget {
  const CameraBezel({super.key, required this.child, required this.color, required this.label, required this.icon});

  final Widget child;
  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    if (hc) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AccessibilityUtils.getContrastColor(context), width: 4),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: child),
      );
    }
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B5563), Color(0xFF111827), Color(0xFF374151), Color(0xFF0B0F17)],
          stops: [0.0, 0.45, 0.7, 1.0],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 1),
          const BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Назабениот прстен (како прстен за фокус на објектив).
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _KnurlPainter(color)))),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
            ),
          ),
          // Шрафчиња во аглите.
          for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
            Align(
              alignment: a,
              child: Transform.translate(
                offset: Offset(a.x * 3, a.y * 3),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(colors: [Color(0xFFE5E7EB), Color(0xFF6B7280)]),
                    border: Border.all(color: const Color(0xFF1F2937), width: 1),
                  ),
                ),
              ),
            ),
          // Плочката со режимот горе на средина.
          Align(
            alignment: Alignment.topCenter,
            child: Transform.translate(
              offset: const Offset(0, -19),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(label.toUpperCase(), style: Playful.title(13, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KnurlPainter extends CustomPainter {
  _KnurlPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(26));
    final metric = (Path()..addRRect(rr)).computeMetrics().first;
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.4;
    for (var d = 0.0; d < metric.length; d += 7) {
      final tan = metric.getTangentForOffset(d);
      if (tan == null) continue;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      canvas.drawLine(tan.position + n * 1.5, tan.position + n * 5.5, tick);
    }
    // Тенка обоена линија во бојата на режимот.
    canvas.drawRRect(rr.deflate(6), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _KnurlPainter old) => old.color != color;
}

/// Што се црта преку камерата.
class LensOverlay extends StatefulWidget {
  const LensOverlay({
    super.key,
    required this.color,
    this.busy = false,
    this.searching = false,
    this.searchFraction = 1,
    this.found = false,
  });

  /// Бојата на режимот.
  final Color color;

  /// Анализа во тек (едно сликање).
  final bool busy;

  /// Барање во тек (радар + одбројување).
  final bool searching;

  /// Колку време останува од барањето (1 = почеток, 0 = крај).
  final double searchFraction;

  /// Поимот е пронајден - аглите се собираат кон средината, зелено.
  final bool found;

  @override
  State<LensOverlay> createState() => _LensOverlayState();
}

class _LensOverlayState extends State<LensOverlay> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _lock = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LensOverlay old) {
    super.didUpdateWidget(old);
    if (widget.found && !old.found) {
      _lock.forward(from: 0);
    } else if (!widget.found && old.found) {
      _lock.value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final reduce = Playful.reduceMotion(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _lock]),
          builder: (context, _) => CustomPaint(
            painter: _LensPainter(
              t: _loop.value,
              lock: widget.found ? (reduce ? 1 : Curves.easeOutBack.transform(_lock.value)) : 0,
              color: widget.color,
              busy: widget.busy,
              searching: widget.searching,
              fraction: widget.searchFraction,
              hc: hc,
              reduce: reduce,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _LensPainter extends CustomPainter {
  _LensPainter({
    required this.t,
    required this.lock,
    required this.color,
    required this.busy,
    required this.searching,
    required this.fraction,
    required this.hc,
    required this.reduce,
  });

  final double t;
  final double lock;
  final Color color;
  final bool busy;
  final bool searching;
  final double fraction;
  final bool hc;
  final bool reduce;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final gold = hc ? Colors.white : Playful.sun;
    final green = hc ? const Color(0xFFFFFF00) : const Color(0xFF22C55E);

    // Радар: светол клин што кружи околу средината додека се бара.
    if (searching && !hc && !reduce) {
      final r = size.longestSide * 0.75;
      final ang = t * math.pi * 2;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(ang);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = SweepGradient(
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.0), color.withValues(alpha: 0.32)],
            stops: const [0.0, 0.8, 1.0],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
      canvas.restore();
      // Кругови на радарот.
      for (var k = 1; k <= 3; k++) {
        canvas.drawCircle(c, size.shortestSide * 0.16 * k, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.18));
      }
    }

    // Аглите: „дишат“ (изострување); кога е пронајдено - се собираат кон
    // средината и стануваат зелени.
    final breathe = reduce ? 0.0 : math.sin(t * math.pi * 2 * (busy || searching ? 2 : 1)) * 5;
    const inset0 = 18.0;
    final lockInset = math.min(size.width, size.height) * 0.28;
    final inset = inset0 + breathe + (lockInset - inset0) * lock;
    final len = (size.shortestSide * 0.14).clamp(18.0, 48.0);
    final corner = Paint()
      ..color = Color.lerp(gold, green, lock.clamp(0.0, 1.0))!
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final l = inset, tp = inset * (size.height / size.width).clamp(0.6, 1.4), r = size.width - inset, b = size.height - tp;
    for (final (p, dx, dy) in [(Offset(l, tp), 1.0, 1.0), (Offset(r, tp), -1.0, 1.0), (Offset(l, b), 1.0, -1.0), (Offset(r, b), -1.0, -1.0)]) {
      canvas.drawLine(p, p + Offset(dx * len, 0), corner);
      canvas.drawLine(p, p + Offset(0, dy * len), corner);
    }

    // Нишан во средина.
    final reticle = Paint()
      ..color = (lock > 0 ? green : Colors.white).withValues(alpha: hc ? 1 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rr = 14.0 + (busy ? 4 * math.sin(t * math.pi * 4).abs() : 0);
    canvas.drawCircle(c, rr, reticle);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * (rr + 4), c + d * (rr + 14), reticle);
    }

    // REC светло горе лево (трепка додека се слика / бара).
    if (busy || searching) {
      final on = reduce || (t * 4).floor().isEven;
      final dot = Offset(34, 34);
      if (on) {
        canvas.drawCircle(dot, 8, Paint()..color = hc ? const Color(0xFFFFFF00) : const Color(0xFFEF4444));
        if (!hc) {
          canvas.drawCircle(dot, 13, Paint()
            ..color = const Color(0xFFEF4444).withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        }
      }
      final tpainter = TextPainter(
        text: TextSpan(text: 'REC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, shadows: hc ? null : const [Shadow(blurRadius: 4)])),
        textDirection: TextDirection.ltr,
      )..layout();
      tpainter.paint(canvas, dot + const Offset(14, -9));
      tpainter.dispose();
    }

    // Одбројување на барањето: светла линија по работ што се скратува.
    if (searching) {
      final rect = (Offset.zero & size).deflate(4);
      final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * fraction.clamp(0.0, 1.0));
      canvas.drawPath(part, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = hc ? const Color(0xFFFFFF00) : Color.lerp(const Color(0xFFEF4444), gold, fraction)!);
    }
  }

  @override
  bool shouldRepaint(covariant _LensPainter old) => true;
}

/// Копче-бленда: шест сечила што се затвораат и отвораат додека се
/// анализира; наоколу златен прстен.
class ApertureShutterButton extends StatefulWidget {
  const ApertureShutterButton({super.key, required this.label, required this.onTap, required this.color, this.busy = false, this.size = 96, this.icon = Icons.camera_alt_rounded});

  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool busy;
  final double size;
  final IconData icon;

  @override
  State<ApertureShutterButton> createState() => _ApertureShutterButtonState();
}

class _ApertureShutterButtonState extends State<ApertureShutterButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ApertureShutterButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.busy && !Playful.reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final s = widget.size;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PressableScale(
              enabled: widget.onTap != null,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hc ? Colors.black : null,
                    gradient: hc ? null : const RadialGradient(colors: [Color(0xFF374151), Color(0xFF0B0F17)]),
                    border: Border.all(color: hc ? Colors.white : Playful.sun, width: 5),
                    boxShadow: hc ? null : [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 2)],
                  ),
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, child) => CustomPaint(
                      painter: _AperturePainter(close: Curves.easeInOut.transform(_c.value), color: widget.color, hc: hc),
                      child: child,
                    ),
                    child: Center(
                      child: Icon(widget.icon, size: s * 0.34, color: hc ? const Color(0xFFFFFF00) : Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(widget.label, textAlign: TextAlign.center, style: Playful.title(17 * 1.4, color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _AperturePainter extends CustomPainter {
  _AperturePainter({required this.close, required this.color, required this.hc});

  final double close;
  final Color color;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    // Шест сечила; отворот (дупката во средина) се намалува со [close].
    final hole = r * (0.55 - 0.35 * close);
    final rot = close * 0.9;
    for (var k = 0; k < 6; k++) {
      final a = rot + k * math.pi / 3;
      final p0 = c + Offset(math.cos(a), math.sin(a)) * hole;
      final p1 = c + Offset(math.cos(a + math.pi / 3), math.sin(a + math.pi / 3)) * hole;
      final far = c + Offset(math.cos(a + 0.5), math.sin(a + 0.5)) * r * 1.6;
      final far2 = c + Offset(math.cos(a - 0.6), math.sin(a - 0.6)) * r * 1.6;
      final blade = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(far.dx, far.dy)
        ..lineTo(far2.dx, far2.dy)
        ..close();
      final shade = k.isEven ? 0.0 : 0.12;
      canvas.drawPath(
        blade,
        Paint()..color = hc ? (k.isEven ? Colors.black : const Color(0xFF222222)) : Color.lerp(color, Colors.black, 0.45 + shade)!,
      );
      canvas.drawPath(blade, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: hc ? 0.9 : 0.35));
    }
    canvas.restore();
    // Стаклен одблесок.
    if (!hc) {
      canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
  }

  @override
  bool shouldRepaint(covariant _AperturePainter old) => old.close != close || old.color != color || old.hc != hc;
}
