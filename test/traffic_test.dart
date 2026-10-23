import 'package:arah/core/geo.dart';
import 'package:arah/routing/route_model.dart';
import 'package:flutter_test/flutter_test.dart';

ArahRoute straight(double durationS) {
  // About 11 km due north, in 100 points.
  final pts = [for (var i = 0; i <= 100; i++) Geo(3.0 + i * 0.001, 101.6)];
  return ArahRoute(points: pts, maneuvers: const [], distanceM: cumulativeDistances(pts).last, durationS: durationS);
}

void main() {
  test('time left uses the route estimate when there is no traffic info', () {
    final r = straight(1800);
    final total = r.cumDist.last;
    expect(r.etaS, 1800);
    expect(r.remainingS(total / 2), closeTo(900, 1));
  });

  test('live traffic replaces the estimate: 30 min clear becomes 1 hour', () {
    final r = straight(1800)..liveS = 3600;
    final total = r.cumDist.last;
    expect(r.etaS, 3600);
    expect(r.remainingS(total), closeTo(3600, 1));
    expect(r.remainingS(total / 2), closeTo(1800, 1));
  });

  test('a traffic check mid-route counts from where it was taken', () {
    final r = straight(1800);
    final total = r.cumDist.last;
    r
      ..liveS = 1200 // 20 min for the last half, measured at the halfway point
      ..liveFromM = total / 2;
    expect(r.remainingS(total / 2), closeTo(1200, 1));
    expect(r.remainingS(total / 4), closeTo(600, 1));
    expect(r.etaS, 1800); // whole-route figure stays the router's
  });

  test('fastest route counts live traffic', () {
    final a = straight(1800)..liveS = 3600; // usually quickest, jammed now
    final b = straight(2400)..liveS = 2500;
    expect(fastestRoute([a, b]), 1);
    expect(fastestRoute([straight(1800), straight(2400)]), 0);
  });
}
