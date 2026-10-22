// Toll price estimate for a route, like Waze. Malaysia has two kinds of toll:
//  - open: a fixed charge at the plaza (Sungai Besi, Batu Tiga, …)
//  - closed: PLUS and others charge by where you enter and where you leave.
// Plaza locations come from OpenStreetMap; prices from assets/tolls.json,
// gathered from LLM and the concessionaires (tools/data/tolls/NOTES.md).
import 'dart:convert';
import 'dart:math' as math;

import '../core/geo.dart';
import 'route_model.dart';

class OpenPlaza {
  final String id, name;
  final Geo pos;
  final double car, moto;
  final bool bothDirections;
  final double? chargedHeading;
  OpenPlaza(this.id, this.name, this.pos, this.car, this.moto, this.bothDirections, this.chargedHeading);
}

class Gate {
  final String id, name;
  final Geo pos;
  Gate(this.id, this.name, this.pos);
}

class ClosedSystem {
  final String id, name;
  final double carPerKm, motoPerKm, minCar;
  final List<Gate> gates;
  final Map<String, (double, double)> pairs; // "from|to" → (car, moto)
  ClosedSystem(this.id, this.name, this.carPerKm, this.motoPerKm, this.minCar, this.gates, this.pairs);

  (double, double)? pair(String a, String b) => pairs['$a|$b'] ?? pairs['$b|$a'];
}

class TollItem {
  final String name;
  final double amount;
  final bool approximate;
  const TollItem(this.name, this.amount, {this.approximate = false});
}

class TollEstimate {
  final List<TollItem> items;
  const TollEstimate(this.items);
  double get total => items.fold(0, (a, i) => a + i.amount);
  bool get approximate => items.any((i) => i.approximate);
  bool get isEmpty => items.isEmpty;
}

class TollData {
  final String updated;
  final List<OpenPlaza> plazas;
  final List<ClosedSystem> closed;
  TollData(this.updated, this.plazas, this.closed);

  static TollData parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    return TollData(
      j['updated'] as String? ?? '',
      [
        for (final p in (j['plazas'] as List? ?? const []).cast<Map<String, dynamic>>())
          if (p['lat'] != null)
            OpenPlaza(
              p['id'] as String,
              p['name'] as String,
              Geo(d(p['lat']), d(p['lon'])),
              d(p['car']),
              d(p['moto']),
              p['both_directions'] != false,
              (p['charged_heading_deg'] as num?)?.toDouble(),
            ),
      ],
      [
        for (final c in (j['closed'] as List? ?? const []).cast<Map<String, dynamic>>())
          ClosedSystem(
            c['id'] as String,
            c['name'] as String,
            d(c['car_per_km']),
            d(c['moto_per_km']),
            d(c['min_car']),
            [
              for (final g in (c['gates'] as List? ?? const []).cast<Map<String, dynamic>>())
                if (g['lat'] != null) Gate(g['id'] as String, g['name'] as String, Geo(d(g['lat']), d(g['lon']))),
            ],
            {
              for (final p in (c['pairs'] as List? ?? const []).cast<Map<String, dynamic>>())
                '${p['from']}|${p['to']}': (d(p['car']), d(p['moto'])),
            },
          ),
      ],
    );
  }

  /// How close the route must pass to count as going through a plaza. Plazas
  /// are wide (a dozen booths), and their OSM point is the middle of them.
  static const passM = 90.0;

  TollEstimate estimate(ArahRoute r, TravelMode mode) {
    final moto = mode == TravelMode.motorcycle;
    final pts = r.points;
    if (pts.length < 2) return const TollEstimate([]);
    final box = Bounds.of(pts);
    const pad = 0.002;
    bool near(Geo g) => g.lat > box.south - pad && g.lat < box.north + pad && g.lon > box.west - pad && g.lon < box.east + pad;

    final items = <(int, TollItem)>[];

    for (final p in plazas) {
      if (!near(p.pos)) continue;
      final hit = _closestIndex(pts, p.pos);
      if (hit == null) continue;
      if (!p.bothDirections && p.chargedHeading != null) {
        final i = hit.clamp(0, pts.length - 2);
        final heading = bearingDeg(pts[i], pts[i + 1]);
        if (angleDiff(heading, p.chargedHeading!).abs() > 70) continue; // the free direction
      }
      final amount = moto ? p.moto : p.car;
      if (amount > 0) items.add((hit, TollItem(p.name, amount)));
    }

    for (final sys in closed) {
      final passed = <(int, Gate)>[];
      for (final g in sys.gates) {
        if (!near(g.pos)) continue;
        final hit = _closestIndex(pts, g.pos);
        if (hit != null) passed.add((hit, g));
      }
      if (passed.isEmpty) continue;
      passed.sort((a, b) => a.$1.compareTo(b.$1));
      final entry = passed.first, exit = passed.last;
      final km = (r.cumDist[exit.$1] - r.cumDist[entry.$1]) / 1000;
      final known = passed.length >= 2 ? sys.pair(entry.$2.id, exit.$2.id) : null;
      if (known != null) {
        final amount = moto ? known.$2 : known.$1;
        if (amount > 0) items.add((entry.$1, TollItem('${entry.$2.name} → ${exit.$2.name}', amount)));
      } else if (passed.length >= 2 && km > 0.5) {
        final perKm = moto ? sys.motoPerKm : sys.carPerKm;
        final amount = moto ? km * perKm : math.max(sys.minCar, km * perKm);
        if (amount > 0) {
          items.add((entry.$1, TollItem('${entry.$2.name} → ${exit.$2.name}', _round10sen(amount), approximate: true)));
        }
      } else if (passed.length == 1 && !moto && sys.minCar > 0) {
        // Only one gate on the route (it starts or ends inside the system).
        items.add((entry.$1, TollItem(entry.$2.name, sys.minCar, approximate: true)));
      }
    }

    items.sort((a, b) => a.$1.compareTo(b.$1));
    return TollEstimate([for (final (_, i) in items) i]);
  }

  static double _round10sen(double v) => (v * 10).round() / 10;

  /// Index of the route point nearest to [g] if the route passes within passM.
  static int? _closestIndex(List<Geo> pts, Geo g) {
    var best = passM;
    int? bestI;
    for (var i = 0; i < pts.length - 1; i++) {
      // Cheap reject before projecting: both ends far away in latitude.
      if ((pts[i].lat - g.lat).abs() > 0.02 && (pts[i + 1].lat - g.lat).abs() > 0.02) continue;
      final pr = projectOnSegment(g, pts[i], pts[i + 1]);
      if (pr.distanceM < best) {
        best = pr.distanceM;
        bestI = pr.t < 0.5 ? i : i + 1;
      }
    }
    return bestI;
  }
}

String fmtRm(double v) => 'RM ${v.toStringAsFixed(2)}';
