import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../playful_ui.dart';
import 'scene_contract.dart';

// ---------------------------------------------------------------------------
// Заедничка „орбита“: поимите се на навалена елипса (3D прстен). Предните
// (долу) се поголеми и пред централниот објект, задните (горе) се помали,
// потемни и зад него. Избраниот поим е секогаш напред, долу во средина.
// ---------------------------------------------------------------------------

/// Пиксели влечење за еден чекор на изборот.
const double _kDragStep = 60;

/// Траење на вртењето на прстенот до новиот избран поим.
const Duration _kSpin = Duration(milliseconds: 450);

/// Период на тивката позадинска анимација (трепкање, лулање, пулс).
/// Сите циклуси во сцените се цели броеви во овој период - јамка без скок.
const Duration _kAmbient = Duration(seconds: 8);

const double _tau = math.pi * 2;

/// Икона за квиз (значка, обетка, штит).
const IconData _kQuizIcon = Icons.quiz_rounded;

class _OrbitStyle {
  const _OrbitStyle({
    required this.bubble,
    required this.bubbleBorder,
    required this.glow,
    required this.track,
  });

  /// Подлога на балончето на поимот.
  final Color bubble;
  final Color bubbleBorder;

  /// Сјај околу избраниот поим.
  final Color glow;

  /// Линија на орбитата.
  final Color track;
}

/// Пресметана геометрија за дадена големина.
class _OrbitGeom {
  _OrbitGeom._({
    required this.size,
    required this.cx,
    required this.ey,
    required this.rx,
    required this.ry,
    required this.c,
    required this.cy0,
    required this.base,
  });

  factory _OrbitGeom.of(Size size, double centerLift) {
    final w = size.width;
    final h = size.height;
    final m = math.min(w, h);
    final c = m * 0.40;
    final base = (m * 0.165).clamp(40.0, 86.0).toDouble();
    final selSize = base * 1.28;
    final backSize = base * 0.55;
    final top = backSize / 2 + 6;
    final bottom = h - selSize / 2 - 8;
    final ey = (top + bottom) / 2;
    final ry = math.max(20.0, (bottom - top) / 2);
    var rx = w / 2 - base * 0.78 / 2 - 8;
    rx = math.min(rx, ry * 2.4);
    rx = math.max(rx, 40.0);
    return _OrbitGeom._(
      size: size,
      cx: w / 2,
      ey: ey,
      rx: rx,
      ry: ry,
      c: c,
      cy0: ey - c * centerLift,
      base: base,
    );
  }

  final Size size;

  /// Центар на елипсата.
  final double cx;
  final double ey;
  final double rx;
  final double ry;

  /// Големина на централниот објект (~40% од помалата страна).
  final double c;

  /// Вертикален центар на централниот објект.
  final double cy0;

  /// Основна големина на балончето на поимот.
  final double base;

  Offset get center => Offset(cx, cy0);
}

/// Состојба на еден поим во даден момент од вртењето.
class _Slot {
  const _Slot(this.index, this.pos, this.depth, this.size, this.emphasis);

  final int index;
  final Offset pos;

  /// cos(агол): 1 = најнапред (долу), -1 = најназад (горе).
  final double depth;
  final double size;

  /// 1 = на фокус местото, 0 = подалеку од еден чекор.
  final double emphasis;
}

/// Заедничка состојба за трите орбитни сцени.
abstract class _OrbitState<W extends PbScene> extends State<W> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _ambient;

  /// Агол на прстенот во „чекори“ (индекс на поимот што е напред).
  double _from = 0;
  double _to = 0;

  double _dragAcc = 0;
  int _dragSel = 0;

  // ---- куки за конкретните сцени ----

  _OrbitStyle get style;

  /// Колку централниот објект е подигнат над центарот на елипсата
  /// (дел од неговата големина).
  double get centerLift => 0.10;

  /// Позадината (цела површина).
  Widget buildBackground(_OrbitGeom g, double t, bool hc);

  /// Централниот објект - меѓу задните и предните поими.
  List<Widget> buildCenter(_OrbitGeom g, double t, bool hc);

  /// Над сè (на пр. копчето за квиз што виси/се држи пред објектот).
  List<Widget> buildOverlay(_OrbitGeom g, double t, bool hc) => const <Widget>[];

  // ---- животен циклус ----

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: _kSpin, value: 1);
    _ambient = AnimationController(vsync: this, duration: _kAmbient);
    final n = widget.items.length;
    final s = n == 0 ? 0 : widget.selected.clamp(0, n - 1);
    _from = s.toDouble();
    _to = _from;
    _dragSel = s;
    if (!widget.reduceMotion) _ambient.repeat();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.items.length;
    if (n != oldWidget.items.length) {
      final s = n == 0 ? 0 : widget.selected.clamp(0, n - 1);
      _from = s.toDouble();
      _to = _from;
      _spin.value = 1;
    } else if (n > 0 && widget.selected != oldWidget.selected) {
      final cur = _angle % n;
      var delta = (widget.selected - cur) % n;
      if (delta > n / 2) delta -= n;
      _from = cur;
      _to = cur + delta;
      if (widget.reduceMotion) {
        _from = _to;
        _spin.value = 1;
      } else {
        _spin.forward(from: 0);
      }
    }
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (widget.reduceMotion) {
        _ambient.stop();
        _ambient.value = 0;
      } else if (!_ambient.isAnimating) {
        _ambient.repeat();
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _ambient.dispose();
    super.dispose();
  }

  double get _angle => _from + (_to - _from) * Curves.easeOutCubic.transform(_spin.value);

  // ---- допир / влечење ----

  void _tapItem(int i) {
    if (i == widget.selected) {
      widget.onOpen();
    } else {
      widget.onSelect(i);
    }
  }

  void _dragStart(DragStartDetails d) {
    _dragAcc = 0;
    _dragSel = widget.selected;
  }

  void _dragUpdate(DragUpdateDetails d) {
    final n = widget.items.length;
    if (n == 0) return;
    _dragAcc += d.primaryDelta ?? d.delta.dx;
    var moved = false;
    while (_dragAcc <= -_kDragStep) {
      _dragAcc += _kDragStep;
      _dragSel = (_dragSel + 1) % n;
      moved = true;
    }
    while (_dragAcc >= _kDragStep) {
      _dragAcc -= _kDragStep;
      _dragSel = (_dragSel - 1 + n) % n;
      moved = true;
    }
    if (moved) widget.onSelect(_dragSel);
  }

  void _dragEnd(DragEndDetails d) {
    _dragAcc = 0;
  }

  // ---- распоред ----

  List<_Slot> _slots(_OrbitGeom g) {
    final n = widget.items.length;
    final a = _angle;
    final out = <_Slot>[];
    for (var i = 0; i < n; i++) {
      var p = (i - a) % n;
      if (p > n / 2) p -= n;
      final th = _tau * p / n;
      final d = math.cos(th);
      final e = (1 - p.abs()).clamp(0.0, 1.0).toDouble();
      final s = g.base * (0.55 + 0.45 * (d + 1) / 2) * (1 + 0.28 * e);
      out.add(_Slot(i, Offset(g.cx + g.rx * math.sin(th), g.ey + g.ry * d), d, s, e));
    }
    out.sort((x, y) => x.depth.compareTo(y.depth));
    return out;
  }

  Widget _item(_Slot s, double t, bool hc) {
    final item = widget.items[s.index];
    final isSel = s.index == widget.selected;
    final st = style;
    // Лесно лулање на избраниот (само кога има анимации).
    final bob = isSel ? -s.size * 0.05 * math.sin(_tau * t * 4) : 0.0;
    final hit = math.max(s.size, 40.0);
    final shade = (0.45 + 0.4 * (s.depth + 1) / 2 + 0.15 * s.emphasis).clamp(0.0, 1.0).toDouble();

    final Color fill;
    final Color border;
    final double borderW;
    final List<BoxShadow> shadows;
    if (hc) {
      fill = Colors.black;
      border = isSel ? Playful.sun : Colors.white;
      borderW = isSel ? 4 : 2;
      shadows = const <BoxShadow>[];
    } else {
      fill = st.bubble;
      border = isSel ? Playful.sun : st.bubbleBorder;
      borderW = isSel ? 3.5 : 1.5;
      shadows = <BoxShadow>[
        if (s.emphasis > 0.01)
          BoxShadow(
            color: st.glow.withValues(alpha: 0.75 * s.emphasis),
            blurRadius: s.size * 0.45 * s.emphasis,
            spreadRadius: s.size * 0.06 * s.emphasis,
          ),
        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3)),
      ];
    }

    Widget bubble = Container(
      width: s.size,
      height: s.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: borderW),
        boxShadow: shadows,
      ),
      child: Text(
        item.emoji,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: s.size * 0.56, height: 1.0),
      ),
    );

    if (item.visited && s.size > 30) {
      final b = math.max(14.0, s.size * 0.28);
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            right: -b * 0.1,
            top: -b * 0.1,
            child: Container(
              width: b,
              height: b,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : const Color(0xFF2EBD6B),
                border: Border.all(color: hc ? Playful.sun : Colors.white, width: hc ? 2 : 1.5),
              ),
              child: Icon(Icons.check_rounded, size: b * 0.72, color: hc ? Playful.sun : Colors.white),
            ),
          ),
        ],
      );
    }

    if (!hc && shade < 0.999) {
      bubble = Opacity(opacity: shade, child: bubble);
    }

    return Positioned(
      left: s.pos.dx - hit / 2,
      top: s.pos.dy - hit / 2 + bob,
      width: hit,
      height: hit,
      child: Semantics(
        sortKey: OrdinalSortKey(s.index.toDouble()),
        button: true,
        selected: isSel,
        label: item.label,
        onTap: () => _tapItem(s.index),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapItem(s.index),
          child: Center(child: bubble),
        ),
      ),
    );
  }

  /// Заедничко копче за квиз: целата површина на [child] е зона за допир
  /// (повикувачот ја прави најмалку 48 x 48).
  Widget quizTap({required Widget child}) {
    return Semantics(
      sortKey: const OrdinalSortKey(1000),
      button: true,
      label: widget.quizLabel,
      onTap: widget.onQuiz,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onQuiz,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth.isFinite ? cons.maxWidth : 400.0;
        final h = cons.maxHeight.isFinite ? cons.maxHeight : 400.0;
        final g = _OrbitGeom.of(Size(w, h), centerLift);
        final hc = widget.highContrast;
        return SizedBox(
          width: w,
          height: h,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _dragStart,
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: _dragEnd,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_spin, _ambient]),
                builder: (context, _) {
                  final t = widget.reduceMotion ? 0.0 : _ambient.value;
                  final slots = _slots(g);
                  final back = slots.where((s) => s.depth < 0);
                  final front = slots.where((s) => s.depth >= 0);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: buildBackground(g, t, hc)),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _TrackPainter(g, style.track, hc, front: false)),
                        ),
                      ),
                      for (final s in back) _item(s, t, hc),
                      ...buildCenter(g, t, hc),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _TrackPainter(g, style.track, hc, front: true)),
                        ),
                      ),
                      for (final s in front) _item(s, t, hc),
                      ...buildOverlay(g, t, hc),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Половина од линијата на орбитата (задната - пред централниот објект се
/// црта прво; предната - после него).
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.g, this.color, this.hc, {required this.front});

  final _OrbitGeom g;
  final Color color;
  final bool hc;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(g.cx, g.ey), width: g.rx * 2, height: g.ry * 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hc ? 2 : (front ? 2.5 : 1.5)
      ..color = hc ? Colors.white : color.withValues(alpha: front ? 0.55 : 0.3);
    // Во Canvas аголот 0 е десно, а расте надолу: 0..π е долната (предна) половина.
    canvas.drawArc(rect, front ? 0 : math.pi, math.pi, false, paint);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.g.size != g.size || old.color != color || old.hc != hc || old.front != front;
}

// ---------------------------------------------------------------------------
// Вселена
// ---------------------------------------------------------------------------

/// Вселена: голема планета со прстен во средина (таа е копчето за квиз),
/// поимите кружат околу неа.
class SpaceOrbitScene extends PbScene {
  const SpaceOrbitScene({
    super.key,
    required super.items,
    required super.selected,
    required super.onSelect,
    required super.onOpen,
    required super.onQuiz,
    required super.quizLabel,
    required super.highContrast,
    super.reduceMotion,
  });

  @override
  State<SpaceOrbitScene> createState() => _SpaceOrbitSceneState();
}

class _Star {
  const _Star(this.x, this.y, this.r, this.phase, this.speed);

  final double x;
  final double y;
  final double r;
  final double phase;
  final int speed;
}

final List<_Star> _stars = _makeStars();

List<_Star> _makeStars() {
  final rnd = math.Random(11);
  return List<_Star>.generate(
    70,
    (_) => _Star(rnd.nextDouble(), rnd.nextDouble(), 0.6 + rnd.nextDouble() * 1.6, rnd.nextDouble(), 1 + rnd.nextInt(3)),
  );
}

class _SpaceOrbitSceneState extends _OrbitState<SpaceOrbitScene> {
  @override
  _OrbitStyle get style => const _OrbitStyle(
        bubble: Playful.nightRaised,
        bubbleBorder: Color(0xFF6E6BD8),
        glow: Playful.sun,
        track: Playful.mist,
      );

  @override
  double get centerLift => 0.08;

  @override
  Widget buildBackground(_OrbitGeom g, double t, bool hc) =>
      IgnorePointer(child: CustomPaint(painter: _SpaceBgPainter(t, hc)));

  @override
  List<Widget> buildCenter(_OrbitGeom g, double t, bool hc) {
    final c = g.c;
    final pulse = (t * 4) % 1.0;
    final badge = math.max(34.0, c * 0.26);
    final badgeScale = 1 + 0.07 * math.sin(_tau * t * 4);
    // Значката горе-десно, целосно во кругот на планетата.
    final bOff = c / 2 + c * 0.22 - badge / 2;
    return [
      Positioned(
        left: g.cx - c,
        top: g.cy0 - c,
        width: c * 2,
        height: c * 2,
        child: IgnorePointer(child: CustomPaint(painter: _PlanetPainter(c, pulse, hc))),
      ),
      Positioned(
        left: g.cx - c / 2,
        top: g.cy0 - c / 2,
        width: c,
        height: c,
        child: ClipOval(
          child: quizTap(
            child: Stack(
              children: [
                Positioned(
                  left: bOff,
                  top: c - bOff - badge,
                  width: badge,
                  height: badge,
                  child: Transform.scale(
                    scale: badgeScale,
                    child: _QuizBadge(size: badge, hc: hc),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

class _QuizBadge extends StatelessWidget {
  const _QuizBadge({required this.size, required this.hc});

  final double size;
  final bool hc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? Colors.black : Playful.sun,
        border: Border.all(color: hc ? Playful.sun : Colors.white, width: hc ? 3 : 2),
      ),
      child: Icon(_kQuizIcon, size: size * 0.6, color: hc ? Playful.sun : Playful.ink),
    );
  }
}

class _SpaceBgPainter extends CustomPainter {
  _SpaceBgPainter(this.t, this.hc);

  final double t;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (hc) {
      canvas.drawRect(rect, Paint()..color = Colors.black);
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.1),
            radius: 0.9,
            colors: [Playful.nightRaised, Playful.night, Playful.nightDeep],
            stops: [0.0, 0.55, 1.0],
          ).createShader(rect),
      );
      // Мека маглина.
      canvas.drawCircle(
        Offset(size.width * 0.18, size.height * 0.22),
        size.shortestSide * 0.35,
        Paint()
          ..color = const Color(0xFF8E5BD9).withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    final p = Paint();
    for (final s in _stars) {
      final tw = 0.5 + 0.5 * math.sin(_tau * (t * s.speed + s.phase));
      if (hc) {
        p.color = Colors.white;
      } else {
        p.color = Colors.white.withValues(alpha: 0.35 + 0.65 * tw);
      }
      final o = Offset(s.x * size.width, s.y * size.height);
      canvas.drawCircle(o, s.r * (hc ? 1.0 : 0.8 + 0.4 * tw), p);
      if (!hc && s.r > 1.9 && tw > 0.75) {
        // Мал крст на најсветлите.
        final l = s.r * 3 * tw;
        final cross = Paint()
          ..color = Colors.white.withValues(alpha: 0.5 * tw)
          ..strokeWidth = 1;
        canvas.drawLine(o.translate(-l, 0), o.translate(l, 0), cross);
        canvas.drawLine(o.translate(0, -l), o.translate(0, l), cross);
      }
    }
  }

  @override
  bool shouldRepaint(_SpaceBgPainter old) => old.t != t || old.hc != hc;
}

/// Планета со прстен (како Сатурн). Платното е 2c x 2c, планетата е во
/// средина со дијаметар c.
class _PlanetPainter extends CustomPainter {
  _PlanetPainter(this.c, this.pulse, this.hc);

  final double c;
  final double pulse;
  final bool hc;

  static const double _tilt = -0.28;

  void _ring(Canvas canvas, Offset o, double r, {required bool front}) {
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(_tilt);
    final rect = Rect.fromCenter(center: Offset.zero, width: r * 3.1, height: r * 0.8);
    final start = front ? 0.0 : math.pi;
    if (hc) {
      canvas.drawArc(
        rect,
        start,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.1
          ..color = Colors.white,
      );
    } else {
      canvas.drawArc(
        rect,
        start,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..color = const Color(0xFFFFD27A).withValues(alpha: front ? 0.95 : 0.7),
      );
      canvas.drawArc(
        rect.deflate(r * 0.09),
        start,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04
          ..color = const Color(0xFFFFF3CF).withValues(alpha: front ? 0.9 : 0.6),
      );
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final o = size.center(Offset.zero);
    final r = c / 2;

    // Пулс (поканата за квиз).
    if (hc) {
      canvas.drawCircle(
        o,
        r * (1.06 + 0.1 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Playful.sun,
      );
    } else {
      canvas.drawCircle(
        o,
        r * (1.02 + 0.22 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06
          ..color = Playful.sun.withValues(alpha: 0.55 * (1 - pulse)),
      );
      canvas.drawCircle(
        o,
        r * 1.15,
        Paint()
          ..color = const Color(0xFFFF8A65).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    _ring(canvas, o, r, front: false);

    final planet = Rect.fromCircle(center: o, radius: r);
    if (hc) {
      canvas.drawCircle(o, r, Paint()..color = Colors.black);
    } else {
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.35, -0.4),
            radius: 1.0,
            colors: [Color(0xFFFFC08A), Color(0xFFE2566E), Color(0xFF5B2A86)],
            stops: [0.0, 0.55, 1.0],
          ).createShader(planet),
      );
    }

    // Појаси.
    canvas.save();
    canvas.clipPath(Path()..addOval(planet));
    canvas.translate(o.dx, o.dy);
    canvas.rotate(_tilt);
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hc ? 2 : r * 0.1
      ..color = hc ? Colors.white : Colors.white.withValues(alpha: 0.14);
    for (final k in const <double>[-0.45, -0.1, 0.3]) {
      final p = Path()
        ..moveTo(-r * 1.1, r * k)
        ..quadraticBezierTo(0, r * (k + 0.18), r * 1.1, r * k);
      canvas.drawPath(p, band);
    }
    canvas.restore();

    if (hc) {
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Playful.sun,
      );
    } else {
      // Сенка од десно-долу за 3D.
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.5, -0.5),
            radius: 1.3,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
            stops: const [0.6, 1.0],
          ).createShader(planet),
      );
    }

    _ring(canvas, o, r, front: true);
  }

  @override
  bool shouldRepaint(_PlanetPainter old) => old.c != c || old.pulse != pulse || old.hc != hc;
}

// ---------------------------------------------------------------------------
// Музика
// ---------------------------------------------------------------------------

/// Музика: големо нацртано уво во средина, инструментите кружат околу
/// него; квизот е обетка што виси од реската.
class MusicEarScene extends PbScene {
  const MusicEarScene({
    super.key,
    required super.items,
    required super.selected,
    required super.onSelect,
    required super.onOpen,
    required super.onQuiz,
    required super.quizLabel,
    required super.highContrast,
    super.reduceMotion,
  });

  @override
  State<MusicEarScene> createState() => _MusicEarSceneState();
}

class _Note {
  const _Note(this.glyph, this.x, this.y, this.size, this.speed, this.phase);

  final String glyph;
  final double x;
  final double y;
  final double size;
  final int speed;
  final double phase;
}

final List<_Note> _notes = _makeNotes();

List<_Note> _makeNotes() {
  final rnd = math.Random(5);
  const glyphs = <String>['♪', '♫', '♬', '♩'];
  return List<_Note>.generate(
    10,
    (i) => _Note(
      glyphs[i % glyphs.length],
      0.04 + rnd.nextDouble() * 0.92,
      rnd.nextDouble(),
      0.6 + rnd.nextDouble() * 0.6,
      1 + rnd.nextInt(2),
      rnd.nextDouble(),
    ),
  );
}

/// Нормализирана точка на реската во цртежот на увото (0..1).
const Offset _kLobe = Offset(0.46, 0.95);

/// Однос ширина/висина на увото.
const double _kEarAspect = 0.74;

class _MusicEarSceneState extends _OrbitState<MusicEarScene> {
  @override
  _OrbitStyle get style => const _OrbitStyle(
        bubble: Color(0xFF2E2470),
        bubbleBorder: Color(0xFF9C8CF0),
        glow: Color(0xFFFF8FC7),
        track: Color(0xFFFFB3D9),
      );

  @override
  double get centerLift => 0.15;

  @override
  Widget buildBackground(_OrbitGeom g, double t, bool hc) {
    if (hc) return const ColoredBox(color: Colors.black);
    final w = g.size.width;
    final h = g.size.height;
    final noteBase = g.base * 0.55;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MusicBgPainter(t))),
          for (final n in _notes)
            Positioned(
              left: n.x * w - noteBase,
              // Нотите полека се креваат и се враќаат долу (цел циклус).
              top: (1 - ((n.y + t * n.speed) % 1.0)) * (h + noteBase * 2) - noteBase * 2,
              child: Transform.rotate(
                angle: 0.25 * math.sin(_tau * (t * 2 + n.phase)),
                child: Text(
                  n.glyph,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: noteBase * n.size * 1.6,
                    height: 1.0,
                    color: Colors.white.withValues(alpha: 0.12 + 0.12 * (0.5 + 0.5 * math.sin(_tau * (t + n.phase)))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Size _earSize(_OrbitGeom g) => Size(g.c * _kEarAspect, g.c);

  @override
  List<Widget> buildCenter(_OrbitGeom g, double t, bool hc) {
    final es = _earSize(g);
    final glow = 0.5 + 0.5 * math.sin(_tau * t * 2);
    return [
      if (!hc)
        Positioned(
          left: g.cx - g.c * 0.75,
          top: g.cy0 - g.c * 0.75,
          width: g.c * 1.5,
          height: g.c * 1.5,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF8FC7).withValues(alpha: 0.22 + 0.1 * glow),
                    const Color(0xFFFF8FC7).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: g.cx - es.width / 2,
        top: g.cy0 - es.height / 2,
        width: es.width,
        height: es.height,
        child: IgnorePointer(child: CustomPaint(painter: _EarPainter(hc))),
      ),
    ];
  }

  @override
  List<Widget> buildOverlay(_OrbitGeom g, double t, bool hc) {
    final es = _earSize(g);
    final lobe = Offset(
      g.cx - es.width / 2 + _kLobe.dx * es.width,
      g.cy0 - es.height / 2 + _kLobe.dy * es.height,
    );
    final hook = math.max(5.0, g.c * 0.045);
    final chain = math.max(4.0, g.c * 0.05);
    final pr = math.max(15.0, g.c * 0.11);
    final drawH = hook * 2 + chain + pr * 2;
    final boxW = math.max(48.0, pr * 2 + 12);
    final boxH = math.max(48.0, drawH);
    final swing = 0.2 * math.sin(_tau * t * 3);
    return [
      Positioned(
        left: lobe.dx - boxW / 2,
        top: lobe.dy - hook,
        width: boxW,
        height: boxH,
        child: Transform.rotate(
          angle: swing,
          alignment: Alignment(0, -1 + 2 * hook / boxH),
          child: quizTap(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: CustomPaint(painter: _EarringPainter(hook, chain, hc))),
                Positioned(
                  left: boxW / 2 - pr,
                  top: hook * 2 + chain,
                  width: pr * 2,
                  height: pr * 2,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? Colors.black : Playful.sun,
                      border: Border.all(color: hc ? Playful.sun : Colors.white, width: hc ? 3 : 2),
                      boxShadow: hc
                          ? const <BoxShadow>[]
                          : <BoxShadow>[
                              BoxShadow(color: Playful.sun.withValues(alpha: 0.55), blurRadius: pr * 0.8),
                            ],
                    ),
                    child: Icon(_kQuizIcon, size: pr * 1.2, color: hc ? Playful.sun : Playful.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

class _MusicBgPainter extends CustomPainter {
  _MusicBgPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B2470), Color(0xFF3A2878), Playful.nightDeep],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    // Меки бранови нотни линии.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.07);
    final gap = size.height * 0.035;
    final y0 = size.height * 0.78;
    for (var k = 0; k < 5; k++) {
      final p = Path();
      for (var x = 0.0; x <= size.width + 8; x += 8) {
        final y = y0 + k * gap + math.sin(x / size.width * _tau * 1.5 + _tau * t) * gap * 0.8;
        if (x == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      canvas.drawPath(p, line);
    }
  }

  @override
  bool shouldRepaint(_MusicBgPainter old) => old.t != t;
}

/// Стилизирано уво (десно уво од страна): надворешен хеликс, внатрешна
/// крива, школка, трагус и реска.
class _EarPainter extends CustomPainter {
  _EarPainter(this.hc);

  final bool hc;

  static const Color _skin = Color(0xFFF7C9A3);
  static const Color _skinLight = Color(0xFFFFE0C7);
  static const Color _crease = Color(0xFFC47A55);
  static const Color _outline = Color(0xFFA9603F);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    void cubic(Path path, Offset a, Offset b, Offset c) => path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);

    final outer = Path();
    final s = p(0.30, 0.18);
    outer.moveTo(s.dx, s.dy);
    cubic(outer, p(0.36, 0.0), p(0.92, -0.02), p(0.94, 0.30));
    cubic(outer, p(0.96, 0.52), p(0.80, 0.60), p(0.72, 0.70));
    cubic(outer, p(0.64, 0.80), p(0.68, 0.97), p(0.48, 0.98));
    cubic(outer, p(0.30, 0.99), p(0.24, 0.86), p(0.28, 0.78));
    cubic(outer, p(0.31, 0.70), p(0.22, 0.62), p(0.20, 0.48));
    cubic(outer, p(0.18, 0.34), p(0.24, 0.26), p(0.30, 0.18));
    outer.close();

    final helix = Path();
    final hs = p(0.36, 0.24);
    helix.moveTo(hs.dx, hs.dy);
    cubic(helix, p(0.44, 0.08), p(0.84, 0.10), p(0.84, 0.32));
    cubic(helix, p(0.84, 0.50), p(0.68, 0.56), p(0.62, 0.66));

    final anti = Path();
    final as0 = p(0.44, 0.34);
    anti.moveTo(as0.dx, as0.dy);
    cubic(anti, p(0.58, 0.24), p(0.72, 0.36), p(0.64, 0.46));
    cubic(anti, p(0.58, 0.54), p(0.46, 0.52), p(0.46, 0.62));
    cubic(anti, p(0.46, 0.70), p(0.54, 0.74), p(0.58, 0.72));

    final tragus = Path();
    final ts = p(0.30, 0.52);
    tragus.moveTo(ts.dx, ts.dy);
    cubic(tragus, p(0.38, 0.50), p(0.40, 0.62), p(0.32, 0.64));

    final canal = Rect.fromCenter(center: p(0.40, 0.58), width: w * 0.10, height: h * 0.12);
    final crease = w * 0.065;

    if (hc) {
      canvas.drawPath(outer, Paint()..color = Colors.black);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(3.0, crease * 0.6)
        ..color = Colors.white;
      canvas.drawPath(helix, stroke);
      canvas.drawPath(anti, stroke);
      canvas.drawPath(tragus, stroke);
      canvas.drawOval(canal, Paint()..color = Colors.white);
      canvas.drawPath(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Playful.sun,
      );
      return;
    }

    // Мека сенка под увото.
    canvas.drawPath(
      outer.shift(Offset(0, h * 0.02)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.2, -0.3),
          radius: 0.9,
          colors: [_skinLight, _skin, Color(0xFFE8A97F)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    final creasePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = crease
      ..color = _crease;
    canvas.drawPath(helix, creasePaint);
    canvas.drawPath(anti, creasePaint..strokeWidth = crease * 0.85);
    canvas.drawPath(tragus, creasePaint..strokeWidth = crease * 0.8);
    canvas.drawOval(canal, Paint()..color = const Color(0xFF9C5536));
    // Светол одблесок на хеликсот.
    canvas.drawPath(
      helix,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = crease * 0.3
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, w * 0.025)
        ..color = _outline,
    );
  }

  @override
  bool shouldRepaint(_EarPainter old) => old.hc != hc;
}

/// Кукичка (мал прстен) на реската + синџирче до приврзокот.
class _EarringPainter extends CustomPainter {
  _EarringPainter(this.hook, this.chain, this.hc);

  final double hook;
  final double chain;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hc ? 3 : 2.5
      ..color = hc ? Playful.sun : const Color(0xFFFFD27A);
    canvas.drawCircle(Offset(cx, hook), hook * 0.85, paint);
    canvas.drawLine(Offset(cx, hook * 2 - 1), Offset(cx, hook * 2 + chain + 1), paint);
  }

  @override
  bool shouldRepaint(_EarringPainter old) => old.hook != hook || old.chain != chain || old.hc != hc;
}

// ---------------------------------------------------------------------------
// Животни
// ---------------------------------------------------------------------------

/// Животни: голем лав во савана што држи штит (квиз); животните кружат
/// околу него.
class AnimalsLionScene extends PbScene {
  const AnimalsLionScene({
    super.key,
    required super.items,
    required super.selected,
    required super.onSelect,
    required super.onOpen,
    required super.onQuiz,
    required super.quizLabel,
    required super.highContrast,
    super.reduceMotion,
  });

  @override
  State<AnimalsLionScene> createState() => _AnimalsLionSceneState();
}

class _AnimalsLionSceneState extends _OrbitState<AnimalsLionScene> {
  @override
  _OrbitStyle get style => const _OrbitStyle(
        bubble: Color(0xFFFFF4DC),
        bubbleBorder: Color(0xFF8A5A2B),
        glow: Playful.sun,
        track: Color(0xFFFFF1C9),
      );

  @override
  double get centerLift => 0.12;

  @override
  Widget buildBackground(_OrbitGeom g, double t, bool hc) =>
      IgnorePointer(child: CustomPaint(painter: _SavannaPainter(t, hc)));

  @override
  List<Widget> buildCenter(_OrbitGeom g, double t, bool hc) {
    final c = g.c;
    final breathe = 1 + 0.05 * math.sin(_tau * t * 2);
    return [
      Positioned(
        left: g.cx - c * 0.65,
        top: g.cy0 - c * 0.65,
        width: c * 1.3,
        height: c * 1.3,
        child: IgnorePointer(
          child: Transform.scale(
            scale: breathe,
            child: DecoratedBox(
              decoration: hc
                  ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Playful.sun, width: 4))
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFFB347).withValues(alpha: 0.75),
                          const Color(0xFFFF8C1A).withValues(alpha: 0.35),
                          const Color(0xFFFF8C1A).withValues(alpha: 0),
                        ],
                        stops: const [0.35, 0.65, 1.0],
                      ),
                    ),
            ),
          ),
        ),
      ),
      Positioned(
        left: g.cx - c / 2,
        top: g.cy0 - c / 2,
        width: c,
        height: c,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Center(
              child: Text(
                '🦁',
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: c * 0.78, height: 1.0),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  List<Widget> buildOverlay(_OrbitGeom g, double t, bool hc) {
    final c = g.c;
    final sw = math.max(48.0, c * 0.36);
    final sh = sw * 1.15;
    final pulse = 1 + 0.05 * math.sin(_tau * t * 4);
    final center = Offset(g.cx + c * 0.27, g.cy0 + c * 0.27);
    return [
      Positioned(
        left: center.dx - sw / 2,
        top: center.dy - sh / 2,
        width: sw,
        height: sh,
        child: Transform.rotate(
          angle: -0.12,
          child: Transform.scale(
            scale: pulse,
            child: quizTap(
              child: CustomPaint(
                painter: _ShieldPainter(hc),
                child: Align(
                  alignment: const Alignment(0, -0.15),
                  child: Icon(_kQuizIcon, size: sw * 0.5, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _SavannaPainter extends CustomPainter {
  _SavannaPainter(this.t, this.hc);

  final double t;
  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final horizon = h * 0.66;

    if (hc) {
      canvas.drawRect(rect, Paint()..color = Colors.black);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white;
      canvas.drawLine(Offset(0, horizon), Offset(w, horizon), line);
      for (var x = 6.0; x < w; x += 22) {
        canvas.drawLine(Offset(x, h), Offset(x + 4, h - 14), line);
      }
      return;
    }

    // Небо: од ноќно индиго до топол залез.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B2A7A), Color(0xFFE8784A), Playful.sun],
          stops: [0.0, 0.6, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, horizon)),
    );
    // Сонце на хоризонтот.
    canvas.drawCircle(
      Offset(w * 0.82, horizon - h * 0.02),
      h * 0.11,
      Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.9),
    );
    // Далечни ридови.
    final hills = Path()..moveTo(0, horizon);
    hills.quadraticBezierTo(w * 0.2, horizon - h * 0.07, w * 0.42, horizon - h * 0.01);
    hills.quadraticBezierTo(w * 0.65, horizon - h * 0.08, w, horizon - h * 0.02);
    hills.lineTo(w, horizon + 2);
    hills.lineTo(0, horizon + 2);
    hills.close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFFB0643A).withValues(alpha: 0.6));
    // Акација.
    final tree = Paint()..color = const Color(0xFF4A2A1E).withValues(alpha: 0.8);
    final tx = w * 0.12;
    canvas.drawRect(Rect.fromLTWH(tx - 2, horizon - h * 0.12, 4, h * 0.12), tree);
    canvas.drawOval(Rect.fromCenter(center: Offset(tx, horizon - h * 0.13), width: h * 0.2, height: h * 0.05), tree);

    // Земја.
    final ground = Rect.fromLTWH(0, horizon, w, h - horizon);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9A441), Color(0xFF9C7A2C)],
        ).createShader(ground),
    );

    // Трева што се лула.
    final blade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    final rnd = math.Random(3);
    for (var x = 0.0; x < w; x += 9) {
      final len = h * (0.04 + rnd.nextDouble() * 0.05);
      final baseY = h - rnd.nextDouble() * (h - horizon) * 0.5;
      final sway = math.sin(_tau * t * 2 + x * 0.04) * len * 0.35;
      blade.color = (rnd.nextBool() ? const Color(0xFF6E8B2E) : const Color(0xFFB7A23A)).withValues(alpha: 0.85);
      final p = Path()
        ..moveTo(x, baseY)
        ..quadraticBezierTo(x + sway * 0.3, baseY - len * 0.6, x + sway, baseY - len);
      canvas.drawPath(p, blade);
    }
  }

  @override
  bool shouldRepaint(_SavannaPainter old) => old.t != t || old.hc != hc;
}

/// Штит (хералдички облик) со златен раб.
class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.hc);

  final bool hc;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.06, h * 0.10)
      ..quadraticBezierTo(w * 0.5, -h * 0.04, w * 0.94, h * 0.10)
      ..lineTo(w * 0.94, h * 0.45)
      ..quadraticBezierTo(w * 0.92, h * 0.80, w * 0.5, h * 0.99)
      ..quadraticBezierTo(w * 0.08, h * 0.80, w * 0.06, h * 0.45)
      ..close();

    if (hc) {
      canvas.drawPath(path, Paint()..color = Colors.black);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Playful.sun,
      );
      return;
    }

    canvas.drawPath(
      path.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5484D), Color(0xFF9B1C31)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, w * 0.07)
        ..color = Playful.sun,
    );
    // Тенок внатрешен раб.
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.scale(0.78, 0.8);
    canvas.translate(-w * 0.5, -h * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.hc != hc;
}