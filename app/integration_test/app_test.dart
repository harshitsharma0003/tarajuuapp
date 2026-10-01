// End-to-end check run on a real device in Firebase Test Lab (see
// .github/workflows/ci.yml → testlab APKs, and README → Device testing).
//
// Logs in with the Firebase test number (+91 9999911111 / 123456), then walks
// search → product page → ride compare, saving a screenshot per screen to
// <external files dir>/screenshots and a pass/fail summary to results.txt.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tarajuu/main.dart' as app;
import 'package:tarajuu/widgets/product_widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory shots;
  final results = <String>[];
  var shotIndex = 0;

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await t.pump();
  }

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 40}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      await settle(t, 300);
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out after ${seconds}s waiting for $f');
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t, 400);
    try {
      final bytes = await binding.takeScreenshot(name);
      final file = File('${shots.path}/${(++shotIndex).toString().padLeft(2, '0')}_$name.png');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('TARAJUU_TEST screenshot $name failed: $e');
    }
  }

  Future<void> step(WidgetTester t, String name, Future<void> Function() body, {bool required = false}) async {
    try {
      await body();
      results.add('PASS  $name');
      debugPrint('TARAJUU_TEST PASS $name');
    } catch (e) {
      results.add('FAIL  $name — $e');
      debugPrint('TARAJUU_TEST FAIL $name — $e');
      await shot(t, 'FAILED_${name.replaceAll(' ', '_')}');
      if (required) rethrow;
    }
  }

  testWidgets('Tarajuu end-to-end: OTP login, search, product page, rides', (t) async {
    final ext = await getExternalStorageDirectory();
    shots = Directory('${ext!.path}/screenshots')..createSync(recursive: true);

    await app.main();
    // Test numbers skip SMS; this also skips Play Integrity/reCAPTCHA so the
    // flow can run unattended. Only affects this test process.
    await FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: true);
    await binding.convertFlutterSurfaceToImage();

    try {
      await step(t, 'splash', () async {
        await waitFor(t, find.text('Get Started →'));
        await settle(t, 2500); // let the ₹ burst finish
        await shot(t, 'splash');
        await t.tap(find.text('Get Started →'));
        await waitFor(t, find.text('Send OTP →'));
        await shot(t, 'login');
      }, required: true);

      await step(t, 'otp login', () async {
        await t.enterText(find.byType(TextField).first, '9999911111');
        await settle(t);
        await t.tap(find.text('Send OTP →'));
        await waitFor(t, find.text('Enter OTP 🔐'), seconds: 60);
        await shot(t, 'otp');
        // Paste-style entry: the first box spreads the code over all six.
        await t.enterText(find.byType(TextField).first, '123456');
        await waitFor(t, find.text('Ride with'), seconds: 60);
        await settle(t, 3000);
        await shot(t, 'home');
      }, required: true);

      await step(t, 'product search', () async {
        await t.tap(find.text('Search products, rides...'));
        await waitFor(t, find.text('📺 TV'));
        await t.tap(find.text('📺 TV'));
        await shot(t, 'search_loading');
        await waitFor(t, find.byType(ProductTile), seconds: 90);
        await shot(t, 'search_results');
      });

      await step(t, 'product page', () async {
        await t.tap(find.byType(ProductTile).first);
        await waitFor(t, find.textContaining('Buy on'), seconds: 90);
        await settle(t, 2500); // gallery images
        await shot(t, 'product_page');
        await t.drag(find.byType(ListView).first, const Offset(0, -500));
        await shot(t, 'product_sellers');
      });

      await step(t, 'ride compare', () async {
        await t.tap(find.text('Rides').last);
        await waitFor(t, find.text('Check Prices ⚡'));
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), 'Connaught Place');
        await waitFor(t, find.textContaining('New Delhi', findRichText: true), seconds: 30);
        await t.tap(find.textContaining('New Delhi', findRichText: true).first);
        await settle(t);
        await t.enterText(fields.at(1), 'Indira Gandhi International Airport');
        await waitFor(t, find.textContaining('Airport', findRichText: true).hitTestable(), seconds: 30);
        await shot(t, 'ride_suggestions');
        await t.tap(find.textContaining('Airport', findRichText: true).hitTestable().first);
        await settle(t);
        await t.tap(find.text('Check Prices ⚡'));
        await waitFor(t, find.textContaining('saves you'), seconds: 60);
        await shot(t, 'ride_fares');
      });

      await step(t, 'drawer', () async {
        await t.tap(find.text('Profile').last);
        await waitFor(t, find.text('About Tarajuu'));
        await shot(t, 'drawer');
      });
    } finally {
      File('${shots.path}/results.txt').writeAsStringSync('${results.join('\n')}\n');
      debugPrint('TARAJUU_TEST SUMMARY\n${results.join('\n')}');
    }
    expect(results.where((r) => r.startsWith('FAIL')), isEmpty, reason: results.join('\n'));
  });
}
