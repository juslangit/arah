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

  /// Not charged when the trip leaves a closed system at one of these gates,
  /// because that fare already includes it (Second Penang Bridge at Bandar Cassia).
  final List<String> skipIfClosedExit;
  OpenPlaza(this.id, this.name, this.pos, this.car, this.moto, this.bothDirections, this.chargedHeading, this.skipIfClosedExit);
}

class Gate {
  final String id, name;
  final Geo pos;

  /// Only a gate when travelling this way (Penang Bridge: island-bound only).
  final double? chargedHeading;
  Gate(this.id, this.name, this.pos, this.chargedHeading);
}

class ClosedSystem {
  final String id, name;
  final double carPerKm, motoPerKm, minCar;
  final double? maxCar;
  final List<Gate> gates;
  final Map<String, (double, double)> pairs; // "from|to" → (car, moto)
  ClosedSystem(this.id, this.name, this.carPerKm, this.motoPerKm, this.minCar, this.maxCar, this.gates, this.pairs);

  /// Fares can differ by direction (half interchanges, bridge legs): the exact
  /// direction first, the reverse only for gates that charge both ways.
  (double, double)? pair(Gate a, Gate b) {
    final exact = pairs['${a.id}|${b.id}'];
    if (exact != null) return exact;
    if (a.chargedHeading != null || b.chargedHeading != null) return null;
    return pairs['${b.id}|${a.id}'];
  }
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
              [for (final x in (p['skip_if_closed_exit'] as List? ?? const [])) '$x'],
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
            (c['max_car'] as num?)?.toDouble(),
            [
              for (final g in (c['gates'] as List? ?? const []).cast<Map<String, dynamic>>())
                if (g['lat'] != null)
                  Gate(
                    g['id'] as String,
                    g['name'] as String,
                    Geo(d(g['lat']), d(g['lon'])),
                    (g['charged_heading_deg'] as num?)?.toDouble(),
                  ),
            ],
            {
              for (final p in (c['pairs'] as List? ?? const []).cast<Map<String, dynamic>>())
                '${p['from']}|${p['to']}': (d(p['car']), d(p['moto'])),
            },
          ),
      ],
    );
  }

  /// How close the route must pass to count as going through. Open plazas sit
  /// across the carriageway; closed-system gates sit on interchange ramps, and a
  /// route on the main road can pass 50–150 m from one without using it.
  static const plazaM = 75.0, gateM = 45.0;

  TollEstimate estimate(ArahRoute r, TravelMode mode) {
    final moto = mode == TravelMode.motorcycle;
    final pts = r.points;
    if (pts.length < 2) return const TollEstimate([]);
    final box = Bounds.of(pts);
    const pad = 0.002;
    bool near(Geo g) =>
        g.lat > box.south - pad && g.lat < box.north + pad && g.lon > box.west - pad && g.lon < box.east + pad;
    double headingAt(int i) {
      final j = i.clamp(0, pts.length - 2);
      return bearingDeg(pts[j], pts[j + 1]);
    }

    bool wrongWay(double? charged, int i) => charged != null && angleDiff(headingAt(i), charged).abs() > 70;

    final items = <(int, TollItem)>[];
    final closedExits = <String>{};

    for (final sys in closed) {
      final passed = <(int, Gate)>[];
      for (final g in sys.gates) {
        if (!near(g.pos)) continue;
        final hit = _closestIndex(pts, g.pos, gateM);
        if (hit == null || wrongWay(g.chargedHeading, hit)) continue;
        passed.add((hit, g));
      }
      if (passed.isEmpty) continue;
      passed.sort((a, b) => a.$1.compareTo(b.$1));
      // Entry = first gate, exit = last; gates in between are interchanges the
      // route drove past on the main road.
      final entry = passed.first, exit = passed.last;
      if (passed.length == 1) {
        // A lone barrier (Penang Bridge, Tanjung Kupang): its fixed charge.
        final self = sys.pairs['${entry.$2.id}|${entry.$2.id}'];
        if (self != null) {
          final amount = moto ? self.$2 : self.$1;
          if (amount > 0) items.add((entry.$1, TollItem(entry.$2.name, amount)));
        } else if (!moto && sys.minCar > 0) {
          // The trip starts or ends inside the system: at least the minimum.
          items.add((entry.$1, TollItem(entry.$2.name, sys.minCar, approximate: true)));
        }
        continue;
      }
      closedExits.add(exit.$2.id);
      final known = sys.pair(entry.$2, exit.$2);
      final label = '${entry.$2.name} → ${exit.$2.name}';
      if (known != null) {
        final amount = moto ? known.$2 : known.$1;
        if (amount > 0) items.add((entry.$1, TollItem(label, amount)));
      } else {
        final km = (r.cumDist[exit.$1] - r.cumDist[entry.$1]) / 1000;
        var amount = km * (moto ? sys.motoPerKm : sys.carPerKm);
        if (!moto) amount = math.max(sys.minCar, amount);
        if (!moto && sys.maxCar != null) amount = math.min(sys.maxCar!, amount);
        if (amount > 0) items.add((entry.$1, TollItem(label, _round10sen(amount), approximate: true)));
      }
    }

    for (final p in plazas) {
      if (!near(p.pos)) continue;
      final hit = _closestIndex(pts, p.pos, plazaM);
      if (hit == null) continue;
      if (!p.bothDirections && wrongWay(p.chargedHeading, hit)) continue; // the free direction
      if (p.skipIfClosedExit.any(closedExits.contains)) continue; // already in the closed fare
      final amount = moto ? p.moto : p.car;
      if (amount > 0) items.add((hit, TollItem(p.name, amount)));
    }

    items.sort((a, b) => a.$1.compareTo(b.$1));
    return TollEstimate([for (final (_, i) in items) i]);
  }

  static double _round10sen(double v) => (v * 10).round() / 10;

  /// Index of the route point nearest to [g] if the route passes within [within] m.
  static int? _closestIndex(List<Geo> pts, Geo g, double within) {
    var best = within;
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
