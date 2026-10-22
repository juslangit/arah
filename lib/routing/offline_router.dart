// Routing with no internet: A* over the region's road network, fastest
// time first. It also writes the turn-by-turn maneuvers itself by reading the
// junction geometry, the way Organic Maps' turns logic does (app study §A1.3).
//
// Known limits for v1: no turn restrictions ("no right turn" signs) and no
// turn costs, so an offline route can occasionally include a turn the online
// router would avoid. Online routing is always preferred when available.
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/geo.dart';
import 'road_graph.dart';
import 'route_model.dart';

class EdgeSnap {
  final int edge; // directed edge from node a to node b
  final int from; // node a
  final int seg; // segment within the edge's shape
  final double t;
  final Geo point;
  final double distanceM;
  final double alongM; // metres from a to point
  const EdgeSnap(this.edge, this.from, this.seg, this.t, this.point, this.distanceM, this.alongM);
}

class OfflineRouter {
  final RoadGraph g;
  OfflineRouter(this.g);

  bool _allowed(int e, RouteOptions o) {
    final f = g.edgeFlags[e];
    if (o.mode == TravelMode.car ? f & EdgeFlag.car == 0 : f & EdgeFlag.moto == 0) return false;
    if (o.avoidFerries && g.roadClass(e) == RoadClass.ferry) return false;
    return true;
  }

  /// Travel time of an edge in seconds, with avoid-penalties folded in.
  double _cost(int e, RouteOptions o) {
    var kmh = g.edgeSpeed[e].toDouble();
    if (o.mode == TravelMode.motorcycle) kmh = math.min(kmh, 90);
    var s = g.edgeLenDm[e] / 10 / (kmh / 3.6);
    final f = g.edgeFlags[e];
    if (o.avoidTolls && f & EdgeFlag.toll != 0) s *= 6;
    if (o.avoidHighways && f & EdgeFlag.highway != 0) s *= 4;
    return s;
  }

  /// Nearest drivable road to p, up to [maxM] away.
  EdgeSnap? snap(Geo p, RouteOptions o, {double maxM = 3000}) {
    if (!g.covers(p)) return null;
    EdgeSnap? best;
    final seen = <int>{};
    final maxRing = (maxM / g.cellMeters).ceil() + 1;
    for (var ring = 0; ring <= maxRing; ring++) {
      // Once something closer than this ring's inner edge is found, stop.
      if (best != null && best.distanceM < (ring - 1) * g.cellMeters) break;
      for (final e in g.edgesInRing(p, ring)) {
        if (!seen.add(e)) continue;
        final a = g.source(e);
        final rev = g.reverseOf(e, a);
        final usable = _allowed(e, o) || (rev >= 0 && _allowed(rev, o));
        if (!usable) continue;
        final pts = g.shape(e, a);
        var along = 0.0;
        for (var i = 0; i < pts.length - 1; i++) {
          final pr = projectOnSegment(p, pts[i], pts[i + 1]);
          final segLen = distanceM(pts[i], pts[i + 1]);
          if (best == null || pr.distanceM < best.distanceM) {
            best = EdgeSnap(e, a, i, pr.t, pr.point, pr.distanceM, along + segLen * pr.t);
          }
          along += segLen;
        }
      }
    }
    if (best == null || best.distanceM > maxM) return null;
    return best;
  }

  ArahRoute route(Geo from, Geo to, RouteOptions o, {double? headingDeg}) {
    final s = snap(from, o);
    final d = snap(to, o);
    if (s == null || d == null) throw const RoutingException('no road nearby');
    return _route(s, d, o);
  }

  /// Route through several stops: one A* per leg, joined.
  ArahRoute routeVia(List<Geo> stops, RouteOptions o) {
    if (stops.length == 2) return route(stops[0], stops[1], o);
    final legs = <ArahRoute>[];
    for (var i = 0; i < stops.length - 1; i++) {
      legs.add(route(stops[i], stops[i + 1], o));
    }
    return _join(legs);
  }

  ArahRoute _join(List<ArahRoute> legs) {
    final pts = <Geo>[];
    final ms = <Maneuver>[];
    final limits = <int>[];
    for (var li = 0; li < legs.length; li++) {
      final leg = legs[li];
      final off = pts.isEmpty ? 0 : pts.length - 1;
      pts.addAll(pts.isEmpty ? leg.points : leg.points.skip(1));
      limits.addAll(limits.isEmpty ? leg.speedLimits : leg.speedLimits.skip(1));
      for (final m in leg.maneuvers) {
        if (li < legs.length - 1 && isArrival(m.turn)) continue;
        if (li > 0 && m.turn == Turn.start) continue;
        ms.add(_shift(m, off));
      }
    }
    return ArahRoute(
      points: pts,
      maneuvers: ms,
      distanceM: legs.fold(0.0, (a, l) => a + l.distanceM),
      durationS: legs.fold(0.0, (a, l) => a + l.durationS),
      hasToll: legs.any((l) => l.hasToll),
      hasFerry: legs.any((l) => l.hasFerry),
      source: RouteSource.offline,
      speedLimits: limits,
    );
  }

  Maneuver _shift(Maneuver m, int off) => Maneuver(
    turn: m.turn,
    shapeIndex: m.shapeIndex + off,
    street: m.street,
    ref: m.ref,
    exitNumber: m.exitNumber,
    toward: m.toward,
    roundaboutExit: m.roundaboutExit,
    lengthM: m.lengthM,
    timeS: m.timeS,
    toll: m.toll,
    lanes: m.lanes,
  );

  ArahRoute _route(EdgeSnap s, EdgeSnap d, RouteOptions o) {
    final n = g.nodeCount;
    final gScore = Float64List(n)..fillRange(0, n, double.infinity);
    final via = Int32List(n)..fillRange(0, n, -1); // edge used to reach node
    final heap = _Heap();
    final goal = d.point;
    const maxMps = 110 / 3.6;
    double h(int v) {
      // Admissible: straight line at the fastest legal speed.
      final dl = (g.nodeLat[v] / 1e6 - goal.lat) * 111195;
      final dn = (g.nodeLon[v] / 1e6 - goal.lon) * 111195 * math.cos(goal.lat * math.pi / 180);
      return math.sqrt(dl * dl + dn * dn) / maxMps;
    }

    // Start: from the snapped point we can drive on toward b (forward edge),
    // or back toward a if the road is two-way.
    final sb = g.edgeTarget[s.edge];
    final sLen = g.lengthM(s.edge);
    final sRev = g.reverseOf(s.edge, s.from);
    void seed(int v, double cost) {
      if (cost < gScore[v]) {
        gScore[v] = cost;
        via[v] = -2; // reached straight from the start point
        heap.push(cost + h(v), v);
      }
    }

    if (_allowed(s.edge, o)) seed(sb, _cost(s.edge, o) * (1 - s.alongM / math.max(sLen, 0.1)));
    if (sRev >= 0 && _allowed(sRev, o)) seed(s.from, _cost(sRev, o) * (s.alongM / math.max(sLen, 0.1)));

    // Goal: reach a and drive forward to the point, or reach b and come back.
    final da = d.from, db = g.edgeTarget[d.edge];
    final dLen = g.lengthM(d.edge);
    final dRev = g.reverseOf(d.edge, da);
    final extraA = _allowed(d.edge, o) ? _cost(d.edge, o) * (d.alongM / math.max(dLen, 0.1)) : double.infinity;
    final extraB = (dRev >= 0 && _allowed(dRev, o)) ? _cost(dRev, o) * (1 - d.alongM / math.max(dLen, 0.1)) : double.infinity;

    // Same road piece, start before goal in the direction of travel: no search needed.
    final sameEdge = s.edge == d.edge || s.edge == dRev;
    if (sameEdge) {
      final forward = s.edge == d.edge ? d.alongM >= s.alongM : (sLen - d.alongM) >= s.alongM;
      if (forward && _allowed(s.edge, o)) return _sameEdgeRoute(s, d, o);
    }

    var best = double.infinity;
    var bestEnd = -1; // node we leave the graph from
    var settled = 0;
    while (heap.isNotEmpty) {
      final f = heap.minKey;
      final u = heap.pop();
      if (f >= best) break;
      final gu = gScore[u];
      if (f - h(u) > gu + 1e-6) continue; // stale heap entry
      settled++;
      if (u == da && gu + extraA < best) {
        best = gu + extraA;
        bestEnd = da;
      }
      if (u == db && gu + extraB < best) {
        best = gu + extraB;
        bestEnd = db;
      }
      for (var e = g.firstEdge[u]; e < g.firstEdge[u + 1]; e++) {
        if (!_allowed(e, o)) continue;
        final v = g.edgeTarget[e];
        final nv = gu + _cost(e, o);
        if (nv < gScore[v]) {
          gScore[v] = nv;
          via[v] = e;
          heap.push(nv + h(v), v);
        }
      }
    }
    if (bestEnd < 0) throw RoutingException('no route (searched $settled junctions)');

    // Walk back from the end node to the start.
    final path = <int>[];
    var x = bestEnd;
    while (via[x] >= 0) {
      path.add(via[x]);
      x = g.source(via[x]);
    }
    final startNode = x; // sb or s.from
    final firstEdge = startNode == sb ? s.edge : sRev;
    final lastEdge = bestEnd == da ? d.edge : dRev;
    return _assemble(s, d, firstEdge, path.reversed.toList(), lastEdge, o);
  }

  ArahRoute _sameEdgeRoute(EdgeSnap s, EdgeSnap d, RouteOptions o) {
    final pts = <Geo>[s.point];
    final shape = g.shape(s.edge, s.from);
    final dAlong = s.edge == d.edge ? d.alongM : g.lengthM(s.edge) - d.alongM;
    var along = 0.0;
    for (var i = 1; i < shape.length; i++) {
      along += distanceM(shape[i - 1], shape[i]);
      if (along > s.alongM && along < dAlong) pts.add(shape[i]);
    }
    pts.add(d.point);
    final dist = cumulativeDistances(pts).last;
    final names = g.names(s.edge);
    return ArahRoute(
      points: pts,
      maneuvers: [
        Maneuver(turn: Turn.start, shapeIndex: 0, street: names[0], ref: names[1], lengthM: dist),
        Maneuver(turn: Turn.destination, shapeIndex: pts.length - 1),
      ],
      distanceM: dist,
      durationS: _cost(s.edge, o) * dist / math.max(g.lengthM(s.edge), 0.1),
      source: RouteSource.offline,
      speedLimits: List.filled(pts.length, g.edgeMaxspeed[s.edge]),
    );
  }

  /// Turns the edge sequence into points, maneuvers and totals.
  ArahRoute _assemble(EdgeSnap s, EdgeSnap d, int firstEdge, List<int> middle, int lastEdge, RouteOptions o) {
    final pts = <Geo>[];
    final limits = <int>[];
    // Where each edge of the full path starts in pts.
    final edgeStart = <int>[];
    final edges = <int>[firstEdge, ...middle, lastEdge];

    void addPoints(Iterable<Geo> ps, int e) {
      for (final p in ps) {
        if (pts.isNotEmpty && pts.last == p) continue;
        pts.add(p);
        limits.add(g.edgeMaxspeed[e]);
      }
    }

    // First edge: from the snapped point to its end.
    final firstShape = g.shape(firstEdge);
    final firstAlong = firstEdge == s.edge ? s.alongM : g.lengthM(firstEdge) - s.alongM;
    edgeStart.add(0);
    addPoints([s.point, ..._after(firstShape, firstAlong)], firstEdge);

    for (final e in middle) {
      edgeStart.add(pts.length - 1);
      addPoints(g.shape(e).skip(1), e);
    }

    // Last edge: from its start to the snapped goal point.
    final lastShape = g.shape(lastEdge);
    final lastAlong = lastEdge == d.edge ? d.alongM : g.lengthM(lastEdge) - d.alongM;
    edgeStart.add(pts.length - 1);
    addPoints([..._before(lastShape, lastAlong).skip(1), d.point], lastEdge);

    var duration = 0.0;
    for (final e in middle) {
      duration += _cost(e, o);
    }
    duration += _cost(firstEdge, o) * (1 - firstAlong / math.max(g.lengthM(firstEdge), 0.1));
    duration += _cost(lastEdge, o) * (lastAlong / math.max(g.lengthM(lastEdge), 0.1));

    final ms = TurnBuilder(g, o, _allowed).build(edges, edgeStart, pts);
    final cum = cumulativeDistances(pts);
    var hasToll = false, hasFerry = false;
    for (final e in edges) {
      hasToll |= g.has(e, EdgeFlag.toll);
      hasFerry |= g.roadClass(e) == RoadClass.ferry;
    }
    return ArahRoute(
      points: pts,
      maneuvers: ms,
      distanceM: cum.last,
      durationS: duration,
      hasToll: hasToll,
      hasFerry: hasFerry,
      source: RouteSource.offline,
      speedLimits: limits,
    );
  }

  /// Points of a shape after [along] metres (cut point not included).
  List<Geo> _after(List<Geo> shape, double along) {
    var acc = 0.0;
    final out = <Geo>[];
    for (var i = 1; i < shape.length; i++) {
      acc += distanceM(shape[i - 1], shape[i]);
      if (acc > along + 0.01) out.add(shape[i]);
    }
    return out;
  }

  /// Points of a shape up to [along] metres (start included, cut point not).
  List<Geo> _before(List<Geo> shape, double along) {
    var acc = 0.0;
    final out = <Geo>[shape.first];
    for (var i = 1; i < shape.length; i++) {
      acc += distanceM(shape[i - 1], shape[i]);
      if (acc < along - 0.01) out.add(shape[i]);
    }
    return out;
  }
}

/// Reads each junction along a path and decides what, if anything, to say.
class TurnBuilder {
  final RoadGraph g;
  final RouteOptions o;
  final bool Function(int e, RouteOptions o) allowed;
  TurnBuilder(this.g, this.o, this.allowed);

  double _outBearing(int e) {
    final sh = g.shape(e);
    // Look ~20 m in, so a kink at the very start doesn't decide the turn.
    var i = 1;
    var acc = distanceM(sh[0], sh[1]);
    while (acc < 20 && i < sh.length - 1) {
      acc += distanceM(sh[i], sh[i + 1]);
      i++;
    }
    return bearingDeg(sh[0], sh[i]);
  }

  double _inBearing(int e) {
    final sh = g.shape(e);
    final n = sh.length;
    var i = n - 2;
    var acc = distanceM(sh[n - 2], sh[n - 1]);
    while (acc < 20 && i > 0) {
      acc += distanceM(sh[i - 1], sh[i]);
      i--;
    }
    return bearingDeg(sh[i], sh[n - 1]);
  }

  /// How important a road is: 0 motorway … 9 track. Links sit just below
  /// the road they serve. Used so a driveway never causes a "keep left".
  double _rank(int e) {
    const base = [0.0, 1, 2, 3, 4, 5, 6, 8, 7, 9, 0.5, 1.5, 2.5, 3.5, 4.5, 5];
    return base[g.roadClass(e)].toDouble();
  }

  Turn _byAngle(double a) {
    final x = a.abs();
    final right = a > 0;
    if (x < 20) return Turn.straight;
    if (x < 55) return right ? Turn.slightRight : Turn.slightLeft;
    if (x < 135) return right ? Turn.right : Turn.left;
    if (x < 165) return right ? Turn.sharpRight : Turn.sharpLeft;
    // Malaysia drives on the left: a U-turn swings right.
    return right ? Turn.uturnRight : Turn.uturnLeft;
  }

  List<Maneuver> build(List<int> edges, List<int> edgeStart, List<Geo> pts) {
    final cum = cumulativeDistances(pts);
    final raw = <Maneuver>[];
    final first = g.names(edges.first);
    raw.add(Maneuver(turn: Turn.start, shapeIndex: 0, street: first[0], ref: first[1]));

    var i = 1;
    while (i < edges.length) {
      final ein = edges[i - 1], eout = edges[i];
      final node = g.source(eout);
      final inRb = g.has(ein, EdgeFlag.roundabout), outRb = g.has(eout, EdgeFlag.roundabout);
      final angle = angleDiff(_inBearing(ein), _outBearing(eout));
      final nIn = g.names(ein), nOut = g.names(eout);

      // Roundabout: one maneuver on entry, counting the exits we pass.
      if (!inRb && outRb) {
        var exits = 0;
        var j = i;
        while (j < edges.length && g.has(edges[j], EdgeFlag.roundabout)) {
          final atNode = g.edgeTarget[edges[j]];
          for (var x = g.firstEdge[atNode]; x < g.firstEdge[atNode + 1]; x++) {
            if (!g.has(x, EdgeFlag.roundabout) && allowed(x, o)) {
              exits++;
              break;
            }
          }
          j++;
        }
        final after = j < edges.length ? g.names(edges[j]) : nOut;
        raw.add(
          Maneuver(
            turn: Turn.roundaboutEnter,
            shapeIndex: edgeStart[i],
            street: after[0],
            ref: after[1],
            roundaboutExit: math.max(1, exits),
          ),
        );
        i = j + 1;
        continue;
      }
      if (inRb) {
        i++;
        continue;
      }

      // Other ways we could have gone from this junction (not back where we
      // came from), ignoring roads much less important than ours.
      final cameFrom = g.source(ein);
      final options = <double>[];
      final outRank = _rank(eout);
      for (var x = g.firstEdge[node]; x < g.firstEdge[node + 1]; x++) {
        if (x == eout || g.edgeTarget[x] == cameFrom || !allowed(x, o)) continue;
        if (_rank(x) > outRank + 1.5 && _rank(x) >= 7) continue; // service roads, tracks
        options.add(angleDiff(_inBearing(ein), _outBearing(x)));
      }
      final clsIn = g.roadClass(ein), clsOut = g.roadClass(eout);
      final nameChanged = (nOut[0].isNotEmpty || nOut[1].isNotEmpty) && (nOut[0] != nIn[0] || nOut[1] != nIn[1]);
      var turn = _byAngle(angle);

      if (RoadClass.isFast(clsIn) && RoadClass.isLink(clsOut) && options.isNotEmpty) {
        turn = angle < 0 ? Turn.exitLeft : Turn.exitRight;
      } else if (RoadClass.isLink(clsIn) && RoadClass.isFast(clsOut)) {
        turn = options.isEmpty ? Turn.merge : (angle < 0 ? Turn.mergeLeft : Turn.mergeRight);
        if (options.isEmpty) {
          // A plain merge with nowhere else to go: say it only if the name changes.
          if (!nameChanged) {
            i++;
            continue;
          }
        }
      } else if (turn == Turn.straight) {
        // A fork where another branch is also nearly straight: keep left/right —
        // unless we simply stay on the same, more important road.
        final rival = options.where((a) => a.abs() < 40).toList();
        final staysOnRoad = !nameChanged && _rank(eout) <= _rank(ein) + 0.5;
        if (rival.isNotEmpty && staysOnRoad && RoadClass.isLink(clsOut) == RoadClass.isLink(clsIn)) {
          i++;
          continue;
        }
        if (rival.isNotEmpty) {
          turn = rival.first > angle ? Turn.stayLeft : Turn.stayRight;
        } else if (options.isEmpty || !nameChanged) {
          i++;
          continue; // nothing to say
        }
      } else if (options.isEmpty && !nameChanged && angle.abs() < 100) {
        i++;
        continue; // the road just bends
      }
      // Slight bends at junctions where every other way is a sharp turn are just the road.
      if ((turn == Turn.slightLeft || turn == Turn.slightRight) && !nameChanged && options.every((a) => (a - angle).abs() > 60)) {
        i++;
        continue;
      }

      final dest = nOut[2];
      raw.add(
        Maneuver(
          turn: turn,
          shapeIndex: edgeStart[i],
          street: nOut[0],
          ref: nOut[1],
          toward: dest,
          toll: g.has(eout, EdgeFlag.toll),
        ),
      );
      i++;
    }
    raw.add(Maneuver(turn: Turn.destination, shapeIndex: pts.length - 1));

    // Fill in the length of road after each maneuver.
    final out = <Maneuver>[];
    for (var k = 0; k < raw.length; k++) {
      final m = raw[k];
      final endIdx = k + 1 < raw.length ? raw[k + 1].shapeIndex : m.shapeIndex;
      final len = cum[endIdx] - cum[m.shapeIndex];
      out.add(
        Maneuver(
          turn: m.turn,
          shapeIndex: m.shapeIndex,
          street: m.street,
          ref: m.ref,
          toward: m.toward,
          roundaboutExit: m.roundaboutExit,
          lengthM: len,
          toll: m.toll,
        ),
      );
    }
    return out;
  }
}

/// Binary min-heap of (key, node) with lazy deletion.
class _Heap {
  var _keys = Float64List(1024);
  var _vals = Int32List(1024);
  int _n = 0;

  bool get isNotEmpty => _n > 0;
  double get minKey => _keys[0];

  void push(double k, int v) {
    if (_n == _keys.length) {
      _keys = Float64List(_n * 2)..setRange(0, _n, _keys);
      _vals = Int32List(_n * 2)..setRange(0, _n, _vals);
    }
    var i = _n++;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= k) break;
      _keys[i] = _keys[p];
      _vals[i] = _vals[p];
      i = p;
    }
    _keys[i] = k;
    _vals[i] = v;
  }

  int pop() {
    final top = _vals[0];
    _n--;
    if (_n > 0) {
      final k = _keys[_n], v = _vals[_n];
      var i = 0;
      while (true) {
        var c = 2 * i + 1;
        if (c >= _n) break;
        if (c + 1 < _n && _keys[c + 1] < _keys[c]) c++;
        if (_keys[c] >= k) break;
        _keys[i] = _keys[c];
        _vals[i] = _vals[c];
        i = c;
      }
      _keys[i] = k;
      _vals[i] = v;
    }
    return top;
  }
}
