import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'routes.dart';
import 'screens/auth_screens.dart';
import 'screens/confirm.dart';
import 'screens/drawer_about.dart';
import 'screens/home.dart';
import 'screens/pdp.dart';
import 'screens/rides.dart';
import 'screens/shop.dart';
import 'screens/splash.dart';
import 'screens/tracking.dart';
import 'state/location.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not configured: $e');
  }
  final session = Session();
  await session.restore(firebaseReady: firebaseReady);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => LocationState()),
    ],
    child: const TarajuuApp(),
  ));
}

class TarajuuApp extends StatelessWidget {
  const TarajuuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tarajuu',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      initialRoute: Routes.splash,
      // The prototype is drawn on a 320px-wide phone; scale text up a little
      // on wider phones so proportions match.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final k = (mq.size.width / 320).clamp(1.0, 1.2);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(k * mq.textScaler.scale(1).clamp(1.0, 1.3))), child: child!);
      },
      onGenerateRoute: (s) {
        final a = s.arguments;
        Widget page = switch (s.name) {
          Routes.splash => const SplashScreen(),
          Routes.login => const LoginScreen(),
          Routes.otp => const OtpScreen(),
          Routes.signup => const SignupScreen(),
          Routes.home => const HomeScreen(),
          Routes.shop => ShopScreen(initial: a as String?),
          Routes.pdp => PdpScreen(productId: a as String),
          Routes.rides => RidesScreen(initial: a),
          Routes.confirm => ConfirmScreen(args: a as ConfirmArgs),
          Routes.tracking => TrackingScreen(args: a as ConfirmArgs),
          Routes.about => const AboutScreen(),
          _ => const HomeScreen(),
        };
        if (s.name == Routes.drawer) {
          return PageRouteBuilder(
            settings: s,
            opaque: false,
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (_, _, _) => const DrawerScreen(),
            transitionsBuilder: (_, anim, _, child) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(-.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            ),
          );
        }
        return MaterialPageRoute(settings: s, builder: (_) => page);
      },
    );
  }
}
