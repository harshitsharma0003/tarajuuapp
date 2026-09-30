/// Build-time configuration, set with --dart-define.
///
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api
class Config {
  /// Backend base URL. Defaults to the production API on the GCP VM; override
  /// for local work, e.g. --dart-define=API_BASE=http://10.0.2.2:8000/api
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://34-133-147-216.sslip.io/api');

  /// Web OAuth client ID from Firebase (needed by Google sign-in on Android
  /// if it cannot be read from google-services.json).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Show the simulated live-tracking screen after "Confirm Ride". Real trips
  /// are booked in the provider's app (Uber/Ola/Rapido) via deep link, so this
  /// is off by default and only meant for demos.
  static const demoTracking = bool.fromEnvironment('DEMO_TRACKING');
}
