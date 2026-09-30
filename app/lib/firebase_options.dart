// PLACEHOLDER — overwritten by `flutterfire configure`.
//
// Until then the app runs, but phone-OTP and Google sign-in show
// "Sign-in is not configured yet". See README → Firebase setup.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase is not configured. Run `flutterfire configure`.');
}
