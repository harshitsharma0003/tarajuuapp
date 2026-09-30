import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../poll.dart';
import '../routes.dart';
import '../state/location.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/product_widgets.dart';
import '../widgets/svgs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _tabs = [('fan', '🌀 Fan'), ('tv', '📺 TV'), ('headphones', '🎧 Audio'), ('laptop', '💻 Laptop')];
  String _tab = 'fan';
  List<Product>? _strip;
  bool _stripLoading = true;
  int _stripReq = 0;

  bool _recentFavs = false;
  List<RecentItem> _recent = [];
  List<Product> _favs = [];

  @override
  void initState() {
    super.initState();
    _loadStrip();
    _loadRecent();
    final loc = context.read<LocationState>();
    if (loc.current == null) unawaited(loc.locate());
    unawaited(context.read<Session>().refresh());
  }

  Future<void> _loadStrip() async {
    final req = ++_stripReq;
    setState(() => _stripLoading = true);
    try {
      await pollSearch(
        () => Api.instance.home(_tab),
        cancelled: () => !mounted || req != _stripReq,
        onUpdate: (r) => setState(() {
          if (r.results.isNotEmpty || r.done) _strip = r.results;
        }),
      );
    } catch (_) {
      if (mounted && req == _stripReq) _strip ??= [];
    }
    if (mounted && req == _stripReq) setState(() => _stripLoading = false);
  }

  Future<void> _loadRecent() async {
    if (!context.read<Session>().signedIn) return;
    try {
      final (r, f) = await Api.instance.recent();
      if (mounted) {
        setState(() {
          _recent = r;
          _favs = f;
        });
      }
    } catch (_) {}
  }

  void _openCategory(String action) {
    if (action.startsWith('ride:')) {
      Navigator.of(context).pushNamed(Routes.rides, arguments: action.substring(5));
    } else {
      Navigator.of(context).pushNamed(Routes.shop, arguments: action);
    }
  }

  void _openRecent(RecentItem r) {
    if (r.kind == 'ride') {
      Navigator.of(context).pushNamed(Routes.rides, arguments: jsonDecode(r.query));
    } else {
      Navigator.of(context).pushNamed(Routes.shop, arguments: r.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.soft,
      body: Column(children: [
        const _DarkHero(),
        Expanded(
          child: RefreshIndicator(
            color: T.amber,
            onRefresh: () async {
              await Future.wait([_loadStrip(), _loadRecent(), context.read<Session>().refresh()]);
            },
            child: ListView(padding: EdgeInsets.zero, children: [
              _categories(),
              _rideGrid(),
              _fastCard(),
              _compareStrip(),
              _recentBox(),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        const BottomNav(0),
      ]),
    );
  }

  Widget _categories() => Container(
        color: Colors.white,
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categoryIcons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final (label, bg, border, svg, action) = categoryIcons[i];
              return GestureDetector(
                onTap: () => _openCategory(action),
                child: SizedBox(
                  width: 52,
                  child: Column(children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Color(bg), border: Border.all(color: Color(border), width: 2)),
                      child: SvgPicture.string(svg, width: 26, height: 26),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: pop(8.5, w: FontWeight.w600, c: const Color(0xFF444444))),
                  ]),
                ),
              );
            },
          ),
        ),
      );

  Widget _sectionHead(String title, {String? action, VoidCallback? onAction}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: pop(13, w: FontWeight.w700, c: T.ink))),
          if (action != null) GestureDetector(onTap: onAction, child: Text(action, style: pop(10, w: FontWeight.w600, c: T.amber))),
        ]),
      );

  Widget _rideGrid() {
    // "From" prices = the cheapest rate-card minimum fare for each type (backend rides.RATE_CARDS).
    const cards = [('🏍️', 'Bike', 25, 'bike', false), ('🛺', 'Auto', 35, 'auto', true), ('🚗', 'Cab', 80, 'cab', false)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(children: [
        _sectionHead('Ride with', action: 'See all', onAction: () => Navigator.of(context).pushNamed(Routes.rides)),
        Row(children: [
          for (final (i, c) in cards.indexed) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: Material(
                color: c.$5 ? T.amberPale : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: c.$5 ? T.amber : T.line, width: 1.5)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => Navigator.of(context).pushNamed(Routes.rides, arguments: c.$4),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 10, 7, 8),
                    child: Column(children: [
                      Text(c.$1, style: const TextStyle(fontSize: 30, height: 1)),
                      const SizedBox(height: 5),
                      Text(c.$2, style: pop(10, w: FontWeight.w700, c: const Color(0xFF333333))),
                      const SizedBox(height: 5),
                      Text('From ₹${c.$3}', style: pop(9, w: FontWeight.w600, c: T.amber)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _fastCard() => GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(Routes.rides, arguments: 'fast'),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.all(14),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF111827), Color(0xFF1E2D45)]),
          ),
          child: Stack(children: [
            const Positioned(right: 0, top: 0, bottom: 0, child: Center(child: Opacity(opacity: .18, child: Text('⚡', style: TextStyle(fontSize: 40))))),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  border: Border.all(color: Colors.white.withValues(alpha: .22)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('FAST MODE', style: pop(7, w: FontWeight.w800, c: Colors.white.withValues(alpha: .75), ls: 1)),
              ),
              const SizedBox(height: 7),
              Text('Compare at 1 click', style: nun(15, c: Colors.white)),
              const SizedBox(height: 3),
              Text('All providers. One tap.\nCheapest ride wins.', style: pop(10, c: Colors.white.withValues(alpha: .5), h: 1.4)),
              const SizedBox(height: 10),
              const Row(children: [
                _ProviderChip('UBER', Colors.white, Colors.black),
                SizedBox(width: 6),
                _ProviderChip('rapido', Color(0xFFFFD600), Colors.black),
                SizedBox(width: 6),
                _ProviderChip('OLA', Color(0xFF25D366), Colors.white),
              ]),
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(color: T.amber, borderRadius: BorderRadius.circular(17)),
                child: Text('Try Fast Mode ⚡', style: nun(11, w: FontWeight.w700, c: Colors.white)),
              ),
            ]),
          ]),
        ),
      );

  Widget _compareStrip() => Card14(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 7),
            child: Text('Compare prices', style: pop(12, w: FontWeight.w700, c: T.ink)),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.line))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final (key, label) in _tabs)
                  GestureDetector(
                    onTap: () {
                      if (_tab == key) return;
                      setState(() {
                        _tab = key;
                        _strip = null;
                      });
                      _loadStrip();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == key ? T.amber : Colors.transparent, width: 2))),
                      child: Text(label, style: pop(10, w: FontWeight.w600, c: _tab == key ? T.amber : T.gray)),
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(
            height: 182,
            child: Builder(builder: (_) {
              final items = _strip ?? [];
              if (items.isEmpty && _stripLoading) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (_, _) => const SizedBox(width: 100, child: SkeletonCard([.9, .6, .4])),
                );
              }
              if (items.isEmpty) {
                return Center(child: Text('Prices unavailable right now — pull to retry', style: pop(10, c: T.gray)));
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (_, i) => MiniProduct(items[i], onTap: () => Navigator.of(context).pushNamed(Routes.pdp, arguments: items[i].id)),
              );
            }),
          ),
        ]),
      );

  Widget _recentBox() {
    final signedIn = context.watch<Session>().signedIn;
    Widget pill(String label, bool on, VoidCallback tap) => GestureDetector(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: on ? T.amber : T.soft, borderRadius: BorderRadius.circular(18)),
            child: Text(label, style: pop(10, w: FontWeight.w600, c: on ? Colors.white : const Color(0xFF666666))),
          ),
        );

    final rows = <Widget>[];
    if (!_recentFavs) {
      for (final r in _recent.take(5)) {
        rows.add(_recentRow(r.kind == 'ride' ? '🚗' : '🔍', r.title, r.subtitle ?? 'Tap to compare again', () => _openRecent(r)));
      }
    } else {
      for (final p in _favs.take(5)) {
        final sub = p.offers.map((o) => '${o.source == 'amazon' ? 'Amazon' : 'Flipkart'} ₹${inr(o.price)}').join(' · ');
        rows.add(_recentRow(p.emoji, p.title, sub, () => Navigator.of(context).pushNamed(Routes.pdp, arguments: p.id)));
      }
    }

    return Card14(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recent', style: pop(12, w: FontWeight.w700, c: T.ink)),
        const SizedBox(height: 8),
        Row(children: [
          pill('Searches', !_recentFavs, () => setState(() => _recentFavs = false)),
          const SizedBox(width: 6),
          pill('Favourites', _recentFavs, () => setState(() => _recentFavs = true)),
        ]),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              !signedIn ? 'Sign in to see your recent searches' : (_recentFavs ? 'Tap ♡ on a product to save it here' : 'Your searches will show up here'),
              style: pop(10, c: T.gray),
            ),
          )
        else
          ...rows,
      ]),
    );
  }

  Widget _recentRow(String icon, String name, String sub, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.soft))),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: T.amberPale, borderRadius: BorderRadius.circular(9)),
              child: Text(icon, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(11, w: FontWeight.w600, c: T.text)),
                const SizedBox(height: 1),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(9, c: T.gray)),
              ]),
            ),
            const Text('›', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
          ]),
        ),
      );
}

class _ProviderChip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _ProviderChip(this.label, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
        child: Text(label, style: pop(9, w: FontWeight.w800, c: fg)),
      );
}

/// Top of Home: navy gradient, faint map grid, top bar, location, search and banner.
class _DarkHero extends StatelessWidget {
  const _DarkHero();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final loc = context.watch<LocationState>();
    final top = MediaQuery.paddingOf(context).top;
    final address = loc.current?.label ?? (loc.loading ? 'Locating…' : (loc.error ?? 'Set your location'));

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [T.heroTop, T.heroMid, T.heroBottom], stops: [0, .6, 1]),
      ),
      child: Stack(children: [
        const Positioned.fill(child: Opacity(opacity: .18, child: CustomPaint(painter: _MapGridPainter()))),
        Column(children: [
          // top bar
          Padding(
            padding: EdgeInsets.fromLTRB(14, 11 + top, 14, 11),
            child: Row(children: [
              RoundIconButton(
                color: Colors.white.withValues(alpha: .12),
                onTap: () => Navigator.of(context).pushNamed(Routes.drawer),
                child: SvgPicture.string(menu, width: 17, height: 17),
              ),
              Expanded(child: Center(child: Text('⚖️ Tarajuu', style: nun(19, w: FontWeight.w900, c: Colors.white, ls: .5)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: T.amber.withValues(alpha: .25),
                  border: Border.all(color: T.amber.withValues(alpha: .5)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('₹${inr(session.savedTotal)} saved', style: pop(9, w: FontWeight.w700, c: T.amberBorder)),
              ),
              const SizedBox(width: 7),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed(Routes.drawer),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: T.amber),
                  child: Text(session.user?.initial ?? 'T', style: pop(13, w: FontWeight.w800, c: Colors.white)),
                ),
              ),
            ]),
          ),
          // location + search
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('📍', style: TextStyle(fontSize: 11, color: Color(0xFFF87171))),
                const SizedBox(width: 4),
                Text('Your current location', style: pop(9.5, c: Colors.white.withValues(alpha: .5))),
              ]),
              const SizedBox(height: 3),
              GestureDetector(
                onTap: () => context.read<LocationState>().locate(),
                child: Row(children: [
                  Flexible(child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(16, w: FontWeight.w800, c: Colors.white))),
                  const SizedBox(width: 6),
                  Text('▾', style: pop(10, c: T.amber)),
                ]),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pushNamed(Routes.shop),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    border: Border.all(color: Colors.white.withValues(alpha: .15), width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Text('🔍', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .4))),
                    const SizedBox(width: 8),
                    Text('Search products, rides...', style: pop(13, c: Colors.white.withValues(alpha: .4))),
                  ]),
                ),
              ),
            ]),
          ),
          // banner
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 130),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment(-1, -.4),
                  end: Alignment(1, .4),
                  colors: [Color(0xFF0F1923), Color(0xFF162032), Color(0xFF1A2D4A), Color(0xFF1E3655)],
                  stops: [0, .4, .7, 1],
                ),
              ),
              child: Stack(children: [
                Positioned(right: -20, top: -20, child: _circle(110, .06)),
                Positioned(right: 15, bottom: -25, child: _circle(70, .05)),
                const Positioned(right: 14, top: 12, child: Opacity(opacity: .2, child: Text('⚖️', style: TextStyle(fontSize: 52, height: 1)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('🔥 LIMITED TIME', style: pop(8.5, w: FontWeight.w700, c: Colors.white.withValues(alpha: .65), ls: 1.2)),
                    const SizedBox(height: 5),
                    Text('BIGGEST DEAL\nFINDER', style: nun(22, w: FontWeight.w900, c: Colors.white, h: 1.1)),
                    const SizedBox(height: 4),
                    Text('Get upto 18% off · Compare now', style: pop(10, c: Colors.white.withValues(alpha: .7))),
                    const SizedBox(height: 11),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed(Routes.shop),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: T.amber,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 10, offset: Offset(0, 2))],
                        ),
                        child: Text('Shop Now →', style: nun(11, c: Colors.white)),
                      ),
                    ),
                  ]),
                ),
                Positioned(
                  bottom: 10,
                  right: 14,
                  child: Row(children: [
                    _dot(5, 1),
                    const SizedBox(width: 4),
                    _dot(14, .4),
                    const SizedBox(width: 4),
                    _dot(5, .4),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  static Widget _circle(double s, double a) =>
      Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: a)));
  static Widget _dot(double w, double a) =>
      Container(width: w, height: 5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: a), borderRadius: BorderRadius.circular(3)));
}

/// The 28px map grid + route dots behind the Home hero (SVG pattern "mg").
class _MapGridPainter extends CustomPainter {
  const _MapGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    // Scale the 320×280 design to cover, like preserveAspectRatio="xMidYMid slice".
    final s = (size.width / 320) > (size.height / 280) ? size.width / 320 : size.height / 280;
    canvas.translate((size.width - 320 * s) / 2, (size.height - 280 * s) / 2);
    canvas.scale(s);
    final grid = Paint()
      ..color = const Color(0x8063B3ED)
      ..strokeWidth = .4;
    for (double x = 0; x <= 320; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, 280), grid);
    }
    for (double y = 0; y <= 280; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(320, y), grid);
    }
    canvas.drawCircle(const Offset(60, 120), 4, Paint()..color = T.amber.withValues(alpha: .9));
    canvas.drawCircle(const Offset(60, 120), 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = T.amber.withValues(alpha: .5));
    canvas.drawCircle(const Offset(240, 160), 3.5, Paint()..color = const Color(0xCC60A5FA));
    final dash = Paint()
      ..color = const Color(0x5963B3ED)
      ..strokeWidth = 1;
    const a = Offset(60, 120), b = Offset(240, 160);
    final d = b - a;
    final len = d.distance;
    for (double t = 0; t < len; t += 9) {
      final e = (t + 5).clamp(0, len).toDouble();
      canvas.drawLine(a + d * (t / len), a + d * (e / len), dash);
    }
    final w = Paint()..color = Colors.white.withValues(alpha: .3);
    canvas.drawCircle(const Offset(150, 80), 2.5, w);
    canvas.drawCircle(const Offset(200, 50), 2, w..color = Colors.white.withValues(alpha: .2));
    canvas.drawCircle(const Offset(80, 200), 2, w);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
