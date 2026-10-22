// Plain geometry used by routing and navigation. Kept free of Flutter and
// MapLibre types so it can be unit tested on the Mac.
import 'dart:math' as math;

class Geo {
  final double lat;
  final double lon;
  const Geo(this.lat, this.lon);

  @override
  String toString() => 'Geo(${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)})';

  @override
  bool operator ==(Object other) => other is Geo && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

const double earthRadiusM = 6371008.8;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Great-circle distance in metres.
double distanceM(Geo a, Geo b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Initial bearing from a to b, degrees clockwise from north, 0..360.
double bearingDeg(Geo a, Geo b) {
  final y = math.sin(_rad(b.lon - a.lon)) * math.cos(_rad(b.lat));
  final x =
      math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) -
      math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(_rad(b.lon - a.lon));
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Smallest signed difference b - a in degrees, -180..180.
double angleDiff(double a, double b) {
  var d = (b - a) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Result of projecting a point onto a polyline segment.
class Projection {
  final Geo point; // the closest point on the segment
  final double t; // 0..1 along the segment
  final double distanceM; // from the input point to [point]
  const Projection(this.point, this.t, this.distanceM);
}

/// Projects [p] onto segment a-b using a local flat approximation, which is
/// accurate to centimetres at the segment lengths a road has.
Projection projectOnSegment(Geo p, Geo a, Geo b) {
  final cosLat = math.cos(_rad(p.lat));
  final ax = a.lon * cosLat, ay = a.lat;
  final bx = b.lon * cosLat, by = b.lat;
  final px = p.lon * cosLat, py = p.lat;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final q = Geo(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  return Projection(q, t, distanceM(p, q));
}

Geo lerp(Geo a, Geo b, double t) => Geo(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);

/// Decodes a Google-format encoded polyline (the format, not the service)
/// with the given precision; Valhalla uses 6.
List<Geo> decodePolyline(String s, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final out = <Geo>[];
  var index = 0, lat = 0, lon = 0;
  while (index < s.length) {
    for (var k = 0; k < 2; k++) {
      var shift = 0, result = 0, b = 0;
      do {
        b = s.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      // -(x + 1), not ~x: in a browser ~ is unsigned 32-bit and turns every
      // negative step into a huge positive one.
      final delta = (result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1);
      if (k == 0) {
        lat += delta;
      } else {
        lon += delta;
      }
    }
    out.add(Geo(lat / factor, lon / factor));
  }
  return out;
}

/// Cumulative distance along a polyline: result[i] is metres from start to points[i].
List<double> cumulativeDistances(List<Geo> pts) {
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    out[i] = out[i - 1] + distanceM(pts[i - 1], pts[i]);
  }
  return out;
}

/// Bounding box helper.
class Bounds {
  final double south, west, north, east;
  const Bounds(this.south, this.west, this.north, this.east);
  bool contains(Geo p) => p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  static Bounds of(Iterable<Geo> pts) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in pts) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    return Bounds(s, w, n, e);
  }
}
