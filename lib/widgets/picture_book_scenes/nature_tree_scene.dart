import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../playful_ui.dart';
import 'scene_contract.dart';

const Color _kHcYellow = Color(0xFFFFFF00);

/// Колку долго (по допир / влечење) круната мирува пред повторно да го
/// донесе избраниот поим напред и полека да се њиша.
const Duration _kIdlePause = Duration(seconds: 3);

/// „Природа“: дрво чија круна е 3D топка што полека се врти, со иконите
/// на поимите по нејзината површина. Избраниот поим секогаш се носи
/// напред (во средината на круната) - поголем, посветол и со сјаен прстен.
/// Квизот е дрвена табла заковата на стеблото.
///
///  * Хоризонтално влечење ја врти круната (вертикалното останува за
///    лизгање на страницата).
///  * Кога мирува, круната нежно се њиша лево-десно околу избраниот поим
///    (така избраниот останува напред) - освен со [reduceMotion].
///  * По влечење, по ~3 s избраниот поим анимирано се враќа напред.
class NatureTreeScene extends PbScene {
  const NatureTreeScene({
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
  State<NatureTreeScene> createState() => _NatureTreeSceneState();
}

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
}

/// Рамномерни точки по сфера („Фибоначиева“ сфера), |y| <= [maxY].
List<_V3> _fibonacci(int n, double maxY) {
  final golden = math.pi * (3 - math.sqrt(5));
  return [
    for (var i = 0; i < n; i++)
      () {
        final y = n == 1 ? 0.0 : (1 - (i / (n - 1)) * 2) * maxY;
        final r = math.sqrt(math.max(0.0, 1 - y * y));
        final th = golden * i;
        return _V3(math.cos(th) * r, y, math.sin(th) * r);
      }(),
  ];
}

/// Прво околу Y (yaw), па околу X (pitch). z > 0 = кон гледачот.
_V3 _rotate(_V3 p, double yaw, double pitch) {
  final cy = math.cos(yaw), sy = math.sin(yaw);
  final x1 = p.x * cy + p.z * sy;
  final z1 = -p.x * sy + p.z * cy;
  final cp = math.cos(pitch), sp = math.sin(pitch);
  final y2 = p.y * cp - z1 * sp;
  final z2 = p.y * sp + z1 * cp;
  return _V3(x1, y2, z2);
}

class _NatureTreeSceneState extends State<NatureTreeScene> with TickerProviderStateMixin {
  double _yaw = 0;
  double _pitch = 0;

  /// Нежно њишање кога круната мирува (0 = без, 1 = полно).
  double _swayT = 0;
  double _swayAmt = 0;

  /// Инерција по фрлање (радијани во секунда).
  double _vYaw = 0;
  bool _dragging = false;

  /// Полупречник на круната од последниот build (за влечењето).
  double _radius = 100;

  late List<_V3> _points;
  final List<_V3> _leaves = _fibonacci(46, 0.97);

  late final AnimationController _focus;
  double _fromYaw = 0, _toYaw = 0, _fromPitch = 0, _toPitch = 0;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Активен додека трае паузата по допир / влечење.
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _points = _fibonacci(widget.items.length, 0.78);
    _focus = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))
      ..addListener(_onFocusTick);
    _ticker = createTicker(_onTick);
    _jumpTo(widget.selected);
    if (!widget.reduceMotion) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant NatureTreeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lengthChanged = oldWidget.items.length != widget.items.length;
    if (lengthChanged) _points = _fibonacci(widget.items.length, 0.78);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (widget.reduceMotion) {
        _ticker.stop();
        _swayAmt = 0;
        _vYaw = 0;
      } else if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    }
    if (lengthChanged || oldWidget.selected != widget.selected) {
      // Стрелките на родителот се исто допир: пауза за њишањето.
      _interact();
      _bringToFront(widget.selected, rebuild: false);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _effYaw => _yaw + _swayAmt * 0.42 * math.sin(_swayT * 0.55) * 0.75;

  /// Вртење (yaw, pitch) што го носи поимот [i] точно напред, најблиску до
  /// сегашното вртење.
  (double, double) _targetFor(int i) {
    final p = _points[i];
    var ty = math.atan2(-p.x, p.z);
    final tp = math.atan2(p.y, math.sqrt(p.x * p.x + p.z * p.z)).clamp(-1.2, 1.2).toDouble();
    while (ty - _yaw > math.pi) {
      ty -= 2 * math.pi;
    }
    while (ty - _yaw < -math.pi) {
      ty += 2 * math.pi;
    }
    return (ty, tp);
  }

  void _jumpTo(int i) {
    if (i < 0 || i >= _points.length) return;
    final (ty, tp) = _targetFor(i);
    _yaw = ty;
    _pitch = tp;
  }

  /// Њишањето се „впишува“ во вртењето за да нема скок.
  void _bakeSway() {
    _yaw = _effYaw;
    _swayAmt = 0;
  }

  /// [rebuild] = false кога се вика од didUpdateWidget (build и онака следи).
  void _bringToFront(int i, {bool rebuild = true}) {
    if (i < 0 || i >= _points.length) return;
    _bakeSway();
    _vYaw = 0;
    final (ty, tp) = _targetFor(i);
    if (widget.reduceMotion) {
      _focus.stop();
      _yaw = ty;
      _pitch = tp;
      if (rebuild) setState(() {});
      return;
    }
    _fromYaw = _yaw;
    _fromPitch = _pitch;
    _toYaw = ty;
    _toPitch = tp;
    _focus.forward(from: 0);
  }

  void _onFocusTick() {
    final t = Curves.easeInOutCubic.transform(_focus.value);
    setState(() {
      _yaw = _fromYaw + (_toYaw - _fromYaw) * t;
      _pitch = _fromPitch + (_toPitch - _fromPitch) * t;
    });
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _lastTick = elapsed;
    if (!mounted || _dragging) return;
    var changed = false;
    if (_vYaw != 0 && !_focus.isAnimating) {
      _yaw += _vYaw * dt;
      _vYaw *= math.pow(0.12, dt).toDouble();
      if (_vYaw.abs() < 0.02) _vYaw = 0;
      changed = true;
    }
    _swayT += dt;
    final idle = _idle == null && !_focus.isAnimating && _vYaw == 0;
    if (idle) {
      if (_swayAmt < 1) _swayAmt = math.min(1.0, _swayAmt + dt / 1.8);
      changed = true;
    }
    if (changed) setState(() {});
  }

  /// Допир / влечење: пауза од ~3 s, потоа избраниот пак напред.
  void _interact() {
    _bakeSway();
    _idle?.cancel();
    _idle = Timer(_kIdlePause, () {
      _idle = null;
      if (!mounted) return;
      _bringToFront(widget.selected);
    });
  }

  void _tapItem(int i) {
    _interact();
    if (i == widget.selected) {
      widget.onOpen();
    } else {
      widget.onSelect(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.highContrast;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 420.0;
        final groundY = h * 0.92;
        final top = h * 0.05;
        final r = math.max(56.0, math.min(math.min(w * 0.40, h * 0.36), (groundY - top - 72) / 2));
        _radius = r;
        final cx = w / 2;
        final cy = top + r;
        final trunkW = (r * 0.42).clamp(34.0, 90.0).toDouble();
        final base = (r * 0.40).clamp(38.0, 84.0).toDouble();
        final orbit = r * 0.86;

        // Табла за квизот на видливиот дел од стеблото.
        final visTrunk = groundY - (cy + r);
        final signH = (visTrunk * 0.9).clamp(64.0, 88.0).toDouble();
        final signW = (w * 0.48).clamp(155.0, 270.0).clamp(0.0, w - 24).toDouble();
        final signTop = cy + r + math.max(2.0, (visTrunk - signH) / 2);

        final yaw = _effYaw;
        final projected = <(int, _V3)>[
          for (var i = 0; i < _points.length; i++) (i, _rotate(_points[i], yaw, _pitch)),
        ]..sort((a, b) => a.$2.z.compareTo(b.$2.z)); // задните прво

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _bakeSway();
              _idle?.cancel();
              _idle = null;
              _focus.stop();
              _vYaw = 0;
              _dragging = true;
            },
            onHorizontalDragUpdate: (d) {
              setState(() => _yaw += d.delta.dx / _radius);
            },
            onHorizontalDragEnd: (d) {
              _dragging = false;
              if (!widget.reduceMotion) {
                _vYaw = (d.velocity.pixelsPerSecond.dx / _radius).clamp(-6.0, 6.0).toDouble();
                if (_vYaw.abs() < 0.05) _vYaw = 0;
              }
              _interact();
            },
            onHorizontalDragCancel: () {
              _dragging = false;
              _interact();
            },
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreePainter(
                        highContrast: hc,
                        center: Offset(cx, cy),
                        radius: r,
                        groundY: groundY,
                        trunkW: trunkW,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CrownPainter(
                        yaw: yaw,
                        pitch: _pitch,
                        highContrast: hc,
                        center: Offset(cx, cy),
                        radius: r,
                        leaves: _leaves,
                      ),
                    ),
                  ),
                  for (final (i, p) in projected) _item(i, p, cx, cy, orbit, base, hc),
                  Positioned(
                    left: cx - signW / 2,
                    top: signTop,
                    width: signW,
                    height: signH,
                    child: _quizSign(signH, hc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _item(int i, _V3 p, double cx, double cy, double orbit, double base, bool hc) {
    final it = widget.items[i];
    final isSel = i == widget.selected;
    final depth = (p.z + 1) / 2; // 0 = најназад, 1 = најнапред
    var s = base * (0.5 + 0.5 * depth);
    if (isSel) s *= 1.3;
    final opacity = hc || isSel ? 1.0 : (0.30 + 0.62 * math.pow(depth, 1.5)).clamp(0.0, 1.0).toDouble();
    final ringColor = hc ? _kHcYellow : Playful.sun;

    return Positioned(
      left: cx + p.x * orbit - s / 2,
      top: cy - p.y * orbit - s / 2,
      width: s,
      height: s,
      child: Semantics(
        sortKey: OrdinalSortKey(i.toDouble()),
        button: true,
        selected: isSel,
        label: it.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapItem(i),
          child: ExcludeSemantics(
            child: Opacity(
              opacity: opacity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (isSel && !hc)
                    Positioned(
                      left: -s * 0.12,
                      top: -s * 0.12,
                      right: -s * 0.12,
                      bottom: -s * 0.12,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Playful.sun.withValues(alpha: 0.6), width: 3),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc ? Colors.black : Colors.white.withValues(alpha: isSel ? 0.96 : 0.80),
                        border: Border.all(
                          color: isSel ? ringColor : Colors.white,
                          width: isSel ? math.max(3.5, s * 0.06) : 2,
                        ),
                        boxShadow: hc
                            ? null
                            : [
                                if (isSel)
                                  BoxShadow(color: Playful.sun.withValues(alpha: 0.85), blurRadius: 24, spreadRadius: 4)
                                else
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.18 * depth), blurRadius: 8, offset: const Offset(0, 3)),
                              ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(s * 0.12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            it.emoji,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: s * 0.56, height: 1.15),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (it.visited)
                    Positioned(
                      top: -s * 0.04,
                      right: -s * 0.04,
                      width: s * 0.3,
                      height: s * 0.3,
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
        ),
      ),
    );
  }

  /// Дрвена табла на стеблото со бувче и икона за квиз.
  Widget _quizSign(double signH, bool hc) {
    final radius = BorderRadius.circular(16);
    final nail = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? Colors.white : const Color(0xFF3A2410),
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
            onTap: () {
              _interact();
              widget.onQuiz();
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: hc ? Colors.black : null,
                gradient: hc
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFC98A4B), Color(0xFF9A5F2C)],
                      ),
                border: Border.all(color: hc ? _kHcYellow : Playful.sun, width: hc ? 3.5 : 3),
                boxShadow: hc
                    ? null
                    : [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                        BoxShadow(color: Playful.sun.withValues(alpha: 0.35), blurRadius: 16),
                      ],
              ),
              child: Stack(
                children: [
                  Positioned(left: 7, top: 7, child: nail),
                  Positioned(right: 7, top: 7, child: nail),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🦉', style: TextStyle(fontSize: signH * 0.52, height: 1.1)),
                            const SizedBox(width: 6),
                            Icon(Icons.quiz_rounded, size: signH * 0.5, color: hc ? _kHcYellow : Playful.sun),
                            const SizedBox(width: 8),
                            Text(
                              widget.quizLabel,
                              maxLines: 1,
                              style: Playful.title((signH * 0.38).clamp(22.0, 34.0).toDouble(), color: Colors.white),
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

/// Небо, трева, стебло и корени (не зависат од вртењето).
class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.highContrast,
    required this.center,
    required this.radius,
    required this.groundY,
    required this.trunkW,
  });

  final bool highContrast;
  final Offset center;
  final double radius;
  final double groundY;
  final double trunkW;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final hc = highContrast;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Небо.
    if (hc) {
      canvas.drawRect(full, Paint()..color = Colors.black);
    } else {
      canvas.drawRect(
        full,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6FC3F0), Color(0xFFD6F2FF)],
          ).createShader(full),
      );
      // Сонце и облачиња.
      final sunR = math.min(size.width, size.height) * 0.06;
      final sunC = Offset(size.width * 0.1 + sunR, size.height * 0.08 + sunR);
      canvas.drawCircle(sunC, sunR * 1.6, Paint()..color = Playful.sun.withValues(alpha: 0.25));
      canvas.drawCircle(sunC, sunR, Paint()..color = Playful.sun);
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
      void drawCloud(Offset c, double s) {
        canvas.drawCircle(c, s, cloud);
        canvas.drawCircle(c + Offset(s * 0.9, s * 0.15), s * 0.8, cloud);
        canvas.drawCircle(c + Offset(-s * 0.9, s * 0.2), s * 0.7, cloud);
      }

      final cs = math.min(size.width, size.height) * 0.04;
      drawCloud(Offset(size.width * 0.86, size.height * 0.14), cs);
      drawCloud(Offset(size.width * 0.78, size.height * 0.34), cs * 0.75);
    }

    // Трева (благ рид).
    final ground = Path()
      ..moveTo(0, groundY + 6)
      ..quadraticBezierTo(size.width / 2, groundY - 14, size.width, groundY + 6)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (hc) {
      canvas.drawPath(ground, Paint()..color = Colors.black);
      canvas.drawPath(ground, white);
    } else {
      final gRect = Rect.fromLTRB(0, groundY - 14, size.width, size.height);
      canvas.drawPath(
        ground,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6CC24A), Color(0xFF3F8F2F)],
          ).createShader(gRect),
      );
    }

    // Корени.
    final cx = center.dx;
    final baseY = groundY + 2;
    final root = Paint()
      ..color = hc ? Colors.white : const Color(0xFF5C3A1A)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = hc ? 4 : math.max(4.0, trunkW * 0.2);
    for (final dir in const [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + dir * trunkW * 0.45, baseY - 6)
          ..quadraticBezierTo(cx + dir * trunkW * 1.0, baseY + 2, cx + dir * trunkW * 1.6, baseY + 10),
        root,
      );
      canvas.drawPath(
        Path()
          ..moveTo(cx + dir * trunkW * 0.2, baseY - 4)
          ..quadraticBezierTo(cx + dir * trunkW * 0.5, baseY + 8, cx + dir * trunkW * 0.9, baseY + 16),
        root,
      );
    }

    // Стебло (пошироко долу), почнува под круната.
    final trunkTop = center.dy + radius * 0.5;
    final trunk = Path()
      ..moveTo(cx - trunkW / 2, trunkTop)
      ..lineTo(cx + trunkW / 2, trunkTop)
      ..quadraticBezierTo(cx + trunkW * 0.5, baseY - trunkW * 0.3, cx + trunkW * 0.8, baseY)
      ..lineTo(cx - trunkW * 0.8, baseY)
      ..quadraticBezierTo(cx - trunkW * 0.5, baseY - trunkW * 0.3, cx - trunkW / 2, trunkTop)
      ..close();
    if (hc) {
      canvas.drawPath(trunk, Paint()..color = Colors.black);
      canvas.drawPath(trunk, white);
    } else {
      final tRect = Rect.fromLTRB(cx - trunkW, trunkTop, cx + trunkW, baseY);
      canvas.drawPath(
        trunk,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF9C6634), Color(0xFF7A4A22), Color(0xFF5C3A1A)],
            stops: [0.0, 0.55, 1.0],
          ).createShader(tRect),
      );
      // Кора.
      final bark = Paint()
        ..color = const Color(0xFF4A2E14).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2;
      for (final fx in const [-0.22, 0.05, 0.27]) {
        final x = cx + trunkW * fx;
        canvas.drawPath(
          Path()
            ..moveTo(x, trunkTop + radius * 0.55)
            ..quadraticBezierTo(x + trunkW * 0.08, (trunkTop + baseY) / 2 + radius * 0.25, x - trunkW * 0.04, baseY - 6),
          bark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TreePainter old) =>
      old.highContrast != highContrast ||
      old.center != center ||
      old.radius != radius ||
      old.groundY != groundY ||
      old.trunkW != trunkW;
}

/// Круната: зелена топка со „лисја“ што се вртат заедно со поимите.
class _CrownPainter extends CustomPainter {
  _CrownPainter({
    required this.yaw,
    required this.pitch,
    required this.highContrast,
    required this.center,
    required this.radius,
    required this.leaves,
  });

  final double yaw;
  final double pitch;
  final bool highContrast;
  final Offset center;
  final double radius;
  final List<_V3> leaves;

  static const Color _dark = Color(0xFF1F6B2E);
  static const Color _mid = Color(0xFF3FA34D);
  static const Color _light = Color(0xFF8EDB5A);

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius;
    final rect = Rect.fromCircle(center: center, radius: r);
    final pts = [for (final l in leaves) _rotate(l, yaw, pitch)]..sort((a, b) => a.z.compareTo(b.z));

    if (highContrast) {
      canvas.drawCircle(center, r, Paint()..color = Colors.black);
      final line = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final p in pts) {
        if (p.z < 0.15) continue;
        canvas.drawCircle(center + Offset(p.x, -p.y) * r * 0.9, r * (0.07 + 0.05 * p.z), line);
      }
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      return;
    }

    // Мека сенка под круната.
    canvas.drawOval(
      Rect.fromCenter(center: center + Offset(0, r * 0.9), width: r * 1.6, height: r * 0.3),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          colors: [_light, _mid, _dark],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    // Лисја: грутки по површината, светли напред, темни назад.
    for (final p in pts) {
      if (p.z < -0.15) continue;
      final t = ((p.z + 1) / 2).clamp(0.0, 1.0).toDouble();
      final pos = center + Offset(p.x, -p.y) * r * 0.93;
      final br = r * (0.15 + 0.06 * p.z);
      final shade = p.y > 0 ? Color.lerp(_mid, _light, t)! : Color.lerp(_dark, _mid, t)!;
      canvas.drawCircle(pos, br, Paint()..color = shade.withValues(alpha: 0.92));
      canvas.drawCircle(
        pos + Offset(-br * 0.3, -br * 0.3),
        br * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.12 * t),
      );
    }
    // Сјај.
    canvas.drawCircle(
      center + Offset(-r * 0.35, -r * 0.4),
      r * 0.35,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.highContrast != highContrast ||
      old.center != center ||
      old.radius != radius;
}