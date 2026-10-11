import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'scene_contract.dart';

/// „Институции“: градски плоштад гледан од птичја перспектива.
///
/// Институциите се наредени една до друга во два реда (горе и долу), со
/// влезовите свртени кон плоштадот. Секоја има свој покрив за да се
/// препознае одозгора (купола на општината, хелиодром на болницата, црвен
/// покрив и двор на училиштето, столбови на музејот...). Во средина е
/// кружно плоштадче со фонтана - тоа е копчето за квизот (знак „?“).
///
/// * Допир на институција ја избира; допир на избраната ја отвора.
/// * [focusMode] (страницата на поимот): „камерата“ се спушта и се
///   центрира на избраната институција, а другите се затемнуваат. Текстот
///   за институцијата е под сцената (го прави екранот).
class InstitutionsSquareScene extends PbScene {
  const InstitutionsSquareScene({
    super.key,
    required super.items,
    required super.selected,
    required super.onSelect,
    required super.onOpen,
    required super.onQuiz,
    required super.quizLabel,
    required super.highContrast,
    super.reduceMotion,
    this.focusMode = false,
  });

  final bool focusMode;

  @override
  State<InstitutionsSquareScene> createState() => _InstitutionsSquareSceneState();
}

/// Видови згради - секој со свој покрив.
enum _Kind { cityHall, hospital, school, library, police, fire, post, museum, generic }

_Kind _kindFor(String id) {
  if (id.contains('city_hall')) return _Kind.cityHall;
  if (id.contains('hospital')) return _Kind.hospital;
  if (id.contains('school')) return _Kind.school;
  if (id.contains('library')) return _Kind.library;
  if (id.contains('police')) return _Kind.police;
  if (id.contains('fire')) return _Kind.fire;
  if (id.contains('post')) return _Kind.post;
  if (id.contains('museum')) return _Kind.museum;
  return _Kind.generic;
}

/// Боја на покривот за секој вид.
Color _roofColor(_Kind k) => switch (k) {
      _Kind.cityHall => const Color(0xFFD9C7A3),
      _Kind.hospital => const Color(0xFFEFF3F6),
      _Kind.school => const Color(0xFFC2563C),
      _Kind.library => const Color(0xFF7A5C93),
      _Kind.police => const Color(0xFF2F5D9E),
      _Kind.fire => const Color(0xFFB7322C),
      _Kind.post => const Color(0xFFE9B83A),
      _Kind.museum => const Color(0xFFE6DCC8),
      _Kind.generic => const Color(0xFFBFA987),
    };

class _InstitutionsSquareSceneState extends State<InstitutionsSquareScene> with SingleTickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _ambient.repeat();
  }

  @override
  void didUpdateWidget(covariant InstitutionsSquareScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _ambient.isAnimating) {
      _ambient.stop();
    } else if (!widget.reduceMotion && !_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  void _tap(int i) {
    if (i == widget.selected) {
      widget.onOpen();
    } else {
      widget.onSelect(i);
    }
  }

  /// Правоаголник на зградата [i] (горен ред 0..half-1, долен ред остатокот).
  Rect _lot(int i, int count, Size size) {
    final top = (count + 1) ~/ 2;
    final inTop = i < top;
    final rowCount = inTop ? top : count - top;
    final col = inTop ? i : i - top;
    final w = size.width;
    final h = size.height;
    const side = 0.045; // улица лево и десно
    const gap = 0.012;
    final usable = w * (1 - side * 2);
    final lotW = (usable - w * gap * (rowCount - 1)) / math.max(1, rowCount);
    final lotH = h * 0.27;
    final x = w * side + col * (lotW + w * gap);
    final y = inTop ? h * 0.035 : h - h * 0.035 - lotH;
    return Rect.fromLTWH(x, y, lotW, lotH);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final hc = widget.highContrast;
    final active = widget.selected.clamp(0, items.length - 1);
    final focus = widget.focusMode;
    final dur = widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 520);

    return LayoutBuilder(builder: (context, bounds) {
      final size = Size(bounds.maxWidth, bounds.maxHeight);
      final m = math.min(size.width, size.height);
      final lots = [for (var i = 0; i < items.length; i++) _lot(i, items.length, size)];

      // „Камера“: во режим на фокус се зумира и центрира на избраната.
      final target = lots[active].center;
      const zoom = 1.85;
      final Matrix4 camera = focus
          ? (Matrix4.identity()
            ..translate(size.width / 2, size.height / 2)
            ..scale(zoom, zoom)
            ..translate(-target.dx, -target.dy))
          : Matrix4.identity();

      final plazaR = m * 0.17;
      final plazaC = Offset(size.width / 2, size.height / 2);

      final world = SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) => CustomPaint(
                painter: _SquarePainter(hc: hc, t: _ambient.value, lots: lots),
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++)
            _building(i, lots[i], items.length, active, focus, hc, dur, m),
          // Плоштадчето во средина = квиз.
          Positioned(
            left: plazaC.dx - plazaR,
            top: plazaC.dy - plazaR,
            width: plazaR * 2,
            height: plazaR * 2,
            child: Semantics(
              button: true,
              label: widget.quizLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onQuiz,
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) => CustomPaint(
                    painter: _FountainQuizPainter(hc: hc, t: _ambient.value),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: dur,
          curve: Curves.easeInOutCubic,
          transform: camera,
          child: world,
        ),
      );
    });
  }

  Widget _building(int i, Rect lot, int count, int active, bool focus, bool hc, Duration dur, double m) {
    final item = widget.items[i];
    final chosen = i == active;
    final kind = _kindFor(item.id);
    final facesDown = i < (count + 1) ~/ 2; // горниот ред гледа надолу кон плоштадот
    final dim = focus && !chosen;
    final labelSize = (lot.width * 0.13).clamp(9.0, 15.0).toDouble();
    final emojiSize = (math.min(lot.width, lot.height) * 0.34).clamp(16.0, 40.0).toDouble();

    return Positioned.fromRect(
      rect: lot,
      child: Semantics(
        button: true,
        selected: chosen,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tap(i),
          child: AnimatedOpacity(
            duration: dur,
            opacity: dim ? 0.45 : 1,
            child: AnimatedScale(
              duration: dur,
              curve: Curves.easeOutBack,
              scale: chosen && !focus ? 1.06 : 1,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BuildingPainter(kind: kind, selected: chosen, hc: hc, facesDown: facesDown),
                  ),
                ),
                // Знак на покривот (емоџи на поимот).
                Align(
                  alignment: Alignment(0, facesDown ? -0.25 : 0.25),
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc ? Colors.black : Colors.white.withValues(alpha: 0.85),
                        border: Border.all(color: chosen ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC107)) : (hc ? Colors.white : Colors.black26), width: chosen ? 2.5 : 1),
                      ),
                      child: Text(item.emoji, style: TextStyle(fontSize: emojiSize, height: 1.0)),
                    ),
                  ),
                ),
                // Табла со името - на страната кон плоштадот.
                Positioned(
                  left: 2,
                  right: 2,
                  top: facesDown ? null : -2,
                  bottom: facesDown ? -2 : null,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: hc ? Colors.black : (chosen ? const Color(0xFF1E3A5F) : const Color(0xE62B2F36)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: chosen ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC107)) : (hc ? Colors.white : Colors.white38),
                          width: chosen ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: chosen ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFFFE082)) : Colors.white,
                          fontSize: labelSize,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                // Ознака „тука си“ над избраната зграда (само во преглед).
                if (chosen && !focus)
                  Positioned(
                    top: facesDown ? -6 : null,
                    bottom: facesDown ? null : -6,
                    right: -4,
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: _ambient,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, -3 * math.sin(_ambient.value * math.pi * 8).abs()),
                          child: child,
                        ),
                        child: Icon(Icons.location_on_rounded,
                          size: (m * 0.09).clamp(22.0, 36.0).toDouble(),
                          color: hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC107),
                          shadows: hc ? null : const [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2))]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Плоштадот: калдрма, тротоари, улици, дрва и клупи.
// ---------------------------------------------------------------------------

class _SquarePainter extends CustomPainter {
  _SquarePainter({required this.hc, required this.t, required this.lots});
  final bool hc;
  final double t;
  final List<Rect> lots;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    if (hc) {
      canvas.drawRect(rect, Paint()..color = Colors.black);
      final line = Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(Rect.fromLTRB(w * 0.045, h * 0.32, w * 0.955, h * 0.68), line);
      return;
    }
    // Асфалт (улици околу блокот).
    canvas.drawRect(rect, Paint()..color = const Color(0xFF5B6470));
    final lane = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 2;
    for (var y = 6.0; y < h; y += 22) {
      canvas.drawLine(Offset(w * 0.0225, y), Offset(w * 0.0225, y + 10), lane);
      canvas.drawLine(Offset(w * 0.9775, y), Offset(w * 0.9775, y + 10), lane);
    }
    // Тротоар под зградите.
    final walk = Paint()..color = const Color(0xFFCBC3B4);
    canvas.drawRect(Rect.fromLTRB(w * 0.04, h * 0.02, w * 0.96, h * 0.98), walk);
    // Плоштад - калдрма во топли тонови.
    final plaza = Rect.fromLTRB(w * 0.045, h * 0.315, w * 0.955, h * 0.685);
    canvas.drawRect(
      plaza,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE9DCC2), Color(0xFFD3C09D)],
        ).createShader(plaza),
    );
    final stone = Paint()
      ..color = const Color(0x339C8560)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = plaza.center;
    // Концентрични кругови од калдрма околу средината.
    for (var r = math.min(w, h) * 0.22; r < w * 0.7; r += 14) {
      canvas.save();
      canvas.clipRect(plaza);
      canvas.drawCircle(c, r, stone);
      canvas.restore();
    }
    // Патеки од секоја зграда кон средината.
    final path = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final l in lots) {
      final door = l.center.dy < c.dy ? Offset(l.center.dx, l.bottom) : Offset(l.center.dx, l.top);
      canvas.drawLine(door, Offset.lerp(door, c, 0.45)!, path);
    }
    // Дрва во аглите на плоштадот (одозгора - круни што тивко се нишаат).
    final sway = math.sin(t * math.pi * 2) * 1.5;
    for (final p in [
      Offset(plaza.left + 18, plaza.top + 18),
      Offset(plaza.right - 18, plaza.top + 18),
      Offset(plaza.left + 18, plaza.bottom - 18),
      Offset(plaza.right - 18, plaza.bottom - 18),
    ]) {
      canvas.drawCircle(p + const Offset(3, 4), 15, Paint()..color = const Color(0x33000000));
      canvas.drawCircle(p + Offset(sway, 0), 15, Paint()..color = const Color(0xFF3F8A4A));
      canvas.drawCircle(p + Offset(sway - 4, -4), 9, Paint()..color = const Color(0xFF5DAA62));
    }
    // Клупи покрај плоштадчето.
    final bench = Paint()..color = const Color(0xFF8B5E3C);
    final pc = c;
    final br = math.min(w, h) * 0.23;
    for (final a in [math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75]) {
      final p = pc + Offset(math.cos(a), math.sin(a)) * br;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + math.pi / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 22, height: 7), const Radius.circular(2)), bench);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SquarePainter old) => old.hc != hc || old.t != t || old.lots != lots;
}

// ---------------------------------------------------------------------------
// Кружно плоштадче со фонтана и знак „?“ - копчето за квиз.
// ---------------------------------------------------------------------------

class _FountainQuizPainter extends CustomPainter {
  _FountainQuizPainter({required this.hc, required this.t});
  final bool hc;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (hc) {
      canvas.drawCircle(c, r * 0.96, Paint()..color = Colors.black);
      canvas.drawCircle(
        c,
        r * 0.96,
        Paint()
          ..color = const Color(0xFFFFFF00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    } else {
      // Камен раб и мозаик.
      canvas.drawCircle(c + const Offset(3, 5), r * 0.96, Paint()..color = const Color(0x40000000));
      canvas.drawCircle(c, r * 0.96, Paint()..color = const Color(0xFFBBA88A));
      for (var i = 0; i < 16; i++) {
        final a = i / 16 * math.pi * 2;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * r * 0.62,
          c + Offset(math.cos(a), math.sin(a)) * r * 0.94,
          Paint()
            ..color = const Color(0x55FFFFFF)
            ..strokeWidth = 1.5,
        );
      }
      // Вода со бранчиња.
      canvas.drawCircle(
        c,
        r * 0.62,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF8FD3E8), Color(0xFF3B8DB5)],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.62)),
      );
      for (var k = 0; k < 2; k++) {
        final p = (t * 2 + k / 2) % 1.0;
        canvas.drawCircle(
          c,
          r * (0.3 + 0.3 * p),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * (1 - p))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    // Медалјон со „?“ (пулсира тивко).
    final pulse = 1 + 0.05 * math.sin(t * math.pi * 4);
    final mr = r * 0.34 * pulse;
    canvas.drawCircle(
      c,
      mr,
      Paint()..color = hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC107),
    );
    canvas.drawCircle(
      c,
      mr,
      Paint()
        ..color = hc ? Colors.black : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontSize: mr * 1.35,
          fontWeight: FontWeight.w900,
          color: hc ? Colors.black : const Color(0xFF1E293B),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FountainQuizPainter old) => old.hc != hc || old.t != t;
}

// ---------------------------------------------------------------------------
// Зграда одозгора: сенка, покрив со детали според видот, влез кон плоштадот.
// ---------------------------------------------------------------------------

class _BuildingPainter extends CustomPainter {
  _BuildingPainter({required this.kind, required this.selected, required this.hc, required this.facesDown});
  final _Kind kind;
  final bool selected;
  final bool hc;
  final bool facesDown;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Зградата зазема поголем дел; кон плоштадот останува место за влезот.
    final body = facesDown
        ? Rect.fromLTWH(w * 0.04, h * 0.04, w * 0.92, h * 0.74)
        : Rect.fromLTWH(w * 0.04, h * 0.22, w * 0.92, h * 0.74);
    final r = RRect.fromRectAndRadius(body, const Radius.circular(6));
    final roof = hc ? Colors.black : _roofColor(kind);
    final edge = Paint()
      ..color = selected ? (hc ? const Color(0xFFFFFF00) : const Color(0xFFFFC107)) : (hc ? Colors.white : const Color(0x88000000))
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3.5 : 1.4;

    if (!hc) {
      // Сенка (сонцето е горе лево) и сјај околу избраната.
      if (selected) {
        canvas.drawRRect(
          r.inflate(5),
          Paint()
            ..color = const Color(0x88FFC107)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawRRect(r.shift(const Offset(5, 6)), Paint()..color = const Color(0x55000000));
    }
    canvas.drawRRect(r, Paint()..color = roof);
    if (!hc) {
      // Лесна светлина на покривот.
      canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.12)],
          ).createShader(body),
      );
    }
    final detail = Paint()
      ..color = hc ? Colors.white : Colors.black.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final accent = hc ? const Color(0xFFFFFF00) : Colors.white;

    switch (kind) {
      case _Kind.cityHall:
        // Купола во средина + знаме.
        final dc = body.center;
        final dr = math.min(body.width, body.height) * 0.3;
        canvas.drawCircle(dc, dr, Paint()..color = hc ? Colors.black : const Color(0xFF7FA6A0));
        canvas.drawCircle(dc, dr, detail);
        for (var i = 0; i < 8; i++) {
          final a = i / 8 * math.pi * 2;
          canvas.drawLine(dc, dc + Offset(math.cos(a), math.sin(a)) * dr, detail);
        }
        final pole = Offset(body.right - w * 0.1, body.top + h * 0.12);
        canvas.drawLine(pole, pole + Offset(0, h * 0.16), Paint()..color = hc ? Colors.white : Colors.black54..strokeWidth = 2);
        canvas.drawRect(Rect.fromLTWH(pole.dx, pole.dy, w * 0.1, h * 0.07), Paint()..color = hc ? accent : const Color(0xFFD62828));
        break;
      case _Kind.hospital:
        // Хелиодром: круг со „H“ и црвен крст.
        final hc0 = Offset(body.left + body.width * 0.25, body.center.dy);
        final hr = math.min(body.width, body.height) * 0.22;
        canvas.drawCircle(hc0, hr, Paint()..color = hc ? Colors.black : const Color(0xFF9AA5B1));
        canvas.drawCircle(hc0, hr, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 2);
        final tp = TextPainter(
          text: TextSpan(text: 'H', style: TextStyle(fontSize: hr * 1.1, fontWeight: FontWeight.w900, color: accent)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, hc0 - Offset(tp.width / 2, tp.height / 2));
        final cc = Offset(body.right - body.width * 0.22, body.center.dy);
        final cs = hr * 0.8;
        final red = Paint()..color = hc ? accent : const Color(0xFFD62828);
        canvas.drawRect(Rect.fromCenter(center: cc, width: cs * 0.6, height: cs * 1.8), red);
        canvas.drawRect(Rect.fromCenter(center: cc, width: cs * 1.8, height: cs * 0.6), red);
        break;
      case _Kind.school:
        // Коси покрив (слеме) + двор со игралиште.
        canvas.drawLine(Offset(body.left, body.center.dy), Offset(body.right, body.center.dy), detail..strokeWidth = 2.5);
        detail.strokeWidth = 1.4;
        for (var x = body.left + 6; x < body.right; x += 7) {
          canvas.drawLine(Offset(x, body.top), Offset(x, body.bottom), Paint()..color = Colors.black.withValues(alpha: hc ? 0 : 0.08));
        }
        final clock = Offset(body.right - body.width * 0.14, body.top + body.height * 0.22);
        canvas.drawCircle(clock, body.height * 0.12, Paint()..color = hc ? Colors.black : Colors.white);
        canvas.drawCircle(clock, body.height * 0.12, detail);
        canvas.drawLine(clock, clock + Offset(0, -body.height * 0.08), detail);
        canvas.drawLine(clock, clock + Offset(body.height * 0.06, 0), detail);
        break;
      case _Kind.library:
        // Покрив со светларник во форма на отворена книга.
        final b = body.deflate(math.min(body.width, body.height) * 0.22);
        final left = Path()
          ..moveTo(b.center.dx, b.top)
          ..lineTo(b.left, b.top + b.height * 0.12)
          ..lineTo(b.left, b.bottom)
          ..lineTo(b.center.dx, b.bottom - b.height * 0.12)
          ..close();
        final right = Path()
          ..moveTo(b.center.dx, b.top)
          ..lineTo(b.right, b.top + b.height * 0.12)
          ..lineTo(b.right, b.bottom)
          ..lineTo(b.center.dx, b.bottom - b.height * 0.12)
          ..close();
        final glass = Paint()..color = hc ? Colors.black : const Color(0xFFBFE3F2);
        canvas.drawPath(left, glass);
        canvas.drawPath(right, glass);
        canvas.drawPath(left, detail);
        canvas.drawPath(right, detail);
        break;
      case _Kind.police:
        // Ѕвезда-значка и паркинг со ленти.
        final sc = Offset(body.center.dx, body.center.dy);
        final sr = math.min(body.width, body.height) * 0.26;
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5;
          final rr = i.isEven ? sr : sr * 0.45;
          final p = sc + Offset(math.cos(a), math.sin(a)) * rr;
          if (i == 0) {
            star.moveTo(p.dx, p.dy);
          } else {
            star.lineTo(p.dx, p.dy);
          }
        }
        star.close();
        canvas.drawPath(star, Paint()..color = hc ? accent : const Color(0xFFF2C94C));
        canvas.drawPath(star, detail);
        break;
      case _Kind.fire:
        // Гаражни врати кон плоштадот + бело-црвени ленти.
        final doorsY = facesDown ? body.bottom - body.height * 0.3 : body.top + body.height * 0.05;
        for (var i = 0; i < 3; i++) {
          final dw = body.width * 0.24;
          final dx = body.left + body.width * 0.08 + i * (dw + body.width * 0.06);
          final d = Rect.fromLTWH(dx, doorsY, dw, body.height * 0.25);
          canvas.drawRect(d, Paint()..color = hc ? Colors.black : const Color(0xFFEDEDED));
          canvas.drawRect(d, detail);
          for (var k = 1; k < 4; k++) {
            canvas.drawLine(Offset(d.left, d.top + d.height * k / 4), Offset(d.right, d.top + d.height * k / 4), detail);
          }
        }
        final tower = Rect.fromLTWH(body.left + body.width * 0.08, facesDown ? body.top + body.height * 0.12 : body.bottom - body.height * 0.42, body.width * 0.2, body.height * 0.3);
        canvas.drawRect(tower, Paint()..color = hc ? Colors.black : const Color(0xFF8E2420));
        canvas.drawRect(tower, detail);
        break;
      case _Kind.post:
        // Голем плик на покривот.
        final env = Rect.fromCenter(center: body.center, width: body.width * 0.5, height: body.height * 0.42);
        canvas.drawRect(env, Paint()..color = hc ? Colors.black : Colors.white);
        canvas.drawRect(env, detail..color = hc ? Colors.white : const Color(0xFF1D4E89));
        canvas.drawLine(env.topLeft, env.center, detail);
        canvas.drawLine(env.topRight, env.center, detail);
        break;
      case _Kind.museum:
        // Класичен трем: тимпанон и столбови кон плоштадот.
        final colY = facesDown ? body.bottom - body.height * 0.22 : body.top + body.height * 0.04;
        final colPaint = Paint()..color = hc ? Colors.white : const Color(0xFFFFFBF2);
        for (var i = 0; i < 6; i++) {
          final x = body.left + body.width * (0.1 + i * 0.16);
          canvas.drawCircle(Offset(x, colY + body.height * 0.09), body.height * 0.06, colPaint);
          canvas.drawCircle(Offset(x, colY + body.height * 0.09), body.height * 0.06, detail);
        }
        final ridgeY = facesDown ? body.top + body.height * 0.3 : body.bottom - body.height * 0.3;
        canvas.drawLine(Offset(body.left, ridgeY), Offset(body.right, ridgeY), detail..strokeWidth = 2.5);
        detail.strokeWidth = 1.4;
        canvas.drawLine(Offset(body.left, ridgeY), Offset(body.center.dx, facesDown ? body.top : body.bottom), detail);
        canvas.drawLine(Offset(body.right, ridgeY), Offset(body.center.dx, facesDown ? body.top : body.bottom), detail);
        break;
      case _Kind.generic:
        break;
    }

    // Влез и скали кон плоштадот.
    final doorW = w * 0.22;
    final doorH = h * 0.05;
    final doorTop = facesDown ? body.bottom : body.top - doorH;
    final door = Rect.fromLTWH(w / 2 - doorW / 2, doorTop, doorW, doorH);
    canvas.drawRect(door, Paint()..color = hc ? Colors.white : const Color(0xFF8C7B67));
    canvas.drawRRect(r, edge);
  }

  @override
  bool shouldRepaint(covariant _BuildingPainter old) =>
      old.kind != kind || old.selected != selected || old.hc != hc || old.facesDown != facesDown;
}