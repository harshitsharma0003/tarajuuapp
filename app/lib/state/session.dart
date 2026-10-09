import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';

/// Signed-in state. Firebase does the identity work (phone OTP, Google);
/// the backend turns the Firebase ID token into a Tarajuu session.
class Session extends ChangeNotifier {
  static const _kToken = 'tarajuu.token', _kUser = 'tarajuu.user';

  AppUser? user;
  int savedTotal = 0;
  bool firebaseReady = false;

  // Phone-OTP flow state
  String? _verificationId;
  int? _resendToken;
  String? pendingPhone;

  // OTP de-duplication: one request at a time, and no new SMS to the same
  // number within [otpReuseWindow] — the existing code is reused instead.
  static const otpReuseWindow = Duration(seconds: 60);
  bool _sendingOtp = false;
  String? _codeSentTo;
  DateTime? _codeSentAt;

  /// True when a code for [phone] (+91…) was sent recently and can still be entered.
  bool hasRecentCode(String phone) =>
      _verificationId != null &&
      _codeSentTo == phone &&
      _codeSentAt != null &&
      DateTime.now().difference(_codeSentAt!) < otpReuseWindow;
  String? pendingName, pendingEmail;

  bool get signedIn => user != null && Api.instance.token != null;

  Future<void> restore({required bool firebaseReady}) async {
    this.firebaseReady = firebaseReady;
    final prefs = await SharedPreferences.getInstance();
    Api.instance.token = prefs.getString(_kToken);
    final u = prefs.getString(_kUser);
    if (u != null) user = AppUser.fromJson(jsonDecode(u));
    if (signedIn) unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final (u, saved) = await Api.instance.me();
      user = u;
      savedTotal = saved;
      await _persist();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await signOut();
    }
  }

  Future<void> updateProfile({String? name, String? email}) async {
    final j = await Api.instance.patch('/me', {'name': ?name, 'email': ?email});
    user = AppUser.fromJson(j['user']);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (Api.instance.token != null) await prefs.setString(_kToken, Api.instance.token!);
    if (user != null) await prefs.setString(_kUser, jsonEncode(user!.toJson()));
  }

  void _requireFirebase() {
    if (!firebaseReady) {
      throw Exception('Sign-in is not configured yet. Run `flutterfire configure` for this app.');
    }
  }

  // ───────────── phone OTP ─────────────

  /// Sends the SMS. Completes when the code has been sent (→ go to OTP
  /// screen) or when Android auto-verified the number (→ already signed in,
  /// returns true).
  Future<bool> sendOtp(String tenDigits, {String? name, String? email, bool resend = false}) async {
    _requireFirebase();
    final phone = '+91$tenDigits';
    if (_sendingOtp) throw Exception('Sending your OTP… please wait.');
    if (!resend && hasRecentCode(phone)) {
      // Code already on its way to this number — reuse it, don't send another SMS.
      pendingPhone = phone;
      if (name != null) pendingName = name;
      if (email != null) pendingEmail = email;
      return false;
    }
    _sendingOtp = true;
    try {
      return await _requestCode(phone, name: name, email: email, resend: resend);
    } finally {
      _sendingOtp = false;
    }
  }

  Future<bool> _requestCode(String phone, {String? name, String? email, required bool resend}) async {
    pendingPhone = phone;
    // No robot check for Firebase test numbers; real numbers use silent Play Integrity.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: Config.otpTestNumbers.contains(pendingPhone),
    );
    if (name != null) pendingName = name;
    if (email != null) pendingEmail = email;
    final done = Completer<bool>();
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: pendingPhone!,
      forceResendingToken: resend ? _resendToken : null,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        // Android instant verification / auto-retrieval.
        try {
          await _finishWithCredential(cred);
          if (!done.isCompleted) done.complete(true);
        } catch (e) {
          if (!done.isCompleted) done.completeError(e);
        }
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(Exception(_friendly(e)));
      },
      codeSent: (id, token) {
        _verificationId = id;
        _resendToken = token;
        _codeSentTo = phone;
        _codeSentAt = DateTime.now();
        if (!done.isCompleted) done.complete(false);
      },
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
    return done.future;
  }

  Future<void> verifyOtp(String code) async {
    _requireFirebase();
    if (_verificationId == null) throw Exception('Please request a new OTP.');
    final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code);
    await _finishWithCredential(cred);
  }

  // ───────────── Google ─────────────

  bool _googleInit = false;

  Future<void> signInWithGoogle() async {
    _requireFirebase();
    final g = GoogleSignIn.instance;
    if (!_googleInit) {
      await g.initialize(serverClientId: Config.googleServerClientId.isEmpty ? null : Config.googleServerClientId);
      _googleInit = true;
    }
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Google did not return an ID token.');
    await _finishWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  // ───────────── common ─────────────

  Future<void> _finishWithCredential(AuthCredential cred) async {
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(cred);
      final idToken = await result.user!.getIdToken();
      final isSignup = pendingName != null;
      final (token, u) = await Api.instance.firebaseLogin(
        idToken!,
        name: pendingName,
        email: pendingEmail,
        acceptedTerms: isSignup ? true : null,
      );
      Api.instance.token = token;
      user = u;
      pendingName = pendingEmail = null;
      await _persist();
      notifyListeners();
      unawaited(refresh());
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  Future<void> signOut() async {
    Api.instance.token = null;
    user = null;
    savedTotal = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    if (firebaseReady) {
      await FirebaseAuth.instance.signOut();
      if (_googleInit) await GoogleSignIn.instance.signOut();
    }
    notifyListeners();
  }

  static String _friendly(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'That mobile number looks invalid.',
        'invalid-verification-code' => 'Wrong OTP. Please check and try again.',
        'session-expired' => 'OTP expired. Please resend.',
        'too-many-requests' => 'Too many OTP requests for this number. Please wait about an hour and try again.',
        'network-request-failed' => 'No internet connection.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };
}
