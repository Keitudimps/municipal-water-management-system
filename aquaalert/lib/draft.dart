import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// The report being captured: photo + location. Shared between the Capture and Details pages.
class Draft extends ChangeNotifier {
  Uint8List? photo;
  String? photoName;

  // Fallback used when location permission is denied (matches the design's Miami example).
  double lat = 25.7617, lng = -80.1918;
  double? accuracy;
  bool hasFix = false, locating = false;

  void setPhoto(Uint8List bytes, String name) {
    photo = bytes;
    photoName = name;
    notifyListeners();
  }

  void reset() {
    photo = null;
    photoName = null;
    notifyListeners();
  }

  Future<void> locate() async {
    if (locating) return;
    locating = true;
    notifyListeners();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      lat = p.latitude;
      lng = p.longitude;
      accuracy = p.accuracy;
      hasFix = true;
    } catch (_) {
      // keep the fallback location
    } finally {
      locating = false;
      notifyListeners();
    }
  }
}

final draft = Draft();
