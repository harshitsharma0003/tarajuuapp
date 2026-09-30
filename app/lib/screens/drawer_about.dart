import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/svgs.dart';

/// Left drawer shown over a dimmed backdrop (#s-drawer). Pushed as a
/// transparent route so the previous screen stays visible underneath.
class DrawerScreen extends StatelessWidget {
  const DrawerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final nav = Navigator.of(context);
    Widget item(String Function(String) icon, String label, VoidCallback onTap, {bool on = false}) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: on ? T.amberPale : null,
              border: Border(left: BorderSide(color: on ? T.amber : Colors.transparent, width: 3)),
            ),
            child: Row(children: [
              SvgPicture.string(icon(on ? '#D97706' : '#333333'), width: 16, height: 16),
              const SizedBox(width: 12),
              Text(label, style: pop(13, w: on ? FontWeight.w700 : FontWeight.w400, c: on ? T.amber : const Color(0xFF333333))),
            ]),
          ),
        );
    const divider = Padding(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 5), child: Divider(height: 1, color: T.amberPale));

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .45),
      body: GestureDetector(
        onTap: () => nav.pop(),
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: MediaQuery.sizeOf(context).width * .76,
              height: double.infinity,
              decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: T.amberBorder, width: 1.5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  color: T.amber,
                  padding: EdgeInsets.fromLTRB(18, 36 + MediaQuery.paddingOf(context).top, 18, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: Text(user?.initial ?? 'T', style: nun(22, w: FontWeight.w900, c: T.amber)),
                    ),
                    const SizedBox(height: 9),
                    Text(user?.displayName ?? 'Guest', style: pop(14, w: FontWeight.w700, c: Colors.white)),
                    const SizedBox(height: 2),
                    Text(user?.contact ?? 'Sign in to save your searches', style: pop(10, c: Colors.white.withValues(alpha: .65))),
                  ]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
                    item(drawerHome, 'Home', () => nav.pushNamedAndRemoveUntil(Routes.home, (_) => false), on: true),
                    item(drawerProfile, 'Profile', () => _editProfile(context)),
                    divider,
                    item(drawerShop, 'Shop Compare', () => nav.popAndPushNamed(Routes.shop)),
                    item(drawerRide, 'Ride Compare', () => nav.popAndPushNamed(Routes.rides)),
                    divider,
                    item(drawerAbout, 'About Tarajuu', () => nav.popAndPushNamed(Routes.about)),
                  ]),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(18, 13, 18, 13 + MediaQuery.paddingOf(context).bottom),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.amberPale))),
                  child: GestureDetector(
                    onTap: () async {
                      if (session.signedIn) await session.signOut();
                      nav.pushNamedAndRemoveUntil(Routes.login, (_) => false);
                    },
                    child: Row(children: [
                      SvgPicture.string(signOutIcon, width: 14, height: 14),
                      const SizedBox(width: 9),
                      Text(session.signedIn ? 'Sign out' : 'Sign in', style: pop(13, c: const Color(0xFFD85A30))),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final session = context.read<Session>();
    if (!session.signedIn) {
      toast(context, 'Sign in to edit your profile');
      return;
    }
    final name = TextEditingController(text: session.user?.name ?? '');
    final email = TextEditingController(text: session.user?.email ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(18, 22, 18, 28 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your profile', style: pop(14, w: FontWeight.w700, c: T.amberDark)),
          const SizedBox(height: 12),
          const FieldLabel('Full Name'),
          TextField(controller: name, style: pop(13), decoration: amberInput('Your name')),
          const SizedBox(height: 12),
          const FieldLabel('Email'),
          TextField(controller: email, style: pop(13), decoration: amberInput('you@email.com')),
          const SizedBox(height: 14),
          AmberButton('Save', onPressed: () async {
            await session.updateProfile(name: name.text.trim(), email: email.text.trim());
            if (c.mounted) Navigator.pop(c);
          }),
        ]),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget card(String t, String b) => Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: T.amberBorder, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: pop(12, w: FontWeight.w700, c: T.amberDark)),
            const SizedBox(height: 4),
            Text(b, style: pop(11, c: T.gray, h: 1.6)),
          ]),
        );
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        const ScreenHeader('About Tarajuu'),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            Container(
              color: T.amber,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Column(children: [
                const Text('⚖️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text('Tarajuu', style: nun(22, w: FontWeight.w900, c: Colors.white)),
                const SizedBox(height: 5),
                Text('In Hindi, तराजू means a weighing scale — the timeless symbol of balance and fair comparison.',
                    textAlign: TextAlign.center, style: pop(11, c: Colors.white.withValues(alpha: .7), h: 1.6)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Column(children: [
                card('🛍️ Shop Smarter', 'Search any product — see Amazon and Flipkart prices compared instantly.'),
                card('🚕 Ride Smarter', 'Compare Uber, Rapido and Ola fares for any route in one tap.'),
                card('💡 Our Mission', 'Every Indian deserves the best value. Tarajuu puts comparison in your hands.'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text('Version 1.0.0 · Made with ❤️ in India', style: pop(10, c: T.gray)),
                ),
              ]),
            ),
          ]),
        ),
        const BottomNav(3),
      ]),
    );
  }
}
