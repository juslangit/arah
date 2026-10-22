import 'dart:io';

import 'package:arah/core/geo.dart';
import 'package:arah/nav/cameras.dart';
import 'package:arah/routing/route_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 10 km straight road going north.
ArahRoute north() {
  final pts = [for (var i = 0; i <= 100; i++) Geo(3.0 + i * 0.0009, 101.70)];
  return ArahRoute(points: pts, maneuvers: const [], distanceM: 10000, durationS: 400);
}

const data = '''
{"updated":"test","cameras":[
 {"id":"a","kind":"speed","lat":3.0200,"lon":101.70015,"maxspeed":90,"heading_deg":0},
 {"id":"b","kind":"speed","lat":3.0400,"lon":101.70010,"maxspeed":90,"heading_deg":180},
 {"id":"c","kind":"red_light","lat":3.0600,"lon":101.70000,"maxspeed":null,"heading_deg":null},
 {"id":"d","kind":"speed","lat":3.0500,"lon":101.70200,"maxspeed":60,"heading_deg":null},
 {"id":"u","kind":"speed","lat":3.0700,"lon":101.70005,"maxspeed":null,"heading_deg":null,"verified":false}
]}''';

void main() {
  final cams = CameraData.parse(data);

  test('cameras on the route, in order, with where they are', () {
    final on = cams.along(north());
    expect(on.map((c) => c.camera.id), ['a', 'c', 'u']);
    expect(on.first.atM, closeTo(2224, 20));
    expect(on.first.camera.maxspeed, 90);
  });

  test('a camera enforcing the other direction is left out', () {
    expect(cams.along(north()).any((c) => c.camera.id == 'b'), isFalse);
  });

  test('a camera 220 m off the road (a parallel road) is left out', () {
    expect(cams.along(north()).any((c) => c.camera.id == 'd'), isFalse);
  });

  test('unverified cameras are marked, and can be left out', () {
    expect(cams.cameras.firstWhere((c) => c.id == 'u').verified, isFalse);
    expect(cams.cameras.firstWhere((c) => c.id == 'a').verified, isTrue);
    expect(cams.along(north(), unverified: false).map((c) => c.camera.id), ['a', 'c']);
  });

  test('the shipped camera list parses and is all inside Malaysia', () {
    final real = CameraData.parse(File('assets/cameras.json').readAsStringSync());
    expect(real.cameras.where((c) => c.verified), hasLength(40));
    expect(real.cameras.where((c) => !c.verified), hasLength(27));
    for (final c in real.cameras) {
      expect(c.pos.lat, inInclusiveRange(0.8, 7.5));
      expect(c.pos.lon, inInclusiveRange(99.5, 119.5));
      // Not Singapore.
      expect(c.pos.lat < 1.47 && c.pos.lon > 103.6 && c.pos.lon < 104.1, isFalse, reason: c.id);
    }
  });
}
