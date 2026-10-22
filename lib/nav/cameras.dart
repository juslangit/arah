// Fixed speed and red-light cameras (JPJ AWAS and the older AES sites), like
// Waze's camera alerts. Locations: tools/data/cameras (sources in NOTES.md).
// Mobile police speed traps are not here — those come from reports.
import 'dart:convert';

import '../core/geo.dart';
import '../routing/route_model.dart';

enum CameraKind { speed, redLight, averageStart, averageEnd }

class Camera {
  final String id;
  final CameraKind kind;
  final Geo pos;
  final int? maxspeed;
  final double? heading; // enforced direction of travel; null = both or unknown
  final String road;
  const Camera(this.id, this.kind, this.pos, this.maxspeed, this.heading, this.road);
}

/// A camera the route passes, and where along the route it is.
class CameraOnRoute {
  final Camera camera;
  final double atM;
  const CameraOnRoute(this.camera, this.atM);
}

class CameraData {
  final String updated;
  final List<Camera> cameras;
  CameraData(this.updated, this.cameras);

  static CameraData parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    CameraKind kind(String? k) => switch (k) {
      'red_light' => CameraKind.redLight,
      'average_speed_start' => CameraKind.averageStart,
      'average_speed_end' => CameraKind.averageEnd,
      _ => CameraKind.speed,
    };
    return CameraData(j['updated'] as String? ?? '', [
      for (final c in (j['cameras'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (c['lat'] != null)
          Camera(
            '${c['id']}',
            kind(c['kind'] as String?),
            Geo((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
            (c['maxspeed'] as num?)?.toInt(),
            (c['heading_deg'] as num?)?.toDouble(),
            c['road'] as String? ?? '',
          ),
    ]);
  }

  /// Cameras sit beside the carriageway; 35 m keeps the one on the parallel
  /// service road or the opposite carriageway of a wide highway out.
  static const passM = 35.0;

  /// Cameras the route drives past, in order, facing the way we travel.
  List<CameraOnRoute> along(ArahRoute r) {
    final pts = r.points;
    if (pts.length < 2) return const [];
    final box = Bounds.of(pts);
    const pad = 0.001;
    final out = <CameraOnRoute>[];
    for (final c in cameras) {
      final g = c.pos;
      if (g.lat < box.south - pad || g.lat > box.north + pad || g.lon < box.west - pad || g.lon > box.east + pad) continue;
      var best = passM;
      int? seg;
      double t = 0;
      for (var i = 0; i < pts.length - 1; i++) {
        if ((pts[i].lat - g.lat).abs() > 0.01 && (pts[i + 1].lat - g.lat).abs() > 0.01) continue;
        final pr = projectOnSegment(g, pts[i], pts[i + 1]);
        if (pr.distanceM < best) {
          best = pr.distanceM;
          seg = i;
          t = pr.t;
        }
      }
      if (seg == null) continue;
      if (c.heading != null && angleDiff(bearingDeg(pts[seg], pts[seg + 1]), c.heading!).abs() > 60) continue;
      final at = r.cumDist[seg] + t * (r.cumDist[seg + 1] - r.cumDist[seg]);
      out.add(CameraOnRoute(c, at));
    }
    out.sort((a, b) => a.atM.compareTo(b.atM));
    return out;
  }
}
