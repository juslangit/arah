// Real trips against the shipped camera list, on offline-router routes.
import 'dart:io';

import 'package:arah/core/geo.dart';
import 'package:arah/nav/cameras.dart';
import 'package:arah/routing/offline_router.dart';
import 'package:arah/routing/road_graph.dart';
import 'package:arah/routing/route_model.dart';
import 'package:flutter_test/flutter_test.dart';

const roads = 'tools/data/out/semenanjung.roads';

void main() {
  final have = File(roads).existsSync();
  late OfflineRouter router;
  late CameraData cams;
  setUpAll(() {
    if (!have) return;
    router = OfflineRouter(RoadGraph.parse(File(roads).readAsBytesSync()));
    cams = CameraData.parse(File('assets/cameras.json').readAsStringSync());
  });

  List<CameraOnRoute> trip(String name, Geo a, Geo b) {
    final r = router.route(a, b, const RouteOptions());
    final on = cams.along(r);
    // ignore: avoid_print
    print('$name (${(r.distanceM / 1000).round()} km): ${on.length} cameras');
    for (final c in on) {
      // ignore: avoid_print
      print(
        '   km ${(c.atM / 1000).toStringAsFixed(1)}  ${c.camera.kind.name} ${c.camera.maxspeed ?? '-'}  ${c.camera.road}${c.camera.verified ? '' : '  (unverified)'}',
      );
    }
    return on;
  }

  test('KL → Ipoh and back: NSE cameras, each direction its own', () {
    final up = trip('KL→Ipoh', const Geo(3.1478, 101.6953), const Geo(4.5975, 101.0901));
    final down = trip('Ipoh→KL', const Geo(4.5975, 101.0901), const Geo(3.1478, 101.6953));
    expect(up.length + down.length, greaterThan(0));
  }, skip: !have);

  test(
    'KL → Seremban',
    () => trip('KL→Seremban', const Geo(3.1478, 101.6953), const Geo(2.7297, 101.9381)),
    skip: !have,
  );
  test('KL → Johor Bahru', () => trip('KL→JB', const Geo(3.1478, 101.6953), const Geo(1.4927, 103.7414)), skip: !have);
  test(
    'KL → Alor Setar',
    () => trip('KL→Alor Setar', const Geo(3.1478, 101.6953), const Geo(6.1248, 100.3678)),
    skip: !have,
  );

  test('Melaka city and Ipoh town: unverified red-light cameras show up', () {
    final m = trip('Melaka Sentral→Bandar Hilir', const Geo(2.2160, 102.2470), const Geo(2.1920, 102.2490));
    final i = trip('Ipoh town→Jalan Kuala Kangsar', const Geo(4.5975, 101.0901), const Geo(4.6400, 101.0950));
    expect([...m, ...i].where((c) => !c.camera.verified), isNotEmpty);
  }, skip: !have);
}
