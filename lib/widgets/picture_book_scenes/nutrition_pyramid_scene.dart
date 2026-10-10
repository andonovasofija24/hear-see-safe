import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'scene_contract.dart';

/// Four continuous tiers: 1 + 3 + 3 + 3 = 10 selectable food groups.
/// The outside cells are right triangles, while the middle cells are rectangles.
/// The camera zoom and the quiz button are independent of narration.
class NutritionPyramidScene extends PbScene {
  const NutritionPyramidScene({super.key, required super.items, required super.selected,
    required super.onSelect, required super.onOpen, required super.onQuiz,
    required super.quizLabel, required super.highContrast, super.reduceMotion});

  @override
  State<NutritionPyramidScene> createState() => _NutritionPyramidSceneState();
}

class _PyramidCell {
  const _PyramidCell(this.index, this.points, this.center);
  final int index;
  final List<Offset> points;
  final Offset center;
}

class _NutritionPyramidSceneState extends State<NutritionPyramidScene> {
  // Ten groups; each non-top tier has a left triangle, middle rectangle,
  // and right triangle. Their borders meet without spacing or overlap.
  static const _levels = <List<int>>[[0], [1, 2, 3], [4, 5, 6], [7, 8, 9]];

  List<_PyramidCell> _cells(Size size, Rect pyramid) {
    final result = <_PyramidCell>[];
    final center = pyramid.center.dx;
    final halfBase = pyramid.width / 2;
    final tierHeight = pyramid.height / 4;
    for (var row = 0; row < 4; row++) {
      final y0 = pyramid.top + row * tierHeight;
      final y1 = y0 + tierHeight;
      final topHalf = halfBase * row / 4;
      final bottomHalf = halfBase * (row + 1) / 4;
      final lt = center - topHalf;
      final rt = center + topHalf;
      final lb = center - bottomHalf;
      final rb = center + bottomHalf;
      if (row == 0) {
        result.add(_PyramidCell(0, [Offset(center, y0), Offset(rb, y1), Offset(lb, y1)],
          Offset(center, y0 + tierHeight * .67)));
      } else {
        final indices = _levels[row];
        // Both outer triangles have a vertical side and horizontal base,
        // and their hypotenuses coincide exactly with the pyramid outline.
        result.add(_PyramidCell(indices[0], [Offset(lt, y0), Offset(lt, y1), Offset(lb, y1)],
          Offset((lt * 2 + lb) / 3, (y0 + 2 * y1) / 3)));
        result.add(_PyramidCell(indices[1], [Offset(lt, y0), Offset(rt, y0), Offset(rt, y1), Offset(lt, y1)],
          Offset(center, (y0 + y1) / 2)));
        result.add(_PyramidCell(indices[2], [Offset(rt, y0), Offset(rb, y1), Offset(rt, y1)],
          Offset((rt * 2 + rb) / 3, (y0 + 2 * y1) / 3)));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        return const SizedBox.shrink();
      }
      final size = Size(width, height);
      final hc = widget.highContrast;
      final quizHeight = math.min(70.0, math.max(54.0, height * .14));
      // Keep the quiz inside the scene, and reserve space for it.
      final top = quizHeight + 7;
      final bottom = math.max(top + 20, height - math.max(6, height * .025));
      final pyramid = Rect.fromLTRB(width * .035, top, width * .965, bottom);
      final cells = _cells(size, pyramid);
      final selectedCell = cells.firstWhere(
        (cell) => cell.index == widget.selected,
        orElse: () => cells.first,
      );
      // Zoom around the chosen *tile*, not around the center of the pyramid.
      final scale = widget.reduceMotion ? 1.0 : 1.12;
      final anchor = selectedCell.center;
      final transform = Matrix4.identity()
        ..translate(width / 2 - anchor.dx * scale, height * .57 - anchor.dy * scale)
        ..scale(scale);

      return ClipRect(child: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: _EgyptPainter(highContrast: hc)),
        TweenAnimationBuilder<Matrix4>(
          tween: Matrix4Tween(end: transform),
          duration: widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic,
          builder: (context, matrix, child) => Transform(
            transform: matrix, alignment: Alignment.topLeft, child: child,
          ),
          child: SizedBox.expand(child: Stack(children: [
            for (final cell in cells)
              if (cell.index < widget.items.length)
                _PyramidTile(
                  cell: cell,
                  selected: cell.index == widget.selected,
                  highContrast: hc,
                  label: widget.items[cell.index].label,
                  emoji: widget.items[cell.index].emoji,
                  onTap: () {
                    if (cell.index == widget.selected) {
                      widget.onOpen();
                    } else {
                      widget.onSelect(cell.index);
                    }
                  },
                ),
          ])),
        ),
        Positioned(
          top: 3, left: 8, right: 8,
          child: Align(alignment: Alignment.topCenter,
            child: Semantics(button: true, label: widget.quizLabel,
              child: Material(
                color: hc ? Colors.black : const Color(0xFF75421D),
                borderRadius: BorderRadius.circular(26),
                child: InkWell(
                  onTap: widget.onQuiz,
                  borderRadius: BorderRadius.circular(26),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.max(80, width - 16), minHeight: quizHeight - 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.quiz_rounded, color: hc ? Colors.yellow : const Color(0xFFEFC46A), size: 32),
                        const SizedBox(width: 10),
                        Flexible(child: Text(widget.quizLabel, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: hc ? Colors.yellow : const Color(0xFFEFC46A),
                            fontWeight: FontWeight.w800, fontSize: 20))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]));
    });
  }
}

class _PyramidTile extends StatelessWidget {
  const _PyramidTile({required this.cell, required this.selected, required this.highContrast,
    required this.label, required this.emoji, required this.onTap});
  final _PyramidCell cell;
  final bool selected, highContrast;
  final String label, emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final xs = cell.points.map((p) => p.dx);
    final ys = cell.points.map((p) => p.dy);
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    final localPoints = cell.points.map((p) => p - rect.topLeft).toList();
    final isTriangle = localPoints.length == 3;
    final narrow = rect.width < 85;
    final fontSize = (rect.height * .15).clamp(10.0, 18.0);
    final emojiSize = (math.min(rect.height * .35, narrow ? rect.width * .60 : rect.width * .25))
      .clamp(13.0, 42.0);
    // Position text within the visible triangle, away from the sloping edge.
    final contentCenter = cell.center - rect.topLeft;
    return Positioned.fromRect(rect: rect, child: Semantics(
      button: true, selected: selected, label: label,
      child: ClipPath(
        clipper: _PolygonClipper(localPoints),
        child: Material(
          color: selected ? const Color(0xFFFFE3A2) :
            (highContrast ? Colors.black : const Color(0xFFE9BE73)),
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _TileBorderPainter(
                points: localPoints, selected: selected, highContrast: highContrast))),
              Positioned(
                left: (contentCenter.dx - math.max(25, rect.width * (isTriangle ? .48 : .9)) / 2)
                  .clamp(0.0, rect.width),
                top: (contentCenter.dy - rect.height * .34).clamp(0.0, rect.height),
                width: math.min(rect.width, math.max(25, rect.width * (isTriangle ? .48 : .9))),
                height: math.min(rect.height * .68, rect.height),
                child: FittedBox(fit: BoxFit.scaleDown, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(emoji, style: TextStyle(fontSize: emojiSize)),
                    const SizedBox(height: 1),
                    ConstrainedBox(constraints: BoxConstraints(maxWidth: math.max(22, rect.width * .9)),
                      child: Text(label, maxLines: 2, textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900,
                          color: highContrast ? Colors.yellow : const Color(0xFF3B240E)))),
                  ],
                )),
              ),
            ]),
          ),
        ),
      ),
    ));
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.points);
  final List<Offset> points;
  @override Path getClip(Size size) => Path()..addPolygon(points, true);
  @override bool shouldReclip(covariant _PolygonClipper old) => old.points != points;
}

class _TileBorderPainter extends CustomPainter {
  const _TileBorderPainter({required this.points, required this.selected, required this.highContrast});
  final List<Offset> points;
  final bool selected, highContrast;
  @override void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 4 : 2
      ..color = selected ? const Color(0xFFFFE600) :
        (highContrast ? Colors.white : const Color(0xFF96632F)));
  }
  @override bool shouldRepaint(covariant _TileBorderPainter old) =>
    old.selected != selected || old.highContrast != highContrast || old.points != points;
}

class _EgyptPainter extends CustomPainter {
  const _EgyptPainter({required this.highContrast});
  final bool highContrast;
  @override void paint(Canvas canvas, Size s) {
    if (highContrast) {
      canvas.drawColor(Colors.black, BlendMode.src);
      return;
    }
    canvas.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF69B9D8), Color(0xFFF8D596)],
    ).createShader(Offset.zero & s));
    canvas.drawCircle(Offset(s.width * .85, s.height * .12), s.width * .065,
      Paint()..color = const Color(0xFFFFE9AC));
    final sand = Path()..moveTo(0, s.height * .8)
      ..quadraticBezierTo(s.width * .5, s.height * .72, s.width, s.height * .8)
      ..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
    canvas.drawPath(sand, Paint()..color = const Color(0xFFE7B86A));
  }
  @override bool shouldRepaint(covariant _EgyptPainter old) => old.highContrast != highContrast;
}