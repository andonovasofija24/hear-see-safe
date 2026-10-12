import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'playful_ui.dart';

/// Уметност за „Идентификација на звук“ - „Лента до увото“:
/// картичките се лизгаат по свиткана лента (полукруг) кон големо уво;
/// лентата се стеснува, картичките се смалуваат и влегуваат во ушниот
/// канал, па пак се појавуваат на почетокот.
///
/// [EarBeltGeometry] - патеката, ширината на лентата, големината на
/// картичката и каде е увото, за дадена големина на сцената.
class EarBeltGeometry {
  EarBeltGeometry(this.size, {this.cards = 9}) {
    final w = size.width, h = size.height;
    earHeight = math.min(h * 0.82, w * 0.44);
    earCenter = Offset(w - earHeight * 0.36 - 6, h * 0.52);
    canal = earCenter + Offset(-earHeight * 0.04, earHeight * 0.07);
    var card = math.min(h * 0.27, w * 0.2);
    late Path p;
    late ui.PathMetric m;
    // Два чекора: патеката зависи од големината на картичката, а
    // картичката не смее да е поголема од растојанието меѓу картичките.
    for (var it = 0; it < 2; it++) {
      final start = Offset(card * 0.8, h - card * 0.7);
      p = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(w * 0.05, 0, w * 0.5, h * -0.08, canal.dx, canal.dy);
      m = p.computeMetrics().first;
      card = math.min(card, m.length * loop / cards / 1.3);
    }
    maxCard = card;
    path = p;
    _metric = m;
    orbCenter = Offset(w * 0.38, h * 0.6);
    orbSize = math.min(120.0, math.min(w * 0.26, h * 0.34));
  }

  /// Колку картички има на лентата.
  final int cards;

  /// Целиот круг е [loop] пати подолг од видливата патека: картичките
  /// по влегувањето во увото малку „патуваат“ невидливо, па се
  /// појавуваат на почетокот (помалку картички на лентата - поголеми).
  static const double loop = 1.45;

  /// Каде да стои копчето „Пушти звук“ - во средината на полукругот.
  late final Offset orbCenter;
  late final double orbSize;

  final Size size;
  late final double earHeight;
  late final Offset earCenter;
  late final Offset canal;
  late final double maxCard;
  late final Path path;
  late final ui.PathMetric _metric;

  double get length => _metric.length;

  Offset pointAt(double s) => _metric.getTangentForOffset(_metric.length * s.clamp(0.0, 1.0))!.position;

  double angleAt(double s) => _metric.getTangentForOffset(_metric.length * s.clamp(0.0, 1.0))!.angle;

  /// Ширина на лентата: широка на почетокот, тесна до увото.
  double widthAt(double s) => maxCard * 1.25 * (1 - 0.82 * s);

  /// Големина на картичката по патеката.
  double cardAt(double s) => maxCard * (1 - 0.62 * math.pow(s.clamp(0.0, 1.0), 1.1));
}

/// Свитканата лента: перспектива (се стеснува), рабови, линии што се
/// движат (како транспортна лента) и сјај.
class EarBeltPainter extends CustomPainter {
  EarBeltPainter({required this.geo, required this.offset, required this.color, required this.hc, required this.gate});

  final EarBeltGeometry geo;

  /// Поместување на лентата (0..1) - за линиите што се движат.
  final double offset;
  final Color color;
  final bool hc;

  /// Каде е „портата“ пред увото (0..1).
  final double gate;

  @override
  void paint(Canvas canvas, Size size) {
    const steps = 90;
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final s = i / steps;
      final p = geo.pointAt(s);
      final a = geo.angleAt(s);
      final n = Offset(-math.sin(a), math.cos(a)) * (geo.widthAt(s) / 2);
      left.add(p + n);
      right.add(p - n);
    }
    final band = Path()..addPolygon([...left, ...right.reversed], true);
    // Сенка под лентата.
    if (!hc) {
      canvas.drawPath(band.shift(const Offset(0, 10)), Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    canvas.drawPath(
      band,
      Paint()
        ..shader = (hc
                ? const LinearGradient(colors: [Colors.black, Colors.black])
                : LinearGradient(
                    colors: [Color.lerp(color, Colors.white, 0.25)!, color, Color.lerp(color, Colors.black, 0.55)!],
                    stops: const [0.0, 0.5, 1.0],
                  ))
            .createShader(Offset.zero & size),
    );
    // Рабови на лентата.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hc ? 3 : 2.5
      ..color = hc ? Colors.white : Colors.white.withValues(alpha: 0.75);
    canvas.drawPath(Path()..addPolygon(left, false), edge);
    canvas.drawPath(Path()..addPolygon(right, false), edge);
    // Попречни линии што се движат кон увото.
    final rung = Paint()
      ..strokeWidth = 2
      ..color = (hc ? Colors.white : Colors.white).withValues(alpha: hc ? 0.6 : 0.22);
    const rungs = 26;
    for (var k = 0; k < rungs; k++) {
      final s = ((k + offset * rungs) % rungs) / rungs;
      if (s > 0.97) continue;
      final i = (s * steps).round().clamp(0, steps);
      canvas.drawLine(left[i], right[i], rung);
    }
    // Портата пред увото: светла лента преку патеката.
    final gi = (gate * steps).round().clamp(0, steps);
    canvas.drawLine(left[gi], right[gi], Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = hc ? const Color(0xFFFFFF00) : Playful.sun);
  }

  @override
  bool shouldRepaint(covariant EarBeltPainter old) =>
      old.offset != offset || old.color != color || old.hc != hc || old.geo != geo || old.gate != gate;
}

/// Увото - задниот дел (кожа, школка, канал). Картичките се цртаат над
/// ова, а [EarFrontPainter] (работ и трагусот) - над картичките, па
/// картичките изгледаат како да влегуваат во каналот.
class EarBackPainter extends CustomPainter {
  EarBackPainter({required this.geo, required this.hc, required this.pulse, required this.glow});

  final EarBeltGeometry geo;
  final bool hc;

  /// 0..1 - бранови на звук околу увото (додека се слуша).
  final double pulse;

  /// null = обично, зелено = точно, црвено = погрешно.
  final Color? glow;

  Path _outline() {
    final c = geo.earCenter;
    final h = geo.earHeight;
    final w = h * 0.62;
    // Обликот на увото (поглед од страна, отворено кон лево).
    return Path()
      ..moveTo(c.dx - w * 0.30, c.dy - h * 0.30)
      ..cubicTo(c.dx - w * 0.25, c.dy - h * 0.55, c.dx + w * 0.55, c.dy - h * 0.58, c.dx + w * 0.50, c.dy - h * 0.10)
      ..cubicTo(c.dx + w * 0.48, c.dy + h * 0.12, c.dx + w * 0.22, c.dy + h * 0.22, c.dx + w * 0.18, c.dy + h * 0.36)
      ..cubicTo(c.dx + w * 0.14, c.dy + h * 0.50, c.dx - w * 0.06, c.dy + h * 0.56, c.dx - w * 0.16, c.dy + h * 0.42)
      ..cubicTo(c.dx - w * 0.26, c.dy + h * 0.28, c.dx - w * 0.10, c.dy + h * 0.18, c.dx - w * 0.22, c.dy + h * 0.06)
      ..cubicTo(c.dx - w * 0.34, c.dy - h * 0.04, c.dx - w * 0.36, c.dy - h * 0.16, c.dx - w * 0.30, c.dy - h * 0.30)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = geo.earCenter;
    final h = geo.earHeight;
    final w = h * 0.62;
    final outline = _outline();
    // Звучни бранови што одат кон увото.
    if (pulse > 0) {
      for (var k = 0; k < 3; k++) {
        final p = (pulse + k / 3) % 1.0;
        canvas.drawCircle(geo.canal, h * (0.18 + 0.55 * (1 - p)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = (hc ? Colors.white : Playful.sun).withValues(alpha: 0.5 * p));
      }
    }
    if (glow != null && !hc) {
      canvas.drawPath(outline, Paint()
        ..color = glow!.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    }
    if (hc) {
      canvas.drawPath(outline, Paint()..color = Colors.black);
      canvas.drawPath(outline, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = glow ?? Colors.white);
    } else {
      // Сенка и кожа со волумен.
      canvas.drawPath(outline.shift(const Offset(6, 10)), Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.drawPath(
        outline,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.3, -0.4),
            radius: 0.9,
            colors: const [Color(0xFFFFD8BF), Color(0xFFF2A984), Color(0xFFC9745A)],
            stops: const [0.0, 0.6, 1.0],
          ).createShader(Rect.fromCenter(center: c, width: w * 1.2, height: h * 1.2)),
      );
    }
    // Антихеликс - внатрешниот набор.
    final anti = Path()
      ..moveTo(c.dx - w * 0.12, c.dy - h * 0.28)
      ..cubicTo(c.dx + w * 0.30, c.dy - h * 0.36, c.dx + w * 0.34, c.dy - h * 0.02, c.dx + w * 0.10, c.dy + h * 0.16)
      ..cubicTo(c.dx + w * 0.02, c.dy + h * 0.24, c.dx + w * 0.02, c.dy + h * 0.30, c.dx - w * 0.04, c.dy + h * 0.34);
    canvas.drawPath(anti, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..color = hc ? Colors.white54 : const Color(0xFFE79A79));
    canvas.drawPath(anti.shift(Offset(-w * 0.02, -h * 0.01)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round
      ..color = hc ? Colors.white : const Color(0xFFFFE3D1).withValues(alpha: 0.8));
    // Школката (конха) и каналот - темна длабочина.
    final concha = Rect.fromCenter(center: geo.canal + Offset(w * 0.04, -h * 0.02), width: w * 0.42, height: h * 0.30);
    canvas.drawOval(
      concha,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, 0.1),
          colors: hc ? const [Colors.black, Colors.black] : const [Color(0xFF2A0E0A), Color(0xFF7A3524), Color(0xFFC9745A)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(concha),
    );
    if (hc) {
      canvas.drawOval(concha, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant EarBackPainter old) => old.pulse != pulse || old.glow != glow || old.hc != hc || old.geo != geo;
}

/// Работ на увото (хеликсот) и трагусот - над картичките.
class EarFrontPainter extends CustomPainter {
  EarFrontPainter({required this.geo, required this.hc});

  final EarBeltGeometry geo;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final c = geo.earCenter;
    final h = geo.earHeight;
    final w = h * 0.62;
    // Хеликсот - заоблениот раб горе и десно.
    final helix = Path()
      ..moveTo(c.dx - w * 0.26, c.dy - h * 0.30)
      ..cubicTo(c.dx - w * 0.20, c.dy - h * 0.52, c.dx + w * 0.50, c.dy - h * 0.54, c.dx + w * 0.45, c.dy - h * 0.10)
      ..cubicTo(c.dx + w * 0.43, c.dy + h * 0.10, c.dx + w * 0.20, c.dy + h * 0.20, c.dx + w * 0.15, c.dy + h * 0.34);
    canvas.drawPath(helix, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..color = hc ? Colors.black : const Color(0xFFF5B394));
    canvas.drawPath(helix, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round
      ..color = hc ? Colors.white : const Color(0xFFFFE6D6));
    // Трагусот - малото испакнување пред каналот (ја „голта“ картичката).
    final tr = geo.canal + Offset(-w * 0.13, h * 0.04);
    final tragus = Path()
      ..moveTo(tr.dx + w * 0.02, tr.dy - h * 0.10)
      ..quadraticBezierTo(tr.dx - w * 0.12, tr.dy, tr.dx + w * 0.03, tr.dy + h * 0.11)
      ..quadraticBezierTo(tr.dx + w * 0.07, tr.dy, tr.dx + w * 0.02, tr.dy - h * 0.10)
      ..close();
    canvas.drawPath(tragus, Paint()..color = hc ? Colors.black : const Color(0xFFE8A07F));
    canvas.drawPath(tragus, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = hc ? Colors.white : const Color(0xFFFFDCC8));
  }

  @override
  bool shouldRepaint(covariant EarFrontPainter old) => old.hc != hc || old.geo != geo;
}

/// Звучна картичка: обоена рамка, бел круг со сликичка (емоџи), име и мал
/// звучник во аголот. [playing] = бранови околу неа (се слуша нејзиниот
/// звук); [state] true/false = точно/погрешно.
class SoundCard extends StatelessWidget {
  const SoundCard({
    super.key,
    required this.emoji,
    required this.label,
    required this.color,
    required this.size,
    required this.hc,
    this.playing = false,
    this.atGate = false,
    this.state,
    this.wave = 0,
  });

  final String emoji;
  final String label;
  final Color color;
  final double size;
  final bool hc;
  final bool playing;
  final bool atGate;
  final bool? state;

  /// 0..1 за брановите.
  final double wave;

  @override
  Widget build(BuildContext context) {
    final ring = state == null
        ? (atGate ? (hc ? const Color(0xFFFFFF00) : Playful.sun) : Colors.white)
        : (state! ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    final showLabel = size >= 64;
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (playing && !hc)
            Positioned.fill(
              child: CustomPaint(painter: _WavePainter(t: wave, color: Playful.sun)),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.2),
                color: hc ? Colors.black : null,
                gradient: hc
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color.lerp(color, Colors.white, 0.25)!, color, Color.lerp(color, Colors.black, 0.4)!],
                      ),
                border: Border.all(color: ring, width: atGate || state != null ? 4 : 2.5),
                boxShadow: hc
                    ? null
                    : [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: size * 0.12, offset: Offset(0, size * 0.06)),
                        if (atGate || state != null) BoxShadow(color: ring.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 2),
                      ],
              ),
              padding: EdgeInsets.all(size * 0.08),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc ? Colors.black : Colors.white,
                        border: hc ? Border.all(color: Colors.white, width: 2) : null,
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(emoji, style: const TextStyle(fontSize: 60, height: 1.0)),
                        ),
                      ),
                    ),
                  ),
                  if (showLabel) ...[
                    SizedBox(height: size * 0.04),
                    SizedBox(
                      height: size * 0.2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, style: Playful.title(size * 0.17, color: hc ? const Color(0xFFFFFF00) : Colors.white)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Мал звучник во аголот.
          Positioned(
            top: -size * 0.06,
            right: -size * 0.06,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : (playing ? Playful.sun : Colors.white),
                border: Border.all(color: hc ? Colors.white : color, width: 2),
              ),
              child: Icon(playing ? Icons.volume_up_rounded : Icons.music_note_rounded, size: size * 0.18, color: hc ? Colors.white : Playful.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var k = 0; k < 3; k++) {
      final p = (t + k / 3) % 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: size.width * (1 + p * 0.6), height: size.height * (1 + p * 0.5)),
          Radius.circular(size.width * 0.3),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: (1 - p) * 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}
