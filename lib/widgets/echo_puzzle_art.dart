import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/accessibility_utils.dart';
import 'playful_ui.dart';

/// Уметност за „Меморија на звуци“ - „Ехо сложувалка“:
///  * [PuzzleEdges] / [puzzlePath] - делче од сложувалка со јазичиња
///    (+1), вдлабнатини (-1) или рамен раб (0). Двете делчиња од ист пар
///    се вклопуваат: десниот раб на првото (јазиче) влегува во левиот раб
///    на второто (вдлабнатина), а останатите рабови се обратни;
///  * [PuzzlePiece] - делчето: затворено (задна страна со нота) или
///    отворено (сликичка + боја), со бранови за ехо;
///  * [GardenScene] - „заспаната градина“ што се буди со секој пар.

/// Рабовите на едно делче: горе, десно, долу, лево (+1 јазиче, -1 вдлабнатина).
class PuzzleEdges {
  const PuzzleEdges(this.top, this.right, this.bottom, this.left);

  final int top, right, bottom, left;

  /// Рабовите на двете делчиња од парот [pair] - секој пар со свој облик.
  static (PuzzleEdges, PuzzleEdges) forPair(int pair) {
    final t = (pair & 1) == 0 ? 1 : -1;
    final b = (pair & 2) == 0 ? -1 : 1;
    final l = (pair & 4) == 0 ? 1 : -1;
    return (PuzzleEdges(t, 1, b, l), PuzzleEdges(-t, -l, -b, -1));
  }
}

/// Патеката на делчето во правоаголник [size]; телото е вовлечено за
/// [tab] од секоја страна (таму излегуваат јазичињата).
Path puzzlePath(Size size, PuzzleEdges e, {double tabRatio = 0.2, bool square = false}) {
  final tab = math.min(size.width, size.height) * tabRatio;
  final l = tab, t = tab, r = size.width - tab, b = size.height - tab;
  final p = Path()..moveTo(l, t);

  // Еден раб од [a] до [c]; [n] = нормала нанадвор (единечен вектор).
  void edge(Offset a, Offset c, Offset n, int kind) {
    if (kind == 0) {
      p.lineTo(c.dx, c.dy);
      return;
    }
    final d = c - a;
    final len = d.distance;
    final u = d / len;
    final out = n * (tab * 0.95 * kind);
    Offset at(double f) => a + u * (len * f);
    final n1 = at(0.36), n2 = at(0.64);
    p.lineTo(n1.dx, n1.dy);
    if (square) {
      final a1 = n1 + out, a2 = n2 + out;
      p
        ..lineTo(a1.dx, a1.dy)
        ..lineTo(a2.dx, a2.dy)
        ..lineTo(n2.dx, n2.dy);
    } else {
      // Заоблено јазиче (како печурка): стеснување, па круг.
      final neck1 = at(0.40) + out * 0.25, neck2 = at(0.60) + out * 0.25;
      final top1 = at(0.30) + out * 1.0, top2 = at(0.70) + out * 1.0;
      p
        ..cubicTo(neck1.dx, neck1.dy, top1.dx, top1.dy, at(0.5).dx + out.dx, at(0.5).dy + out.dy)
        ..cubicTo(top2.dx, top2.dy, neck2.dx, neck2.dy, n2.dx, n2.dy);
    }
    p.lineTo(c.dx, c.dy);
  }

  edge(Offset(l, t), Offset(r, t), const Offset(0, -1), e.top);
  edge(Offset(r, t), Offset(r, b), const Offset(1, 0), e.right);
  edge(Offset(r, b), Offset(l, b), const Offset(0, 1), e.bottom);
  edge(Offset(l, b), Offset(l, t), const Offset(-1, 0), e.left);
  return p..close();
}

/// Едно делче од сложувалката.
class PuzzlePiece extends StatelessWidget {
  const PuzzlePiece({
    super.key,
    required this.edges,
    required this.open,
    required this.emoji,
    required this.label,
    required this.color,
    required this.accent,
    this.square = false,
    this.matched = false,
    this.echo = 0,
    this.wrong = false,
  });

  final PuzzleEdges edges;
  final bool open;
  final String emoji;
  final String label;
  final Color color;
  final Color accent;
  final bool square;
  final bool matched;

  /// 0..1 - бранови на ехо (партнерот одговара); 0 = без бранови.
  final double echo;

  /// Погрешен пар - црвен раб.
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final tab = math.min(size.width, size.height) * 0.2;
      final inner = Rect.fromLTRB(tab, tab, size.width - tab, size.height - tab);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PiecePainter(
                edges: edges,
                square: square,
                open: open,
                color: color,
                accent: accent,
                matched: matched,
                wrong: wrong,
                echo: echo,
                hc: hc,
              ),
            ),
          ),
          Positioned.fromRect(
            rect: inner,
            child: Padding(
              padding: EdgeInsets.all(inner.shortestSide * 0.06),
              child: open
                  ? Column(
                      children: [
                        Expanded(
                          child: FittedBox(
                            child: Text(emoji, style: const TextStyle(fontSize: 64, height: 1.0)),
                          ),
                        ),
                        if (inner.height > 70)
                          SizedBox(
                            height: inner.height * 0.22,
                            child: FittedBox(
                              child: Text(label, style: Playful.title(18, color: hc ? const Color(0xFFFFFF00) : Colors.white)),
                            ),
                          ),
                      ],
                    )
                  : FittedBox(
                      child: Icon(Icons.music_note_rounded, size: 48, color: hc ? Colors.white70 : Playful.sun.withValues(alpha: 0.9)),
                    ),
            ),
          ),
        ],
      );
    });
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({
    required this.edges,
    required this.square,
    required this.open,
    required this.color,
    required this.accent,
    required this.matched,
    required this.wrong,
    required this.echo,
    required this.hc,
  });

  final PuzzleEdges edges;
  final bool square;
  final bool open;
  final Color color;
  final Color accent;
  final bool matched;
  final bool wrong;
  final double echo;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final path = puzzlePath(size, edges, square: square);
    final bounds = Offset.zero & size;
    // Бранови на ехо околу делчето.
    if (echo > 0) {
      for (var k = 0; k < 3; k++) {
        final p = (echo + k / 3) % 1.0;
        canvas.save();
        final s = 1 + p * 0.35;
        canvas.translate(size.width / 2, size.height / 2);
        canvas.scale(s, s);
        canvas.translate(-size.width / 2, -size.height / 2);
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 / s
          ..color = (hc ? const Color(0xFFFFFF00) : Playful.sun).withValues(alpha: (1 - p) * 0.8));
        canvas.restore();
      }
    }
    if (!hc) {
      canvas.drawPath(path.shift(const Offset(3, 6)), Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    final Paint fill;
    if (hc) {
      fill = Paint()..color = open ? Colors.black : const Color(0xFF1A1A1A);
    } else if (open) {
      fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.3)!, color, Color.lerp(color, Colors.black, 0.4)!],
        ).createShader(bounds);
    } else {
      fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Playful.nightRaised, Color.lerp(Playful.night, accent, 0.35)!],
        ).createShader(bounds);
    }
    canvas.drawPath(path, fill);
    if (!hc && !open) {
      // Шара на задната страна: мали ноти во мрежа.
      canvas.save();
      canvas.clipPath(path);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.06);
      for (var y = 8.0; y < size.height; y += 16) {
        for (var x = ((y ~/ 16).isEven ? 8.0 : 16.0); x < size.width; x += 16) {
          canvas.drawCircle(Offset(x, y), 2.2, dot);
        }
      }
      canvas.restore();
    }
    // Сјај горе-лево (волумен).
    if (!hc) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(bounds, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
        ).createShader(bounds));
      canvas.restore();
    }
    final borderColor = wrong
        ? const Color(0xFFEF4444)
        : matched
            ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF22C55E))
            : (hc ? Colors.white : Playful.sun.withValues(alpha: 0.9));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = matched || wrong ? 4 : 3
      ..strokeJoin = StrokeJoin.round
      ..color = borderColor);
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) =>
      old.open != open || old.echo != echo || old.matched != matched || old.wrong != wrong || old.hc != hc || old.color != color;
}

/// „Заспаната градина“: ноќна сцена што се буди со секој пронајден пар.
/// [awake] - звуците (id) што се веќе разбудени; [progress] 0..1 за небото
/// (ноќ -> зора); [t] за мали анимации; [bounce] - id што моментално
/// „пее“ (на крајот на рундата).
class GardenScene extends StatelessWidget {
  const GardenScene({super.key, required this.awake, required this.progress, required this.t, this.bounce});

  final Set<String> awake;
  final double progress;
  final double t;
  final String? bounce;

  /// Каде во сцената се појавува секој поим (делови од ширина/висина) и
  /// што се гледа.
  static const Map<String, (double, double, String)> spots = {
    'dog': (0.20, 0.80, '🐕'),
    'cat': (0.42, 0.62, '🐈'),
    'bird': (0.79, 0.30, '🐦'),
    'rain': (0.55, 0.14, '🌧️'),
    'car': (0.50, 0.90, '🚗'),
    'heels': (0.66, 0.78, '🚶‍♀️'),
    'wind': (0.12, 0.22, '🌬️'),
    'water': (0.86, 0.80, '⛲'),
    'glass': (0.30, 0.42, '🥂'),
  };

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final e = math.min(w, h) * 0.2;
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GardenPainter(progress: progress, t: t, hc: hc, rain: awake.contains('rain'), wind: awake.contains('wind')))),
            for (final id in awake)
              if (spots[id] != null)
                () {
                  final (fx, fy, emoji) = spots[id]!;
                  // Колата полека вози; останатите малку „дишат“.
                  final drive = id == 'car' ? ((t * 0.5) % 1.0) * 1.2 - 0.1 : fx;
                  final bob = math.sin(t * math.pi * 2 + fx * 9) * e * 0.06;
                  final pop = bounce == id ? 1.35 : 1.0;
                  return Positioned(
                    left: w * drive - e / 2,
                    top: h * fy - e / 2 + bob,
                    width: e,
                    height: e,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('garden-$id'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) => Transform.scale(scale: v * pop, child: child),
                      child: FittedBox(child: Text(emoji, style: const TextStyle(fontSize: 60, height: 1.0))),
                    ),
                  );
                }(),
          ],
        ),
      );
    });
  }
}

class _GardenPainter extends CustomPainter {
  _GardenPainter({required this.progress, required this.t, required this.hc, required this.rain, required this.wind});

  final double progress;
  final double t;
  final bool hc;
  final bool rain;
  final bool wind;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    if (hc) {
      canvas.drawRect(rect, Paint()..color = Colors.black);
      canvas.drawRect(rect, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white);
      canvas.drawLine(Offset(0, h * 0.7), Offset(w, h * 0.7), Paint()
        ..color = Colors.white
        ..strokeWidth = 2);
      return;
    }
    // Небо: од ноќ кон зора.
    final top = Color.lerp(const Color(0xFF0B1030), const Color(0xFF7DD3FC), progress)!;
    final bottom = Color.lerp(const Color(0xFF2A1B4E), const Color(0xFFFDE68A), progress)!;
    canvas.drawRect(rect, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(rect));
    // Ѕвезди (бледнеат со зората) и месечина / сонце.
    final rnd = math.Random(4);
    for (var i = 0; i < 26; i++) {
      final s = Offset(w * rnd.nextDouble(), h * 0.55 * rnd.nextDouble());
      canvas.drawCircle(s, 1.2 + rnd.nextDouble(), Paint()..color = Colors.white.withValues(alpha: (1 - progress) * (0.4 + 0.4 * math.sin(t * 6 + i))));
    }
    final orb = Offset(w * 0.88, h * (0.22 - 0.08 * progress));
    canvas.drawCircle(orb, h * 0.09, Paint()..color = Color.lerp(const Color(0xFFFFF7D6), const Color(0xFFFFC93C), progress)!);
    canvas.drawCircle(orb, h * 0.16, Paint()..color = const Color(0xFFFFC93C).withValues(alpha: 0.12 + 0.2 * progress));
    // Ридови.
    final hill = Path()
      ..moveTo(0, h * 0.68)
      ..quadraticBezierTo(w * 0.25, h * 0.52, w * 0.5, h * 0.64)
      ..quadraticBezierTo(w * 0.78, h * 0.76, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = Color.lerp(const Color(0xFF14321F), const Color(0xFF4ADE80), progress * 0.8)!);
    // Пат.
    canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.09), Paint()..color = Color.lerp(const Color(0xFF1F2937), const Color(0xFF6B7280), progress)!);
    for (var x = 0.0; x < w; x += 34) {
      canvas.drawLine(Offset(x, h * 0.905), Offset(x + 16, h * 0.905), Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2);
    }
    // Дрво (се нишка ако има ветер).
    final sway = wind ? math.sin(t * math.pi * 2) * 0.06 : 0.0;
    final trunk = Offset(w * 0.8, h * 0.68);
    canvas.drawLine(trunk, trunk + Offset(0, -h * 0.28), Paint()
      ..color = const Color(0xFF5B3A1E)
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round);
    canvas.save();
    canvas.translate(trunk.dx, trunk.dy - h * 0.28);
    canvas.rotate(sway);
    canvas.drawCircle(Offset.zero, h * 0.16, Paint()..color = Color.lerp(const Color(0xFF14532D), const Color(0xFF22C55E), progress)!);
    canvas.drawCircle(Offset(-h * 0.1, h * 0.05), h * 0.1, Paint()..color = Color.lerp(const Color(0xFF166534), const Color(0xFF16A34A), progress)!);
    canvas.restore();
    // Куќичка.
    final house = Rect.fromLTWH(w * 0.06, h * 0.56, w * 0.14, h * 0.18);
    canvas.drawRect(house, Paint()..color = Color.lerp(const Color(0xFF3B2F4F), const Color(0xFFFCA5A5), progress)!);
    canvas.drawPath(
      Path()
        ..moveTo(house.left - 6, house.top)
        ..lineTo(house.center.dx, house.top - h * 0.1)
        ..lineTo(house.right + 6, house.top)
        ..close(),
      Paint()..color = Color.lerp(const Color(0xFF4C1D24), const Color(0xFFDC2626), progress)!,
    );
    canvas.drawRect(Rect.fromCenter(center: house.center, width: house.width * 0.35, height: house.height * 0.35),
        Paint()..color = Color.lerp(const Color(0xFFFDE68A), const Color(0xFFFFFFFF), progress)!.withValues(alpha: 0.9));
    // Дожд: капки (и цвеќиња што растат).
    if (rain) {
      final drop = Paint()
        ..color = const Color(0xFF93C5FD).withValues(alpha: 0.7)
        ..strokeWidth = 2;
      for (var i = 0; i < 18; i++) {
        final x = w * (0.42 + (i % 6) * 0.045);
        final y = h * (0.2 + (((t * 1.6) + i * 0.17) % 1.0) * 0.45);
        canvas.drawLine(Offset(x, y), Offset(x - 2, y + 8), drop);
      }
      for (var i = 0; i < 5; i++) {
        final base = Offset(w * (0.4 + i * 0.05), h * 0.84);
        canvas.drawLine(base, base + Offset(0, -h * 0.06), Paint()
          ..color = const Color(0xFF16A34A)
          ..strokeWidth = 2);
        canvas.drawCircle(base + Offset(0, -h * 0.07), 4, Paint()..color = [const Color(0xFFF472B6), const Color(0xFFFDE047), const Color(0xFFA78BFA)][i % 3]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GardenPainter old) =>
      old.progress != progress || old.t != t || old.hc != hc || old.rain != rain || old.wind != wind;
}
