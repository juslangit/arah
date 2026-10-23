// Live traffic time for a route Arah already has. The routing server
// (Valhalla) knows typical speeds only, so TomTom is asked to rebuild the same
// route from points along it and say how long it takes right now, and how long
// with clear roads. Online only; any failure means "no traffic info".
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../core/geo.dart';

class TrafficTime {
  /// Seconds with today's traffic, and with clear roads.
  final double liveS, clearS;
  const TrafficTime(this.liveS, this.clearS);

  double get delayS => (liveS - clearS).clamp(0, double.infinity).toDouble();
}

class TrafficEta {
  static const _url = 'https://api.tomtom.com/routing/1/calculateRoute';

  /// TomTom's live and clear-road times along [pts], or null.
  static Future<TrafficTime?> along(List<Geo> pts) async {
    if (ArahConfig.tomtomKey.isEmpty || pts.length < 2) return null;
    // ~150 points keep the request small and still pin TomTom to our roads.
    final step = (pts.length / 150).ceil().clamp(1, pts.length);
    final support = [for (var i = 0; i < pts.length; i += step) pts[i], if ((pts.length - 1) % step != 0) pts.last];
    final a = pts.first, b = pts.last;
    final uri = Uri.parse(
      '$_url/${a.lat},${a.lon}:${b.lat},${b.lon}/json'
      '?key=${ArahConfig.tomtomKey}&traffic=true&travelMode=car'
      '&computeTravelTimeFor=all&routeRepresentation=summaryOnly',
    );
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', ...ArahConfig.userAgent},
            body: jsonEncode({
              'supportingPoints': [
                for (final p in support) {'latitude': p.lat, 'longitude': p.lon},
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final s = ((jsonDecode(res.body) as Map)['routes'] as List).first['summary'] as Map;
      final live = (s['travelTimeInSeconds'] as num?)?.toDouble();
      final clear = (s['noTrafficTravelTimeInSeconds'] as num?)?.toDouble();
      if (live == null || clear == null) return null;
      return TrafficTime(live, clear);
    } catch (_) {
      return null;
    }
  }
}
