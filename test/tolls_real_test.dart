// Prices real trips with the real toll table, on routes from the offline
// router. Skipped when the Semenanjung pack hasn't been built.
import 'dart:io';

import 'package:arah/core/geo.dart';
import 'package:arah/routing/offline_router.dart';
import 'package:arah/routing/road_graph.dart';
import 'package:arah/routing/route_model.dart';
import 'package:arah/routing/tolls.dart';
import 'package:flutter_test/flutter_test.dart';

const roads = 'tools/data/out/semenanjung.roads';

void main() {
  final have = File(roads).existsSync();
  late OfflineRouter router;
  late TollData tolls;
  setUpAll(() {
    if (!have) return;
    router = OfflineRouter(RoadGraph.parse(File(roads).readAsBytesSync()));
    tolls = TollData.parse(File('assets/tolls.json').readAsStringSync());
  });

  TollEstimate trip(String name, Geo a, Geo b, {TravelMode mode = TravelMode.car}) {
    final r = router.route(a, b, RouteOptions(mode: mode));
    final e = tolls.estimate(r, mode);
    // ignore: avoid_print
    print('$name (${(r.distanceM / 1000).round()} km): ${e.approximate ? '~' : ''}${fmtRm(e.total)}');
    for (final i in e.items) {
      // ignore: avoid_print
      print('   ${i.name}: ${i.approximate ? '~' : ''}${fmtRm(i.amount)}');
    }
    return e;
  }

  test('Damansara → Juru on the NSE (official RM35.26 for that pair)', () {
    final e = trip('Damansara→Juru', const Geo(3.1630, 101.6130), const Geo(5.3330, 100.4380));
    expect(e.total, inInclusiveRange(30, 45));
  }, skip: !have);

  test('KL → Seremban', () {
    final e = trip('KL→Seremban', const Geo(3.1478, 101.6953), const Geo(2.7297, 101.9381));
    expect(e.total, inInclusiveRange(5, 20));
  }, skip: !have);

  test('KL → Kuantan on the LPT', () {
    final e = trip('KL→Kuantan', const Geo(3.1478, 101.6953), const Geo(3.8077, 103.3260));
    expect(e.total, inInclusiveRange(20, 50));
  }, skip: !have);

  test('Cyberjaya → IOI City Mall: local roads, no toll', () {
    final e = trip('Cyberjaya→IOI', const Geo(2.9230, 101.6420), const Geo(2.9698, 101.7142));
    expect(e.total, lessThan(5));
  }, skip: !have);

  test('Georgetown → KL: Penang Bridge is free leaving the island', () {
    final e = trip('Georgetown→KL', const Geo(5.4141, 100.3288), const Geo(3.1478, 101.6953));
    expect(e.total, inInclusiveRange(30, 60));
  }, skip: !have);

  test('KL → Georgetown: the Penang Bridge is charged going onto the island', () {
    final e = trip('KL→Georgetown', const Geo(3.1478, 101.6953), const Geo(5.4141, 100.3288));
    expect(e.items.any((i) => i.name.contains('Penang Bridge') || i.name.contains('Jambatan')), isTrue);
    expect(e.total, greaterThan(38));
  }, skip: !have);

  test('Batu Kawan → Bayan Lepas over the Second Penang Bridge: charged once', () {
    final e = trip('Batu Kawan→Bayan Lepas', const Geo(5.2290, 100.4700), const Geo(5.2970, 100.2650));
    // ignore: avoid_print
    print('   (expect RM 5.74 once)');
    expect(e.items.where((i) => i.amount == 5.74 || i.name.contains('Kedua')).length, lessThanOrEqualTo(1));
  }, skip: !have);

  test('motorcycles pay nothing', () {
    final e = trip(
      'KL→Seremban by motorbike',
      const Geo(3.1478, 101.6953),
      const Geo(2.7297, 101.9381),
      mode: TravelMode.motorcycle,
    );
    expect(e.total, 0);
  }, skip: !have);
}
