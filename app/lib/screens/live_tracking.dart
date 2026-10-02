import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'rides.dart';

/// Live tracking of a ride booked through the Uber Guest Rides API.
/// Same layout as the prototype's tracking screen, fed by real trip data
/// (status, driver, vehicle, PIN, driver location) refreshed every 4 seconds.
class LiveTrackingScreen extends StatefulWidget {
  final ConfirmArgs confirm;
  final String bookingId;
  const LiveTrackingScreen({super.key, required this.confirm, required this.bookingId});
  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  TripStatus? _trip;
  String? _error;
  Timer? _poll;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final t = await Api.instance.rideStatus(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _trip = t;
        _error = null;
      });
      if (t.terminal) _poll?.cancel();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel this ride?', style: pop(15, w: FontWeight.w700)),
        content: Text('Uber may charge a cancellation fee if the driver is already on the way.', style: pop(12, c: T.gray)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep ride')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel ride', style: TextStyle(color: T.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cancelling = true);
    try {
      await Api.instance.cancelRide(widget.bookingId);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = _trip;
    final initial = context.read<Session>().user?.initial ?? 'T';
    final h = MediaQuery.sizeOf(context).height;
    final canCancel = t != null && !t.terminal && t.status != 'in_progress';

    return Scaffold(
      body: Column(children: [
        SizedBox(
          height: h * .52,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LiveMapPainter(
                  route: widget.confirm.estimate.route,
                  pickup: widget.confirm.from,
                  dropoff: widget.confirm.to,
                  driver: t?.driverLat == null ? null : Offset(t!.driverLon!, t.driverLat!),
                  bearing: t?.driverBearing ?? 0,
                ),
              ),
            ),
            Positioned(
              top: 10 + MediaQuery.paddingOf(context).top,
              left: 10,
              right: 10,
              child: Row(children: [
                _pill(GestureDetector(
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false),
                  child: Text('×', style: pop(16, c: T.ink)),
                ), circle: true),
                const Spacer(),
                _pill(Text(t == null ? 'Connecting…' : _badge(t), style: pop(11, w: FontWeight.w700, c: T.ink))),
                const Spacer(),
                _pill(Text(initial, style: pop(12, w: FontWeight.w800, c: T.amber)), circle: true),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: T.amber,
            onRefresh: _refresh,
            child: ListView(padding: EdgeInsets.zero, children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(t?.headline ?? 'Booking your ride…', textAlign: TextAlign.center, style: nun(21, w: FontWeight.w900, c: T.ink)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!, textAlign: TextAlign.center, style: pop(10, c: T.red)),
                ),
              const SizedBox(height: 12),
              // trip details
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Trip details', style: pop(10, c: T.gray)),
                      const SizedBox(height: 3),
                      Text('Meet at your pickup point', style: nun(13, c: T.ink)),
                      const SizedBox(height: 4),
                      Text('${widget.confirm.from.name} → ${widget.confirm.to.name}', style: pop(10, c: T.gray, h: 1.5)),
                    ]),
                  ),
                  if (t?.trackingUrl != null)
                    GestureDetector(
                      onTap: () => SharePlus.instance.share(ShareParams(text: 'Track my Uber ride: ${t!.trackingUrl}')),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(8)),
                        child: const Text('⬆', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                ]),
              ),
              // PIN
              if (t?.pin != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(children: [
                    Text('PIN for this trip', style: pop(12, w: FontWeight.w600, c: const Color(0xFF333333))),
                    const Spacer(),
                    for (final d in t!.pin!.split(''))
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: T.blue, borderRadius: BorderRadius.circular(5)),
                        child: Text(d, style: nun(13, c: Colors.white)),
                      ),
                  ]),
                ),
              // driver
              if (t?.driverName != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: T.amberPale, border: Border.all(color: T.amberBorder, width: 2)),
                        child: const Text('👨', style: TextStyle(fontSize: 22)),
                      ),
                      Positioned(bottom: -4, right: -4, child: Text(widget.confirm.estimate.emoji, style: const TextStyle(fontSize: 20))),
                    ]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t!.plate ?? '', style: pop(12, w: FontWeight.w800, c: T.ink)),
                        Text(t.vehicle ?? t.product ?? '', style: pop(10, c: T.gray)),
                      ]),
                    ),
                    if (t.driverRating != null) Text('★ ${t.driverRating!.toStringAsFixed(2)}', style: pop(13, w: FontWeight.w800, c: T.amber)),
                  ]),
                ),
                Center(child: Text(t.driverName!, style: pop(12, w: FontWeight.w700, c: T.amber))),
                const SizedBox(height: 10),
              ],
              // actions
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: canCancel && !_cancelling ? _cancel : null,
                      style: TextButton.styleFrom(
                        backgroundColor: T.soft,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: Text(
                        t != null && t.terminal ? 'Done' : (_cancelling ? 'Cancelling…' : 'Cancel ride'),
                        style: pop(12, w: FontWeight.w600, c: canCancel ? T.red : T.gray),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _round('📞', t?.driverPhone == null ? null : () => launchUrl(Uri.parse('tel:${t!.driverPhone}'))),
                  const SizedBox(width: 8),
                  _round('💬', t?.driverPhone == null ? null : () => launchUrl(Uri.parse('sms:${t!.driverPhone}'))),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _badge(TripStatus t) {
    if (t.status == 'accepted' && t.pickupEtaMin != null) return '${t.pickupEtaMin} min away';
    if (t.status == 'arriving') return 'Arriving now!';
    if (t.status == 'in_progress') return 'On trip';
    if (t.status == 'processing') return 'Matching driver…';
    return t.headline;
  }

  Widget _round(String icon, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? .4 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: T.soft, shape: BoxShape.circle),
            child: Text(icon, style: const TextStyle(fontSize: 18)),
          ),
        ),
      );

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

/// Prototype-styled map with real geometry: the OSRM route, pickup/drop pins
/// and the driver's live position, projected into the box.
class _LiveMapPainter extends CustomPainter {
  final List<List<double>> route; // [lon, lat]
  final Place pickup, dropoff;
  final Offset? driver; // (lon, lat)
  final double bearing;
  _LiveMapPainter({required this.route, required this.pickup, required this.dropoff, this.driver, this.bearing = 0});

  @override
  void paint(Canvas canvas, Size size) {
    // background in the prototype's palette
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE8EDE4));
    final block = Paint()..color = const Color(0xFFD2DACE);
    for (double y = 6; y < size.height; y += 78) {
      for (double x = 6; x < size.width; x += 70) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 58, 62), const Radius.circular(3)), block);
      }
    }

    final pts = <Offset>[
      for (final p in route) Offset(p[0], p[1]),
      Offset(pickup.lon, pickup.lat),
      Offset(dropoff.lon, dropoff.lat),
      ?driver,
    ];
    var minX = pts.map((p) => p.dx).reduce(math.min), maxX = pts.map((p) => p.dx).reduce(math.max);
    var minY = pts.map((p) => p.dy).reduce(math.min), maxY = pts.map((p) => p.dy).reduce(math.max);
    final spanX = math.max(maxX - minX, 0.002), spanY = math.max(maxY - minY, 0.002);
    const pad = 36.0;
    final scale = math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad - 40) / spanY);
    final ox = (size.width - spanX * scale) / 2, oy = (size.height - spanY * scale) / 2 + 20;
    Offset proj(Offset ll) => Offset(ox + (ll.dx - minX) * scale, oy + (maxY - ll.dy) * scale);

    if (route.length > 1) {
      final path = Path()..moveTo(proj(Offset(route[0][0], route[0][1])).dx, proj(Offset(route[0][0], route[0][1])).dy);
      for (final p in route.skip(1)) {
        final q = proj(Offset(p[0], p[1]));
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, Paint()
        ..color = T.ink
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round);
    }

    // drop (green) and pickup (black, labelled) pins — as in the prototype
    final drop = proj(Offset(dropoff.lon, dropoff.lat));
    canvas.drawCircle(drop, 7, Paint()..color = T.green);
    canvas.drawCircle(drop, 3.5, Paint()..color = Colors.white);
    final pick = proj(Offset(pickup.lon, pickup.lat));
    canvas.drawCircle(pick, 9, Paint()..color = T.ink);
    canvas.drawCircle(pick, 5, Paint()..color = Colors.white);
    final label = TextPainter(
      text: TextSpan(text: 'Pick-up spot', style: pop(9, w: FontWeight.w700, c: T.ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    final lr = Rect.fromLTWH(pick.dx + 12, pick.dy - 10, label.width + 10, 18);
    canvas.drawRRect(RRect.fromRectAndRadius(lr, const Radius.circular(3)), Paint()..color = Colors.white.withValues(alpha: .95));
    label.paint(canvas, Offset(lr.left + 5, lr.top + 3));

    // driver car
    if (driver != null) {
      final c = proj(driver!);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate((bearing - 90) * math.pi / 180);
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 9), width: 22, height: 8), Paint()..color = const Color(0x2E000000));
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -6, 20, 14), const Radius.circular(4)), Paint()..color = T.amber);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -12, 12, 9), const Radius.circular(3)), Paint()..color = T.amberLight);
      for (final w in const [Offset(-7, 7), Offset(7, 7), Offset(-7, -4), Offset(7, -4)]) {
        canvas.drawCircle(w, 3.5, Paint()..color = const Color(0xFF1A1A1A));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LiveMapPainter old) => old.driver != driver || old.bearing != bearing;
}
