import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../routes.dart';
import '../state/location.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ConfirmArgs {
  final Place from, to;
  final RideEstimate estimate;
  final Fare fare;
  ConfirmArgs(this.from, this.to, this.estimate, this.fare);
}

class RidesScreen extends StatefulWidget {
  /// A ride type ("cab"…), "fast", or a saved search {pickup, dropoff, type}.
  final Object? initial;
  const RidesScreen({super.key, this.initial});
  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  static const _types = [('cab', '🚗 Cab'), ('premium', '✨ Premium'), ('auto', '🛺 Auto'), ('bike', '🏍️ Bike')];

  final _fromCtrl = TextEditingController(), _toCtrl = TextEditingController();
  final _fromFocus = FocusNode(), _toFocus = FocusNode();
  Place? _from, _to;
  String _type = 'cab';

  String? _activeField; // 'from' | 'to'
  List<Place> _sugg = [];
  bool _suggLoading = false;
  Timer? _debounce;

  bool _loading = false, _fast = false;
  RideEstimate? _est;
  String? _error, _fastStatus;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init is String && init != 'fast') _type = init;
    if (init is Map) {
      _type = init['type'] ?? 'cab';
      _from = Place(name: init['pickup']['name'] ?? '', lat: init['pickup']['lat'], lon: init['pickup']['lon']);
      _to = Place(name: init['dropoff']['name'] ?? '', lat: init['dropoff']['lat'], lon: init['dropoff']['lon']);
      _fromCtrl.text = _from!.name;
      _toCtrl.text = _to!.name;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    } else {
      final here = context.read<LocationState>().current;
      if (here != null) {
        _from = here;
        _fromCtrl.text = here.name;
      }
    }
    if (init == 'fast') WidgetsBinding.instance.addPostFrameCallback((_) => _startFast());
    _fromFocus.addListener(() => _onFocus('from', _fromFocus.hasFocus));
    _toFocus.addListener(() => _onFocus('to', _toFocus.hasFocus));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_fromCtrl, _toCtrl]) {
      c.dispose();
    }
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _onFocus(String field, bool has) {
    if (has) {
      setState(() => _activeField = field);
      _query(field == 'from' ? _fromCtrl.text : _toCtrl.text);
    } else if (_activeField == field) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _activeField == field) setState(() => _activeField = null);
      });
    }
  }

  void _query(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _sugg = [];
        _suggLoading = false;
      });
      return;
    }
    setState(() => _suggLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final here = context.read<LocationState>().current;
      try {
        final res = await Api.instance.autocomplete(q.trim(), lat: here?.lat, lon: here?.lon);
        if (mounted) setState(() => _sugg = res);
      } catch (_) {
        if (mounted) setState(() => _sugg = []);
      }
      if (mounted) setState(() => _suggLoading = false);
    });
  }

  void _pick(Place p) {
    setState(() {
      if (_activeField == 'from') {
        _from = p;
        _fromCtrl.text = p.name;
      } else {
        _to = p;
        _toCtrl.text = p.name;
      }
      _activeField = null;
      _sugg = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _useCurrent() async {
    final loc = context.read<LocationState>();
    if (loc.current == null) await loc.locate();
    if (!mounted) return;
    if (loc.current == null) return toast(context, loc.error ?? 'Could not get your location');
    _pick(loc.current!);
  }

  bool _ready() {
    if (_from == null) {
      toast(context, 'Choose a pickup point from the list');
      return false;
    }
    if (_to == null) {
      toast(context, 'Choose a destination from the list');
      return false;
    }
    return true;
  }

  Future<void> _check() async {
    if (!_ready()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _fast = false;
      _error = null;
    });
    try {
      final e = await Api.instance.estimate(_from!, _to!, _type);
      if (mounted) setState(() => _est = e);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Fast Mode: fetch all providers, then book whichever arrives soonest.
  Future<void> _startFast() async {
    setState(() {
      _fast = true;
      _est = null;
      _error = null;
      _fastStatus = null;
    });
    if (_from == null || _to == null) {
      setState(() => _fastStatus = 'Set From and To, then tap Book');
      return;
    }
    const statuses = ['Pinging Uber...', 'Rapido searching...', 'Ola checking...', 'Finding nearest driver...'];
    for (final s in statuses) {
      if (!mounted || !_fast) return;
      setState(() => _fastStatus = s);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    try {
      final e = await Api.instance.estimate(_from!, _to!, _type);
      if (mounted && _fast) {
        setState(() {
          _est = e;
          _fastStatus = 'All providers checked ✓';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _fastStatus = e.message);
    }
  }

  Future<void> _bookFast() async {
    if (!_ready()) return;
    var est = _est;
    if (est == null) {
      await _startFast();
      est = _est;
      if (est == null) return;
    }
    final winner = [...est.fares]..sort((a, b) => a.pickupEtaMin.compareTo(b.pickupEtaMin));
    final f = winner.first;
    setState(() => _fastStatus = '✅ ${f.providerName} is closest — booking now!');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) _openConfirm(est, f);
  }

  void _openConfirm(RideEstimate est, Fare f) =>
      Navigator.of(context).pushNamed(Routes.confirm, arguments: ConfirmArgs(_from!, _to!, est, f));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: Column(children: [
        ScreenHeader(
          '🚕 Ride Compare',
          trailing: GestureDetector(
            onTap: _startFast,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(14)),
              child: Text('⚡ Fast Mode', style: pop(10, w: FontWeight.w700, c: Colors.white)),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            _label('From'),
            _placeField(_fromCtrl, _fromFocus, '📍 Current location or type address', 'from'),
            if (_activeField == 'from') _dropdown('from'),
            const SizedBox(height: 8),
            _label('To'),
            _placeField(_toCtrl, _toFocus, '🏁 Search destination', 'to'),
            if (_activeField == 'to') _dropdown('to'),
            const SizedBox(height: 12),
            _label('Select ride type'),
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final (key, label) in _types)
                GestureDetector(
                  onTap: () => setState(() {
                    _type = key;
                    if (!_fast) _est = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: _type == key ? T.amber : Colors.white,
                      border: Border.all(color: _type == key ? T.amber : T.amberBorder, width: 1.5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(label, style: pop(11, w: FontWeight.w600, c: _type == key ? Colors.white : T.gray)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            AmberButton('Check Prices ⚡', radius: 11, onPressed: _check, busy: _loading),
            const SizedBox(height: 16),
            ..._results(),
          ]),
        ),
        const BottomNav(2),
      ]),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: pop(11, w: FontWeight.w600, c: T.gray)));

  Widget _placeField(TextEditingController c, FocusNode f, String hint, String field) => TextField(
        controller: c,
        focusNode: f,
        style: pop(12, c: const Color(0xFF333333)),
        onChanged: (v) {
          setState(() => field == 'from' ? _from = null : _to = null);
          _query(v);
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: pop(12, c: const Color(0xFF9CA3AF)),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: T.amberBorder, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: T.amber, width: 1.5)),
        ),
      );

  Widget _dropdown(String field) {
    final rows = <Widget>[
      if (field == 'from') _suggRow('📍', 'Use current location', '', _useCurrent),
      if (_suggLoading) const Padding(padding: EdgeInsets.all(10), child: Center(child: AmberSpinner())),
      for (final p in _sugg) _suggRow(field == 'from' ? '📍' : '🏁', p.name, p.subtitle, () => _pick(p)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.amberBorder, width: 1.5),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: rows),
    );
  }

  Widget _suggRow(String icon, String name, String sub, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.soft))),
          child: Row(children: [
            Text(icon, style: pop(13, c: T.gray)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(style: pop(12, c: const Color(0xFF333333)), children: [
                  TextSpan(text: name),
                  if (sub.isNotEmpty) TextSpan(text: '  $sub', style: pop(10, c: T.gray)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      );

  List<Widget> _results() {
    final est = _est;
    if (_error != null) return [EmptyState(icon: '⚠️', title: 'Couldn\'t fetch fares', body: _error!)];
    if (!_fast && est == null) {
      return [
        CustomPaint(
          painter: _DashedBorder(),
          child: SizedBox(
            height: 130,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('🚕', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 7),
              Text('Enter route & check prices', style: pop(12, c: T.gray)),
            ]),
          ),
        ),
      ];
    }
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          (_fast ? '⚡ Fast Mode — All Providers' : '${est!.label} · Fare Comparison').toUpperCase(),
          style: pop(10, w: FontWeight.w700, c: T.gray, ls: .5),
        ),
      ),
    ];
    if (!_fast && est != null) {
      final minP = est.fares.first.price;
      for (final f in est.fares) {
        out.add(_FareCard(f, cheapest: f.price == minP, onBook: () => _openConfirm(est, f)));
      }
      out.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(color: T.greenBg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(child: Text('${est.fares.first.product} saves you ₹${est.savings} on this trip!', style: pop(11, w: FontWeight.w700, c: T.green))),
        ]),
      ));
      if (est.fares.any((f) => f.estimated)) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'est. = estimated from published rate cards · ${est.distanceKm} km · ~${est.durationMin} min. Final fare is shown in the provider\'s app.',
            style: pop(9, c: T.gray, h: 1.5),
          ),
        ));
      }
    }
    if (_fast) out.add(_fastCard());
    return out;
  }

  Widget _fastCard() => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF111827), Color(0xFF1E2D45)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚡ FAST MODE — FIRST TO ARRIVE WINS', style: pop(7.5, w: FontWeight.w800, c: Colors.white.withValues(alpha: .6), ls: 1.5)),
          const SizedBox(height: 6),
          Text(_est == null ? 'Searching all providers...' : 'Nearest drivers found', style: nun(14, c: Colors.white)),
          const SizedBox(height: 4),
          Text('Whichever cab arrives first, you ride that.', style: pop(10, c: Colors.white.withValues(alpha: .5))),
          const SizedBox(height: 12),
          Row(children: [
            for (final (l, bg, fg) in const [('UBER', Colors.white, Colors.black), ('rapido', Color(0xFFFFD600), Colors.black), ('OLA', Color(0xFF25D366), Colors.white)]) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
                child: Text(l, style: pop(10, w: FontWeight.w800, c: fg)),
              ),
              const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 12),
          if (_fastStatus != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_fastStatus!, style: pop(11, w: FontWeight.w600, c: T.amberBorder))),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _bookFast,
              style: FilledButton.styleFrom(
                backgroundColor: T.amber,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text('🚀 Book Fastest Available', style: nun(12, w: FontWeight.w700, c: Colors.white)),
            ),
          ),
        ]),
      );
}

class _FareCard extends StatelessWidget {
  final Fare f;
  final bool cheapest;
  final VoidCallback onBook;
  const _FareCard(this.f, {required this.cheapest, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final (lbg, lfg) = switch (f.provider) {
      'uber' => (const Color(0xFF1A1A1A), Colors.white),
      'rapido' => (T.amzBg, T.amzFg),
      _ => (T.fkBg, T.fkFg),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: cheapest ? T.amber : T.amberBorder, width: 1.5),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: lbg, borderRadius: BorderRadius.circular(10)),
          child: Text(f.logo, style: nun(9, c: lfg)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.product, style: pop(12, w: FontWeight.w700, c: T.amberDark)),
            const SizedBox(height: 2),
            Text('${f.durationMin} min · ${f.distanceKm} km · pickup ${f.pickupEtaMin} min', style: pop(10, c: T.gray)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (f.estimated) Text('est. ', style: pop(8, c: T.gray)),
            Text(f.priceText, style: nun(15, c: T.amber)),
          ]),
          if (cheapest) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(5)),
              child: Text('🏆 Cheapest', style: pop(8, w: FontWeight.w700, c: const Color(0xFF5A4000))),
            ),
          ],
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onBook,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(color: T.amber, borderRadius: BorderRadius.circular(8)),
              child: Text('Book →', style: nun(10, w: FontWeight.w700, c: Colors.white)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = T.amberBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(rrect.deflate(1));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
