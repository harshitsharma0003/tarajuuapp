import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../models.dart';

/// Device location + its street address, used on Home and as ride pickup.
class LocationState extends ChangeNotifier {
  Place? current;
  bool loading = false;
  String? error;

  Future<void> locate() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Location is turned off');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
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
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
