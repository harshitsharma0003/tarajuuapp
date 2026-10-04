/// Build-time configuration, set with --dart-define.
///
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api
class Config {
  /// Backend base URL. Defaults to the backend running on the dev PC, exposed
  /// through ngrok (the account's fixed free domain). The GCP VM is parked;
  /// its URL was https://34-133-147-216.sslip.io/api. Override with
  /// --dart-define=API_BASE=... (e.g. http://10.0.2.2:8000/api for an emulator).
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://amused-chapter-unbitten.ngrok-free.dev/api');

  /// Web OAuth client ID from Firebase (needed by Google sign-in on Android
  /// if it cannot be read from google-services.json).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Google sign-in is wired but switched off until the Google provider is
  /// enabled in Firebase (tarajuumobile). The button stays, showing "coming soon".
  static const googleSignInEnabled = bool.fromEnvironment('GOOGLE_SIGN_IN');

  /// Firebase test numbers (Authentication → Phone → test numbers). For these
  /// the app skips Play Integrity / reCAPTCHA so cloud devices, emulators and
  /// store reviewers never see a browser check. Firebase only honours the skip
  /// for numbers configured as test numbers, so real numbers are unaffected.
  static const otpTestNumbers = {'+919999911111'};

  /// Show the simulated live-tracking screen after "Confirm Ride". Real trips
  /// are booked in the provider's app (Uber/Ola/Rapido) via deep link, so this
  /// is off by default and only meant for demos.
  static const demoTracking = bool.fromEnvironment('DEMO_TRACKING');
}
