import 'package:arah/core/geo.dart';
import 'package:arah/routing/route_model.dart';
import 'package:arah/routing/tolls.dart';
import 'package:flutter_test/flutter_test.dart';

/// A made-up 20 km straight road going north from (3.00, 101.70).
ArahRoute north() {
  final pts = [for (var i = 0; i <= 200; i++) Geo(3.0 + i * 0.0009, 101.70)];
  return ArahRoute(points: pts, maneuvers: const [], distanceM: 20000, durationS: 900);
}

const data = '''
{"updated":"2026-10-22","plazas":[
  {"id":"a","name":"Plaza A","lat":3.0450,"lon":101.7003,"car":1.30,"moto":0},
  {"id":"b","name":"Plaza B (southbound only)","lat":3.0900,"lon":101.7002,"car":2.00,"moto":1.00,
   "both_directions":false,"charged_heading_deg":180},
  {"id":"far","name":"Elsewhere","lat":3.0450,"lon":101.7200,"car":9.99,"moto":0}
 ],
 "closed":[{"id":"plus","name":"PLUS","car_per_km":0.10,"moto_per_km":0,"min_car":1.0,
   "gates":[{"id":"g1","name":"Gate 1","lat":3.0100,"lon":101.7001},
            {"id":"g2","name":"Gate 2","lat":3.1500,"lon":101.7001},
            {"id":"g3","name":"Gate 3","lat":3.1700,"lon":101.6999}],
   "pairs":[{"from":"g1","to":"g2","car":12.40,"moto":0}]}]}
''';

void main() {
  final t = TollData.parse(data);

  test('open plaza on the route is charged; one 2 km away is not', () {
    final e = t.estimate(north(), TravelMode.car);
    expect(e.items.map((i) => i.name), contains('Plaza A'));
    expect(e.items.map((i) => i.name), isNot(contains('Elsewhere')));
  });

  test('one-way plaza is free in the other direction', () {
    final e = t.estimate(north(), TravelMode.car);
    expect(e.items.map((i) => i.name), isNot(contains('Plaza B (southbound only)')));
  });

  test('closed system: entry and exit use the official pair, not per-km', () {
    final pts = north().points.where((p) => p.lat <= 3.155).toList();
    final r = ArahRoute(points: pts, maneuvers: const [], distanceM: 17000, durationS: 800);
    final e = t.estimate(r, TravelMode.car);
    final plus = e.items.firstWhere((i) => i.name.startsWith('Gate 1'));
    expect(plus.amount, 12.40);
    expect(plus.approximate, isFalse);
    expect(e.total, closeTo(12.40 + 1.30, 1e-9));
  });

  test('unknown pair falls back to per-km and says it is approximate', () {
    final e = t.estimate(north(), TravelMode.car);
    // Passes g1, g2, g3: entry g1, exit g3, no official pair → 0.10/km.
    final plus = e.items.firstWhere((i) => i.name.startsWith('Gate 1'));
    expect(plus.approximate, isTrue);
    expect(plus.amount, closeTo(1.8, 0.05)); // ~17.7 km × RM 0.10
    expect(e.approximate, isTrue);
  });

  test('motorcycles pay the motorcycle rate (often nothing)', () {
    final e = t.estimate(north(), TravelMode.motorcycle);
    expect(e.total, 0);
  });
}
