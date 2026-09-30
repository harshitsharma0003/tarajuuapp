import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import 'rides.dart';

/// Uber-style live tracking, ported from the prototype's animated SVG map.
///
/// DEMO ONLY (enabled with --dart-define=DEMO_TRACKING=true): real trips are
/// booked and tracked inside the provider's own app, which does not share
/// driver location with third parties.
class TrackingScreen extends StatefulWidget {
  final ConfirmArgs args;
  const TrackingScreen({super.key, required this.args});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> with SingleTickerProviderStateMixin {
  // carT advances 0.002/frame to 0.97 in the prototype ≈ 8s at 60fps.
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..forward();
  int _eta = 3;
  Timer? _etaTimer;

  @override
  void initState() {
    super.initState();
    _etaTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted) return t.cancel();
      setState(() => _eta--);
      if (_eta <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _etaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    final initial = context.read<Session>().user?.initial ?? 'T';
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Column(children: [
        SizedBox(
          height: h * .52,
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(painter: _MapPainter(_c.value * .97, DateTime.now().millisecondsSinceEpoch)),
              ),
            ),
            Positioned(
              top: 10 + MediaQuery.paddingOf(context).top,
              left: 10,
              right: 10,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final dist = ((1 - _c.value * .97) * 450).round();
                  return Row(children: [
                    _pill(
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false),
                        child: Text('×', style: pop(16, c: T.ink)),
                      ),
                      circle: true,
                    ),
                    const Spacer(),
                    _pill(Text(dist > 30 ? '$dist m away' : 'Arriving now!', style: pop(11, w: FontWeight.w700, c: T.ink))),
                    const Spacer(),
                    _pill(Text(initial, style: pop(12, w: FontWeight.w800, c: T.amber)), circle: true),
                  ]);
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            Center(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(_eta > 0 ? 'Pick-up in $_eta min' : 'Driver arriving now!', textAlign: TextAlign.center, style: nun(21, w: FontWeight.w900, c: T.ink)),
            const SizedBox(height: 4),
            Text('DEMO — track your real trip in the ${a.fare.providerName} app', textAlign: TextAlign.center, style: pop(9, w: FontWeight.w700, c: T.red)),
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trip details', style: pop(10, c: T.gray)),
                const SizedBox(height: 3),
                Text('Meet at your pickup point', style: nun(13, c: T.ink)),
                const SizedBox(height: 4),
                Text('${a.from.name} → ${a.to.name}', style: pop(10, c: T.gray, h: 1.5)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                Text('${a.fare.product} · ${a.fare.priceText}', style: pop(12, w: FontWeight.w600, c: const Color(0xFF333333))),
                const Spacer(),
                Text(a.estimate.emoji, style: const TextStyle(fontSize: 22)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(Widget child, {bool circle = false}) => Container(
        width: circle ? 32 : null,
        height: 32,
        padding: circle ? null : const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: child,
      );
}

class _MapPainter extends CustomPainter {
  final double t;
  final int now;
  _MapPainter(this.t, this.now);

  static const _way = [Offset(76, 20), Offset(76, 65), Offset(76, 137), Offset(200, 137), Offset(200, 200)];

  Offset _pt(double t) {
    final segs = _way.length - 1;
    final si = math.min((t * segs).floor(), segs - 1);
    final lt = t * segs - si;
    return Offset.lerp(_way[si], _way[si + 1], lt)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 0 0 320 240, preserveAspectRatio slice
    final s = math.max(size.width / 320, size.height / 240);
    canvas.translate((size.width - 320 * s) / 2, (size.height - 240 * s) / 2);
    canvas.scale(s);
    Paint f(int c) => Paint()..color = Color(c);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 320, 240), f(0xFFE8EDE4));
    for (final r in const [
      Rect.fromLTWH(0, 0, 68, 55), Rect.fromLTWH(80, 0, 52, 55), Rect.fromLTWH(144, 0, 40, 55), Rect.fromLTWH(196, 0, 124, 55),
      Rect.fromLTWH(0, 74, 68, 52), Rect.fromLTWH(80, 74, 52, 52), Rect.fromLTWH(144, 74, 40, 52), Rect.fromLTWH(196, 74, 124, 52),
      Rect.fromLTWH(0, 148, 68, 92), Rect.fromLTWH(80, 148, 52, 92), Rect.fromLTWH(196, 148, 124, 92),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), f(0xFFD2DACE));
    }
    canvas.drawOval(Rect.fromCenter(center: const Offset(248, 32), width: 88, height: 44), f(0xA6B8D4E8));
    final road = f(0xFFC8D0C4);
    canvas.drawRect(const Rect.fromLTWH(0, 58, 320, 14), road);
    canvas.drawRect(const Rect.fromLTWH(0, 130, 320, 14), road);
    canvas.drawRect(const Rect.fromLTWH(70, 0, 12, 240), road);
    canvas.drawRect(const Rect.fromLTWH(136, 0, 12, 240), road);
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: .8)
      ..strokeWidth = 1.2;
    for (double x = 0; x < 320; x += 24) {
      canvas.drawLine(Offset(x, 65), Offset(x + 14, 65), dash);
      canvas.drawLine(Offset(x, 137), Offset(x + 14, 137), dash);
    }
    for (double y = 0; y < 240; y += 24) {
      canvas.drawLine(Offset(76, y), Offset(76, y + 14), dash);
      canvas.drawLine(Offset(142, y), Offset(142, y + 14), dash);
    }

    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..strokeWidth = w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final full = Path()..moveTo(_way[0].dx, _way[0].dy);
    for (final p in _way.skip(1)) {
      full.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(full, stroke(T.ink, 3));
    // driven part
    final segs = _way.length - 1;
    final si = math.min((t * segs).floor(), segs - 1);
    final driven = Path()..moveTo(_way[0].dx, _way[0].dy);
    for (var i = 1; i <= si; i++) {
      driven.lineTo(_way[i].dx, _way[i].dy);
    }
    final car = _pt(t);
    driven.lineTo(car.dx, car.dy);
    canvas.drawPath(driven, stroke(T.amber, 3.5));

    // pickup pin + pulse
    canvas.drawCircle(const Offset(200, 200), 9, f(0xFF111111));
    canvas.drawCircle(const Offset(200, 200), 5, f(0xFFFFFFFF));
    canvas.drawCircle(const Offset(200, 200), 14 + 4 * math.sin(now / 350), stroke(T.ink.withValues(alpha: .35), 1.5));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(212, 190, 76, 18), const Radius.circular(3)), f(0xF2FFFFFF));
    _text(canvas, 'Pick-up spot', const Offset(217, 193), 8.5, bold: true);
    // start pin
    canvas.drawCircle(const Offset(76, 20), 7, f(0xFF15803D));
    canvas.drawCircle(const Offset(76, 20), 3.5, f(0xFFFFFFFF));

    // car
    final next = _pt(math.min(t + .02, 1));
    final angle = math.atan2(next.dy - car.dy, next.dx - car.dx);
    canvas.save();
    canvas.translate(car.dx, car.dy);
    canvas.rotate(angle);
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, 9), width: 22, height: 8), f(0x2E000000));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -6, 20, 14), const Radius.circular(4)), f(0xFFD97706));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -12, 12, 9), const Radius.circular(3)), f(0xFFF59E0B));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -11, 4.5, 7), const Radius.circular(1.5)), f(0xCCA8D8EA));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(.5, -11, 4.5, 7), const Radius.circular(1.5)), f(0x99A8D8EA));
    for (final w in const [Offset(-7, 7), Offset(7, 7), Offset(-7, -4), Offset(7, -4)]) {
      canvas.drawCircle(w, 3.5, f(0xFF1A1A1A));
    }
    canvas.restore();

    // distance badge
    final dist = ((1 - t) * 450).round();
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(110, 94, 88, 22), const Radius.circular(4)), f(0xF2FFFFFF));
    _text(canvas, dist > 30 ? '$dist metres' : 'Arriving!', const Offset(154, 99), 10, bold: true, center: true);
  }

  void _text(Canvas c, String s, Offset o, double size, {bool bold = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: T.ink, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? o.translate(-tp.width / 2, 0) : o);
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
