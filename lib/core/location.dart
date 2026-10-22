// GPS through Android's own LocationManager — never Google Play Services'
// fused provider — so Arah stays free of Google APIs. While navigating, a
// foreground notification keeps GPS alive with the screen off.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../nav/nav_engine.dart';
import 'geo.dart';

class LocationService {
  StreamSubscription<Position>? _sub;
  final _ctrl = StreamController<Fix>.broadcast();
  Fix? last;

  Stream<Fix> get fixes => _ctrl.stream;

  Future<bool> ensurePermission({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied && request) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// [navigating] turns on the foreground notification and 1 Hz updates.
  Future<void> start({bool navigating = false, String title = 'Arah', String text = ''}) async {
    await _sub?.cancel();
    // In a browser, GPS only runs while the page is open and on screen.
    final settings = kIsWeb
        ? const LocationSettings(accuracy: LocationAccuracy.bestForNavigation)
        : AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            forceLocationManager: true,
            foregroundNotificationConfig: navigating
                ? ForegroundNotificationConfig(
                    notificationTitle: title,
                    notificationText: text,
                    enableWakeLock: true,
                    setOngoing: true,
                  )
                : null,
          );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      final f = Fix(
        Geo(p.latitude, p.longitude),
        accuracyM: p.accuracy,
        speedMps: p.speed,
        headingDeg: p.heading >= 0 && p.speed > 0.5 ? p.heading : null,
        time: p.timestamp,
      );
      last = f;
      _ctrl.add(f);
    }, onError: (_) {});
  }

  Future<Fix?> current() async {
    if (last != null) return last;
    if (kIsWeb) {
      try {
        final q = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
        );
        return last ??= Fix(Geo(q.latitude, q.longitude), accuracyM: q.accuracy, time: q.timestamp);
      } catch (_) {
        return null;
      }
    }
    try {
      final p = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);
      if (p != null) return last = Fix(Geo(p.latitude, p.longitude), accuracyM: p.accuracy, time: p.timestamp);
      // No cached fix: ask Android's network/GPS providers for one, briefly.
      final q = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 20),
        ),
      );
      return last ??= Fix(Geo(q.latitude, q.longitude), accuracyM: q.accuracy, time: q.timestamp);
    } catch (_) {}
    return null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
