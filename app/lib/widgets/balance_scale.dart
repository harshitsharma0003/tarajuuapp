import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The rocking weighing-scale animation from the splash (.balance, @keyframes
/// rock/sl/sr/pl/pr — 2s ease-in-out, alternating).
class BalanceScale extends StatefulWidget {
  const BalanceScale({super.key});
  @override
  State<BalanceScale> createState() => _BalanceScaleState();
}

class _BalanceScaleState extends State<BalanceScale> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  late final _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        height: 110,
        child: AnimatedBuilder(animation: _t, builder: (_, _) => CustomPaint(painter: _ScalePainter(_t.value))),
      );
}

class _ScalePainter extends CustomPainter {
  final double t; // 0 → 1
  _ScalePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final cx = size.width / 2;

    // pole
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 2, 8, 4, 30), const Radius.circular(2)), white);
    // base
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 20, 100, 40, 5), const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: .5),
    );

    // beam rotates -13° → 13° about its centre
    final angle = (-13 + 26 * t) * math.pi / 180;
    canvas.save();
    canvas.translate(cx, 40.5);
    canvas.rotate(angle);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-55, -2.5, 110, 5), const Radius.circular(3)), white);

    final string = Paint()
      ..color = Colors.white.withValues(alpha: .7)
      ..strokeWidth = 1.5;
    final pan = Paint()..color = Colors.white.withValues(alpha: .88);
    // left string 18→30, right 30→18; pans bob opposite ways
    final ls = 18 + 12 * t, rs = 30 - 12 * t;
    canvas.drawLine(const Offset(-39, 2.5), Offset(-39, 2.5 + ls), string);
    canvas.drawLine(const Offset(39, 2.5), Offset(39, 2.5 + rs), string);
    _pan(canvas, const Offset(-39, 0).translate(0, 2.5 + ls), pan);
    _pan(canvas, const Offset(39, 0).translate(0, 2.5 + rs), pan);
    canvas.restore();
  }

  void _pan(Canvas canvas, Offset top, Paint p) {
    final r = Rect.fromLTWH(top.dx - 19, top.dy, 38, 9);
    canvas.drawRRect(RRect.fromRectAndCorners(r, bottomLeft: const Radius.circular(18), bottomRight: const Radius.circular(18)), p);
  }

  @override
  bool shouldRepaint(_ScalePainter old) => old.t != t;
}
