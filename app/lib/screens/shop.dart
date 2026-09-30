import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../poll.dart';
import '../routes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/product_widgets.dart';

/// Chip key → (label, query). Queries match backend services/catalog.py so the
/// Home strip and these chips share the server-side cache.
const shopCategories = <String, (String, String)>{
  'fan': ('🌀 Fan', 'ceiling fan 1200mm'),
  'tv': ('📺 TV', 'smart tv 43 inch'),
  'laptop': ('💻 Laptop', 'laptop 16gb ram'),
  'headphones': ('🎧 Audio', 'bluetooth headphones'),
  'mobile': ('📱 Mobile', '5g smartphone'),
  'ac': ('❄️ AC', '1.5 ton 5 star inverter split ac'),
  'watch': ('⌚ Watch', 'smartwatch'),
  'washing': ('🫧 Washer', 'washing machine'),
};

enum _Sort { relevance, priceLow, priceHigh, rating }

class ShopScreen extends StatefulWidget {
  /// Category key (e.g. "fan") or free-text query; null = empty state.
  final String? initial;
  const ShopScreen({super.key, this.initial});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const _msgs = ['Searching Amazon.in...', 'Checking Flipkart...', 'Comparing prices...', 'Almost done...'];

  final _q = TextEditingController();
  String? _chip;
  String _shownQuery = '';
  List<Product>? _results;
  Map<String, dynamic> _sources = {};
  bool _loading = false, _bad = false;
  String? _error;
  int _msg = 0, _req = 0;
  Timer? _msgTimer;
  _Sort _sort = _Sort.relevance;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      if (shopCategories.containsKey(init)) {
        _chipSearch(init);
      } else {
        _q.text = init;
        _run(init);
      }
    }
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _chipSearch(String key) {
    setState(() => _chip = key);
    _q.text = shopCategories[key]!.$2;
    _run(shopCategories[key]!.$2);
  }

  void _submit() {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _bad = true);
      Timer(const Duration(milliseconds: 1500), () => mounted ? setState(() => _bad = false) : null);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _chip = shopCategories.entries.where((e) => e.value.$2 == q).firstOrNull?.key);
    _run(q);
  }

  Future<void> _run(String q) async {
    final req = ++_req;
    _msgTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
      _shownQuery = q;
      _msg = 0;
      _sort = _Sort.relevance;
    });
    _msgTimer = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (!mounted || _msg >= _msgs.length - 1) return t.cancel();
      setState(() => _msg++);
    });
    var first = true;
    try {
      await pollSearch(
        () {
          final f = Api.instance.search(q, record: first);
          first = false;
          return f;
        },
        cancelled: () => !mounted || req != _req,
        onUpdate: (r) => setState(() {
          _sources = r.sources;
          if (r.results.isNotEmpty || r.done) _results = r.results;
        }),
      );
    } on ApiException catch (e) {
      if (mounted && req == _req) setState(() => _error = e.message);
    }
    if (mounted && req == _req) {
      _msgTimer?.cancel();
      setState(() => _loading = false);
    }
  }

  List<Product> get _sorted {
    final list = [...?_results];
    switch (_sort) {
      case _Sort.priceLow:
        list.sort((a, b) => (a.bestPrice ?? 1 << 30).compareTo(b.bestPrice ?? 1 << 30));
      case _Sort.priceHigh:
        list.sort((a, b) => (b.bestPrice ?? 0).compareTo(a.bestPrice ?? 0));
      case _Sort.rating:
        list.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case _Sort.relevance:
        break;
    }
    return list;
  }

  String get _sortLabel => switch (_sort) {
        _Sort.relevance => 'Sort ↕',
        _Sort.priceLow => 'Price ↑',
        _Sort.priceHigh => 'Price ↓',
        _Sort.rating => 'Rating ★',
      };

  String? get _sourceNote {
    final a = _sources['amazon'], f = _sources['flipkart'];
    if (a == 'blocked') return 'Amazon is busy right now — showing what we have. Try again in a minute.';
    if (a == 'error' && f != 'ok') return 'Couldn\'t reach the stores. Pull down to retry.';
    if (f == 'disabled' || f == 'error') return 'Flipkart prices unavailable right now.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        ScreenHeader('Product Search', onBack: () => Navigator.of(context).maybePop()),
        // search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: T.amberBorder, width: 1.5))),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  style: pop(12, c: const Color(0xFF333333)),
                  decoration: amberInput('🔍 Fan, TV, Laptop, Watch...', error: _bad).copyWith(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _bad ? T.red : T.amberBorder, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: T.amber, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: T.amber,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Search', style: nun(12, w: FontWeight.w700, c: Colors.white)),
              ),
            ]),
            const SizedBox(height: 7),
            SizedBox(
              height: 28,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shopCategories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (_, i) {
                  final key = shopCategories.keys.elementAt(i);
                  final on = key == _chip;
                  return GestureDetector(
                    onTap: () => _chipSearch(key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: on ? T.amber : Colors.white,
                        border: Border.all(color: on ? T.amber : T.amberBorder, width: 1.5),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(shopCategories[key]!.$1, style: pop(10, w: FontWeight.w600, c: on ? Colors.white : T.amberDark)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: T.amber,
            onRefresh: () async => _shownQuery.isEmpty ? null : _run(_shownQuery),
            child: CustomScrollView(slivers: [
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      const AmberSpinner(),
                      const SizedBox(width: 7),
                      Text(results?.isNotEmpty == true ? 'Refreshing live prices...' : _msgs[_msg], style: pop(11, c: T.gray)),
                    ]),
                  ),
                ),
              if (_loading && (results == null || results.isEmpty))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: .95,
                    children: const [
                      SkeletonCard([.9, .6, .4]),
                      SkeletonCard([.85, .65, .45]),
                      SkeletonCard([.8, .5, .42]),
                      SkeletonCard([.95, .55, .35]),
                    ],
                  ),
                )
              else if (_error != null && (results == null || results.isEmpty))
                SliverToBoxAdapter(child: EmptyState(icon: '⚠️', title: 'Search failed', body: _error!))
              else if (results == null)
                const SliverToBoxAdapter(
                  child: EmptyState(icon: '🔍', title: 'Search any product', body: 'Tap a category or type a product name.\nWe search Amazon & Flipkart instantly.'),
                )
              else if (results.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(icon: '🤷', title: 'No results', body: _sourceNote ?? 'Try a different product name.'),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(children: [
                      Expanded(child: Text('${results.length} results for "$_shownQuery"', maxLines: 1, overflow: TextOverflow.ellipsis, style: pop(11, w: FontWeight.w600, c: T.gray))),
                      GestureDetector(
                        onTap: () => setState(() => _sort = _Sort.values[(_sort.index + 1) % _Sort.values.length]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(border: Border.all(color: T.amberBorder, width: 1.5), borderRadius: BorderRadius.circular(7)),
                          child: Text(_sortLabel, style: pop(10, w: FontWeight.w600, c: T.amber)),
                        ),
                      ),
                    ]),
                  ),
                ),
                if (_sourceNote != null && !_loading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
                      child: Text(_sourceNote!, style: pop(9.5, c: T.gray)),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 206),
                    itemCount: _sorted.length,
                    itemBuilder: (_, i) {
                      final p = _sorted[i];
                      return ProductTile(p, onTap: () => Navigator.of(context).pushNamed(Routes.pdp, arguments: p.id));
                    },
                  ),
                ),
              ],
            ]),
          ),
        ),
        const BottomNav(1),
      ]),
    );
  }
}
