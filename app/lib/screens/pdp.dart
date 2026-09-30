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
import '../widgets/product_widgets.dart';

class PdpScreen extends StatefulWidget {
  final String productId;
  const PdpScreen({super.key, required this.productId});
  @override
  State<PdpScreen> createState() => _PdpScreenState();
}

class _PdpScreenState extends State<PdpScreen> {
  ProductDetail? _d;
  String? _error;
  bool _fastTab = false;
  int _img = 0;
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await Api.instance.product(widget.productId);
      if (mounted) setState(() => _d = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggleFav() async {
    final d = _d!;
    if (!context.read<Session>().signedIn) {
      toast(context, 'Sign in to save favourites');
      return;
    }
    final on = !d.favourite;
    setState(() => d.favourite = on);
    try {
      await Api.instance.setFavourite(d.product.id, on);
      if (mounted) toast(context, on ? 'Added to favourites ♥' : 'Removed from favourites');
    } catch (_) {
      if (mounted) setState(() => d.favourite = !on);
    }
  }

  Future<void> _buy(Seller s) async {
    final url = s.url;
    if (url == null) return;
    final p = _d!.product;
    final worst = p.offers.map((o) => o.price).fold<int>(0, (a, b) => a > b ? a : b);
    if (context.read<Session>().signedIn) {
      Api.instance.buyClick(productId: p.id, kind: 'product', source: s.source, saved: (worst - s.price).clamp(0, 1 << 30)).ignore();
    }
    toast(context, 'Opening ${s.name}...');
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _share() {
    final p = _d!.product;
    final best = p.offers.isEmpty ? null : p.offers.first;
    SharePlus.instance.share(ShareParams(
      title: 'Tarajuu — Price Compare',
      text: 'Check out this deal on Tarajuu! ${p.title} — ₹${inr(p.bestPrice)}${best?.url != null ? '\n${best!.url}' : ''}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: T.tileBg,
      body: Column(children: [
        ScreenHeader(
          d?.product.brand ?? 'Product',
          trailing: d == null ? null : RoundIconButton(size: 28, onTap: _share, child: Text('⬆', style: pop(14, c: Colors.white))),
        ),
        Expanded(
          child: d == null
              ? (_error != null
                  ? EmptyState(icon: '⚠️', title: 'Couldn\'t load product', body: _error!, action: AmberButton('Retry', onPressed: _load))
                  : const Center(child: AmberSpinner(size: 28)))
              : RefreshIndicator(color: T.amber, onRefresh: _load, child: _body(d)),
        ),
        const BottomNav(1),
      ]),
    );
  }

  Widget _body(ProductDetail d) {
    final p = d.product;
    final images = p.images.isEmpty ? [p.image] : p.images;
    final cheapest = d.sellers.isEmpty ? null : d.sellers.first;
    final sellers = [...d.sellers];
    if (_fastTab) {
      // Sellers with a stated delivery date first; unknown dates keep price order.
      sellers.sort((a, b) => (a.delivery == null ? 1 : 0).compareTo(b.delivery == null ? 1 : 0));
    }
    final off = p.offPercent;

    return ListView(padding: EdgeInsets.zero, children: [
      // ── image gallery ──
      SizedBox(
        height: 190,
        child: Stack(children: [
          PageView.builder(
            controller: _pager,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _img = i),
            itemBuilder: (_, i) => ProductImage(url: images[i], emoji: p.emoji, emojiSize: 96, padding: const EdgeInsets.fromLTRB(40, 12, 40, 30)),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: GestureDetector(
              onTap: _toggleFav,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .9),
                  border: Border.all(color: T.amberBorder, width: 1.5),
                ),
                child: Text(d.favourite ? '♥' : '♡', style: pop(14, c: d.favourite ? T.red : T.text)),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 12,
            child: Row(children: [
              for (final o in p.offers) ...[
                PlatTag(
                  o.source,
                  fontSize: 9,
                  text: '${o.source == 'amazon' ? 'AMZ' : 'FLK'} ₹${inr(o.price)}',
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  radius: 18,
                ),
                const SizedBox(width: 5),
              ],
            ]),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 12,
              right: 12,
              child: Row(children: [
                for (var i = 0; i < images.length.clamp(0, 6); i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _img ? 13 : 5,
                    height: 5,
                    decoration: BoxDecoration(color: i == _img ? T.amber : Colors.black.withValues(alpha: .15), borderRadius: BorderRadius.circular(3)),
                  ),
                ],
              ]),
            ),
        ]),
      ),
      // ── info ──
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((p.brand ?? '').toUpperCase(), style: pop(9.5, w: FontWeight.w700, c: T.amber, ls: .5)),
          const SizedBox(height: 2),
          Text(p.title, style: pop(13, w: FontWeight.w700, c: T.ink, h: 1.35)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.only(bottom: 11),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.line))),
            child: Row(children: [
              if (p.rating != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: T.ink, borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('★', style: pop(9.5, c: const Color(0xFFFFD700))),
                    const SizedBox(width: 2),
                    Text(p.rating!.toStringAsFixed(1), style: pop(9.5, w: FontWeight.w700, c: Colors.white)),
                  ]),
                ),
              const SizedBox(width: 7),
              if (p.reviews != null) Text('${compactCount(p.reviews)} ratings', style: pop(10, c: T.gray)),
            ]),
          ),
        ]),
      ),
      // ── trust strip ──
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: T.line))),
        child: IntrinsicHeight(
          child: Row(children: [
            for (final (i, (ico, t, s)) in const [('🛡️', 'Buyer Protection', '100% safe'), ('✅', 'Authenticity', 'Verified sellers'), ('💰', 'Money Back', 'Guarantee')].indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                  decoration: BoxDecoration(border: i < 2 ? const Border(right: BorderSide(color: T.line)) : null),
                  child: Row(children: [
                    Text(ico, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t, style: pop(8.5, w: FontWeight.w600, c: const Color(0xFF333333), h: 1.3)),
                        Text(s, style: pop(7.5, c: T.gray)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      // ── price + CTA ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: T.line, width: 5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.bestPrice != null && p.bestPrice! >= 3000)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(color: T.amberPale, border: Border.all(color: T.amberBorder), borderRadius: BorderRadius.circular(18)),
              child: Text.rich(TextSpan(style: pop(10, c: T.amberDark), children: [
                const TextSpan(text: '💳 Get it at '),
                TextSpan(text: '₹${inr((p.bestPrice! / 12).round())}/mo', style: pop(10, w: FontWeight.w700, c: T.amberDark)),
                const TextSpan(text: ' · Pay Later'),
              ])),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('₹${inr(p.bestPrice)}', style: nun(22, c: T.ink)),
            const SizedBox(width: 7),
            if (p.compareAtPrice != null) Text('₹${inr(p.compareAtPrice)}', style: pop(11, c: const Color(0xFFAAAAAA), deco: TextDecoration.lineThrough)),
            const SizedBox(width: 7),
            if (off > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: T.greenBg, borderRadius: BorderRadius.circular(5)),
                child: Text('$off% off', style: pop(10, w: FontWeight.w700, c: T.green)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: AmberButton(
                cheapest == null ? 'Unavailable' : 'Buy on ${cheapest.source == 'amazon' ? 'Amazon' : 'Flipkart'} →',
                fontSize: 13,
                radius: 10,
                onPressed: cheapest == null ? null : () => _buy(cheapest),
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              onTap: _toggleFav,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: T.amber, width: 2), borderRadius: BorderRadius.circular(10)),
                child: Text(d.favourite ? '♥' : '♡', style: TextStyle(fontSize: 17, color: d.favourite ? T.red : T.text)),
              ),
            ),
          ]),
        ]),
      ),
      // ── compare sellers ──
      Container(
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Compare prices for', style: pop(12, w: FontWeight.w700, c: T.ink))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: T.soft, border: Border.all(color: const Color(0xFFE5E5E5)), borderRadius: BorderRadius.circular(14)),
                  child: Text('ONE SIZE ▾', style: pop(9, w: FontWeight.w600, c: const Color(0xFF444444))),
                ),
              ]),
              const SizedBox(height: 9),
              Text.rich(TextSpan(style: pop(8.5, c: T.gray), children: [
                const TextSpan(text: 'Recommended · '),
                TextSpan(text: 'Lowest Price', style: pop(8.5, w: FontWeight.w600, c: T.amber)),
                const TextSpan(text: ' · Fastest Delivery'),
              ])),
              const SizedBox(height: 7),
              Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: T.line))),
                child: Row(children: [
                  for (final (fast, label) in const [(false, 'Lowest Price'), (true, 'Fastest Delivery')])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _fastTab = fast),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _fastTab == fast ? T.amber : Colors.transparent, width: 2))),
                          child: Text(label, textAlign: TextAlign.center, style: pop(10, w: _fastTab == fast ? FontWeight.w700 : FontWeight.w600, c: _fastTab == fast ? T.amber : T.gray)),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          for (final s in sellers) _SellerRow(s, onBuy: () => _buy(s)),
          if (sellers.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text('Only listed on ${sellers.isEmpty ? 'no stores' : sellers.first.name} right now.', style: pop(10, c: T.gray)),
            ),
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed(Routes.shop, arguments: p.title.split(' ').take(4).join(' ')),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.line))),
              child: Text('See similar products →', textAlign: TextAlign.center, style: pop(11, w: FontWeight.w700, c: T.amber)),
            ),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    ]);
  }
}

class _SellerRow extends StatelessWidget {
  final Seller s;
  final VoidCallback onBuy;
  const _SellerRow(this.s, {required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final amz = s.source == 'amazon';
    return InkWell(
      onTap: onBuy,
      child: Container(
        color: s.best ? T.amberPale : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: amz ? T.amzBg : T.fkBg, borderRadius: BorderRadius.circular(7)),
            child: Text(s.logo, style: pop(9, w: FontWeight.w800, c: amz ? T.amzFg : T.fkFg)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(s.name, style: pop(11, w: FontWeight.w700, c: T.ink)),
                if (s.verified) _tag('✓ Verified', const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
                if (s.best) _tag('BEST', T.amberPale, T.amber),
              ]),
              const SizedBox(height: 2),
              Text(s.delivery != null ? 'Delivery ${s.delivery}' : 'See delivery on ${s.name}', style: pop(9.5, w: FontWeight.w600, c: T.green)),
              if (s.mrp != null && s.mrp! > s.price) Text('MRP ₹${inr(s.mrp)}', style: pop(9, c: T.gray)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${inr(s.price)}', style: nun(13, c: T.ink)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onBuy,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: T.amber, borderRadius: BorderRadius.circular(6)),
                child: Text('Buy →', style: nun(8.5, w: FontWeight.w700, c: Colors.white)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _tag(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: pop(7.5, w: FontWeight.w700, c: fg)),
      );
}
