import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../models.dart';

/// Why the device location couldn't be read.
enum LocIssue { serviceOff, denied, deniedForever, failed }

/// Device location + its street address, used on Home and as ride pickup.
class LocationState extends ChangeNotifier with WidgetsBindingObserver {
  LocationState() {
    WidgetsBinding.instance.addObserver(this);
  }

  Place? current;
  bool loading = false;
  LocIssue? issue;

  /// Set when we sent the user to a settings screen; we retry when they come back.
  bool _awaitingSettings = false;

  /// Short text for the Home header.
  String? get error => switch (issue) {
        LocIssue.serviceOff => 'Turn on GPS / location',
        LocIssue.denied => 'Allow location access',
        LocIssue.deniedForever => 'Location blocked — tap to allow',
        LocIssue.failed => "Couldn't get location — tap to retry",
        null => null,
      };

  /// Full explanation for banners.
  String? get message => switch (issue) {
        LocIssue.serviceOff => "Your phone's GPS (Location) is off. Turn it on to auto-fill your pickup.",
        LocIssue.denied => 'Tarajuu needs location permission to auto-fill your pickup.',
        LocIssue.deniedForever =>
          'Location is blocked for Tarajuu. Open Settings → Permissions → Location → "Allow only while using the app".',
        LocIssue.failed => "Couldn't get your location. Make sure GPS is on and try again.",
        null => null,
      };

  /// Label for the button that fixes [issue].
  String get actionLabel => switch (issue) {
        LocIssue.serviceOff => 'Turn on GPS',
        LocIssue.denied => 'Allow',
        LocIssue.deniedForever => 'Open Settings',
        _ => 'Retry',
      };

  /// Does whatever resolves the current [issue]: asks for permission again,
  /// or opens the right settings screen (and retries when the user returns).
  Future<void> fix() async {
    switch (issue) {
      case LocIssue.serviceOff:
        _awaitingSettings = true;
        if (!await Geolocator.openLocationSettings()) _awaitingSettings = false;
      case LocIssue.denied:
        final perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.deniedForever) {
          // Android stops showing the dialog after repeated "Don't allow".
          _awaitingSettings = true;
          await Geolocator.openAppSettings();
        } else {
          await locate();
        }
      case LocIssue.deniedForever:
        _awaitingSettings = true;
        await Geolocator.openAppSettings();
      case LocIssue.failed:
      case null:
        await locate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettings) {
      _awaitingSettings = false;
      locate();
    }
  }

  Future<void> locate() async {
    if (loading) return;
    loading = true;
    issue = null;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        issue = LocIssue.serviceOff;
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        issue = LocIssue.denied;
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        issue = LocIssue.deniedForever;
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      try {
        final p = await Api.instance.reverse(pos.latitude, pos.longitude);
        current = Place(name: p.name, subtitle: p.subtitle, lat: pos.latitude, lon: pos.longitude);
      } catch (_) {
        current = Place(name: 'Current location', lat: pos.latitude, lon: pos.longitude);
      }
    } on LocationServiceDisabledException {
      issue = LocIssue.serviceOff;
    } catch (_) {
      issue = LocIssue.failed;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
