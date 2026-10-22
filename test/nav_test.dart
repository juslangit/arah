import 'package:arah/core/geo.dart';
import 'package:arah/nav/nav_engine.dart';
import 'package:arah/nav/phrases.dart';
import 'package:arah/nav/voice_planner.dart';
import 'package:arah/routing/route_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// An L-shaped test route in KL: 2 km east along lat 3.0, then 1 km north.
/// Points every ~111 m so snapping has real segments to work with.
ArahRoute lRoute() {
  final pts = <Geo>[];
  for (var i = 0; i <= 18; i++) {
    pts.add(Geo(3.0, 101.0 + i * 0.001));
  }
  final corner = pts.length - 1;
  for (var i = 1; i <= 9; i++) {
    pts.add(Geo(3.0 + i * 0.001, 101.018));
  }
  final cum = cumulativeDistances(pts);
  return ArahRoute(
    points: pts,
    maneuvers: [
      const Maneuver(turn: Turn.start, shapeIndex: 0, street: 'Jalan Satu'),
      Maneuver(turn: Turn.left, shapeIndex: corner, street: 'Jalan Ampang'),
      Maneuver(turn: Turn.destinationRight, shapeIndex: pts.length - 1),
    ],
    distanceM: cum.last,
    durationS: cum.last / 10,
  );
}

Fix at(Geo p, int sec, {double speed = 13.9, double? heading = 90, double acc = 5}) =>
    Fix(p, accuracyM: acc, speedMps: speed, headingDeg: heading, time: DateTime(2026, 10, 22, 8, 0, sec));

void main() {
  group('geo', () {
    test('distance of 0.001 deg longitude at the equator-ish is ~111 m', () {
      expect(distanceM(const Geo(3, 101), const Geo(3, 101.001)), closeTo(111, 1));
    });
    test('polyline6 round trip of a known string', () {
      // Valhalla docs example shape decodes to a list of points.
      final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5);
      expect(pts.first.lat, closeTo(38.5, 1e-6));
      expect(pts.first.lon, closeTo(-120.2, 1e-6));
      expect(pts.length, 3);
    });
    test('angleDiff wraps', () {
      expect(angleDiff(350, 10), closeTo(20, 1e-9));
      expect(angleDiff(10, 350), closeTo(-20, 1e-9));
    });
  });

  group('nav engine', () {
    test('snaps a fix 15 m off the road onto it and finds the next turn', () {
      final e = NavEngine(lRoute());
      final u = e.update(at(const Geo(3.000135, 101.005), 0)); // ~15 m north of the road
      expect(u.onRoute, isTrue);
      expect(u.position.lat, closeTo(3.0, 1e-6));
      expect(u.nextIndex, 1);
      expect(u.toNextM, closeTo(13 * 111.2, 5));
    });

    test('needs 3 fixes and 4 s off the road before calling off-route', () {
      final e = NavEngine(lRoute());
      e.update(at(const Geo(3.0, 101.002), 0));
      final off = const Geo(3.001, 101.004); // ~111 m north of the road
      expect(e.update(at(off, 1)).event, NavEvent.none);
      expect(e.update(at(off, 2)).event, NavEvent.none);
      expect(e.update(at(off, 3)).event, NavEvent.none); // 3 fixes, only 2 s
      expect(e.update(at(off, 5)).event, NavEvent.offRoute);
    });

    test('ignores a single wild fix with poor accuracy', () {
      final e = NavEngine(lRoute());
      e.update(at(const Geo(3.0, 101.002), 0));
      for (var s = 1; s < 10; s++) {
        expect(e.update(at(const Geo(3.002, 101.004), s, acc: 80)).event, NavEvent.none);
      }
    });

    test('driving the wrong way triggers a reroute after 5 s', () {
      final e = NavEngine(lRoute());
      e.update(at(const Geo(3.0, 101.010), 0));
      NavEvent last = NavEvent.none;
      // 30 m off the road, heading west against the route.
      for (var s = 1; s <= 7; s++) {
        last = e.update(at(Geo(3.00027, 101.010 - s * 0.0001), s, heading: 270)).event;
      }
      expect(last, NavEvent.offRoute);
    });

    test('arrives within 20 m of the end', () {
      final r = lRoute();
      final e = NavEngine(r);
      e.update(at(const Geo(3.0, 101.002), 0));
      final u = e.update(at(Geo(r.end.lat - 0.0001, r.end.lon), 1));
      expect(u.event, NavEvent.arrived);
    });

    test('remaining distance shrinks as we drive', () {
      final e = NavEngine(lRoute());
      final a = e.update(at(const Geo(3.0, 101.001), 0));
      final b = e.update(at(const Geo(3.0, 101.010), 60));
      expect(b.remainingM, lessThan(a.remainingM));
      expect(a.remainingM - b.remainingM, closeTo(9 * 111.2, 5));
    });
  });

  group('phrases', () {
    test('BM and EN turn prompts', () {
      const m = Maneuver(turn: Turn.right, shapeIndex: 0, street: 'Jalan Ampang');
      expect(spokenPrompt(m, Lang.ms, distanceM: 300), 'Dalam 300 meter, belok kanan ke Jalan Ampang.');
      expect(spokenPrompt(m, Lang.en, distanceM: 300), 'In 300 metres, turn right onto Jalan Ampang.');
    });
    test('roundabout exit number and expressway exit', () {
      const r = Maneuver(turn: Turn.roundaboutEnter, shapeIndex: 0, roundaboutExit: 3);
      expect(bannerText(r, Lang.ms), 'Di bulatan, ambil susur keluar ketiga');
      const x = Maneuver(turn: Turn.exitLeft, shapeIndex: 0, toward: 'Seremban', exitNumber: '225');
      expect(spokenPrompt(x, Lang.ms, distanceM: 2000), 'Dalam 2 kilometer, keluar di sebelah kiri arah Seremban.');
    });
    test('then-chaining', () {
      const a = Maneuver(turn: Turn.left, shapeIndex: 0);
      const b = Maneuver(turn: Turn.right, shapeIndex: 0);
      expect(spokenPrompt(a, Lang.en, then: b, thenGapM: 30), 'Turn left, then turn right.');
      expect(spokenPrompt(a, Lang.ms, then: b, thenGapM: 200), 'Belok kiri, kemudian dalam 200 meter belok kanan.');
    });
    test('distances', () {
      expect(displayDistance(1234), '1.2 km');
      expect(displayDistance(437), '450 m');
      expect(displayDistance(84), '80 m');
      expect(spokenDistance(1900, Lang.en), '2 kilometres');
      expect(spokenDistance(1400, Lang.ms), '1.5 kilometer');
    });
    test('refs are spelled out for speech', () {
      const m = Maneuver(turn: Turn.merge, shapeIndex: 0, ref: 'E1');
      expect(spokenPrompt(m, Lang.en), 'Merge onto E 1.');
      expect(bannerText(m, Lang.en), 'Merge onto E1');
    });
  });

  group('voice planner', () {
    test('town speed: one "in 300 m" then one "now", nothing else', () {
      final r = lRoute();
      final e = NavEngine(r);
      final v = VoicePlanner(r, lang: Lang.en);
      final said = <String>[];
      // Drive the 2 km east leg at 50 km/h (13.9 m/s), one fix per second.
      for (var s = 0; s < 150; s++) {
        final lon = 101.0 + (13.9 * s) / 111200;
        if (lon > 101.018) break;
        final u = e.update(at(Geo(3.0, lon), s));
        final p = v.next(u, DateTime(2026, 10, 22, 8, 0, s));
        if (p != null) said.add(p.text);
      }
      expect(said.where((t) => t.startsWith('In 300')).length + said.where((t) => t.startsWith('In 350')).length, 1);
      expect(said.where((t) => t.startsWith('Turn left onto Jalan Ampang')).length, 1);
      expect(said.length, 2);
    });

    test('expressway speed adds an early prompt', () {
      expect(distancesFor(110).early, 2000);
      expect(distancesFor(75).mid, 500);
      expect(distancesFor(20).now, 30);
      expect(distancesFor(110, bluetooth: true).now, closeTo(250 + 110 / 3.6 * 1.5, 0.01));
    });
  });
}
