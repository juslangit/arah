// Reads a .roads file (written by tools/data/build_pack.py) into typed
// arrays without copying, so a whole region's road network sits in a few
// flat lists the router can walk quickly.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/geo.dart';

class RoadClass {
  static const motorway = 0, trunk = 1, primary = 2, secondary = 3, tertiary = 4, unclassified = 5;
  static const residential = 6, service = 7, livingStreet = 8, track = 9;
  static const motorwayLink = 10, trunkLink = 11, primaryLink = 12, secondaryLink = 13, tertiaryLink = 14;
  static const ferry = 15;
  static bool isLink(int c) => c >= motorwayLink && c <= tertiaryLink;
  static bool isFast(int c) => c == motorway || c == trunk;
}

class EdgeFlag {
  static const toll = 1 << 4, roundabout = 1 << 5, car = 1 << 6, moto = 1 << 7;
  static const reversed = 1 << 8, tunnel = 1 << 9, highway = 1 << 10;
}

class RoadGraph {
  final int nodeCount, edgeCount;
  final Int32List nodeLat, nodeLon;
  final Uint8List nodeFlags;
  final Uint32List firstEdge;
  final Uint32List edgeTarget, edgeLenDm, edgeGeom, edgeName;
  final Uint16List edgeGeomCount, edgeFlags;
  final Uint8List edgeMaxspeed, edgeSpeed;
  final Int32List geomLat, geomLon;
  final Uint32List nameOffset;
  final Uint8List nameBlob;
  final int gridRows, gridCols;
  final double gridMinLat, gridMinLon, gridCell;
  final Uint32List gridStart, gridEdges;

  RoadGraph._({
    required this.nodeCount,
    required this.edgeCount,
    required this.nodeLat,
    required this.nodeLon,
    required this.nodeFlags,
    required this.firstEdge,
    required this.edgeTarget,
    required this.edgeLenDm,
    required this.edgeGeom,
    required this.edgeGeomCount,
    required this.edgeName,
    required this.edgeFlags,
    required this.edgeMaxspeed,
    required this.edgeSpeed,
    required this.geomLat,
    required this.geomLon,
    required this.nameOffset,
    required this.nameBlob,
    required this.gridRows,
    required this.gridCols,
    required this.gridMinLat,
    required this.gridMinLon,
    required this.gridCell,
    required this.gridStart,
    required this.gridEdges,
  });

  static RoadGraph parse(Uint8List bytes) {
    // Typed views need aligned offsets; copy once if the buffer isn't aligned.
    if (bytes.offsetInBytes % 4 != 0) bytes = Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(bytes);
    if (ascii.decode(bytes.sublist(0, 8)) != 'ARAHRD01') {
      throw const FormatException('not an Arah roads file');
    }
    var p = 8;
    int u32() {
      final v = bd.getUint32(p, Endian.little);
      p += 4;
      return v;
    }

    double f32() {
      final v = bd.getFloat32(p, Endian.little);
      p += 4;
      return v;
    }

    u32(); // version
    final n = u32(), e = u32(), g = u32(), m = u32(), b = u32(), rows = u32(), cols = u32(), k = u32();
    final minLat = f32(), minLon = f32(), cell = f32();
    final buf = bytes.buffer;
    final base = bytes.offsetInBytes;
    void align() => p = (p + 3) & ~3;
    Int32List i32(int len) {
      final v = buf.asInt32List(base + p, len);
      p += len * 4;
      return v;
    }

    Uint32List w32(int len) {
      final v = buf.asUint32List(base + p, len);
      p += len * 4;
      return v;
    }

    Uint16List w16(int len) {
      final v = buf.asUint16List(base + p, len);
      p += len * 2;
      align();
      return v;
    }

    Uint8List w8(int len) {
      final v = buf.asUint8List(base + p, len);
      p += len;
      align();
      return v;
    }

    final nodeLat = i32(n), nodeLon = i32(n);
    final nodeFlags = w8(n);
    final firstEdge = w32(n + 1);
    final target = w32(e), len = w32(e), geom = w32(e);
    final geomCount = w16(e);
    final name = w32(e);
    final flags = w16(e);
    final maxspeed = w8(e), speed = w8(e);
    final gLat = i32(g), gLon = i32(g);
    final nameOffset = w32(m + 1);
    final blob = w8(b);
    final gridStart = w32(rows * cols + 1);
    final gridEdges = w32(k);
    return RoadGraph._(
      nodeCount: n,
      edgeCount: e,
      nodeLat: nodeLat,
      nodeLon: nodeLon,
      nodeFlags: nodeFlags,
      firstEdge: firstEdge,
      edgeTarget: target,
      edgeLenDm: len,
      edgeGeom: geom,
      edgeGeomCount: geomCount,
      edgeName: name,
      edgeFlags: flags,
      edgeMaxspeed: maxspeed,
      edgeSpeed: speed,
      geomLat: gLat,
      geomLon: gLon,
      nameOffset: nameOffset,
      nameBlob: blob,
      gridRows: rows,
      gridCols: cols,
      gridMinLat: minLat,
      gridMinLon: minLon,
      gridCell: cell,
      gridStart: gridStart,
      gridEdges: gridEdges,
    );
  }

  Geo node(int i) => Geo(nodeLat[i] / 1e6, nodeLon[i] / 1e6);
  int roadClass(int e) => edgeFlags[e] & 0xF;
  bool has(int e, int flag) => edgeFlags[e] & flag != 0;
  double lengthM(int e) => edgeLenDm[e] / 10;

  /// Edge source isn't stored; find it by binary search over firstEdge.
  int source(int e) {
    var lo = 0, hi = nodeCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (firstEdge[mid] <= e) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Every point of edge e in travel order, end nodes included.
  List<Geo> shape(int e, [int? from]) {
    final a = from ?? source(e);
    final out = <Geo>[node(a)];
    final gs = edgeGeom[e], gc = edgeGeomCount[e];
    if (has(e, EdgeFlag.reversed)) {
      for (var i = gc - 1; i >= 0; i--) {
        out.add(Geo(geomLat[gs + i] / 1e6, geomLon[gs + i] / 1e6));
      }
    } else {
      for (var i = 0; i < gc; i++) {
        out.add(Geo(geomLat[gs + i] / 1e6, geomLon[gs + i] / 1e6));
      }
    }
    out.add(node(edgeTarget[e]));
    return out;
  }

  final _names = <int, List<String>>{};

  /// [name, ref, destination] for the road an edge is on.
  List<String> names(int e) {
    final id = edgeName[e];
    return _names.putIfAbsent(id, () {
      if (id == 0) return const ['', '', ''];
      final s = utf8.decode(nameBlob.sublist(nameOffset[id], nameOffset[id + 1]));
      final parts = s.split('\x1f');
      while (parts.length < 3) {
        parts.add('');
      }
      return parts;
    });
  }

  /// Is there an edge from b back to a (a two-way road)?
  int reverseOf(int e, int a) {
    final b = edgeTarget[e];
    for (var x = firstEdge[b]; x < firstEdge[b + 1]; x++) {
      if (edgeTarget[x] == a && edgeGeom[x] == edgeGeom[e] && edgeGeomCount[x] == edgeGeomCount[e]) return x;
    }
    return -1;
  }

  /// Edges listed in the square ring of grid cells [ring] steps away from p's
  /// cell. Two-way roads are listed once; use [reverseOf] for the other way.
  Iterable<int> edgesInRing(Geo p, int ring) sync* {
    final r0 = ((p.lat - gridMinLat) / gridCell).floor();
    final c0 = ((p.lon - gridMinLon) / gridCell).floor();
    for (var r = r0 - ring; r <= r0 + ring; r++) {
      for (var c = c0 - ring; c <= c0 + ring; c++) {
        if (math.max((r - r0).abs(), (c - c0).abs()) != ring) continue;
        if (r < 0 || c < 0 || r >= gridRows || c >= gridCols) continue;
        final cell = r * gridCols + c;
        for (var i = gridStart[cell]; i < gridStart[cell + 1]; i++) {
          yield gridEdges[i];
        }
      }
    }
  }

  /// Approximate size of one grid cell in metres (the smaller side).
  double get cellMeters => gridCell * 111000 * math.cos(gridMinLat * math.pi / 180);

  bool covers(Geo p) {
    final r = ((p.lat - gridMinLat) / gridCell).floor();
    final c = ((p.lon - gridMinLon) / gridCell).floor();
    return r >= 0 && c >= 0 && r < gridRows && c < gridCols;
  }
}
