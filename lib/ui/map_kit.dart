// Shared map pieces: icons drawn once into images the map can use, the
// route/report layers, and the turn-arrow icon for each maneuver.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../core/geo.dart';
import '../reports/reports.dart';
import '../routing/route_model.dart';

LatLng ll(Geo g) => LatLng(g.lat, g.lon);
Geo geo(LatLng l) => Geo(l.latitude, l.longitude);

IconData reportIcon(ReportKind k) => switch (k) {
  ReportKind.polis => Icons.local_police,
  ReportKind.kemalangan => Icons.car_crash,
  ReportKind.kesesakan => Icons.traffic,
  ReportKind.bahaya => Icons.warning_rounded,
  ReportKind.banjir => Icons.flood,
  ReportKind.ditutup => Icons.block,
};

Color reportColor(ReportKind k) => ArahColors.report[k.name]!;

IconData turnIcon(Maneuver m) => switch (m.turn) {
  Turn.start || Turn.startLeft || Turn.startRight => Icons.navigation,
  Turn.destination || Turn.destinationLeft || Turn.destinationRight => Icons.flag,
  Turn.becomes || Turn.straight || Turn.stayStraight || Turn.rampStraight => Icons.straight,
  Turn.slightRight => Icons.turn_slight_right,
  Turn.slightLeft => Icons.turn_slight_left,
  Turn.right => Icons.turn_right,
  Turn.left => Icons.turn_left,
  Turn.sharpRight => Icons.turn_sharp_right,
  Turn.sharpLeft => Icons.turn_sharp_left,
  Turn.uturnRight => Icons.u_turn_right,
  Turn.uturnLeft => Icons.u_turn_left,
  Turn.rampRight || Turn.exitRight => Icons.ramp_right,
  Turn.rampLeft || Turn.exitLeft => Icons.ramp_left,
  Turn.stayRight => Icons.fork_right,
  Turn.stayLeft => Icons.fork_left,
  Turn.merge || Turn.mergeLeft || Turn.mergeRight => Icons.merge,
  // Malaysia's roundabouts turn clockwise.
  Turn.roundaboutEnter || Turn.roundaboutExit => Icons.roundabout_left,
  Turn.ferryEnter || Turn.ferryExit => Icons.directions_boat,
};

/// Draws a round badge with a Material icon into PNG bytes.
Future<Uint8List> iconBadge(IconData icon, Color bg, {double size = 72, Color fg = Colors.white}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final r = size / 2;
  c.drawCircle(Offset(r, r + 2), r - 4, Paint()..color = Colors.black26);
  c.drawCircle(Offset(r, r), r - 4, Paint()..color = Colors.white);
  c.drawCircle(Offset(r, r), r - 9, Paint()..color = bg);
  final tp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(fontSize: size * 0.48, fontFamily: icon.fontFamily, package: icon.fontPackage, color: fg),
    )
    ..layout();
  tp.paint(c, Offset(r - tp.width / 2, r - tp.height / 2));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt() + 2);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// A teardrop pin for the chosen place.
Future<Uint8List> pinImage(Color color, {double w = 64, double h = 84}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final path = Path()
    ..moveTo(w / 2, h - 2)
    ..cubicTo(w * 0.15, h * 0.55, 2, h * 0.42, 2, w / 2)
    ..arcToPoint(Offset(w - 2, w / 2), radius: Radius.circular(w / 2 - 2))
    ..cubicTo(w - 2, h * 0.42, w * 0.85, h * 0.55, w / 2, h - 2)
    ..close();
  c.drawPath(path.shift(const Offset(0, 2)), Paint()..color = Colors.black26);
  c.drawPath(path, Paint()..color = color);
  c.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  c.drawCircle(Offset(w / 2, w / 2), w * 0.16, Paint()..color = Colors.white);
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt() + 2);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Map<String, dynamic> lineFeature(List<Geo> pts, {Map<String, dynamic> props = const {}, Object? id}) => {
  'type': 'Feature',
  if (id != null) 'id': id,
  'properties': props,
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      for (final p in pts) [p.lon, p.lat],
    ],
  },
};

Map<String, dynamic> pointFeature(Geo p, {Map<String, dynamic> props = const {}}) => {
  'type': 'Feature',
  'properties': props,
  'geometry': {
    'type': 'Point',
    'coordinates': [p.lon, p.lat],
  },
};

Map<String, dynamic> collection(List<Map<String, dynamic>> f) => {'type': 'FeatureCollection', 'features': f};

/// Adds Arah's own sources and layers on top of whatever map style loaded:
/// routes (alternatives grey under the chosen blue one), reports and a pin.
class MapLayers {
  final MapLibreMapController c;
  MapLayers(this.c);

  static const routes = 'arah-routes', reports = 'arah-reports', pin = 'arah-pin';

  Future<void> install() async {
    for (final k in ReportKind.values) {
      await c.addImage('report-${k.name}', await iconBadge(reportIcon(k), reportColor(k)));
    }
    await c.addImage('arah-pin', await pinImage(ArahColors.warn));
    await c.addImage('arah-stop', await iconBadge(Icons.flag, ArahColors.brand, size: 56));
    await c.addImage('arah-start', await iconBadge(Icons.trip_origin, ArahColors.route, size: 56));

    await c.addGeoJsonSource(routes, collection([]));
    await c.addLineLayer(
      routes,
      'arah-route-alt',
      const LineLayerProperties(lineColor: '#9AA4B2', lineWidth: 7, lineCap: 'round', lineJoin: 'round', lineOpacity: 0.9),
      filter: [
        '==',
        ['get', 'selected'],
        false,
      ],
    );
    await c.addLineLayer(
      routes,
      'arah-route-casing',
      const LineLayerProperties(lineColor: '#1B3FA6', lineWidth: 11, lineCap: 'round', lineJoin: 'round'),
      filter: [
        '==',
        ['get', 'selected'],
        true,
      ],
    );
    await c.addLineLayer(
      routes,
      'arah-route',
      const LineLayerProperties(lineColor: '#2F6BFF', lineWidth: 7, lineCap: 'round', lineJoin: 'round'),
      filter: [
        '==',
        ['get', 'selected'],
        true,
      ],
    );

    await c.addGeoJsonSource(reports, collection([]));
    await c.addSymbolLayer(
      reports,
      'arah-reports',
      const SymbolLayerProperties(
        iconImage: [
          'concat',
          'report-',
          ['get', 'kind'],
        ],
        iconSize: 0.62,
        iconAllowOverlap: true,
        iconOpacity: [
          'case',
          ['get', 'faded'],
          0.55,
          1.0,
        ],
      ),
    );

    await c.addGeoJsonSource(pin, collection([]));
    await c.addSymbolLayer(
      pin,
      'arah-pin',
      const SymbolLayerProperties(iconImage: ['get', 'icon'], iconSize: 0.6, iconAnchor: 'bottom', iconAllowOverlap: true),
    );
  }

  Future<void> showRoutes(List<ArahRoute> rs, int selected) async {
    // Alternatives first so the chosen route is drawn on top.
    final f = <Map<String, dynamic>>[];
    for (var i = 0; i < rs.length; i++) {
      if (i != selected) f.add(lineFeature(rs[i].points, props: {'selected': false, 'index': i}, id: i));
    }
    if (selected >= 0 && selected < rs.length) {
      f.add(lineFeature(rs[selected].points, props: {'selected': true, 'index': selected}, id: selected));
    }
    await c.setGeoJsonSource(routes, collection(f));
  }

  Future<void> showRemaining(List<Geo> pts) async => c.setGeoJsonSource(
    routes,
    collection([
      if (pts.length > 1) lineFeature(pts, props: {'selected': true}),
    ]),
  );

  Future<void> showReports(List<Report> rs) async {
    final now = DateTime.now();
    await c.setGeoJsonSource(
      reports,
      collection([
        for (final r in rs) pointFeature(r.pos, props: {'kind': r.kind.name, 'faded': r.faded(now), 'id': r.id}),
      ]),
    );
  }

  Future<void> showPins(List<(Geo, String)> pins) async => c.setGeoJsonSource(
    pin,
    collection([
      for (final (p, icon) in pins) pointFeature(p, props: {'icon': icon}),
    ]),
  );
}

/// Camera that fits a set of points, leaving room for UI at top and bottom.
CameraUpdate fitPoints(List<Geo> pts, {double top = 160, double bottom = 320, double side = 48}) {
  final b = Bounds.of(pts);
  return CameraUpdate.newLatLngBounds(
    LatLngBounds(southwest: LatLng(b.south, b.west), northeast: LatLng(b.north, b.east)),
    left: side,
    right: side,
    top: top,
    bottom: bottom,
  );
}
