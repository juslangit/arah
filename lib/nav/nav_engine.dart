// Turn-by-turn state: where on the route the car is, the next maneuver,
// what is left, and whether the driver has left the route. Pure Dart: it is
// fed GPS fixes and returns a NavUpdate, so it can be tested with made-up
// drives. Thresholds come from the app study (research/app-study.md §C3).
import 'dart:math' as math;

import '../core/geo.dart';
import '../routing/route_model.dart';

class Fix {
  final Geo pos;
  final double accuracyM;
  final double speedMps; // < 0 when unknown
  final double? headingDeg;
  final DateTime time;
  const Fix(this.pos, {this.accuracyM = 5, this.speedMps = -1, this.headingDeg, required this.time});
}

enum NavEvent { none, offRoute, arrived }

class NavUpdate {
  final Geo position; // snapped to the route when on it
  final double bearingDeg;
  final bool onRoute;
  final double distanceFromRouteM;
  final double travelledM;
  final double remainingM;
  final double remainingS;

  /// Index into route.maneuvers of the next maneuver, or -1 past the last.
  final int nextIndex;
  final double toNextM;

  /// The maneuver after next when it comes within 400 m of the next one.
  final int thenIndex;
  final double thenGapM;
  final double speedKmh;
  final int speedLimitKmh; // 0 when unknown
  final NavEvent event;
  final bool gpsWeak;

  const NavUpdate({
    required this.position,
    required this.bearingDeg,
    required this.onRoute,
    required this.distanceFromRouteM,
    required this.travelledM,
    required this.remainingM,
    required this.remainingS,
    required this.nextIndex,
    required this.toNextM,
    required this.thenIndex,
    required this.thenGapM,
    required this.speedKmh,
    required this.speedLimitKmh,
    required this.event,
    required this.gpsWeak,
  });
}

class NavThresholds {
  final double minOffRouteM = 40;
  final double maxOffRouteM = 100;
  final int offRouteFixes = 3;
  final Duration offRouteTime = const Duration(seconds: 4);
  final int offRouteFixesSlow = 8;
  final double wrongWayDeg = 120;
  final Duration wrongWayTime = const Duration(seconds: 5);
  final double wrongWayMinM = 25;
  final double ignoreAccuracyM = 50;
  final double arrivalM = 20;
  final double thenWithinM = 400;
  final double lookAheadM = 1500;
  const NavThresholds();
}

class NavEngine {
  final ArahRoute route;
  final NavThresholds t;

  int _seg = 0; // current segment: points[_seg] → points[_seg+1]
  double _travelled = 0;
  int _offCount = 0;
  DateTime? _offSince;
  DateTime? _wrongSince;
  DateTime? _lastGoodFix;
  bool _arrived = false;
  double _lastBearing = 0;

  NavEngine(this.route, {this.t = const NavThresholds()}) {
    if (route.points.length > 1) _lastBearing = bearingDeg(route.points[0], route.points[1]);
  }

  bool get arrived => _arrived;
  double get travelledM => _travelled;

  NavUpdate update(Fix fix) {
    final pts = route.points;
    final cum = route.cumDist;
    final speed = fix.speedMps;
    final weak = fix.accuracyM > t.ignoreAccuracyM;
    if (!weak) _lastGoodFix = fix.time;
    final gpsWeak = _lastGoodFix == null || fix.time.difference(_lastGoodFix!) > const Duration(seconds: 10);

    // 1. Find the closest point on the route, looking a little back and
    //    up to lookAheadM forward from where we were.
    var best = _bestIn(fix.pos, math.max(0, _seg - 1), _forwardLimit(_seg));
    final radius = _offRouteRadius(fix.accuracyM);
    if (best.$2.distanceM > radius) {
      // Maybe a GPS jump along the route (tunnel exit): try the whole rest of it.
      final all = _bestIn(fix.pos, _seg, pts.length - 2);
      if (all.$2.distanceM <= radius) best = all;
    }
    final segIdx = best.$1;
    final proj = best.$2;
    final along = cum[segIdx] + proj.t * (cum[segIdx + 1] - cum[segIdx]);
    final onRoute = proj.distanceM <= radius;

    // 2. Off-route debounce: several fixes and several seconds, ignoring bad fixes.
    var event = NavEvent.none;
    if (!weak) {
      if (!onRoute) {
        _offCount++;
        _offSince ??= fix.time;
        final moving = speed >= 3 / 3.6;
        final enough = moving
            ? _offCount >= t.offRouteFixes && fix.time.difference(_offSince!) >= t.offRouteTime
            : _offCount >= t.offRouteFixesSlow;
        if (enough) event = NavEvent.offRoute;
      } else {
        _offCount = 0;
        _offSince = null;
      }
    }

    // 3. Wrong way: heading far from the route direction for a while.
    final routeBearing = bearingDeg(pts[segIdx], pts[segIdx + 1]);
    if (!weak && fix.headingDeg != null && speed > 2) {
      final diff = angleDiff(routeBearing, fix.headingDeg!).abs();
      if (diff > t.wrongWayDeg && proj.distanceM > t.wrongWayMinM) {
        _wrongSince ??= fix.time;
        if (fix.time.difference(_wrongSince!) >= t.wrongWayTime) event = NavEvent.offRoute;
      } else {
        _wrongSince = null;
      }
    }

    // Only move forward along the route while on it; never jump backwards
    // more than a few metres (GPS jitter at a stop).
    if (onRoute && along >= _travelled - 30) {
      _seg = segIdx;
      _travelled = along;
    }

    // 4. Arrival.
    final remaining = math.max(0.0, route.distanceM > 0 ? cum.last - _travelled : 0.0);
    if (!_arrived && (remaining <= t.arrivalM || distanceM(fix.pos, route.end) <= t.arrivalM)) {
      _arrived = true;
    }
    if (_arrived) event = NavEvent.arrived;

    // 5. Next maneuver and the one after it.
    final ms = route.maneuvers;
    var next = -1;
    for (var i = 0; i < ms.length; i++) {
      final at = cum[ms[i].shapeIndex.clamp(0, cum.length - 1)];
      if (at > _travelled + 1 && ms[i].turn != Turn.start) {
        next = i;
        break;
      }
    }
    final toNext = next < 0 ? 0.0 : cum[ms[next].shapeIndex.clamp(0, cum.length - 1)] - _travelled;
    var thenIdx = -1;
    var thenGap = 0.0;
    if (next >= 0 && next + 1 < ms.length) {
      thenGap =
          cum[ms[next + 1].shapeIndex.clamp(0, cum.length - 1)] - cum[ms[next].shapeIndex.clamp(0, cum.length - 1)];
      if (thenGap <= t.thenWithinM) thenIdx = next + 1;
    }

    // 6. Remaining time: the route's own estimate, scaled by distance left.
    final remainingS = route.distanceM > 0 ? route.durationS * (remaining / cum.last.clamp(1, double.infinity)) : 0.0;

    // Bearing: follow the road when moving on it, else the GPS heading.
    double bearing = _lastBearing;
    if (onRoute && (speed < 0 || speed > 5 / 3.6)) {
      bearing = routeBearing;
    } else if (fix.headingDeg != null && speed > 1) {
      bearing = fix.headingDeg!;
    }
    _lastBearing = bearing;

    final limit = route.speedLimits.isEmpty ? 0 : route.speedLimits[segIdx.clamp(0, route.speedLimits.length - 1)];

    return NavUpdate(
      position: onRoute ? proj.point : fix.pos,
      bearingDeg: bearing,
      onRoute: onRoute,
      distanceFromRouteM: proj.distanceM,
      travelledM: _travelled,
      remainingM: remaining,
      remainingS: remainingS,
      nextIndex: next,
      toNextM: toNext,
      thenIndex: thenIdx,
      thenGapM: thenGap,
      speedKmh: speed < 0 ? 0 : speed * 3.6,
      speedLimitKmh: limit,
      event: event,
      gpsWeak: gpsWeak,
    );
  }

  double _offRouteRadius(double acc) => math.min(t.maxOffRouteM, math.max(t.minOffRouteM, 2 * acc));

  int _forwardLimit(int from) {
    final cum = route.cumDist;
    var i = from;
    while (i < route.points.length - 2 && cum[i] - cum[from] < t.lookAheadM) {
      i++;
    }
    return i;
  }

  (int, Projection) _bestIn(Geo p, int from, int to) {
    final pts = route.points;
    var bestI = from;
    Projection? best;
    for (var i = from; i <= to && i < pts.length - 1; i++) {
      final pr = projectOnSegment(p, pts[i], pts[i + 1]);
      // Prefer the earliest segment on near-ties, so a road that doubles back
      // (a U-turn bay) doesn't snap to its far side.
      if (best == null || pr.distanceM < best.distanceM - 0.5) {
        best = pr;
        bestI = i;
      }
    }
    return (bestI, best ?? Projection(pts.first, 0, distanceM(p, pts.first)));
  }
}
