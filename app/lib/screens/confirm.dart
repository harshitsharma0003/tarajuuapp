import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../config.dart';
import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'rides.dart';
import 'tracking.dart';

class ConfirmScreen extends StatelessWidget {
  final ConfirmArgs args;
  const ConfirmScreen({super.key, required this.args});

  /// Hand off to the provider's own app with the route pre-filled (rider can pay cash there).
  Future<void> _openInApp(BuildContext context) async {
    final f = args.fare;
    final cheapest = args.estimate.fares.first.price == f.price;
    if (context.read<Session>().signedIn) {
      Api.instance.buyClick(kind: 'ride', source: f.provider, saved: cheapest ? args.estimate.savings : 0).ignore();
    }
    toast(context, 'Opening ${f.providerName}...');
    final ok = await launchUrl(Uri.parse(f.deeplink), mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) toast(context, 'Could not open ${f.providerName}');
    if (Config.demoTracking) Navigator.of(context).pushNamed(Routes.tracking, arguments: TrackingArgs(args));
  }

  /// Book through the provider API (Uber Guest Rides) and track it in-app.
  Future<void> _bookViaApi(BuildContext context) async {
    final session = context.read<Session>();
    if (!session.signedIn) {
      toast(context, 'Please sign in to book rides');
      return;
    }
    final f = args.fare;
    try {
      final bookingId = await Api.instance.bookRide(args.from, args.to, f);
      final cheapest = args.estimate.fares.first.price == f.price;
      Api.instance.buyClick(kind: 'ride', source: f.provider, saved: cheapest ? args.estimate.savings : 0).ignore();
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed(Routes.tracking, arguments: TrackingArgs(args, bookingId: bookingId));
      }
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = args.fare, est = args.estimate;
    final cheapest = est.fares.first.price == f.price;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(t.toUpperCase(), style: pop(10, w: FontWeight.w700, c: T.gray, ls: .5)),
        );
    Widget stat(String v, String l, {Color c = T.ink}) =>
        Column(children: [Text(v, style: nun(16, c: c)), Text(l, style: pop(9, c: T.gray))]);
    final box = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: T.amberBorder, width: 1.5));

    return Scaffold(
      backgroundColor: T.soft,
      body: Column(children: [
        const ScreenHeader('Confirm Ride'),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            // route
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: box,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    label('Your Route'),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Column(children: [
                          Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: T.green)),
                          const SizedBox(height: 3),
                          Container(width: 1.5, height: 30, color: const Color(0xFFDDDDDD)),
                          const SizedBox(height: 3),
                          Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: T.amber)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(args.from.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(12, w: FontWeight.w700, c: T.ink)),
                          Text('Pickup point', style: pop(9, c: T.gray)),
                          const SizedBox(height: 18),
                          Text(args.to.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(12, w: FontWeight.w700, c: T.ink)),
                          Text('Drop point', style: pop(9, c: T.gray)),
                        ]),
                      ),
                    ]),
                  ]),
                ),
                Container(
                  color: T.tileBg,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: IntrinsicHeight(
                    child: Row(children: [
                      stat('${est.distanceKm} km', 'Distance'),
                      const SizedBox(width: 14),
                      const VerticalDivider(width: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(width: 14),
                      stat('${f.durationMin} min', 'Est. time'),
                      const SizedBox(width: 14),
                      const VerticalDivider(width: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(width: 14),
                      stat(f.priceText, f.estimated ? 'Fare (est.)' : 'Fare', c: T.amber),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            // vehicle + provider
            Container(
              padding: const EdgeInsets.all(14),
              decoration: box,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Your Ride'),
                Row(children: [
                  Text(est.emoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.product, style: nun(14, c: T.ink)),
                      Text('via ${f.providerName}', style: pop(11, c: T.gray)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(cheapest ? 'Cheapest option' : 'Pickup in ${f.pickupEtaMin} min', style: pop(9, c: T.gray)),
                    Text(f.priceText, style: nun(13, c: T.amber)),
                  ]),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            // payment
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: box,
              child: Row(children: [
                Text(f.bookable ? '🧾' : '💵', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.bookable ? 'Booked by Tarajuu · pay Tarajuu after the ride' : 'Pay in ${f.providerName} app',
                    style: pop(12, w: FontWeight.w600, c: const Color(0xFF333333)),
                  ),
                ),
                Text(f.bookable ? 'UPI / Card' : 'Cash / UPI', style: pop(10, w: FontWeight.w600, c: T.amber)),
              ]),
            ),
            const SizedBox(height: 12),
            _BookButton(
              label: f.bookable ? 'Confirm Ride →' : 'Confirm in ${f.providerName} →',
              onPressed: () => f.bookable ? _bookViaApi(context) : _openInApp(context),
            ),
            const SizedBox(height: 8),
            if (f.bookable)
              Center(
                child: TextButton(
                  onPressed: () => _openInApp(context),
                  child: Text('Prefer cash? Book in the ${f.providerName} app →', style: pop(11, w: FontWeight.w600, c: T.amber)),
                ),
              )
            else
              Text("You'll finish booking in the ${f.providerName} app with this route pre-filled — pay cash there.",
                  textAlign: TextAlign.center, style: pop(9.5, c: T.gray)),
          ]),
        ),
      ]),
    );
  }
}

class _BookButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  const _BookButton({required this.label, required this.onPressed});
  @override
  State<_BookButton> createState() => _BookButtonState();
}

class _BookButtonState extends State<_BookButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: [BoxShadow(color: T.amber.withValues(alpha: .3), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: AmberButton(widget.label, fontSize: 15, radius: 13, vPad: 14, busy: _busy, onPressed: () async {
          setState(() => _busy = true);
          await widget.onPressed();
          if (mounted) setState(() => _busy = false);
        }),
      );
}
