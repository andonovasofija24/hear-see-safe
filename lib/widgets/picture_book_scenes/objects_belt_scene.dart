import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../playful_ui.dart';
import 'scene_contract.dart';

const Color _kHcYellow = Color(0xFFFFFF00);

/// „Секојдневни предмети“: фабричка подвижна лента. Предметите стојат во
/// кутии на лентата; избраниот е секогаш во СРЕДИНАТА, под рефлекторот и
/// во рамка - поголем и посветол. Листата е кружна (се гледаат предмети од
/// двете страни). Квизот е машина горе десно над лентата.
///
///  * Хоризонтално влечење по лентата: по еден предмет на секоја ширина
///    на поле ([onSelect]).
///  * Допир на страничен предмет -> [onSelect]; на средниот -> [onOpen].
///  * Лентата (ленти и валјаци) постојано се движи, освен со [reduceMotion].
class ObjectsBeltScene extends PbScene {
  const ObjectsBeltScene({
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

  /// Во деталниот приказ ја задржува сцената и го зголемува централниот поим.
  final bool focusMode;

  @override
  State<ObjectsBeltScene> createState() => _ObjectsBeltSceneState();
}

class _ObjectsBeltSceneState extends State<ObjectsBeltScene> with TickerProviderStateMixin {
  /// Непрекината позиција на лентата во „полиња“: предметот со индекс
  /// round(_pos) mod n е во средината.
  double _pos = 0;

  late final AnimationController _slide;
  double _from = 0, _to = 0;

  /// Постојано движење на лентата (0..1, се повторува).
  late final AnimationController _run;

  bool _dragging = false;
  int _emitted = 0;
  double _slotW = 100;

  int get _n => widget.items.length;

  int _mod(int j) {
    final n = _n;
    if (n == 0) return 0;
    return ((j % n) + n) % n;
  }

  @override
  void initState() {
    super.initState();
    _pos = widget.selected.toDouble();
    _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_slide.value);
        setState(() => _pos = _from + (_to - _from) * t);
      });
    _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (!widget.reduceMotion) _run.repeat();
  }

  @override
  void didUpdateWidget(covariant ObjectsBeltScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (widget.reduceMotion) {
        _run.stop();
      } else {
        _run.repeat();
      }
    }
    if (oldWidget.items.length != widget.items.length) {
      _slide.stop();
      _pos = widget.selected.toDouble();
      return;
    }
    if (oldWidget.selected != widget.selected && !_dragging) {
      final cur = _slide.isAnimating ? _to : _pos;
      if (_mod(cur.round()) != widget.selected) _slideTo(_nearest(widget.selected, cur), rebuild: false);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _run.dispose();
    super.dispose();
  }

  /// Најблиската позиција (по пократкиот пат околу кругот) каде [index]
  /// е во средината.
  double _nearest(int index, double from) {
    final n = _n;
    if (n == 0) return from;
    final base = from.roundToDouble();
    final curIdx = _mod(base.toInt());
    var d = (index - curIdx) % n; // 0..n-1
    if (d > n / 2) d -= n;
    return base + d;
  }

  void _slideTo(double target, {bool rebuild = true}) {
    if (widget.reduceMotion) {
      _slide.stop();
      _pos = target;
      if (rebuild) setState(() {});
      return;
    }
    _from = _pos;
    _to = target;
    _slide.forward(from: 0);
  }

  void _tapSlot(int slot, int index) {
    if (_n == 0) return;
    final centerSlot = (_slide.isAnimating ? _to : _pos).round();
    if (slot == centerSlot && index == widget.selected) {
      widget.onOpen();
    } else if (index == widget.selected) {
      // Копија на избраниот (кратка листа) - само лизни до неа.
      _slideTo(slot.toDouble());
    } else {
      _slideTo(slot.toDouble());
      widget.onSelect(index);
    }
  }

  void _onDragStart(DragStartDetails d) {
    if (_n == 0) return;
    _slide.stop();
    _dragging = true;
    _emitted = widget.selected;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() => _pos -= d.delta.dx / _slotW);
    final idx = _mod(_pos.round());
    if (idx != _emitted) {
      _emitted = idx;
      widget.onSelect(idx);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    // Мало „фрлање“: најмногу 2 полиња понатаму.
    final fling = (-d.velocity.pixelsPerSecond.dx / _slotW * 0.15).clamp(-2.0, 2.0).toDouble();
    final target = (_pos + fling).roundToDouble();
    final idx = _mod(target.toInt());
    _slideTo(target);
    if (idx != _emitted) {
      _emitted = idx;
      widget.onSelect(idx);
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _slideTo(_pos.roundToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.highContrast;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 420.0;

        final visible = w < 400 ? 4.2 : (w < 700 ? 5.0 : 5.6);
        final slotW = w / visible;
        _slotW = slotW;
        final beltTop = h * 0.64;
        final beltH = (h * 0.11).clamp(30.0, 52.0).toDouble();
        final floorY = h * 0.95;
        final sc = (math.min(slotW * 0.95, h * 0.32)).clamp(60.0, 150.0).toDouble();
        final ss = sc * 0.72;

        final mW = (w * 0.35).clamp(118.0, 210.0).clamp(0.0, w - 28).toDouble();
        final mH = (beltTop - ss - 22).clamp(76.0, 155.0).toDouble();

        final n = _n;
        final children = <Widget>[];
        if (n > 0) {
          final half = (visible / 2).ceil() + 1;
          final first = _pos.floor() - half;
          final last = _pos.floor() + half + 1;
          final centerSlot = _pos.round();
          final shown = <int>{};
          // Од рабовите кон средината, за средниот да е најгоре.
          final slots = [for (var j = first; j <= last; j++) j]
            ..sort((a, b) => (b - _pos).abs().compareTo((a - _pos).abs()));
          for (final j in slots) {
            final cx = w / 2 + (j - _pos) * slotW;
            if (cx < -slotW || cx > w + slotW) continue;
            final idx = _mod(j);
            final t = (1 - (j - _pos).abs()).clamp(0.0, 1.0).toDouble();
            final s = ss + (sc - ss) * t;
            final isCenter = j == centerSlot && idx == widget.selected;
            // Кај кратка листа истиот предмет може да се појави двапати:
            // читачот на екран го слуша само еднаш.
            final duplicate = !shown.add(idx);
            children.add(
              Positioned(
                left: cx - s / 2,
                top: beltTop - s + beltH * 0.08,
                width: s,
                height: s,
                child: widget.focusMode && isCenter
                    ? Transform.scale(
                        scale: 1.22,
                        alignment: Alignment.bottomCenter,
                        child: _box(j, idx, s, t, isCenter, duplicate, hc),
                      )
                    : _box(j, idx, s, t, isCenter, duplicate, hc),
              ),
            );
          }
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FactoryPainter(
                        highContrast: hc,
                        beltTop: beltTop,
                        floorY: floorY,
                        spotW: sc * 1.3,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BeltPainter(
                        run: _run,
                        pos: _pos,
                        slotW: slotW,
                        highContrast: hc,
                        beltTop: beltTop,
                        beltH: beltH,
                        floorY: floorY,
                      ),
                    ),
                  ),
                  ...children,
                  // Рамка (како на камера) околу средното поле.
                  Positioned(
                    left: w / 2 - sc * 0.64,
                    top: beltTop - sc * 1.12,
                    width: sc * 1.28,
                    height: sc * 1.12 + beltH * 0.2,
                    child: IgnorePointer(
                      child: CustomPaint(painter: _FramePainter(color: hc ? _kHcYellow : Playful.sun)),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 10,
                    width: mW,
                    height: mH,
                    child: _quizMachine(mH, hc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Кутија на лентата со предметот.
  Widget _box(int slot, int index, double s, double t, bool isCenter, bool duplicate, bool hc) {
    final it = widget.items[index];
    final opacity = hc || isCenter ? 1.0 : 0.45 + 0.4 * t;
    final radius = BorderRadius.circular(s * 0.16);
    Widget box = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapSlot(slot, index),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: opacity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: hc ? Colors.black : null,
                    gradient: hc
                        ? null
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isCenter
                                ? const [Color(0xFFFFF4D6), Color(0xFFFFE08A)]
                                : const [Color(0xFFE2B57A), Color(0xFFC48A4E)],
                          ),
                    border: Border.all(
                      color: isCenter ? (hc ? _kHcYellow : Playful.sun) : (hc ? Colors.white : const Color(0xFF8A5A2B)),
                      width: isCenter ? math.max(3.5, s * 0.05) : 2,
                    ),
                    boxShadow: hc
                        ? null
                        : [
                            if (isCenter)
                              BoxShadow(color: Playful.sun.withValues(alpha: 0.8), blurRadius: 26, spreadRadius: 3)
                            else
                              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3)),
                          ],
                  ),
                ),
              ),
              // Леплива трака на кутијата.
              if (!hc && !isCenter)
                Positioned(
                  left: s * 0.42,
                  width: s * 0.16,
                  top: 0,
                  height: s * 0.2,
                  child: ColoredBox(color: const Color(0xFFF3D9A8).withValues(alpha: 0.85)),
                ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(s * 0.1),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      it.emoji,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: s * 0.6, height: 1.15),
                    ),
                  ),
                ),
              ),
              if (it.visited)
                Positioned(
                  top: -s * 0.06,
                  right: -s * 0.06,
                  width: s * 0.28,
                  height: s * 0.28,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hc ? _kHcYellow : const Color(0xFF2FBF71),
                      border: Border.all(color: hc ? Colors.black : Colors.white, width: 1.5),
                    ),
                    child: FittedBox(
                      child: Icon(Icons.check_rounded, color: hc ? Colors.black : Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (duplicate) return ExcludeSemantics(child: box);
    return Semantics(
      sortKey: OrdinalSortKey(index.toDouble()),
      button: true,
      selected: index == widget.selected,
      label: it.label,
      child: box,
    );
  }

  /// Машината за квиз (горе десно, над крајот на лентата).
  Widget _quizMachine(double mH, bool hc) {
    final light = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? Colors.white : const Color(0xFF7CFFB2),
      ),
    );
    return Semantics(
      sortKey: const OrdinalSortKey(1000),
      button: true,
      label: widget.quizLabel,
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onQuiz,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: hc ? Colors.black : null,
                gradient: hc
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF5B6CFF), Color(0xFF3A47C9)],
                      ),
                border: Border.all(color: hc ? _kHcYellow : Playful.sun, width: 3),
                boxShadow: hc
                    ? null
                    : [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                        BoxShadow(color: Playful.sun.withValues(alpha: 0.3), blurRadius: 18),
                      ],
              ),
              child: Stack(
                children: [
                  Positioned(left: 9, top: 9, child: light),
                  Positioned(right: 9, top: 9, child: light),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: hc ? Colors.black : Playful.ink,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(Icons.quiz_rounded, size: mH * 0.42, color: hc ? _kHcYellow : Playful.sun),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.quizLabel,
                              maxLines: 1,
                              style: Playful.title((mH * 0.24).clamp(20.0, 32.0).toDouble(), color: Colors.white),
                            ),
                          ],
                        ),
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
}

/// Ѕид, под, светилка со рефлектор кон средното поле.
class _FactoryPainter extends CustomPainter {
  _FactoryPainter({required this.highContrast, required this.beltTop, required this.floorY, required this.spotW});

  final bool highContrast;
  final double beltTop;
  final double floorY;
  final double spotW;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final cx = size.width / 2;
    if (highContrast) {
      canvas.drawRect(full, Paint()..color = Colors.black);
      canvas.drawLine(
        Offset(0, floorY),
        Offset(size.width, floorY),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3,
      );
    } else {
      canvas.drawRect(
        full,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Playful.nightRaised, Playful.night],
          ).createShader(full),
      );
      // Прозорци на ѕидот.
      final win = Paint()..color = Colors.white.withValues(alpha: 0.06);
      final ww = size.width * 0.12;
      final wh = beltTop * 0.28;
      for (final fx in const [0.06, 0.24]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(size.width * fx, beltTop * 0.12, ww, wh), const Radius.circular(6)),
          win,
        );
      }
      // Под.
      canvas.drawRect(
        Rect.fromLTRB(0, floorY, size.width, size.height),
        Paint()..color = const Color(0xFF2A2960),
      );
      // Рефлектор.
      final top = size.height * 0.07;
      final cone = Path()
        ..moveTo(cx - 12, top)
        ..lineTo(cx + 12, top)
        ..lineTo(cx + spotW / 2, beltTop)
        ..lineTo(cx - spotW / 2, beltTop)
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Playful.sun.withValues(alpha: 0.45), Playful.sun.withValues(alpha: 0.06)],
          ).createShader(Rect.fromLTRB(cx - spotW / 2, top, cx + spotW / 2, beltTop)),
      );
    }
    // Светилка: кабел + абажур.
    final top = size.height * 0.07;
    final lamp = Paint()..color = highContrast ? Colors.white : const Color(0xFF9AA3C7);
    canvas.drawLine(Offset(cx, 0), Offset(cx, top - 8), lamp..strokeWidth = 2);
    final shade = Path()
      ..moveTo(cx - 7, top - 10)
      ..lineTo(cx + 7, top - 10)
      ..lineTo(cx + 16, top + 2)
      ..lineTo(cx - 16, top + 2)
      ..close();
    canvas.drawPath(shade, Paint()..color = highContrast ? Colors.white : const Color(0xFF9AA3C7));
    canvas.drawCircle(Offset(cx, top + 3), 4, Paint()..color = highContrast ? _kHcYellow : Playful.sun);
  }

  @override
  bool shouldRepaint(covariant _FactoryPainter old) =>
      old.highContrast != highContrast || old.beltTop != beltTop || old.floorY != floorY || old.spotW != spotW;
}

/// Лентата: подвижни пруги, валјаци што се вртат и нозе.
class _BeltPainter extends CustomPainter {
  _BeltPainter({
    required this.run,
    required this.pos,
    required this.slotW,
    required this.highContrast,
    required this.beltTop,
    required this.beltH,
    required this.floorY,
  }) : super(repaint: run);

  final Animation<double> run;
  final double pos;
  final double slotW;
  final bool highContrast;
  final double beltTop;
  final double beltH;
  final double floorY;

  @override
  void paint(Canvas canvas, Size size) {
    final hc = highContrast;
    final left = 6.0;
    final right = size.width - 6;
    final belt = Rect.fromLTRB(left, beltTop, right, beltTop + beltH);
    final rr = RRect.fromRectAndRadius(belt, Radius.circular(beltH / 2));

    // Нозе (под лентата).
    final legCount = size.width < 600 ? 3 : 4;
    final legW = math.max(10.0, beltH * 0.3);
    final legPaint = Paint()..color = hc ? Colors.black : const Color(0xFF6B7280);
    final legEdge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var k = 0; k < legCount; k++) {
      final x = size.width * (0.12 + 0.76 * k / (legCount - 1));
      final leg = Rect.fromLTRB(x - legW / 2, beltTop + beltH - 2, x + legW / 2, floorY);
      canvas.drawRect(leg, legPaint);
      final foot = Rect.fromLTRB(x - legW, floorY - 6, x + legW, floorY);
      canvas.drawRRect(RRect.fromRectAndRadius(foot, const Radius.circular(3)), legPaint);
      if (hc) {
        canvas.drawRect(leg, legEdge);
        canvas.drawRRect(RRect.fromRectAndRadius(foot, const Radius.circular(3)), legEdge);
      }
    }

    // Тело на лентата.
    canvas.drawRRect(rr, Paint()..color = hc ? Colors.black : const Color(0xFF23253A));

    // Поместување: постојано движење + лизгање при промена на избраниот.
    final gap = beltH * 0.9;
    final shift = run.value * gap * 2 - pos * slotW;

    canvas.save();
    canvas.clipRRect(rr);
    // Горна површина со пруги.
    final surfH = beltH * 0.38;
    final surf = Rect.fromLTRB(left, beltTop, right, beltTop + surfH);
    canvas.drawRect(surf, Paint()..color = hc ? Colors.black : const Color(0xFF3A3D5C));
    final stripe = Paint()
      ..color = hc ? Colors.white : const Color(0xFF5A5E85)
      ..strokeWidth = hc ? 2 : 3
      ..strokeCap = StrokeCap.round;
    final off = shift % gap; // 0..gap
    for (var x = left - gap + off; x < right + gap; x += gap) {
      canvas.drawLine(Offset(x, beltTop + 2), Offset(x - surfH * 0.6, beltTop + surfH - 2), stripe);
    }
    // Валјаци.
    final rollerR = beltH * 0.24;
    final rollerY = beltTop + surfH + (beltH - surfH) / 2;
    final rollerGap = rollerR * 3.2;
    final angle = shift / rollerR;
    final rollerFill = Paint()..color = hc ? Colors.black : const Color(0xFF8E94B8);
    final rollerEdge = Paint()
      ..color = hc ? Colors.white : const Color(0xFF4B4F73)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final spoke = Paint()
      ..color = hc ? Colors.white : const Color(0xFF4B4F73)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = left + rollerR * 1.6; x < right - rollerR; x += rollerGap) {
      final c = Offset(x, rollerY);
      canvas.drawCircle(c, rollerR, rollerFill);
      canvas.drawCircle(c, rollerR, rollerEdge);
      for (var k = 0; k < 2; k++) {
        final a = angle + k * math.pi / 2;
        final d = Offset(math.cos(a), math.sin(a)) * (rollerR * 0.8);
        canvas.drawLine(c - d, c + d, spoke);
      }
    }
    canvas.restore();

    // Раб на лентата.
    canvas.drawRRect(
      rr,
      Paint()
        ..color = hc ? Colors.white : const Color(0xFF101120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hc ? 3 : 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BeltPainter old) =>
      old.pos != pos ||
      old.slotW != slotW ||
      old.highContrast != highContrast ||
      old.beltTop != beltTop ||
      old.beltH != beltH ||
      old.floorY != floorY ||
      old.run != run;
}

/// Четири агли (како визир на камера) околу средното поле.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final l = math.min(size.width, size.height) * 0.22;
    final w = size.width;
    final h = size.height;
    const i = 3.0;
    canvas.drawPath(Path()..moveTo(i, i + l)..lineTo(i, i)..lineTo(i + l, i), p);
    canvas.drawPath(Path()..moveTo(w - i - l, i)..lineTo(w - i, i)..lineTo(w - i, i + l), p);
    canvas.drawPath(Path()..moveTo(i, h - i - l)..lineTo(i, h - i)..lineTo(i + l, h - i), p);
    canvas.drawPath(Path()..moveTo(w - i - l, h - i)..lineTo(w - i, h - i)..lineTo(w - i, h - i - l), p);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.color != color;
}