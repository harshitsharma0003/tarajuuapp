import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2200)));
}

/// The Tarajuu brand mark (orange balance scale with ₹ coins).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/tarajuu_mark.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// White rounded square with the brand mark (.auth-logo / .sp-logo-box).
class LogoBox extends StatelessWidget {
  final double size, radius, icon;
  const LogoBox({super.key, this.size = 60, this.radius = 16, this.icon = 48});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 3))],
        ),
        alignment: Alignment.center,
        child: BrandMark(size: icon),
      );
}

/// Amber header on Login / OTP / Sign-up (.auth-head).
class AuthHeader extends StatelessWidget {
  final String tag;
  const AuthHeader(this.tag, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: T.amber,
        padding: EdgeInsets.fromLTRB(20, 30 + MediaQuery.paddingOf(context).top, 20, 22),
        child: Column(children: [
          const LogoBox(),
          const SizedBox(height: 10),
          Text('Tarajuu', style: nun(21, w: FontWeight.w900, c: Colors.white)),
          const SizedBox(height: 1),
          Text(tag, style: pop(10, c: Colors.white.withValues(alpha: .6), ls: 2)),
        ]),
      );
}

/// Amber bar with a round back button (.screen-hd).
class ScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  const ScreenHeader(this.title, {super.key, this.onBack, this.trailing});
  @override
  Widget build(BuildContext context) => Container(
        color: T.amber,
        padding: EdgeInsets.fromLTRB(14, 11 + MediaQuery.paddingOf(context).top, 14, 11),
        child: Row(children: [
          RoundIconButton(
            size: 28,
            onTap: onBack ?? () => Navigator.maybePop(context),
            child: Text('‹', style: pop(17, c: Colors.white, h: 1)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: nun(14, w: FontWeight.w700, c: Colors.white), overflow: TextOverflow.ellipsis)),
          ?trailing,
        ]),
      );
}

class RoundIconButton extends StatelessWidget {
  final double size;
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  const RoundIconButton({super.key, required this.child, this.onTap, this.size = 32, this.color = const Color(0x2EFFFFFF)});
  @override
  Widget build(BuildContext context) => Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Center(child: child)),
        ),
      );
}

/// Full-width amber button (.btn).
class AmberButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double fontSize, radius, vPad;
  const AmberButton(this.label, {super.key, this.onPressed, this.busy = false, this.fontSize = 14, this.radius = 12, this.vPad = 12});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: T.amber,
            disabledBackgroundColor: T.amber.withValues(alpha: .6),
            padding: EdgeInsets.symmetric(vertical: vPad),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          ),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: nun(fontSize, w: FontWeight.w700, c: Colors.white)),
        ),
      );
}

/// Amber-pale input (.inp).
InputDecoration amberInput(String hint, {bool error = false}) => InputDecoration(
      hintText: hint,
      hintStyle: pop(13, c: const Color(0xFF9CA3AF)),
      isDense: true,
      filled: true,
      fillColor: T.amberPale,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: error ? T.red : T.amberBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: error ? T.red : T.amber, width: 1.5),
      ),
    );

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(text.toUpperCase(), style: pop(10, w: FontWeight.w700, c: T.gray, ls: .5)),
      );
}

/// "🇮🇳 +91" pill (.flag).
class FlagBox extends StatelessWidget {
  const FlagBox({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: T.amberPale,
          border: Border.all(color: T.amberBorder, width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text('🇮🇳 +91', style: pop(13, c: const Color(0xFF333333))),
      );
}

/// Bottom navigation (.bnav). [current]: 0 Home, 1 Shop, 2 Rides, 3 Profile.
class BottomNav extends StatelessWidget {
  final int current;
  const BottomNav(this.current, {super.key});

  static const _items = [('🏠', 'Home'), ('🛍️', 'Shop'), ('🚕', 'Rides'), ('👤', 'Profile')];

  void _go(BuildContext context, int i) {
    if (i == current && i != 3) return;
    switch (i) {
      case 0:
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
      case 1:
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.shop, ModalRoute.withName(Routes.home));
      case 2:
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.rides, ModalRoute.withName(Routes.home));
      case 3:
        Navigator.of(context).pushNamed(Routes.drawer);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: T.amberBorder, width: 1.5)),
        ),
        padding: EdgeInsets.only(top: 5, bottom: 8 + MediaQuery.paddingOf(context).bottom),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => _go(context, i),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_items[i].$1, style: const TextStyle(fontSize: 17, height: 1)),
                  const SizedBox(height: 2),
                  Text(_items[i].$2, style: pop(9, c: i == current ? T.amber : T.gray)),
                ]),
              ),
            ),
        ]),
      );
}

/// Small amber spinner (.spin).
class AmberSpinner extends StatelessWidget {
  final double size;
  const AmberSpinner({super.key, this.size = 14});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2, color: T.amber, backgroundColor: T.amberBorder),
      );
}

/// Section card with white background and the prototype's 14px radius.
class Card14 extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin, padding;
  final Border? border;
  const Card14({super.key, required this.child, this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 10), this.padding = EdgeInsets.zero, this.border});
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: border),
        child: child,
      );
}

/// Empty/error state (.empty-state).
class EmptyState extends StatelessWidget {
  final String icon, title, body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text(title, style: pop(14, w: FontWeight.w700, c: T.amberDark), textAlign: TextAlign.center),
          const SizedBox(height: 5),
          Text(body, style: pop(11, c: T.gray, h: 1.6), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      );
}
