import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/accessibility_utils.dart';
import 'playful_ui.dart';

/// Уметност за „Игри со броеви“ - заштитниот знак на модулот:
///  * [NumberModeBackdrop] - позадина: во менито тетратка на квадратчиња со
///    соѕвездие од бројки; во секоја игра - своја шара (вага, абакус,
///    цртички, мапа на квадрати...);
///  * [NumberModeEmblem] - мал жив амблем на секоја игра (до копчето назад).
///
/// Редоследот на [NumArt] е ист како режимите во number_games_screen.
enum NumArt { recognize, biggerSmaller, operations, multiplyDivide, countObjects, tally, grid, sequence, sort, sudoku }

const Map<NumArt, List<String>> _modeEmojis = {
  NumArt.recognize: ['🔢', '7️⃣', '3️⃣', '✨'],
  NumArt.biggerSmaller: ['⚖️', '🐘', '🐭', '🔼'],
  NumArt.operations: ['➕', '➖', '🧮', '🍎'],
  NumArt.multiplyDivide: ['✖️', '➗', '🍪', '🧩'],
  NumArt.countObjects: ['🍎', '⚽', '⭐', '🎈'],
  NumArt.tally: ['✋', '🖐️', '✏️', '📏'],
  NumArt.grid: ['🗺️', '📍', '🧭', '🔎'],
  NumArt.sequence: ['🪄', '✨', '🔮', '🌟'],
  NumArt.sort: ['📶', '🪜', '🏆', '📊'],
  NumArt.sudoku: ['🧩', '✏️', '🧠', '🔲'],
};

/// Позадина: [mode] == null - менито; инаку шарата на таа игра.
class NumberModeBackdrop extends StatelessWidget {
  const NumberModeBackdrop({super.key, this.mode, required this.tint});

  final NumArt? mode;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final m = mode;
    return Stack(
      fit: StackFit.expand,
      children: [
        EmojiBackdrop(
          emojis: m == null ? const ['🔢', '➕', '➖', '🧮', '⭐', '🎲'] : _modeEmojis[m]!,
          tint: tint,
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(painter: _PatternPainter(m, tint)),
            ),
          ),
        ),
      ],
    );
  }
}

TextPainter _text(String s, double size, Color color, {FontWeight weight = FontWeight.w900}) => TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();

void _drawCentered(Canvas canvas, String s, Offset c, double size, Color color, {FontWeight weight = FontWeight.w900}) {
  final tp = _text(s, size, color, weight: weight);
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  tp.dispose();
}

/// Тивка шара преку целата позадина (не му пречи на текстот).
class _PatternPainter extends CustomPainter {
  _PatternPainter(this.mode, this.tint);

  final NumArt? mode;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final faint = Colors.white.withValues(alpha: 0.07);
    final line = Paint()
      ..color = faint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final bold = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rnd = math.Random(7);

    switch (mode) {
      case null:
        // Тетратка на квадратчиња + соѕвездие од бројки поврзани со линии.
        for (var x = 0.0; x < w; x += 28) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        }
        for (var y = 0.0; y < h; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        }
        final pts = <Offset>[for (var i = 0; i < 10; i++) Offset(w * (0.06 + rnd.nextDouble() * 0.88), h * (0.05 + rnd.nextDouble() * 0.9))];
        final star = Paint()
          ..color = Playful.sun.withValues(alpha: 0.12)
          ..strokeWidth = 1.5;
        for (var i = 0; i < pts.length - 1; i++) {
          canvas.drawLine(pts[i], pts[i + 1], star);
        }
        for (var i = 0; i < pts.length; i++) {
          canvas.drawCircle(pts[i], 16, Paint()..color = Playful.sun.withValues(alpha: 0.10));
          _drawCentered(canvas, '$i', pts[i], 20, Colors.white.withValues(alpha: 0.22));
        }
      case NumArt.recognize:
        // Големи шупливи бројки.
        for (var i = 0; i < 14; i++) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${rnd.nextInt(10)}',
              style: TextStyle(
                fontSize: 70 + rnd.nextDouble() * 70,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.5
                  ..color = Colors.white.withValues(alpha: 0.08),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(w * rnd.nextDouble() - 30, h * rnd.nextDouble() - 40));
          tp.dispose();
        }
      case NumArt.biggerSmaller:
        // Редови од < и >.
        var row = 0;
        for (var y = 30.0; y < h; y += 90, row++) {
          for (var x = (row.isEven ? 20.0 : 65.0); x < w; x += 90) {
            _drawCentered(canvas, (row + (x ~/ 90)).isEven ? '<' : '>', Offset(x, y), 46, Colors.white.withValues(alpha: 0.07));
          }
        }
      case NumArt.operations:
        // „Јорган“ од плус и минус.
        var qrow = 0;
        for (var y = 30.0; y < h; y += 70, qrow++) {
          for (var x = (qrow.isEven ? 25.0 : 60.0); x < w; x += 70) {
            final plus = ((x ~/ 70) + qrow).isEven;
            canvas.drawLine(Offset(x - 12, y), Offset(x + 12, y), bold);
            if (plus) canvas.drawLine(Offset(x, y - 12), Offset(x, y + 12), bold);
          }
        }
      case NumArt.multiplyDivide:
        // Низи од точки (како 3 x 4) - основата на множењето.
        for (var i = 0; i < 9; i++) {
          final ox = w * rnd.nextDouble(), oy = h * rnd.nextDouble();
          final rows = 2 + rnd.nextInt(3), cols = 2 + rnd.nextInt(4);
          for (var r = 0; r < rows; r++) {
            for (var c = 0; c < cols; c++) {
              canvas.drawCircle(Offset(ox + c * 18, oy + r * 18), 5, Paint()..color = Colors.white.withValues(alpha: 0.09));
            }
          }
        }
      case NumArt.countObjects:
        // Растурени облици: круг, квадрат, триаголник, ѕвезда.
        for (var i = 0; i < 26; i++) {
          final c = Offset(w * rnd.nextDouble(), h * rnd.nextDouble());
          final s = 14 + rnd.nextDouble() * 18;
          switch (i % 4) {
            case 0:
              canvas.drawCircle(c, s, bold);
            case 1:
              canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 2, height: s * 2), const Radius.circular(5)), bold);
            case 2:
              canvas.drawPath(Path()
                ..moveTo(c.dx, c.dy - s)
                ..lineTo(c.dx + s, c.dy + s * 0.8)
                ..lineTo(c.dx - s, c.dy + s * 0.8)
                ..close(), bold);
            default:
              canvas.drawPath(_starPath(c, s, s * 0.45), bold);
          }
        }
      case NumArt.tally:
        // Групи од пет цртички (четири + прецртана), како со креда на ѕид.
        for (var i = 0; i < 16; i++) {
          final o = Offset(w * rnd.nextDouble(), h * rnd.nextDouble());
          for (var k = 0; k < 4; k++) {
            canvas.drawLine(o + Offset(k * 12.0, 0), o + Offset(k * 12.0 + 2, 44), bold);
          }
          canvas.drawLine(o + const Offset(-6, 36), o + const Offset(44, 6), bold);
        }
      case NumArt.grid:
        // Карта на квадрати со координати по рабовите.
        const step = 56.0;
        for (var x = step; x < w; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        }
        for (var y = step; y < h; y += step) {
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        }
        var n = 1;
        for (var x = step / 2; x < w; x += step, n++) {
          _drawCentered(canvas, '$n', Offset(x, 14), 14, Colors.white.withValues(alpha: 0.18));
        }
        var l = 0;
        for (var y = step / 2; y < h && l < 26; y += step, l++) {
          _drawCentered(canvas, String.fromCharCode(65 + l), Offset(12, y), 14, Colors.white.withValues(alpha: 0.18));
        }
        // Неколку „богатства“ означени со X.
        for (var i = 0; i < 4; i++) {
          final c = Offset((1 + rnd.nextInt(math.max(1, (w / step).floor() - 1))) * step - step / 2,
              (1 + rnd.nextInt(math.max(1, (h / step).floor() - 1))) * step - step / 2);
          final p = Paint()
            ..color = Playful.sun.withValues(alpha: 0.16)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(c + const Offset(-12, -12), c + const Offset(12, 12), p);
          canvas.drawLine(c + const Offset(12, -12), c + const Offset(-12, 12), p);
        }
      case NumArt.sequence:
        // Магичен бран од точки што растат - низа.
        for (var band = 0; band < 4; band++) {
          final y0 = h * (0.15 + band * 0.24);
          for (var i = 0; i < 14; i++) {
            final x = w * i / 13;
            final y = y0 + math.sin(i * 0.8 + band) * 26;
            canvas.drawCircle(Offset(x, y), 2.0 + i * 0.7, Paint()..color = Playful.sun.withValues(alpha: 0.07 + i * 0.004));
          }
        }
      case NumArt.sort:
        // Скалила - столбови што растат од лево кон десно, долу.
        const bars = 12;
        final bw = w / bars;
        for (var i = 0; i < bars; i++) {
          final bh = h * (0.08 + 0.32 * (i + 1) / bars);
          canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(i * bw + 4, h - bh, bw - 8, bh), topLeft: const Radius.circular(8), topRight: const Radius.circular(8)),
            Paint()..color = Colors.white.withValues(alpha: 0.05),
          );
        }
      case NumArt.sudoku:
        // Големи 3 x 3 мрежи со подебели рабови.
        const cell = 34.0;
        for (var i = 0; i < 6; i++) {
          final o = Offset(w * rnd.nextDouble() - 40, h * rnd.nextDouble() - 40);
          for (var k = 0; k <= 9; k++) {
            final p = k % 3 == 0 ? bold : line;
            canvas.drawLine(o + Offset(k * cell / 3, 0), o + Offset(k * cell / 3, cell * 3), p);
            canvas.drawLine(o + Offset(0, k * cell / 3), o + Offset(cell * 3, k * cell / 3), p);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.mode != mode || old.tint != tint;
}

Path _starPath(Offset c, double outer, double inner) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) {
      p.moveTo(pt.dx, pt.dy);
    } else {
      p.lineTo(pt.dx, pt.dy);
    }
  }
  return p..close();
}

/// Мал жив амблем на играта - кружна значка со своја мини-анимација.
class NumberModeEmblem extends StatefulWidget {
  const NumberModeEmblem({super.key, required this.mode, required this.color, this.size = 56});

  final NumArt mode;
  final Color color;
  final double size;

  @override
  State<NumberModeEmblem> createState() => _NumberModeEmblemState();
}

class _NumberModeEmblemState extends State<NumberModeEmblem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _c
        ..stop()
        ..value = 0.62;
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
    final hc = AccessibilityUtils.isHighContrast(context);
    return ExcludeSemantics(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hc ? Colors.black : null,
          gradient: hc
              ? null
              : RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: [Color.lerp(widget.color, Colors.white, 0.3)!, widget.color, Color.lerp(widget.color, Colors.black, 0.45)!],
                  stops: const [0.0, 0.6, 1.0],
                ),
          border: Border.all(color: hc ? Colors.white : Playful.sun, width: 3),
          boxShadow: hc ? null : [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 14)],
        ),
        child: ClipOval(
          child: CustomPaint(painter: _EmblemPainter(widget.mode, _c, hc)),
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.mode, this.t, this.hc) : super(repaint: t);

  final NumArt mode;
  final Animation<double> t;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final v = t.value;
    final ink = hc ? const Color(0xFFFFFF00) : Colors.white;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = ink;
    final sun = hc ? const Color(0xFFFFFF00) : Playful.sun;

    switch (mode) {
      case NumArt.recognize:
        // Картичка со бројка што се менува 1 → 9.
        final n = 1 + (v * 9).floor() % 9;
        final card = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.5, height: s * 0.62), Radius.circular(s * 0.08));
        canvas.drawRRect(card, Paint()..color = hc ? Colors.black : Colors.white);
        canvas.drawRRect(card, Paint()
          ..color = sun
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04);
        _drawCentered(canvas, '$n', c, s * 0.42, hc ? const Color(0xFFFFFF00) : Playful.ink);
        // Искра.
        final sp = (v * 9) % 1.0;
        canvas.drawPath(_starPath(c + Offset(s * 0.27, -s * 0.27), s * 0.09 * (0.6 + 0.4 * math.sin(sp * math.pi)), s * 0.035), Paint()..color = sun);
      case NumArt.biggerSmaller:
        // Вага што се нишка.
        final tilt = math.sin(v * math.pi * 2) * 0.32;
        final top = c + Offset(0, -s * 0.18);
        canvas.drawLine(top, c + Offset(0, s * 0.26), stroke);
        canvas.drawLine(c + Offset(-s * 0.16, s * 0.26), c + Offset(s * 0.16, s * 0.26), stroke);
        final dx = math.cos(tilt) * s * 0.3, dy = math.sin(tilt) * s * 0.3;
        final l = top - Offset(dx, dy), r = top + Offset(dx, dy);
        canvas.drawLine(l, r, stroke);
        for (final (p, big) in [(l, false), (r, true)]) {
          canvas.drawLine(p, p + Offset(0, s * 0.12), stroke..strokeWidth = s * 0.03);
          canvas.drawArc(Rect.fromCenter(center: p + Offset(0, s * 0.14), width: s * 0.24, height: s * 0.12), 0, math.pi, true, fill);
          canvas.drawCircle(p + Offset(0, s * (big ? 0.07 : 0.1)), s * (big ? 0.07 : 0.04), Paint()..color = sun);
        }
        stroke.strokeWidth = s * 0.06;
      case NumArt.operations:
        // Абакус: три жици, топчињата се лизгаат.
        final frame = Rect.fromCenter(center: c, width: s * 0.62, height: s * 0.5);
        canvas.drawRRect(RRect.fromRectAndRadius(frame, Radius.circular(s * 0.05)), stroke..strokeWidth = s * 0.04);
        final colors = hc ? [ink, ink, ink] : [const Color(0xFFFF6B6B), sun, const Color(0xFF4ADE80)];
        for (var row = 0; row < 3; row++) {
          final y = frame.top + frame.height * (row + 1) / 4;
          canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), Paint()
            ..color = ink.withValues(alpha: 0.7)
            ..strokeWidth = s * 0.015);
          final shift = (math.sin(v * math.pi * 2 + row * 1.3) + 1) / 2;
          for (var b = 0; b < 3; b++) {
            final x = frame.left + s * 0.07 + b * s * 0.09 + shift * s * 0.22;
            canvas.drawCircle(Offset(x, y), s * 0.045, Paint()..color = colors[row]);
          }
        }
        stroke.strokeWidth = s * 0.06;
      case NumArt.multiplyDivide:
        // Низа 3 x 3 што се полни ред по ред, со знак x.
        final shown = (v * 12).floor().clamp(0, 9);
        for (var i = 0; i < 9; i++) {
          final p = c + Offset(((i % 3) - 1) * s * 0.17, ((i ~/ 3) - 1) * s * 0.17);
          canvas.drawCircle(p, s * 0.055, Paint()..color = i < shown ? sun : ink.withValues(alpha: 0.3));
        }
      case NumArt.countObjects:
        // Три облици што подскокнуваат еден по еден.
        for (var i = 0; i < 3; i++) {
          final hop = math.max(0.0, math.sin((v * 3 - i * 0.33) * math.pi * 2)) * s * 0.12;
          final p = c + Offset((i - 1) * s * 0.22, s * 0.08 - hop);
          final r = s * 0.08;
          final paint = Paint()..color = hc ? ink : [const Color(0xFFFF6B6B), sun, const Color(0xFF60A5FA)][i];
          switch (i) {
            case 0:
              canvas.drawCircle(p, r, paint);
            case 1:
              canvas.drawPath(_starPath(p, r * 1.2, r * 0.5), paint);
            default:
              canvas.drawRect(Rect.fromCenter(center: p, width: r * 1.8, height: r * 1.8), paint);
          }
        }
      case NumArt.tally:
        // Цртички се додаваат 1..5, петтата прецртува.
        final marks = (v * 7).floor().clamp(0, 5);
        for (var k = 0; k < math.min(marks, 4); k++) {
          final x = c.dx - s * 0.18 + k * s * 0.12;
          canvas.drawLine(Offset(x, c.dy - s * 0.2), Offset(x + s * 0.02, c.dy + s * 0.2), stroke);
        }
        if (marks >= 5) {
          canvas.drawLine(c + Offset(-s * 0.27, s * 0.14), c + Offset(s * 0.27, -s * 0.14), Paint()
            ..color = sun
            ..strokeWidth = s * 0.07
            ..strokeCap = StrokeCap.round);
        }
      case NumArt.grid:
        // Мрежа 3 x 3 и маркер што скока од поле на поле.
        final cell = s * 0.18;
        final o = c - Offset(cell * 1.5, cell * 1.5);
        final thin = Paint()
          ..color = ink.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.02;
        for (var k = 0; k <= 3; k++) {
          canvas.drawLine(o + Offset(k * cell, 0), o + Offset(k * cell, cell * 3), thin);
          canvas.drawLine(o + Offset(0, k * cell), o + Offset(cell * 3, k * cell), thin);
        }
        const path = [4, 1, 2, 5, 8, 7, 6, 3, 0];
        final idx = path[(v * path.length).floor() % path.length];
        final mc = o + Offset((idx % 3 + 0.5) * cell, (idx ~/ 3 + 0.5) * cell);
        canvas.drawCircle(mc, cell * 0.36, Paint()..color = sun);
      case NumArt.sequence:
        // Стапче со трага од точки што растат.
        final tip = c + Offset(s * 0.12, -s * 0.12);
        canvas.drawLine(c + Offset(-s * 0.22, s * 0.22), tip, stroke);
        canvas.drawPath(_starPath(tip, s * 0.1, s * 0.04), Paint()..color = sun);
        final k = (v * 4).floor() % 4;
        for (var i = 0; i <= k; i++) {
          canvas.drawCircle(tip + Offset(s * 0.06 + i * s * 0.07, -s * 0.02 + i * s * 0.09), s * (0.018 + i * 0.012), Paint()..color = sun);
        }
      case NumArt.sort:
        // Столбови што се редат од најмал до најголем.
        const unsorted = [3, 1, 4, 2];
        final p = Curves.easeInOut.transform((math.sin(v * math.pi * 2 - math.pi / 2) + 1) / 2);
        final bw = s * 0.11;
        for (var i = 0; i < 4; i++) {
          final hgt = unsorted[i];
          final from = i.toDouble();
          final to = (hgt - 1).toDouble();
          final x = c.dx - s * 0.25 + (from + (to - from) * p) * s * 0.14;
          final bh = s * 0.09 * hgt;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, c.dy + s * 0.22 - bh, bw, bh), Radius.circular(s * 0.02)),
              Paint()..color = hc ? ink : Color.lerp(Colors.white, Playful.sun, hgt / 4)!);
        }
      case NumArt.sudoku:
        // Мала 3 x 3 табла каде бројките се појавуваат.
        final sc = s * 0.18;
        final so = c - Offset(sc * 1.5, sc * 1.5);
        canvas.drawRect(Rect.fromLTWH(so.dx, so.dy, sc * 3, sc * 3), Paint()..color = hc ? Colors.black : Colors.white.withValues(alpha: 0.92));
        final sthin = Paint()
          ..color = hc ? Colors.white : Playful.ink.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.015;
        for (var k = 0; k <= 3; k++) {
          canvas.drawLine(so + Offset(k * sc, 0), so + Offset(k * sc, sc * 3), sthin);
          canvas.drawLine(so + Offset(0, k * sc), so + Offset(sc * 3, k * sc), sthin);
        }
        const digits = [5, 0, 3, 0, 9, 0, 1, 0, 7];
        const order = [1, 3, 5, 7];
        final filled = (v * 5).floor();
        for (var i = 0; i < 9; i++) {
          var d = digits[i];
          if (d == 0) {
            final pos = order.indexOf(i);
            if (pos >= filled) continue;
            d = const [8, 2, 4, 6][pos];
          }
          _drawCentered(canvas, '$d', so + Offset((i % 3 + 0.5) * sc, (i ~/ 3 + 0.5) * sc), sc * 0.75,
              digits[i] == 0 ? (hc ? const Color(0xFFFFFF00) : const Color(0xFF0F766E)) : (hc ? Colors.white : Playful.ink));
        }
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) => old.mode != mode || old.hc != hc;
}

/// Жива икона во топчето на 3D сферата - заштитниот знак на секоја игра.
///  * Кој е бројот: неонско „?“ што трепка; кога е најнапред - сеф со шифра;
///  * Поголем/помал: вага што се ниша според вртењето на сферата;
///  * Собирање/одземање: + и − што се спојуваат во ± и пак се раздвојуваат;
///  * Множење/делење: коцка што се дели на 4 помали и пак се спојува;
///  * Локатор: квадрат од 4 дела што се врти во просторот;
///  * Магична низа: светечки синџир со една скршена алка;
///  * останатите: живиот амблем на играта.
class NumberSphereIcon extends StatefulWidget {
  const NumberSphereIcon({super.key, required this.mode, required this.size, required this.yaw, required this.front});

  final NumArt mode;
  final double size;
  final double yaw;
  final bool front;

  @override
  State<NumberSphereIcon> createState() => _NumberSphereIconState();
}

class _NumberSphereIconState extends State<NumberSphereIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _c
        ..stop()
        ..value = 0.3;
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
    final hc = AccessibilityUtils.isHighContrast(context);
    final s = widget.size;
    switch (widget.mode) {
      case NumArt.countObjects:
      case NumArt.tally:
      case NumArt.sort:
      case NumArt.sudoku:
        return SizedBox(width: s, height: s, child: CustomPaint(painter: _EmblemPainter(widget.mode, _c, hc)));
      case NumArt.grid:
        // Квадратот од 4 дела се врти во 3D.
        return SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.004)
                ..rotateY(_c.value * 2 * math.pi)
                ..rotateX(0.45 * math.sin(_c.value * 2 * math.pi)),
              child: child,
            ),
            child: CustomPaint(painter: _QuadSquarePainter(hc)),
          ),
        );
      case NumArt.recognize:
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.front ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutBack,
          builder: (context, m, _) => SizedBox(
            width: s,
            height: s,
            child: CustomPaint(painter: _SphereArtPainter(widget.mode, _c, widget.yaw, m, hc)),
          ),
        );
      case NumArt.biggerSmaller:
      case NumArt.operations:
      case NumArt.multiplyDivide:
      case NumArt.sequence:
        return SizedBox(width: s, height: s, child: CustomPaint(painter: _SphereArtPainter(widget.mode, _c, widget.yaw, 0, hc)));
    }
  }
}

/// Квадрат поделен на 4 обоени дела (за локаторот).
class _QuadSquarePainter extends CustomPainter {
  _QuadSquarePainter(this.hc);

  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final side = s * 0.62;
    final o = Offset((s - side) / 2, (s - side) / 2);
    const colors = [Color(0xFFFF6B6B), Color(0xFFFFC93C), Color(0xFF4ADE80), Color(0xFF60A5FA)];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(o.dx + (i % 2) * side / 2, o.dy + (i ~/ 2) * side / 2, side / 2, side / 2);
      canvas.drawRect(r, Paint()..color = hc ? (i.isEven ? Colors.black : Colors.white) : colors[i]);
    }
    final edge = Paint()
      ..color = hc ? const Color(0xFFFFFF00) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.04;
    canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, side, side), edge);
    canvas.drawLine(Offset(o.dx + side / 2, o.dy), Offset(o.dx + side / 2, o.dy + side), edge);
    canvas.drawLine(Offset(o.dx, o.dy + side / 2), Offset(o.dx + side, o.dy + side / 2), edge);
  }

  @override
  bool shouldRepaint(covariant _QuadSquarePainter old) => old.hc != hc;
}

class _SphereArtPainter extends CustomPainter {
  _SphereArtPainter(this.mode, this.t, this.yaw, this.morph, this.hc) : super(repaint: t);

  final NumArt mode;
  final Animation<double> t;
  final double yaw;
  final double morph;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final v = t.value;
    final ink = hc ? const Color(0xFFFFFF00) : Colors.white;
    switch (mode) {
      case NumArt.recognize:
        _question(canvas, s, c, v, 1 - morph);
        _safe(canvas, s, c, v, morph);
      case NumArt.biggerSmaller:
        _scale(canvas, s, c, v, ink);
      case NumArt.operations:
        _plusMinus(canvas, s, c, v, ink);
      case NumArt.multiplyDivide:
        _cubes(canvas, s, c, v);
      case NumArt.sequence:
        _chain(canvas, s, c, v);
      default:
        break;
    }
  }

  /// Неонско „?“ што трепка (како стара светлечка реклама).
  void _question(Canvas canvas, double s, Offset c, double v, double a) {
    if (a <= 0.01) return;
    final flicker = (math.sin(v * math.pi * 14) > 0.75 || math.sin(v * math.pi * 3.3) > 0.92) ? 0.45 : 1.0;
    final neon = hc ? const Color(0xFFFFFF00) : const Color(0xFF5EF2FF);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final sc = 0.7 + 0.3 * a;
    canvas.scale(sc, sc);
    for (final (blur, alpha) in [(s * 0.12, 0.55), (s * 0.05, 0.8), (0.0, 1.0)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: '?',
          style: TextStyle(
            fontSize: s * 0.82,
            fontWeight: FontWeight.w900,
            height: 1.0,
            foreground: Paint()
              ..style = blur == 0 ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = s * 0.06
              ..color = (blur == 0 ? Colors.white : neon).withValues(alpha: alpha * a * flicker)
              ..maskFilter = blur == 0 ? null : MaskFilter.blur(BlurStyle.normal, blur),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      tp.dispose();
    }
    canvas.restore();
  }

  /// Сеф со тркалце за шифра што се врти.
  void _safe(Canvas canvas, double s, Offset c, double v, double a) {
    if (a <= 0.01) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final sc = 0.6 + 0.4 * a;
    canvas.scale(sc, sc);
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a.clamp(0.0, 1.0)));
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 0.74, height: s * 0.7), Radius.circular(s * 0.08));
    // Длабочина (задниот раб).
    canvas.drawRRect(body.shift(Offset(s * 0.04, s * 0.04)), Paint()..color = hc ? Colors.white : const Color(0xFF2B2F36));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = (hc
                ? const LinearGradient(colors: [Colors.black, Colors.black])
                : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD9DEE5), Color(0xFF8A939E), Color(0xFF5C6570)]))
            .createShader(body.outerRect),
    );
    canvas.drawRRect(body, Paint()
      ..color = hc ? const Color(0xFFFFFF00) : const Color(0xFF3A4048)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03);
    // Тркалце.
    final dialR = s * 0.2;
    canvas.drawCircle(Offset.zero, dialR, Paint()..color = hc ? Colors.black : const Color(0xFF1F2933));
    canvas.drawCircle(Offset.zero, dialR, Paint()
      ..color = hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC93C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025);
    final rot = math.sin(v * math.pi * 2) * math.pi;
    for (var k = 0; k < 10; k++) {
      final ang = rot + k * math.pi / 5;
      final p1 = Offset(math.cos(ang), math.sin(ang)) * dialR * 0.72;
      final p2 = Offset(math.cos(ang), math.sin(ang)) * dialR * 0.95;
      canvas.drawLine(p1, p2, Paint()
        ..color = Colors.white
        ..strokeWidth = s * 0.015);
    }
    canvas.drawCircle(Offset.zero, dialR * 0.3, Paint()..color = hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC93C));
    // Рачка.
    canvas.drawLine(Offset(s * 0.27, -s * 0.12), Offset(s * 0.27, s * 0.12), Paint()
      ..color = hc ? Colors.white : const Color(0xFFE5E7EB)
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round);
    canvas.restore();
    canvas.restore();
  }

  /// 3D вага: нишањето зависи од вртењето на сферата.
  void _scale(Canvas canvas, double s, Offset c, double v, Color ink) {
    final tilt = math.sin(yaw * 2) * 0.38 + math.sin(v * math.pi * 2) * 0.05;
    final metal = hc ? ink : const Color(0xFFFFD36B);
    final dark = hc ? ink : const Color(0xFFB7791F);
    final top = c + Offset(0, -s * 0.2);
    // Столб и подножје (со сенка за длабочина).
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, s * 0.33), width: s * 0.42, height: s * 0.08), Radius.circular(s * 0.03)), Paint()..color = dark);
    canvas.drawRect(Rect.fromCenter(center: c + Offset(s * 0.012, s * 0.07), width: s * 0.06, height: s * 0.54), Paint()..color = dark);
    canvas.drawRect(Rect.fromCenter(center: c + Offset(0, s * 0.07), width: s * 0.05, height: s * 0.54), Paint()..color = metal);
    final dx = math.cos(tilt) * s * 0.36, dy = math.sin(tilt) * s * 0.36;
    final l = top - Offset(dx, dy), r = top + Offset(dx, dy);
    canvas.drawLine(l, r, Paint()
      ..color = metal
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(top, s * 0.045, Paint()..color = hc ? Colors.black : Colors.white);
    for (final (p, n) in [(l, '3'), (r, '8')]) {
      final pan = p + Offset(0, s * 0.2);
      final chain = Paint()
        ..color = metal.withValues(alpha: 0.85)
        ..strokeWidth = s * 0.015;
      canvas.drawLine(p, pan + Offset(-s * 0.12, 0), chain);
      canvas.drawLine(p, pan + Offset(s * 0.12, 0), chain);
      // Тасот: елипса (3D) со потемен долен дел.
      canvas.drawArc(Rect.fromCenter(center: pan, width: s * 0.28, height: s * 0.16), 0, math.pi, true, Paint()..color = dark);
      canvas.drawOval(Rect.fromCenter(center: pan, width: s * 0.28, height: s * 0.07), Paint()..color = metal);
      _drawCentered(canvas, n, pan + Offset(0, -s * 0.07), s * 0.15, hc ? const Color(0xFFFFFF00) : Colors.white);
    }
  }

  /// + и − што се приближуваат, се спојуваат во ± и пак се раздвојуваат.
  void _plusMinus(Canvas canvas, double s, Offset c, double v, Color ink) {
    final d = (math.cos(v * math.pi * 2) + 1) / 2; // 1 = раздвоени, 0 = споени
    final bar = s * 0.09;
    final len = s * 0.3;
    final plusC = c + Offset(-d * s * 0.2, -(1 - d) * s * 0.1);
    final minusC = c + Offset(d * s * 0.2, (1 - d) * s * 0.14);
    void glyph(Offset at, bool plus, Color col) {
      // 3D: потемна копија малку подолу-десно.
      for (final (off, color) in [(Offset(s * 0.025, s * 0.03), hc ? Colors.white : Color.lerp(col, Colors.black, 0.5)!), (Offset.zero, col)]) {
        final p = Paint()..color = color;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at + off, width: len, height: bar), Radius.circular(bar / 2)), p);
        if (plus) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at + off, width: bar, height: len), Radius.circular(bar / 2)), p);
        }
      }
    }

    glyph(plusC, true, hc ? ink : const Color(0xFF4ADE80));
    glyph(minusC, false, hc ? ink : const Color(0xFFFF8A65));
    if (d < 0.15 && !hc) {
      canvas.drawCircle(c, s * 0.3, Paint()
        ..color = Playful.sun.withValues(alpha: (0.15 - d) * 2.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.08));
    }
  }

  /// Изометриска коцка.
  void _cube(Canvas canvas, Offset at, double e, Color base) {
    final h = e * 0.5;
    final topP = Path()
      ..moveTo(at.dx, at.dy - e)
      ..lineTo(at.dx + e * 0.87, at.dy - h)
      ..lineTo(at.dx, at.dy)
      ..lineTo(at.dx - e * 0.87, at.dy - h)
      ..close();
    final leftP = Path()
      ..moveTo(at.dx - e * 0.87, at.dy - h)
      ..lineTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + e)
      ..lineTo(at.dx - e * 0.87, at.dy + h)
      ..close();
    final rightP = Path()
      ..moveTo(at.dx + e * 0.87, at.dy - h)
      ..lineTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + e)
      ..lineTo(at.dx + e * 0.87, at.dy + h)
      ..close();
    if (hc) {
      final edge = Paint()
        ..color = const Color(0xFFFFFF00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final p in [topP, leftP, rightP]) {
        canvas.drawPath(p, Paint()..color = Colors.black);
        canvas.drawPath(p, edge);
      }
      return;
    }
    canvas.drawPath(topP, Paint()..color = Color.lerp(base, Colors.white, 0.45)!);
    canvas.drawPath(leftP, Paint()..color = base);
    canvas.drawPath(rightP, Paint()..color = Color.lerp(base, Colors.black, 0.35)!);
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final p in [topP, leftP, rightP]) {
      canvas.drawPath(p, edge);
    }
  }

  /// Коцка што се дели на 4 помали и пак се спојува.
  void _cubes(Canvas canvas, double s, Offset c, double v) {
    final p = Curves.easeInOut.transform((math.sin(v * math.pi * 2 - math.pi / 2) + 1) / 2);
    final e = s * 0.3 * (1 - 0.5 * p);
    final spread = p * s * 0.2;
    const colors = [Color(0xFFFFC93C), Color(0xFFFF6B6B), Color(0xFF60A5FA), Color(0xFF4ADE80)];
    // Од задните кон предните (горе прво).
    final offsets = [Offset(0, -spread * 0.8), Offset(-spread, 0), Offset(spread, 0), Offset(0, spread * 0.8)];
    for (var i = 0; i < 4; i++) {
      _cube(canvas, c + offsets[i] + Offset(0, s * 0.02), e, p < 0.04 ? colors[0] : colors[i]);
    }
  }

  /// Синџир од светечки алки со бројки; третата алка е скршена.
  void _chain(Canvas canvas, double s, Offset c, double v) {
    const n = 4;
    const nums = ['2', '4', '?', '8'];
    const colors = [Color(0xFF60A5FA), Color(0xFF4ADE80), Color(0xFFFF6B6B), Color(0xFFFFC93C)];
    final lw = s * 0.27, lh = s * 0.19;
    final step = s * 0.2;
    final x0 = c.dx - step * (n - 1) / 2;
    for (var i = 0; i < n; i++) {
      final at = Offset(x0 + i * step, c.dy + (i.isEven ? -s * 0.03 : s * 0.03));
      final glow = 0.5 + 0.5 * math.sin((v * 2 - i * 0.25) * math.pi * 2);
      final col = hc ? const Color(0xFFFFFF00) : colors[i];
      final rect = Rect.fromCenter(center: at, width: lw, height: lh);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(lh / 2));
      if (!hc) {
        canvas.drawRRect(rr, Paint()
          ..color = col.withValues(alpha: 0.35 + 0.4 * glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03));
      }
      final link = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035;
      if (i == 2) {
        // Скршена алка: два лака со празнина горе-десно и искри.
        canvas.drawArc(rect, math.pi * 0.15, math.pi * 1.2, false, link);
        canvas.drawArc(rect, math.pi * 1.55, math.pi * 0.25, false, link);
        final sp = at + Offset(lw * 0.36, -lh * 0.42);
        canvas.drawPath(_starPath(sp, s * 0.05 * (0.6 + 0.4 * glow), s * 0.02), Paint()..color = hc ? Colors.white : Colors.white);
      } else {
        canvas.drawRRect(rr, link);
      }
      _drawCentered(canvas, nums[i], at, s * 0.12, hc ? Colors.white : Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _SphereArtPainter old) => old.mode != mode || old.yaw != yaw || old.morph != morph || old.hc != hc;
}