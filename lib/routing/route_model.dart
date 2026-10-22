// One route model for both routers (Valhalla online, Arah's own offline
// router), so navigation, voice and UI never care where a route came from.
import '../core/geo.dart';

enum TravelMode { car, motorcycle }

enum Turn {
  start,
  startLeft,
  startRight,
  destination,
  destinationLeft,
  destinationRight,
  becomes,
  straight,
  slightRight,
  right,
  sharpRight,
  uturnRight,
  uturnLeft,
  sharpLeft,
  left,
  slightLeft,
  rampStraight,
  rampRight,
  rampLeft,
  exitRight,
  exitLeft,
  stayStraight,
  stayRight,
  stayLeft,
  merge,
  mergeLeft,
  mergeRight,
  roundaboutEnter,
  roundaboutExit,
  ferryEnter,
  ferryExit,
}

/// Valhalla maneuver `type` code → [Turn]. Codes from Valhalla's API reference.
Turn turnFromValhalla(int code) {
  const map = <int, Turn>{
    0: Turn.straight,
    1: Turn.start,
    2: Turn.startRight,
    3: Turn.startLeft,
    4: Turn.destination,
    5: Turn.destinationRight,
    6: Turn.destinationLeft,
    7: Turn.becomes,
    8: Turn.straight,
    9: Turn.slightRight,
    10: Turn.right,
    11: Turn.sharpRight,
    12: Turn.uturnRight,
    13: Turn.uturnLeft,
    14: Turn.sharpLeft,
    15: Turn.left,
    16: Turn.slightLeft,
    17: Turn.rampStraight,
    18: Turn.rampRight,
    19: Turn.rampLeft,
    20: Turn.exitRight,
    21: Turn.exitLeft,
    22: Turn.stayStraight,
    23: Turn.stayRight,
    24: Turn.stayLeft,
    25: Turn.merge,
    26: Turn.roundaboutEnter,
    27: Turn.roundaboutExit,
    28: Turn.ferryEnter,
    29: Turn.ferryExit,
    37: Turn.mergeRight,
    38: Turn.mergeLeft,
  };
  return map[code] ?? Turn.straight;
}

bool isArrival(Turn t) => t == Turn.destination || t == Turn.destinationLeft || t == Turn.destinationRight;

/// One lane at a maneuver. [directions] is Valhalla's bitmask.
class Lane {
  final int directions;
  final bool valid; // usable for this maneuver
  final bool active; // the best lane
  const Lane(this.directions, {this.valid = false, this.active = false});
}

class Maneuver {
  final Turn turn;

  /// Index into [ArahRoute.points] where the maneuver happens.
  final int shapeIndex;

  /// Name of the road the maneuver turns onto ("Jalan Ampang"), may be empty.
  final String street;

  /// Highway ref of that road ("E1"), may be empty.
  final String ref;

  /// Sign text: exit number and "toward" destinations, for expressway exits.
  final String exitNumber;
  final String toward;

  /// Roundabout exit to take, 1-based; 0 when not a roundabout.
  final int roundaboutExit;

  /// Length and time of the stretch that follows this maneuver.
  final double lengthM;
  final double timeS;
  final bool toll;
  final List<Lane> lanes;

  const Maneuver({
    required this.turn,
    required this.shapeIndex,
    this.street = '',
    this.ref = '',
    this.exitNumber = '',
    this.toward = '',
    this.roundaboutExit = 0,
    this.lengthM = 0,
    this.timeS = 0,
    this.toll = false,
    this.lanes = const [],
  });

  /// What to show as the target road name: name, else ref, else toward.
  String get label {
    if (street.isNotEmpty) return street;
    if (ref.isNotEmpty) return ref;
    return toward;
  }
}

enum RouteSource { online, offline }

class ArahRoute {
  final List<Geo> points;
  final List<Maneuver> maneuvers;
  final double distanceM;
  final double durationS;
  final bool hasToll;
  final bool hasFerry;
  final RouteSource source;

  /// Per-point speed limit in km/h, 0 when unknown. Same length as [points]
  /// when present; empty when the router gave none. Online routes get theirs
  /// filled in afterwards from the offline road network, when a pack is there.
  List<int> speedLimits;

  /// Lazily computed cumulative distance per point.
  late final List<double> cumDist = cumulativeDistances(points);

  ArahRoute({
    required this.points,
    required this.maneuvers,
    required this.distanceM,
    required this.durationS,
    this.hasToll = false,
    this.hasFerry = false,
    this.source = RouteSource.online,
    this.speedLimits = const [],
  });

  Geo get start => points.first;
  Geo get end => points.last;
}

class RouteOptions {
  final TravelMode mode;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;
  const RouteOptions({
    this.mode = TravelMode.car,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
  });

  RouteOptions copyWith({TravelMode? mode, bool? avoidTolls, bool? avoidHighways, bool? avoidFerries}) =>
      RouteOptions(
        mode: mode ?? this.mode,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        avoidFerries: avoidFerries ?? this.avoidFerries,
      );
}

class RoutingException implements Exception {
  final String message;
  final bool busy; // server said "slow down" (HTTP 429)
  const RoutingException(this.message, {this.busy = false});
  @override
  String toString() => 'RoutingException: $message';
}
