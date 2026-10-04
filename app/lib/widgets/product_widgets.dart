import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Scraped product image on the prototype's cream gradient; the category
/// emoji stands in while loading or if the image fails.
class ProductImage extends StatelessWidget {
  final String? url;
  final String emoji;
  final double emojiSize;
  final EdgeInsets padding;
  const ProductImage({super.key, this.url, required this.emoji, this.emojiSize = 42, this.padding = const EdgeInsets.all(8)});

  @override
  Widget build(BuildContext context) {
    final fallback = Center(child: Text(emoji, style: TextStyle(fontSize: emojiSize)));
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: T.productImageGradient),
      child: url == null
          ? fallback
          : Padding(
              padding: padding,
              child: Image.network(
                url!,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) => p == null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

/// AMZ / FLK pill (.tp-a / .tp-f / .mp-a / .mp-f).
class PlatTag extends StatelessWidget {
  final String source;
  final double fontSize;
  final String? text;
  final EdgeInsets padding;
  final double radius;
  const PlatTag(this.source, {super.key, this.fontSize = 7.5, this.text, this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 2), this.radius = 4});
  @override
  Widget build(BuildContext context) {
    final amz = source == 'amazon';
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: amz ? T.amzBg : T.fkBg, borderRadius: BorderRadius.circular(radius)),
      child: Text(text ?? (amz ? 'AMZ' : 'FLK'), style: pop(fontSize, w: FontWeight.w700, c: amz ? T.amzFg : T.fkFg)),
    );
  }
}

Widget platTags(Product p, {double fontSize = 7.5, EdgeInsets? padding, double radius = 4}) => Wrap(spacing: 3, children: [
      for (final o in p.offers)
        PlatTag(o.source, fontSize: fontSize, padding: padding ?? const EdgeInsets.symmetric(horizontal: 5, vertical: 2), radius: radius),
    ]);

String stars(double? r) {
  final n = (r ?? 0).round().clamp(0, 5);
  return '★' * n + '☆' * (5 - n);
}

/// PLP grid tile (.prod-tile).
class ProductTile extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  const ProductTile(this.p, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = p.badge;
    final (bbg, bfg) = switch (b?.type) {
      'off' => (const Color(0xFFFDE8E8), const Color(0xFFC0392B)),
      'new' => (const Color(0xFFE8F5E9), const Color(0xFF1A6B2E)),
      _ => (T.amberPale, T.amberDark),
    };
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: T.amberBorder, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 96,
            child: Stack(fit: StackFit.expand, children: [
              ProductImage(url: p.image, emoji: p.emoji),
              if (b != null)
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: bbg, borderRadius: BorderRadius.circular(5)),
                    child: Text(b.text, style: pop(7.5, w: FontWeight.w700, c: bfg)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(9.5) * 1.35 * 2 + 2,
                child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: pop(9.5, w: FontWeight.w600, c: const Color(0xFF333333), h: 1.35)),
              ),
              const SizedBox(height: 3),
              Row(children: [
                Text(stars(p.rating), style: pop(9, c: T.amber)),
                if (p.reviews != null) Text(' (${inr(p.reviews)})', style: pop(8, c: T.gray)),
              ]),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('₹${inr(p.bestPrice)}', style: nun(13, c: T.amberDark)),
                const SizedBox(width: 4),
                if (p.compareAtPrice != null)
                  Flexible(child: Text('₹${inr(p.compareAtPrice)}', overflow: TextOverflow.clip, style: pop(8.5, c: const Color(0xFFAAAAAA), deco: TextDecoration.lineThrough))),
              ]),
              const SizedBox(height: 3),
              platTags(p),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Home "Compare prices" strip card (.mini-prod).
class MiniProduct extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  const MiniProduct(this.p, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 100,
        child: Material(
          color: T.tileBg,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(height: 64, width: double.infinity, child: ProductImage(url: p.image, emoji: p.emoji, emojiSize: 32, padding: const EdgeInsets.all(4))),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(8.5) * 1.3 * 2 + 2,
                  child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: pop(8.5, w: FontWeight.w600, c: const Color(0xFF333333), h: 1.3)),
                ),
                const SizedBox(height: 2),
                Text('₹${inr(p.bestPrice)}', style: nun(11, c: T.amberDark)),
                Text(p.offPercent > 0 ? '${p.offPercent}% off' : ' ', style: pop(7.5, w: FontWeight.w700, c: T.green)),
                const SizedBox(height: 2),
                platTags(p, fontSize: 7, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), radius: 3),
              ]),
            ),
          ),
        ),
      );
}

/// Shimmering skeleton card (.skel-card).
class Shimmer extends StatefulWidget {
  final double height, width;
  final double radius;
  const Shimmer({super.key, required this.height, this.width = double.infinity, this.radius = 0});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final x = 2 - _c.value * 4; // 200% → -200%, as in @keyframes shim
          return Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(x - 1, 0),
                end: Alignment(x + 1, 0),
                colors: const [T.amberPale, T.bg, T.amberPale],
                stops: const [.25, .5, .75],
              ),
            ),
          );
        },
      );
}

class SkeletonCard extends StatelessWidget {
  final List<double> widths;
  const SkeletonCard(this.widths, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: T.amberBorder, width: 1.5),
        ),
        child: Column(children: [
          const Shimmer(height: 90),
          Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (_, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in widths) ...[Shimmer(height: 8, width: c.maxWidth * w, radius: 4), const SizedBox(height: 5)],
              ]),
            ),
          ),
        ]),
      );
}
