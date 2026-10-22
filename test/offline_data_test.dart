// Runs the offline router and search against the real Semenanjung pack built
// by tools/data/build_pack.py. Skipped when the pack hasn't been built.
import 'dart:io';

import 'package:arah/core/geo.dart';
import 'package:arah/nav/phrases.dart';
import 'package:arah/routing/offline_router.dart';
import 'package:arah/routing/road_graph.dart';
import 'package:arah/routing/route_model.dart';
import 'package:arah/search/offline_search.dart';
import 'package:flutter_test/flutter_test.dart';

const roads = 'tools/data/out/semenanjung.roads';
const search = 'tools/data/out/semenanjung.search';

void main() {
  final have = File(roads).existsSync() && File(search).existsSync();

  group('offline router (real data)', () {
    late OfflineRouter router;
    setUpAll(() {
      if (!have) return;
      final sw = Stopwatch()..start();
      router = OfflineRouter(RoadGraph.parse(File(roads).readAsBytesSync()));
      // ignore: avoid_print
      print('loaded ${router.g.nodeCount} nodes / ${router.g.edgeCount} edges in ${sw.elapsedMilliseconds} ms');
    });

    test('Cyberjaya → IOI City Mall: a sensible local route', () {
      final sw = Stopwatch()..start();
      final r = router.route(const Geo(2.9230, 101.6420), const Geo(2.9698, 101.7142), const RouteOptions());
      // ignore: avoid_print
      print(
        'cyberjaya→ioi: ${(r.distanceM / 1000).toStringAsFixed(1)} km, ${(r.durationS / 60).round()} min, '
        '${r.maneuvers.length} maneuvers, ${sw.elapsedMilliseconds} ms',
      );
      for (final m in r.maneuvers.take(12)) {
        // ignore: avoid_print
        print('  ${spokenPrompt(m, Lang.en)}  (${m.lengthM.round()} m)');
      }
      // Valhalla gave 15 km / 22 min for the same trip.
      expect(r.distanceM, inInclusiveRange(10000, 22000));
      expect(r.durationS, inInclusiveRange(10 * 60, 40 * 60));
      expect(r.maneuvers.first.turn, Turn.start);
      expect(isArrival(r.maneuvers.last.turn), isTrue);
    }, skip: !have);

    test('KL → Georgetown: crosses the peninsula and a bridge in reasonable time', () {
      final sw = Stopwatch()..start();
      final r = router.route(const Geo(3.1478, 101.6953), const Geo(5.4141, 100.3288), const RouteOptions());
      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print(
        'kl→penang: ${(r.distanceM / 1000).round()} km, ${(r.durationS / 3600).toStringAsFixed(1)} h, '
        'toll=${r.hasToll}, $ms ms',
      );
      expect(r.distanceM, inInclusiveRange(330000, 420000));
      expect(r.hasToll, isTrue);
    }, skip: !have);

    test('avoid tolls takes a different, slower road', () {
      final a = router.route(const Geo(3.1478, 101.6953), const Geo(2.7297, 101.9381), const RouteOptions());
      final b = router.route(
        const Geo(3.1478, 101.6953),
        const Geo(2.7297, 101.9381),
        const RouteOptions(avoidTolls: true),
      );
      // ignore: avoid_print
      print('kl→seremban: toll ${(a.durationS / 60).round()} min vs no-toll ${(b.durationS / 60).round()} min');
      expect(b.durationS, greaterThan(a.durationS));
    }, skip: !have);

    test('snaps a point on the PLUS expressway to the expressway itself', () {
      // On the North–South Expressway near Nilai, far from any junction.
      final s = router.snap(const Geo(2.8340, 101.7832), const RouteOptions());
      expect(s, isNotNull);
      expect(s!.distanceM, lessThan(60));
    }, skip: !have);
  });

  group('offline search (real data)', () {
    late OfflineSearch idx;
    setUpAll(() {
      if (have) idx = OfflineSearch.open(search);
    });

    test('Malaysian shorthand: "jln ampang" finds Jalan Ampang near KL', () {
      final r = idx.search('jln ampang', near: const Geo(3.1478, 101.6953));
      // ignore: avoid_print
      print(r.take(3).map((p) => '${p.name} — ${p.context}').join('\n'));
      expect(r.first.name.toLowerCase(), contains('jalan ampang'));
    }, skip: !have);

    test('a mall by name, as you type', () {
      final r = idx.search('ioi city', near: const Geo(2.92, 101.64));
      expect(r.any((p) => p.name.toLowerCase().contains('ioi city')), isTrue);
    }, skip: !have);

    test('petrol stations nearby by category', () {
      final r = idx.byKind(['fuel'], const Geo(2.92, 101.64));
      // ignore: avoid_print
      print(r.take(3).map((p) => '${p.name} ${distanceM(const Geo(2.92, 101.64), p.pos).round()} m').join('\n'));
      expect(r, isNotEmpty);
      expect(distanceM(const Geo(2.92, 101.64), r.first.pos), lessThan(5000));
    }, skip: !have);
  });
}
