import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Илустрации и „хартиен“ изглед за „Тајните на Брајовата азбука“.
///
/// Идејата: работна маса на Луј Брај ноќе - темна маса, стара хартија со
/// испакнати (втиснати) точки, плоча и шило, книги во кожен повез и восочни
/// печати. Сè е нацртано со код (без слики), а во висок контраст сè станува
/// црно со бели/жолти контури.
abstract final class LabPalette {
  static const Color desk = Color(0xFF0E1622);
  static const Color deskLine = Color(0xFF1C2A3B);
  static const Color paper = Color(0xFFFBF3E1);
  static const Color paperDeep = Color(0xFFEFDFBE);
  static const Color paperEdge = Color(0xFFD9C29A);
  static const Color ink = Color(0xFF2B1D12);
  static const Color inkSoft = Color(0xFF5A4431);
  static const Color sepia = Color(0xFF9A5B22);
  static const Color dot = Color(0xFFC07A2C);
  static const Color dotAdded = Color(0xFF0F8A7E);
  static const Color gold = Color(0xFFE9BC55);
  static const Color goldLight = Color(0xFFFFE6A3);
  static const Color leather = Color(0xFF5E1A2A);
  static const Color leatherDark = Color(0xFF3A0F1A);
  static const Color leatherBlue = Color(0xFF1D3557);
  static const Color seal = Color(0xFFB3261E);
  static const Color hcYellow = Color(0xFFFFFF00);
}

// ---------------------------------------------------------------------------
// Позадина: ноќна работна маса со едвај видливи втиснати точки.
// ---------------------------------------------------------------------------

class LabDeskBackdrop extends StatelessWidget {
  const LabDeskBackdrop({super.key, required this.hc, required this.child});
  final bool hc;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (hc) return ColoredBox(color: Colors.black, child: child);
    return CustomPaint(painter: _DeskPainter(), child: child);
  }
}

class _DeskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.6),
          radius: 1.3,
          colors: [Color(0xFF1B2B40), LabPalette.desk],
        ).createShader(rect),
    );
    // Мрежа од Брајови клетки - многу тивко, како шара на тапет.
    const cellW = 46.0;
    const cellH = 64.0;
    final faint = Paint()..color = const Color(0x14FFFFFF);
    final lit = Paint()..color = const Color(0x22E9BC55);
    var seed = 7;
    for (var y = 12.0; y < size.height; y += cellH) {
      for (var x = 12.0; x < size.width; x += cellW) {
        for (var i = 0; i < 6; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          final on = seed % 5 == 0;
          final dx = x + (i ~/ 3) * 14;
          final dy = y + (i % 3) * 14;
          canvas.drawCircle(Offset(dx, dy), on ? 3.2 : 2.2, on ? lit : faint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DeskPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Хартија: топла боја, влакна, свиткан агол и мека сенка.
// ---------------------------------------------------------------------------

class PaperPanel extends StatelessWidget {
  const PaperPanel({
    super.key,
    required this.hc,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.foldCorner = true,
    this.radius = 22,
    this.borderColor,
  });

  final bool hc;
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final bool foldCorner;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        color: hc ? Colors.black : null,
        gradient: hc
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [LabPalette.paper, LabPalette.paperDeep],
              ),
        border: Border.all(
          color: hc ? Colors.white : (borderColor ?? LabPalette.paperEdge),
          width: hc ? 2 : 1.5,
        ),
        boxShadow: hc
            ? null
            : const [
                BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
              ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: CustomPaint(
          painter: hc ? null : _PaperGrainPainter(foldCorner: foldCorner),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _PaperGrainPainter extends CustomPainter {
  _PaperGrainPainter({required this.foldCorner});
  final bool foldCorner;

  @override
  void paint(Canvas canvas, Size size) {
    // Ситни влакна на хартијата.
    final fiber = Paint()
      ..color = const Color(0x12704A20)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final r = math.Random(size.width.round() * 31 + size.height.round());
    final count = (size.width * size.height / 2600).clamp(20, 400).toInt();
    for (var i = 0; i < count; i++) {
      final p = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      final a = r.nextDouble() * math.pi;
      final l = 3 + r.nextDouble() * 7;
      canvas.drawLine(p, p + Offset(math.cos(a), math.sin(a)) * l, fiber);
    }
    // Потемнети рабови (стара хартија).
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.0,
          colors: [Color(0x00000000), Color(0x14704A20)],
          stops: [0.7, 1.0],
        ).createShader(rect),
    );
    if (foldCorner && size.width > 120 && size.height > 80) {
      const f = 26.0;
      final corner = Path()
        ..moveTo(size.width - f, 0)
        ..lineTo(size.width, f)
        ..lineTo(size.width - f, f)
        ..close();
      canvas.drawPath(corner, Paint()..color = const Color(0xFFE3CC9F));
      canvas.drawPath(
        Path()
          ..moveTo(size.width - f, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, f)
          ..close(),
        Paint()..color = LabPalette.desk.withValues(alpha: 0.9),
      );
      canvas.drawLine(
        Offset(size.width - f, 0),
        Offset(size.width, f),
        Paint()
          ..color = const Color(0x55704A20)
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGrainPainter oldDelegate) => oldDelegate.foldCorner != foldCorner;
}

// ---------------------------------------------------------------------------
// Втисната (испакната) точка.
// ---------------------------------------------------------------------------

class EmbossedDot extends StatelessWidget {
  const EmbossedDot({
    super.key,
    required this.size,
    required this.active,
    required this.hc,
    this.added = false,
    this.number,
    this.strong = false,
  });

  final double size;
  final bool active;
  final bool added;
  final bool hc;

  /// Посилен контраст: темни (мастило) точки и јасно оцртани празни места.
  final bool strong;

  /// Бројот на точката (1-6), прикажан внатре - кај интерактивната клетка.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final Color base = added
        ? (strong ? const Color(0xFF00695C) : LabPalette.dotAdded)
        : (strong ? const Color(0xFF3A2212) : LabPalette.dot);
    final BoxDecoration deco;
    if (hc) {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: active ? (added ? Colors.white : LabPalette.hcYellow) : Colors.black,
        border: Border.all(color: Colors.white, width: 2),
      );
    } else if (active) {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [Color.lerp(base, Colors.white, strong ? 0.3 : 0.45)!, base, Color.lerp(base, Colors.black, 0.35)!],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(2, 3)),
          BoxShadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: 2, offset: const Offset(-1, -1)),
        ],
      );
    } else {
      // Празно место - само мала вдлабнатина во хартијата.
      deco = BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0.3, 0.35),
          colors: [LabPalette.paper, Color(0xFFE2CFA6)],
        ),
        border: Border.all(
          color: strong ? const Color(0xAA5A4431) : const Color(0x55704A20),
          width: strong ? math.max(1.5, size * 0.06) : 1.2,
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: deco,
      child: number == null
          ? null
          : Text(
              '$number',
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                color: hc
                    ? (active ? Colors.black : Colors.white)
                    : (active ? Colors.white : LabPalette.inkSoft),
              ),
            ),
    );
  }
}

/// Цела Брајова клетка (2 x 3) втисната во парче хартија.
class EmbossedCell extends StatelessWidget {
  const EmbossedCell({
    super.key,
    required this.dots,
    required this.hc,
    this.added = const {},
    this.dotSize = 40,
    this.onTapDot,
    this.showNumbers = false,
    this.dotLabel,
    this.strong = false,
  });

  final List<int> dots;
  final bool strong;
  final Set<int> added;
  final bool hc;
  final double dotSize;
  final void Function(int dot)? onTapDot;
  final bool showNumbers;

  /// Опис за читач на екран за секоја точка (кај интерактивната клетка).
  final String Function(int dot)? dotLabel;

  @override
  Widget build(BuildContext context) {
    final gap = dotSize * 0.22;
    Widget dotAt(int n) {
      final d = EmbossedDot(
        size: dotSize,
        active: dots.contains(n),
        added: added.contains(n),
        hc: hc,
        number: showNumbers ? n : null,
        strong: strong,
      );
      final padded = Padding(padding: EdgeInsets.all(gap / 2), child: d);
      final Widget tappable = onTapDot == null
          ? padded
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onTapDot!(n), child: padded);
      if (dotLabel == null) return tappable;
      return Semantics(button: onTapDot != null, label: dotLabel!(n), child: ExcludeSemantics(child: tappable));
    }

    return Container(
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(dotSize * 0.45),
        color: hc ? Colors.black : null,
        gradient: hc
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFAEE), LabPalette.paperDeep],
              ),
        border: Border.all(color: hc ? Colors.white : LabPalette.paperEdge, width: hc ? 2 : 1.5),
        boxShadow: hc
            ? null
            : const [BoxShadow(color: Color(0x33704A20), blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < 3; row++)
            Row(mainAxisSize: MainAxisSize.min, children: [dotAt(row + 1), dotAt(row + 4)]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Восочен печат со број или знак.
// ---------------------------------------------------------------------------

class WaxSeal extends StatelessWidget {
  const WaxSeal({super.key, required this.label, required this.hc, this.size = 64, this.color = LabPalette.seal});
  final String label;
  final bool hc;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SealPainter(color: color, hc: hc),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * 0.18),
            child: FittedBox(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: hc ? LabPalette.hcYellow : LabPalette.goldLight,
                  shadows: hc ? null : const [Shadow(color: Color(0x88000000), blurRadius: 2, offset: Offset(1, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter({required this.color, required this.hc});
  final Color color;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    const bumps = 14;
    for (var i = 0; i <= bumps * 4; i++) {
      final a = i / (bumps * 4) * math.pi * 2;
      final rr = r * (0.9 + 0.08 * math.sin(a * bumps));
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    if (hc) {
      canvas.drawPath(path, Paint()..color = Colors.black);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [Color.lerp(color, Colors.white, 0.25)!, color, Color.lerp(color, Colors.black, 0.4)!],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.66,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06,
    );
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) => oldDelegate.color != color || oldDelegate.hc != hc;
}

// ---------------------------------------------------------------------------
// Медалјон со портрет на Луј Брај (стилизиран цртеж, сепија).
// ---------------------------------------------------------------------------

class LouisBraillePortrait extends StatelessWidget {
  const LouisBraillePortrait({super.key, required this.size, required this.hc});
  final double size;
  final bool hc;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PortraitPainter(hc)),
      );
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.hc);
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2;
    final line = hc ? Colors.white : LabPalette.ink;
    final accent = hc ? LabPalette.hcYellow : LabPalette.gold;

    // Златна рамка со точки (како Брајов натпис наоколу).
    canvas.drawCircle(c, r, Paint()..color = hc ? Colors.black : LabPalette.leatherDark);
    canvas.drawCircle(
      c,
      r * 0.97,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
    for (var i = 0; i < 36; i++) {
      if (i % 4 == 3) continue;
      final a = i / 36 * math.pi * 2;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.86, r * 0.03, Paint()..color = accent);
    }
    // Внатрешен круг - сепија хартија.
    final inner = r * 0.76;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..shader = (hc
                ? const RadialGradient(colors: [Colors.black, Colors.black])
                : const RadialGradient(
                    center: Alignment(-0.2, -0.3),
                    colors: [Color(0xFFF6E7C6), Color(0xFFD8B98A)],
                  ))
            .createShader(Rect.fromCircle(center: c, radius: inner)),
    );

    final skin = hc ? Colors.black : const Color(0xFFF1D9B5);
    final coat = hc ? Colors.black : const Color(0xFF3B2A20);
    final hair = hc ? Colors.black : const Color(0xFF4A3220);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Капут и јака.
    final shoulders = Path()
      ..moveTo(c.dx - inner, c.dy + inner)
      ..quadraticBezierTo(c.dx - inner * 0.75, c.dy + inner * 0.28, c.dx - inner * 0.2, c.dy + inner * 0.3)
      ..lineTo(c.dx + inner * 0.2, c.dy + inner * 0.3)
      ..quadraticBezierTo(c.dx + inner * 0.75, c.dy + inner * 0.28, c.dx + inner, c.dy + inner)
      ..close();
    canvas.drawPath(shoulders, Paint()..color = coat);
    canvas.drawPath(shoulders, stroke);
    // Бела кравата.
    final cravat = Path()
      ..moveTo(c.dx - inner * 0.2, c.dy + inner * 0.3)
      ..lineTo(c.dx, c.dy + inner * 0.62)
      ..lineTo(c.dx + inner * 0.2, c.dy + inner * 0.3)
      ..close();
    canvas.drawPath(cravat, Paint()..color = hc ? Colors.black : Colors.white);
    canvas.drawPath(cravat, stroke);
    // Врат.
    canvas.drawRect(
      Rect.fromCenter(center: Offset(c.dx, c.dy + inner * 0.2), width: inner * 0.26, height: inner * 0.24),
      Paint()..color = skin,
    );
    // Глава.
    final head = Rect.fromCenter(center: Offset(c.dx, c.dy - inner * 0.18), width: inner * 0.78, height: inner * 0.95);
    canvas.drawOval(head, Paint()..color = skin);
    canvas.drawOval(head, stroke);
    // Коса (кадрава, кратка, со шишки на страна).
    final hairPath = Path()
      ..moveTo(head.left - inner * 0.02, head.center.dy)
      ..quadraticBezierTo(head.left - inner * 0.08, head.top - inner * 0.02, head.center.dx, head.top - inner * 0.06)
      ..quadraticBezierTo(head.right + inner * 0.1, head.top, head.right + inner * 0.02, head.center.dy)
      ..quadraticBezierTo(head.right - inner * 0.08, head.top + inner * 0.12, head.center.dx + inner * 0.05, head.top + inner * 0.16)
      ..quadraticBezierTo(head.left + inner * 0.08, head.top + inner * 0.1, head.left - inner * 0.02, head.center.dy)
      ..close();
    canvas.drawPath(hairPath, Paint()..color = hair);
    canvas.drawPath(hairPath, stroke);
    // Затворени очи (Луј Брај бил слеп) - мирни лакови.
    final eyeY = head.center.dy + inner * 0.02;
    for (final dx in [-inner * 0.15, inner * 0.15]) {
      final e = Path()
        ..moveTo(c.dx + dx - inner * 0.08, eyeY)
        ..quadraticBezierTo(c.dx + dx, eyeY + inner * 0.05, c.dx + dx + inner * 0.08, eyeY);
      canvas.drawPath(e, stroke);
    }
    // Нос и мала насмевка.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, eyeY + inner * 0.04)
        ..quadraticBezierTo(c.dx - inner * 0.05, eyeY + inner * 0.16, c.dx + inner * 0.02, eyeY + inner * 0.18),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - inner * 0.09, eyeY + inner * 0.27)
        ..quadraticBezierTo(c.dx, eyeY + inner * 0.32, c.dx + inner * 0.09, eyeY + inner * 0.27),
      stroke,
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035,
    );
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter oldDelegate) => oldDelegate.hc != hc;
}

// ---------------------------------------------------------------------------
// Мали илустрации за секој дел: плоча и шило, ѕвездена клетка, брајева
// машина, книга.
// ---------------------------------------------------------------------------

enum LabArtKind { slate, sparkle, brailler, book, letters, numbers, signs }

class LabArt extends StatelessWidget {
  const LabArt({super.key, required this.kind, required this.size, required this.hc});
  final LabArtKind kind;
  final double size;
  final bool hc;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LabArtPainter(kind, hc)),
      );
}

class _LabArtPainter extends CustomPainter {
  _LabArtPainter(this.kind, this.hc);
  final LabArtKind kind;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = hc ? Colors.white : LabPalette.ink;
    final gold = hc ? LabPalette.hcYellow : LabPalette.gold;
    final dotC = hc ? LabPalette.hcYellow : LabPalette.dot;
    final paperC = hc ? Colors.black : LabPalette.paper;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void dotAt(Offset p, double r, {bool on = true}) {
      canvas.drawCircle(p, r, Paint()..color = on ? dotC : (hc ? Colors.black : const Color(0xFFDCC69B)));
      if (!on) canvas.drawCircle(p, r, stroke..strokeWidth = s * 0.015);
      stroke.strokeWidth = s * 0.035;
    }

    switch (kind) {
      case LabArtKind.slate:
        // Метална плоча со прозорчиња и дрвено шило.
        final plate = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.06, s * 0.2, s * 0.72, s * 0.55),
          Radius.circular(s * 0.06),
        );
        canvas.drawRRect(plate, Paint()..color = hc ? Colors.black : const Color(0xFF9AA5B1));
        canvas.drawRRect(plate, stroke);
        for (var row = 0; row < 2; row++) {
          for (var col = 0; col < 3; col++) {
            final win = RRect.fromRectAndRadius(
              Rect.fromLTWH(s * (0.12 + col * 0.21), s * (0.27 + row * 0.24), s * 0.16, s * 0.19),
              Radius.circular(s * 0.03),
            );
            canvas.drawRRect(win, Paint()..color = paperC);
            canvas.drawRRect(win, stroke..strokeWidth = s * 0.02);
            stroke.strokeWidth = s * 0.035;
            if ((row + col) % 2 == 0) {
              dotAt(win.outerRect.topLeft + Offset(s * 0.05, s * 0.05), s * 0.025);
              dotAt(win.outerRect.topLeft + Offset(s * 0.11, s * 0.1), s * 0.025);
            }
          }
        }
        // Шило.
        canvas.save();
        canvas.translate(s * 0.78, s * 0.62);
        canvas.rotate(-0.7);
        final handle = RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.06, -s * 0.34, s * 0.12, s * 0.22), Radius.circular(s * 0.06));
        canvas.drawRRect(handle, Paint()..color = hc ? Colors.black : LabPalette.sepia);
        canvas.drawRRect(handle, stroke);
        canvas.drawLine(Offset(0, -s * 0.12), Offset(0, s * 0.04), stroke);
        canvas.restore();
        break;
      case LabArtKind.sparkle:
        // Клетка што „оживува“ - точки и искри.
        final cell = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.22, s * 0.12, s * 0.46, s * 0.74), Radius.circular(s * 0.1));
        canvas.drawRRect(cell, Paint()..color = paperC);
        canvas.drawRRect(cell, stroke);
        const on = [true, false, true, true, true, false];
        for (var i = 0; i < 6; i++) {
          final p = Offset(s * (0.35 + (i ~/ 3) * 0.2), s * (0.26 + (i % 3) * 0.23));
          dotAt(p, s * 0.06, on: on[i]);
        }
        final spark = Paint()
          ..color = gold
          ..strokeWidth = s * 0.04
          ..strokeCap = StrokeCap.round;
        for (final p in [Offset(s * 0.12, s * 0.2), Offset(s * 0.86, s * 0.32), Offset(s * 0.82, s * 0.82)]) {
          canvas.drawLine(p - Offset(s * 0.06, 0), p + Offset(s * 0.06, 0), spark);
          canvas.drawLine(p - Offset(0, s * 0.06), p + Offset(0, s * 0.06), spark);
        }
        break;
      case LabArtKind.brailler:
        // Брајева машина за пишување: лист хартија и шест копчиња.
        final sheet = Rect.fromLTWH(s * 0.24, s * 0.06, s * 0.52, s * 0.36);
        canvas.drawRect(sheet, Paint()..color = paperC);
        canvas.drawRect(sheet, stroke..strokeWidth = s * 0.025);
        stroke.strokeWidth = s * 0.035;
        for (var i = 0; i < 4; i++) {
          dotAt(Offset(sheet.left + s * (0.09 + i * 0.11), sheet.top + s * 0.1), s * 0.022);
          if (i.isEven) dotAt(Offset(sheet.left + s * (0.09 + i * 0.11), sheet.top + s * 0.18), s * 0.022);
        }
        final body = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.06, s * 0.36, s * 0.88, s * 0.48), Radius.circular(s * 0.1));
        canvas.drawRRect(body, Paint()..color = hc ? Colors.black : const Color(0xFF6B7F99));
        canvas.drawRRect(body, stroke);
        for (var i = 0; i < 6; i++) {
          final x = s * (0.17 + i * 0.13 + (i >= 3 ? 0.03 : 0));
          canvas.drawCircle(Offset(x, s * 0.56), s * 0.045, Paint()..color = gold);
          canvas.drawCircle(Offset(x, s * 0.56), s * 0.045, stroke..strokeWidth = s * 0.018);
          stroke.strokeWidth = s * 0.035;
        }
        final space = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.36, s * 0.68, s * 0.28, s * 0.08), Radius.circular(s * 0.04));
        canvas.drawRRect(space, Paint()..color = gold);
        canvas.drawRRect(space, stroke..strokeWidth = s * 0.018);
        break;
      case LabArtKind.book:
      case LabArtKind.letters:
      case LabArtKind.numbers:
      case LabArtKind.signs:
        // Отворена книга со точки на страниците.
        final left = Path()
          ..moveTo(s * 0.5, s * 0.25)
          ..quadraticBezierTo(s * 0.3, s * 0.15, s * 0.06, s * 0.22)
          ..lineTo(s * 0.06, s * 0.82)
          ..quadraticBezierTo(s * 0.3, s * 0.75, s * 0.5, s * 0.85)
          ..close();
        final right = Path()
          ..moveTo(s * 0.5, s * 0.25)
          ..quadraticBezierTo(s * 0.7, s * 0.15, s * 0.94, s * 0.22)
          ..lineTo(s * 0.94, s * 0.82)
          ..quadraticBezierTo(s * 0.7, s * 0.75, s * 0.5, s * 0.85)
          ..close();
        for (final p in [left, right]) {
          canvas.drawPath(p, Paint()..color = paperC);
          canvas.drawPath(p, stroke);
        }
        // Што пишува на страниците зависи од делот.
        final glyph = switch (kind) {
          LabArtKind.numbers => '12',
          LabArtKind.signs => '?!',
          LabArtKind.letters => 'AБ',
          _ => '',
        };
        if (glyph.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: glyph,
              style: TextStyle(fontSize: s * 0.26, fontWeight: FontWeight.w900, color: hc ? Colors.white : LabPalette.sepia),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(s * 0.28 - tp.width / 2, s * 0.52 - tp.height / 2));
        }
        for (var i = 0; i < 6; i++) {
          dotAt(Offset(s * (0.64 + (i ~/ 3) * 0.14), s * (0.36 + (i % 3) * 0.14)), s * 0.035, on: i != 1 && i != 5);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LabArtPainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.hc != hc;
}

// ---------------------------------------------------------------------------
// Корица на книга во кожен повез (за трите големи теми).
// ---------------------------------------------------------------------------

class LeatherCover extends StatelessWidget {
  const LeatherCover({
    super.key,
    required this.hc,
    required this.child,
    this.color = LabPalette.leather,
    this.open = false,
  });

  final bool hc;
  final Widget child;
  final Color color;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(18);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        color: hc ? Colors.black : null,
        gradient: hc
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(color, Colors.white, 0.08)!, color, Color.lerp(color, Colors.black, 0.45)!],
              ),
        border: Border.all(
          color: hc ? (open ? LabPalette.hcYellow : Colors.white) : LabPalette.gold.withValues(alpha: open ? 1 : 0.7),
          width: open ? 3 : 2,
        ),
        boxShadow: hc
            ? null
            : const [BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Stack(
        children: [
          if (!hc)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: LabPalette.gold.withValues(alpha: 0.45), width: 1.2),
                  ),
                ),
              ),
            ),
          // Рбет на книгата.
          if (!hc)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 14,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                    gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent]),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Ред Брајови точки што пишуваат збор (пр. „BRAILLE“) - украс.
class BrailleWordStrip extends StatelessWidget {
  const BrailleWordStrip({super.key, required this.cells, required this.hc, this.dotSize = 9});
  final List<List<int>> cells;
  final bool hc;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final on = hc ? LabPalette.hcYellow : LabPalette.dot;
    final off = hc ? Colors.white24 : const Color(0x33704A20);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: dotSize * 1.6,
      runSpacing: dotSize,
      children: [
        for (final cell in cells)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < 3; row++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in [row + 1, row + 4])
                      Container(
                        width: dotSize,
                        height: dotSize,
                        margin: EdgeInsets.all(dotSize * 0.22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cell.contains(d) ? on : off,
                          boxShadow: cell.contains(d) && !hc
                              ? const [BoxShadow(color: Color(0x55000000), blurRadius: 2, offset: Offset(1, 1))]
                              : null,
                        ),
                      ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}