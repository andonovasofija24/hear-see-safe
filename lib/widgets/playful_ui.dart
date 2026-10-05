import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../braille/braille_data.dart';
import '../utils/accessibility_utils.dart';
import '../utils/voice_hotkey.dart';
import '../utils/voice_level.dart';

/// Множител за читливиот текст во заедничките делови (објаснување,
/// напредок, резултат, плочки, совети). Не важи за Playful.display/title/body
/// (екраните сами ги зголемуваат своите големини).
const double _kPlayText = 1.55;

/// Заеднички изглед за почетниот екран и екранот за јазик: темна „ноќна“
/// позадина (бел текст = силен контраст), полни бои на картичките и брајови
/// точки како мотив. Сите бои на картичките се избрани така што белиот текст
/// врз нив има контраст од најмалку 4.5:1.
abstract final class Playful {
  /// Длабоко индиго - основа.
  static const Color night = Color(0xFF14134A);
  static const Color nightDeep = Color(0xFF0C0B33);
  static const Color nightRaised = Color(0xFF23216B);

  /// Сончоглед - главен акцент (копче за глас, фокус, клучеви).
  static const Color sun = Color(0xFFFFC93C);

  /// Мастило - темен текст врз светли/жолти површини.
  static const Color ink = Color(0xFF14134A);

  static const Color paper = Colors.white;
  static const Color mist = Color(0xFFD7D9FF);

  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1C1A63), night, nightDeep],
    stops: [0.0, 0.5, 1.0],
  );

  static TextStyle display(double size, {Color color = paper}) => GoogleFonts.lexend(
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle title(double size, {Color color = paper}) => GoogleFonts.lexend(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: color,
      );

  static TextStyle body(double size, {Color color = paper}) => GoogleFonts.lexend(
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: color,
      );

  /// Дали уредот бара помалку движење (системска поставка).
  static bool reduceMotion(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Позадина со брајови точки што полека лебдат нагоре. Реагира на звукот
/// (VoiceLevel): кога некој зборува додека апликацијата слуша, или кога
/// апликацијата зборува, точките светат и скокаат, а бранот долу расте.
class BrailleBackdrop extends StatefulWidget {
  const BrailleBackdrop({super.key});

  @override
  State<BrailleBackdrop> createState() => _BrailleBackdropState();
}

class _BrailleBackdropState extends State<BrailleBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))
    ..addListener(_tick);

  /// Измазната „енергија“ на звукот (0..1).
  double _energy = 0;
  final Stopwatch _clock = Stopwatch()..start();

  void _tick() {
    final secs = _clock.elapsedMilliseconds / 1000.0;
    var target = VoiceLevel.level.value;
    if (VoiceLevel.speaking.value) {
      // Апликацијата зборува - мек ритам како говор.
      target = math.max(target, 0.28 + 0.18 * math.sin(secs * 9) * math.sin(secs * 2.3).abs());
    } else if (VoiceLevel.listening.value) {
      target = math.max(target, 0.12);
    }
    _energy += (target - _energy) * 0.12;
  }

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
            child: CustomPaint(
              painter: _BackdropPainter(_c, () => _energy),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.energy) : super(repaint: t);

  final Animation<double> t;
  final double Function() energy;

  static const _colors = [
    Color(0xFFFFC93C),
    Color(0xFF5EEAD4),
    Color(0xFFF472B6),
    Color(0xFF93C5FD),
    Color(0xFFC4B5FD),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Неколку меки светла.
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.9, size.height * 0.08), size.width * 0.55, const Color(0xFF6D28D9).withValues(alpha: 0.35));
    glow(Offset(size.width * 0.05, size.height * 0.55), size.width * 0.6, const Color(0xFF0E7490).withValues(alpha: 0.28));
    glow(Offset(size.width * 0.8, size.height * 0.95), size.width * 0.5, const Color(0xFFBE185D).withValues(alpha: 0.22));

    final e = energy();

    // Звучен бран долу - мирен кога е тивко, расте со гласот.
    final waveY = size.height * 0.9;
    final unitW = math.max(size.width, 360.0) / 60;
    for (var layer = 0; layer < 2; layer++) {
      final path = Path();
      final amp = unitW * (0.6 + e * 7) * (layer == 0 ? 1.0 : 0.6);
      final freq = layer == 0 ? 2.2 : 3.4;
      final shift = t.value * math.pi * 2 * (layer == 0 ? 30 : -22);
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = waveY + math.sin(x / size.width * math.pi * 2 * freq + shift) * amp;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 0 ? 4 : 3
          ..strokeCap = StrokeCap.round
          ..color = (layer == 0 ? const Color(0xFFFFC93C) : const Color(0xFF5EEAD4)).withValues(alpha: 0.18 + 0.55 * e),
      );
    }

    // Брајови ќелии (2x3 точки) што лебдат нагоре и малку се нишаат.
    final rnd = math.Random(7);
    const cells = 14;
    final unit = math.max(size.width, 360.0) / 60;
    for (var i = 0; i < cells; i++) {
      final baseX = rnd.nextDouble();
      final speed = 0.5 + rnd.nextDouble();
      final phase = rnd.nextDouble();
      final scale = 0.7 + rnd.nextDouble() * 0.9;
      final pattern = 1 + rnd.nextInt(62);
      final color = _colors[i % _colors.length];
      final p = (phase + t.value * speed) % 1.0;
      final y = size.height * (1.1 - p * 1.25);
      final x = size.width * baseX + math.sin((p + phase) * math.pi * 2) * unit * 2;
      final bounce = e * unit * 2.5 * math.sin((t.value * 400 + i) % (math.pi * 2));
      final alpha = math.min(0.9, (0.10 + 0.16 * math.sin(p * math.pi)) * (1 + 2.2 * e));
      final r = unit * 0.55 * scale * (1 + 0.5 * e);
      final gap = unit * 1.6 * scale;
      for (var d = 0; d < 6; d++) {
        final on = (pattern >> d) & 1 == 1;
        final col = d < 3 ? 0 : 1;
        final row = d % 3;
        final c = Offset(x + col * gap, y + row * gap - bounce);
        if (on) {
          canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: alpha));
        } else {
          canvas.drawCircle(
            c,
            r * 0.8,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = color.withValues(alpha: alpha * 0.6),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// Влез со „скок“: елементот се појавува и малку се зголемува преку мерката,
/// со задоцнување по `index` (за редоследно појавување).
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.index = 0, this.stepMs = 70, this.startMs = 120});

  final Widget child;
  final int index;
  final int stepMs;
  final int startMs;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Playful.reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    // Најмногу ~10 чекори задоцнување - елементите подолу во листата се
    // градат дури при лизгање и не смеат да чекаат предолго.
    Future.delayed(Duration(milliseconds: widget.startMs + math.min(widget.index, 10) * widget.stepMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOut));
    return FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: scale,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 24 * (1 - scale.value)),
          child: Transform.scale(scale: 0.88 + 0.12 * scale.value, child: child),
        ),
        child: widget.child,
      ),
    );
  }
}

/// При допир/клик елементот малку се „притиска“ (се смалува), за да се види
/// дека е допрен.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Звучни бранови: кругови што се шират околу `child` (копчето-микрофон).
/// `active` = побрзи, посилни бранови (додека се слуша).
class RippleRings extends StatefulWidget {
  const RippleRings({super.key, required this.child, required this.color, this.active = false, this.spread = 26});

  final Widget child;
  final Color color;
  final bool active;
  final double spread;

  @override
  State<RippleRings> createState() => _RippleRingsState();
}

class _RippleRingsState extends State<RippleRings> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RippleRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _c.duration = Duration(milliseconds: widget.active ? 1100 : 2400);
    if (Playful.reduceMotion(context)) {
      _c.stop();
    } else {
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
    return CustomPaint(
      painter: _RingsPainter(_c, widget.color, widget.spread, widget.active),
      child: widget.child,
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color, this.spread, this.active) : super(repaint: t);

  final AnimationController t;
  final Color color;
  final double spread;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (t.value == 0 && !t.isAnimating) return;
    final rect = Offset.zero & size;
    final baseRadius = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t.value + i / 3) % 1.0;
      final grow = spread * p;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 4 : 3
        ..color = color.withValues(alpha: (1 - p) * (active ? 0.75 : 0.5));
      final r = RRect.fromRectAndRadius(rect.inflate(grow), Radius.circular(baseRadius + grow));
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.color != color || old.active != active || old.spread != spread;
}

/// Една брајова ќелија (6 точки) што ги пали точките по ред - знакот на
/// апликацијата во заглавието.
class BrailleCellMark extends StatefulWidget {
  const BrailleCellMark({super.key, this.size = 56, this.color = Playful.sun});

  final double size;
  final Color color;

  @override
  State<BrailleCellMark> createState() => _BrailleCellMarkState();
}

class _BrailleCellMarkState extends State<BrailleCellMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Playful.reduceMotion(context)) {
      _c.value = 0.5;
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
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size * 0.66,
        height: widget.size,
        child: CustomPaint(painter: _CellPainter(_c, widget.color)),
      ),
    );
  }
}

class _CellPainter extends CustomPainter {
  _CellPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  // Редослед на палење: 1,4,2,5,3,6 (по редови), па сите се гасат.
  static const _order = [0, 3, 1, 4, 2, 5];

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.2;
    final colX = [size.width * 0.25, size.width * 0.75];
    final rowY = [size.height * 0.17, size.height * 0.5, size.height * 0.83];
    final lit = (t.value * 8).floor(); // 0..7: 6 точки + 2 чекори пауза
    for (var d = 0; d < 6; d++) {
      final c = Offset(colX[d ~/ 3], rowY[d % 3]);
      final on = _order.indexOf(d) < lit && lit <= 6;
      canvas.drawCircle(
        c,
        r,
        Paint()..color = on ? color : color.withValues(alpha: 0.18),
      );
      if (!on) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CellPainter old) => old.color != color;
}

/// Тастер од тастатура (ESC, Г, M, < >) - за упатствата.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.size = 1.0, this.background = Playful.sun, this.foreground = Playful.ink});

  final String label;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: 48 * size, minHeight: 48 * size),
      padding: EdgeInsets.symmetric(horizontal: 10 * size),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12 * size),
        border: Border(bottom: BorderSide(color: Color.lerp(background, Colors.black, 0.35)!, width: 4 * size)),
      ),
      child: Text(label, style: Playful.display(20 * size, color: foreground)),
    );
  }
}

// =====================================================================
// Брајово писмо како дел од изгледот.
// =====================================================================

/// Брајовиот јазик според јазикот на апликацијата.
BrailleLang brailleLangFor(String languageCode) {
  switch (languageCode) {
    case 'en':
      return BrailleLang.en;
    case 'sq':
      return BrailleLang.sq;
    default:
      return BrailleLang.mk;
  }
}

/// Текст → брајови ќелии (буква + точки). Празно место = null (нов збор).
/// Знаците што ги нема во азбуката (пр. &, –) се прескокнуваат. Ги
/// препознава и албанските двојни букви (sh, gj, ...).
List<(String, List<int>)?> brailleCellsFor(String text, BrailleLang lang) {
  final map = {for (final s in BrailleData.lettersFor(lang)) s.char: s.dots};
  final lower = text.toLowerCase();
  final out = <(String, List<int>)?>[];
  var i = 0;
  while (i < lower.length) {
    final ch = lower[i];
    if (ch.trim().isEmpty) {
      if (out.isNotEmpty && out.last != null) out.add(null);
      i++;
      continue;
    }
    if (i + 1 < lower.length && map.containsKey(lower.substring(i, i + 2))) {
      out.add((text.substring(i, i + 2), map[lower.substring(i, i + 2)]!));
      i += 2;
      continue;
    }
    final dots = map[ch];
    if (dots != null) out.add((text[i], dots));
    i++;
  }
  while (out.isNotEmpty && out.last == null) {
    out.removeLast();
  }
  return out;
}

/// Една брајова ќелија нацртана „испакнато“: точките се како мали копчиња
/// со сенка, празните места се вдлабнати. `pop` (0..1 за секоја точка по
/// ред) ги „искокнува“ точките.
class _CellDotsPainter extends CustomPainter {
  _CellDotsPainter({required this.dots, required this.pop, required this.dotColor, required this.holeColor, this.glow = 0});

  final List<int> dots;
  final double Function(int order) pop;
  final Color dotColor;
  final Color holeColor;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.19;
    final xs = [size.width * 0.27, size.width * 0.73];
    final ys = [size.height * 0.18, size.height * 0.5, size.height * 0.82];
    final sorted = [...dots]..sort();
    for (var n = 1; n <= 6; n++) {
      final c = Offset(xs[(n - 1) ~/ 3], ys[(n - 1) % 3]);
      // Вдлабнато место (секогаш се гледа - ја покажува формата на ќелијата).
      canvas.drawCircle(c, r * 0.72, Paint()..color = holeColor);
      final order = sorted.indexOf(n);
      if (order < 0) continue;
      final p = pop(order).clamp(0.0, 1.4);
      if (p <= 0) continue;
      final rr = r * p;
      // Сенка под точката.
      canvas.drawCircle(c + Offset(0, rr * 0.28), rr, Paint()..color = Colors.black.withValues(alpha: 0.35));
      // Точката со сјај (испакнат изглед).
      final rect = Rect.fromCircle(center: c, radius: rr);
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            colors: [Color.lerp(dotColor, Colors.white, 0.75)!, dotColor, Color.lerp(dotColor, Colors.black, 0.25)!],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(rect),
      );
      if (glow > 0) {
        canvas.drawCircle(c, rr * 1.5, Paint()..color = Colors.white.withValues(alpha: 0.35 * glow));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CellDotsPainter old) => true;
}

/// Испакната брајова ќелија (пр. првата буква од името на играта) со
/// буквата под неа. Точките искокнуваат една по една при појавување.
class EmbossedBrailleCell extends StatefulWidget {
  const EmbossedBrailleCell({
    super.key,
    required this.dots,
    required this.letter,
    this.size = 44,
    this.dotColor = Playful.sun,
    this.plateColor = const Color(0x33000000),
    this.letterColor = Colors.white,
    this.delayMs = 300,
  });

  final List<int> dots;
  final String letter;
  final double size;
  final Color dotColor;
  final Color plateColor;
  final Color letterColor;
  final int delayMs;

  @override
  State<EmbossedBrailleCell> createState() => _EmbossedBrailleCellState();
}

class _EmbossedBrailleCellState extends State<EmbossedBrailleCell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Playful.reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _pop(int order) {
    final n = math.max(widget.dots.length, 1);
    final start = order / (n + 1);
    final local = ((_c.value - start) / (1.6 / (n + 1))).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(local);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size * 0.72;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w + 14,
            height: widget.size + 14,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: widget.plateColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size(w, widget.size),
                painter: _CellDotsPainter(
                  dots: widget.dots,
                  pop: _pop,
                  dotColor: widget.dotColor,
                  holeColor: Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: CurvedAnimation(parent: _c, curve: const Interval(0.6, 1.0)),
            child: Text(widget.letter.toUpperCase(), style: Playful.display(widget.size * 0.42, color: widget.letterColor)),
          ),
        ],
      ),
    );
  }
}

/// Текст „напишан“ на Брајово писмо: ќелиите се појавуваат една по една
/// (точките искокнуваат), а под секоја се појавува печатената буква. Потоа,
/// на секои неколку секунди, светлина поминува преку ќелиите.
class BrailleWordReveal extends StatefulWidget {
  const BrailleWordReveal({
    super.key,
    required this.text,
    required this.lang,
    this.cellSize = 30,
    this.dotColor = Playful.sun,
    this.letterColor = Colors.white,
    this.alignment = WrapAlignment.start,
    this.showLetters = true,
  });

  /// Печатените букви под точките (исклучено кога текстот веќе е над нив).
  final bool showLetters;
  final String text;
  final BrailleLang lang;
  final double cellSize;
  final Color dotColor;
  final Color letterColor;
  final WrapAlignment alignment;

  @override
  State<BrailleWordReveal> createState() => _BrailleWordRevealState();
}

class _BrailleWordRevealState extends State<BrailleWordReveal> with TickerProviderStateMixin {
  static const _stepMs = 140;
  late List<(String, List<int>)?> _cells = brailleCellsFor(widget.text, widget.lang);
  late int _count = _cells.where((c) => c != null).length;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 500 + _count * _stepMs),
  );
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 6500));
  bool _started = false;

  @override
  void didUpdateWidget(covariant BrailleWordReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.lang != widget.lang) {
      _cells = brailleCellsFor(widget.text, widget.lang);
      _count = _cells.where((c) => c != null).length;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Playful.reduceMotion(context)) {
      _reveal.value = 1;
      return;
    }
    _reveal.forward().whenComplete(() {
      if (mounted) _shine.repeat();
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _reveal.duration!.inMilliseconds.toDouble();
    final cellW = widget.cellSize * 0.66;
    // Групирај по зборови.
    final words = <List<(int, String, List<int>)>>[[]];
    var idx = 0;
    for (final c in _cells) {
      if (c == null) {
        words.add([]);
      } else {
        words.last.add((idx++, c.$1, c.$2));
      }
    }

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([_reveal, _shine]),
        builder: (context, _) {
          final elapsed = _reveal.value * totalMs;
          // Светлината поминува во првите 40% од секој циклус.
          final shinePos = _shine.isAnimating ? (_shine.value / 0.4) * (_count + 2) - 1 : -10.0;
          return Wrap(
            alignment: widget.alignment,
            spacing: widget.cellSize * 0.55,
            runSpacing: widget.cellSize * 0.35,
            children: [
              for (final word in words)
                if (word.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, letter, dots) in word)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: widget.cellSize * 0.08),
                          child: Builder(builder: (context) {
                            final local = ((elapsed - i * _stepMs) / 420).clamp(0.0, 1.0);
                            final glow = (1 - (shinePos - i).abs()).clamp(0.0, 1.0);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CustomPaint(
                                  size: Size(cellW, widget.cellSize),
                                  painter: _CellDotsPainter(
                                    dots: dots,
                                    pop: (order) {
                                      final n = dots.length;
                                      final start = order / (n + 2);
                                      return Curves.easeOutBack.transform(((local - start) * 2.2).clamp(0.0, 1.0));
                                    },
                                    dotColor: Color.lerp(widget.dotColor, Colors.white, glow * 0.6)!,
                                    holeColor: Colors.white.withValues(alpha: 0.10),
                                    glow: glow,
                                  ),
                                ),
                                if (widget.showLetters) ...[
                                  SizedBox(height: widget.cellSize * 0.12),
                                  Opacity(
                                    opacity: ((local - 0.55) / 0.45).clamp(0.0, 1.0),
                                    child: Text(letter, style: Playful.title(widget.cellSize * 0.5, color: widget.letterColor)),
                                  ),
                                ],
                              ],
                            );
                          }),
                        ),
                    ],
                  ),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// Звук што се гледа.
// =====================================================================

/// Текст што светнува збор по збор додека се слуша снимката (караоке).
/// `progress` = 0..1 колку од снимката е изговорено.
class KaraokeText extends StatelessWidget {
  const KaraokeText({
    super.key,
    required this.text,
    required this.progress,
    required this.style,
    this.activeColor = Playful.sun,
    this.idleColor = const Color(0xFFB8BBEA),
    this.doneColor = Colors.white,
  });

  final String text;
  final ValueListenable<double> progress;
  final TextStyle style;
  final Color activeColor;
  final Color idleColor;
  final Color doneColor;

  @override
  Widget build(BuildContext context) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final weights = [for (final w in words) w.length + 2];
    final total = weights.fold<int>(0, (a, b) => a + b);
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, _) {
        final spoken = p * total;
        var acc = 0;
        final spans = <TextSpan>[];
        for (var i = 0; i < words.length; i++) {
          final start = acc;
          acc += weights[i];
          final Color color;
          if (p >= 1 || spoken >= acc) {
            color = doneColor;
          } else if (spoken >= start) {
            color = activeColor;
          } else {
            color = idleColor;
          }
          spans.add(TextSpan(
            text: i == words.length - 1 ? words[i] : '${words[i]} ',
            style: style.copyWith(color: color),
          ));
        }
        return Text.rich(TextSpan(children: spans));
      },
    );
  }
}

/// Столбчиња што скокаат според гласот (VoiceLevel) додека се слуша.
class SoundWave extends StatefulWidget {
  const SoundWave({super.key, this.color = Playful.ink, this.bars = 9, this.height = 30, this.barWidth = 5});

  final Color color;
  final int bars;
  final double height;
  final double barWidth;

  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..addListener(_tick);
  double _energy = 0;
  final Stopwatch _clock = Stopwatch()..start();

  void _tick() => _energy += (VoiceLevel.level.value - _energy) * 0.25;

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
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final secs = _clock.elapsedMilliseconds / 1000.0;
          return SizedBox(
            height: widget.height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.bars; i++)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: widget.barWidth * 0.35),
                    width: widget.barWidth,
                    height: widget.height *
                        (0.18 +
                                0.12 * (0.5 + 0.5 * math.sin(secs * 5 + i * 0.9)) +
                                _energy * (0.45 + 0.25 * math.sin(secs * 13 + i * 1.7)) *
                                    (1 - (i - (widget.bars - 1) / 2).abs() / widget.bars))
                            .clamp(0.12, 1.0),
                    decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(widget.barWidth)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Облик на балонче за говор (опашка долу лево) - за InkWell/Material.
class SpeechBubbleBorder extends ShapeBorder {
  const SpeechBubbleBorder({this.radius = 28, this.tail = 18, this.side = BorderSide.none});

  final double radius;
  final double tail;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: tail);

  Path _path(Rect rect) {
    final body = Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - tail);
    final path = Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    final x = body.left + radius + 6;
    path
      ..moveTo(x, body.bottom - 2)
      ..lineTo(x - 4, body.bottom + tail)
      ..lineTo(x + tail * 1.4, body.bottom - 2)
      ..close();
    return path;
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => SpeechBubbleBorder(radius: radius * t, tail: tail * t, side: side.scale(t));
}

/// Темна позадина за квиз: сликите (емоџи) од категоријата полека лебдат,
/// со меко светло во бојата на категоријата. Реагира на звукот (VoiceLevel)
/// исто како позадината на почетниот екран.
class EmojiBackdrop extends StatefulWidget {
  const EmojiBackdrop({super.key, required this.emojis, required this.tint});

  final List<String> emojis;
  final Color tint;

  @override
  State<EmojiBackdrop> createState() => _EmojiBackdropState();
}

class _EmojiBackdropState extends State<EmojiBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 36))
    ..addListener(_tick);
  double _energy = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, TextPainter> _cache = {};

  void _tick() {
    final secs = _clock.elapsedMilliseconds / 1000.0;
    var target = VoiceLevel.level.value;
    if (VoiceLevel.speaking.value) {
      target = math.max(target, 0.25 + 0.15 * math.sin(secs * 9) * math.sin(secs * 2.3).abs());
    }
    _energy += (target - _energy) * 0.12;
  }

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
    for (final p in _cache.values) {
      p.dispose();
    }
    super.dispose();
  }

  TextPainter _painter(String emoji) => _cache.putIfAbsent(emoji, () {
        return TextPainter(
          text: TextSpan(text: emoji, style: const TextStyle(fontSize: 64)),
          textDirection: TextDirection.ltr,
        )..layout();
      });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: Playful.background),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _EmojiBackdropPainter(_c, () => _energy, widget.emojis, widget.tint, _painter),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiBackdropPainter extends CustomPainter {
  _EmojiBackdropPainter(this.t, this.energy, this.emojis, this.tint, this.painterFor) : super(repaint: t);

  final Animation<double> t;
  final double Function() energy;
  final List<String> emojis;
  final Color tint;
  final TextPainter Function(String) painterFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || emojis.isEmpty) return;
    final e = energy();
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.15, size.height * 0.12), size.shortestSide * 0.8, tint.withValues(alpha: 0.35 + 0.2 * e));
    glow(Offset(size.width * 0.95, size.height * 0.75), size.shortestSide * 0.7, const Color(0xFF0E7490).withValues(alpha: 0.3));

    final rnd = math.Random(11);
    const count = 16;
    for (var i = 0; i < count; i++) {
      final baseX = rnd.nextDouble();
      final speed = 0.4 + rnd.nextDouble() * 0.8;
      final phase = rnd.nextDouble();
      final scale = 0.45 + rnd.nextDouble() * 0.6;
      final p = (phase + t.value * speed) % 1.0;
      final tp = painterFor(emojis[i % emojis.length]);
      final x = size.width * baseX + math.sin((p + phase) * math.pi * 2) * 24;
      final y = size.height * (1.1 - p * 1.3);
      final alpha = math.min(0.55, (0.14 + 0.1 * math.sin(p * math.pi)) * (1 + 1.6 * e));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin((p + phase) * math.pi * 4) * 0.25);
      final s = scale * (1 + 0.25 * e);
      canvas.scale(s, s);
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: alpha));
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _EmojiBackdropPainter old) => old.tint != tint || old.emojis != emojis;
}


// =====================================================================
// Заеднички делови за игрите (ноќен изглед): објаснување, напредок по
// рунди, голем „звучен круг“, екран со резултат.
// =====================================================================

/// Копче „Прикажи / Скриј објаснување“ - проѕирно со бел раб.
class PlayfulExplainButton extends StatelessWidget {
  const PlayfulExplainButton({super.key, required this.open, required this.label, required this.onTap, this.compact = false});

  final bool open;
  final String label;
  final VoidCallback onTap;

  /// Понизок изглед - за екрани каде играта треба повеќе место.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getPrimaryButtonForeground(context) : Colors.white;
    return ExplainHotkeyListener(
      onTrigger: onTap,
      child: Semantics(
      label: label,
      button: true,
      child: PressableScale(
        child: Material(
          color: hc ? AccessibilityUtils.getPrimaryButtonBackground(context) : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: compact ? 8 : 15, horizontal: compact ? 14 : 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white.withValues(alpha: 0.6), width: 2),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(open ? Icons.expand_less_rounded : Icons.menu_book_rounded, size: compact ? 28 : 36, color: hc ? fg : Playful.sun),
                    SizedBox(width: compact ? 8 : 10),
                    Flexible(child: Text(label, style: Playful.title((compact ? 16 : 19) * _kPlayText, color: fg))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Отвореното објаснување - бела картичка со темен текст и златен раб.
class PlayfulExplainPanel extends StatelessWidget {
  const PlayfulExplainPanel({super.key, required this.icon, required this.title, required this.text, required this.accent});

  final IconData icon;
  final String title;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? Colors.white : Playful.ink;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: hc ? Colors.white : Playful.sun, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: hc ? Colors.white : accent, size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Playful.title(20 * _kPlayText, color: fg))),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: Playful.body(17.5 * _kPlayText, color: fg)),
        ],
      ),
    );
  }
}

/// Наслов на рундата + лента од сегменти (поминати - злато, тековна -
/// поголема).
class RoundProgress extends StatelessWidget {
  const RoundProgress({super.key, required this.label, required this.current, required this.total, this.extra, this.trailing});

  final String label;
  final int current; // 0-базирано
  final int total;
  final String? extra;

  /// По избор: копче на крајот од насловниот ред (пр. гласовна команда).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    return Semantics(
      container: true,
      label: extra == null ? label : '$label. $extra',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: ExcludeSemantics(child: Text(label, style: Playful.display(24 * _kPlayText, color: fg)))),
              if (extra != null)
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Playful.sun,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: hc ? 1.5 : 2),
                    ),
                    child: Text(extra!, style: TextStyle(fontSize: 16 * _kPlayText, fontWeight: FontWeight.w900, color: hc ? Colors.white : Playful.ink)),
                  ),
                ),
              // Копчето (пр. гласовна команда) останува посебно копче за
              // читачот на екран.
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
                      height: i == current ? 11 : 7,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: i <= current
                            ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
                            : (hc ? Colors.white24 : Colors.white.withValues(alpha: 0.22)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Голем жолт круг (пушти звук / почни) со бранови додека свири.
class SoundOrb extends StatelessWidget {
  const SoundOrb({super.key, required this.icon, required this.label, required this.onTap, this.active = false, this.size = 124});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Semantics(
      label: label,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RippleRings(
              color: hc ? Colors.white : Playful.sun,
              active: active,
              spread: 24,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                scale: active ? 1.08 : 1.0,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hc ? Colors.black : Playful.sun,
                    border: Border.all(color: Colors.white, width: hc ? 3 : 4),
                    boxShadow: hc ? null : [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 24)],
                  ),
                  child: Center(
                    child: active && !hc
                        ? SoundWave(color: Playful.ink, bars: 7, height: size * 0.4, barWidth: 6)
                        : Icon(icon, size: size * 0.48, color: hc ? Colors.white : Playful.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Text(label, textAlign: TextAlign.center, style: Playful.title(20 * _kPlayText, color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Крај на играта: трофеј со бранови, текстот и „Играј повторно“.
class PlayfulResult extends StatelessWidget {
  const PlayfulResult({super.key, required this.text, required this.buttonLabel, required this.onAgain, this.stars, this.total});

  final String text;
  final String buttonLabel;
  final VoidCallback onAgain;
  final int? stars;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - 560) / 2).clamp(24.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 24, side, 32),
          children: [
            PopIn(
              child: Center(
                child: RippleRings(
                  color: hc ? Colors.white : Playful.sun,
                  spread: 24,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Playful.night,
                      shape: BoxShape.circle,
                      border: Border.all(color: hc ? Colors.white : Playful.sun, width: 5),
                    ),
                    child: Icon(Icons.emoji_events_rounded, size: 76, color: hc ? const Color(0xFFFFFF00) : Playful.sun),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (stars != null && total != null && total! > 0) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (var i = 0; i < total!; i++)
                    PopIn(
                      index: 1 + i,
                      stepMs: 50,
                      child: Icon(
                        i < stars! ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: total! > 12 ? 30 : 40,
                        color: i < stars! ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFF59E0B)) : fg.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            PopIn(index: 2, child: Text(text, textAlign: TextAlign.center, style: Playful.title(22 * _kPlayText, color: fg))),
            const SizedBox(height: 28),
            PressableScale(
              child: Material(
                color: hc ? Colors.black : Playful.sun,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onAgain,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: hc ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh_rounded, color: hc ? Colors.white : Playful.ink, size: 36),
                        const SizedBox(width: 10),
                        Flexible(child: Text(buttonLabel, style: Playful.title(20 * _kPlayText, color: hc ? Colors.white : Playful.ink))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Плочка со звук (икона + име) во полна боја: затемнет градиент (бел
/// текст секогаш читлив), бел раб, сјај; `flash` = свети (се пушта),
/// `state` = null / true (точно) / false (погрешно).
class SoundTile extends StatelessWidget {
  const SoundTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.dimmed = false,
    this.flash = false,
    this.state,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;
  final bool dimmed;
  final bool flash;
  final bool? state;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    var c = color;
    if (state == true) c = const Color(0xFF16A34A);
    if (state == false) c = const Color(0xFFDC2626);
    final top = Color.lerp(c, Colors.black, 0.05)!;
    final bottom = Color.lerp(c, Colors.black, 0.42)!;
    return Semantics(
      label: label,
      button: enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: dimmed ? 0.35 : 1.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: flash || state != null ? 1.06 : 1.0,
          child: AbsorbPointer(
            absorbing: !enabled,
            child: PressableScale(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: hc ? (flash ? Colors.white24 : Colors.black) : null,
                      gradient: hc
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: flash ? [Colors.white, Color.lerp(c, Colors.white, 0.4)!] : [top, bottom],
                            ),
                      border: Border.all(color: flash ? Playful.sun : Colors.white.withValues(alpha: hc ? 1 : 0.85), width: flash ? 5 : 3),
                      boxShadow: hc ? null : [BoxShadow(color: (flash ? Playful.sun : c).withValues(alpha: flash ? 0.7 : 0.4), blurRadius: flash ? 26 : 14)],
                    ),
                    child: ExcludeSemantics(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
                          final iconSize = shortSide * (showLabel ? 0.46 : 0.62);
                          // Поголем натпис, но ограничен според плочката (икона + натпис да собере).
                          final labelSize = math.min(19 * _kPlayText, shortSide * 0.22);
                          final fg = flash && !hc ? Color.lerp(c, Colors.black, 0.45)! : Colors.white;
                          return Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: iconSize, color: fg),
                                    if (showLabel) ...[
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(label, style: GoogleFonts.lexend(fontSize: labelSize, fontWeight: FontWeight.w800, color: fg)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (state != null)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: c, width: 2)),
                                    child: Icon(state! ? Icons.check_rounded : Icons.close_rounded, color: c, size: 22),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Секундарно копче (пушти повторно / слушај пак): проѕирно, бел раб.
class PlayfulGhostButton extends StatelessWidget {
  const PlayfulGhostButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          enabled: onTap != null,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 31, color: hc ? fg : Playful.sun),
            label: Text(label, style: Playful.title(17 * _kPlayText, color: fg)),
            style: OutlinedButton.styleFrom(
              backgroundColor: hc ? Colors.black : Colors.white.withValues(alpha: 0.1),
              side: BorderSide(color: hc ? fg : Colors.white.withValues(alpha: 0.7), width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кратка инструкција на темна позадина (бел текст, во проѕирна лента).
class PlayfulHint extends StatelessWidget {
  const PlayfulHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hc ? fg : Colors.white.withValues(alpha: 0.25), width: hc ? 2 : 1),
      ),
      child: Text(text, textAlign: TextAlign.center, style: Playful.body(17 * _kPlayText, color: fg)),
    );
  }
}

/// Мрежа од плочки БЕЗ сопствено лизгање (редови со иста ширина) - за
/// во листа што веќе се лизга, без вгнездени лизгачи.
class PlayfulGrid extends StatelessWidget {
  const PlayfulGrid({super.key, required this.columns, required this.children, this.spacing = 16, this.aspectRatio = 1.0});

  final int columns;
  final List<Widget> children;
  final double spacing;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: start + c < children.length
                    ? AspectRatio(aspectRatio: aspectRatio, child: children[start + c])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}