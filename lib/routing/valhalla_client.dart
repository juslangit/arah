// Online routing through a Valhalla server. During development this is the
// FOSSGIS demo server (1 request per second per user, must send X-Client-Id);
// before a public launch it becomes Arah's own server — one line in config.dart.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../core/geo.dart';
import 'route_model.dart';

class ValhallaClient {
  final http.Client _http;
  final String baseUrl;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  ValhallaClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? ArahConfig.valhallaUrl;

  Map<String, dynamic> buildRequest(List<Geo> stops, RouteOptions o, {bool alternates = true, double? headingDeg}) {
    final costing = o.mode == TravelMode.motorcycle ? 'motorcycle' : 'auto';
    final locations = <Map<String, dynamic>>[];
    for (var i = 0; i < stops.length; i++) {
      final loc = <String, dynamic>{'lat': stops[i].lat, 'lon': stops[i].lon};
      // The car's current heading helps the router not start with a U-turn.
      if (i == 0 && headingDeg != null) {
        loc['heading'] = headingDeg.round();
        loc['heading_tolerance'] = 45;
      }
      locations.add(loc);
    }
    return {
      'locations': locations,
      'costing': costing,
      'costing_options': {
        costing: {
          'use_tolls': o.avoidTolls ? 0.0 : 0.5,
          'use_highways': o.avoidHighways ? 0.0 : 1.0,
          'use_ferry': o.avoidFerries ? 0.0 : 0.5,
        }
      },
      'directions_options': {'units': 'kilometers', 'language': 'en-GB'},
      'turn_lanes': true,
      if (alternates && stops.length == 2) 'alternates': 2,
    };
  }

  /// Returns the main route first, then up to two alternatives.
  Future<List<ArahRoute>> route(List<Geo> stops, RouteOptions o, {bool alternates = true, double? headingDeg}) async {
    // Hard client-side guard for the demo server's 1 request/second rule.
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();

    final body = jsonEncode(buildRequest(stops, o, alternates: alternates, headingDeg: headingDeg));
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$baseUrl/route'), headers: ArahConfig.serverHeaders, body: body)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw RoutingException('network: $e');
    }
    if (res.statusCode == 429) throw const RoutingException('busy', busy: true);
    if (res.statusCode != 200) {
      throw RoutingException('HTTP ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
    }
    return parseResponse(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  static List<ArahRoute> parseResponse(Map<String, dynamic> json) {
    final out = <ArahRoute>[parseTrip(json['trip'] as Map<String, dynamic>)];
    for (final alt in (json['alternates'] as List? ?? const [])) {
      out.add(parseTrip((alt as Map<String, dynamic>)['trip'] as Map<String, dynamic>));
    }
    return out;
  }

  static ArahRoute parseTrip(Map<String, dynamic> trip) {
    final points = <Geo>[];
    final maneuvers = <Maneuver>[];
    final legs = trip['legs'] as List;
    for (var li = 0; li < legs.length; li++) {
      final leg = legs[li] as Map<String, dynamic>;
      final shape = decodePolyline(leg['shape'] as String);
      // Legs share their joining point; drop the duplicate.
      final offset = points.isEmpty ? 0 : points.length - 1;
      points.addAll(points.isEmpty ? shape : shape.skip(1));
      final ms = leg['maneuvers'] as List;
      for (var mi = 0; mi < ms.length; mi++) {
        final m = ms[mi] as Map<String, dynamic>;
        var turn = turnFromValhalla(m['type'] as int);
        // An intermediate leg's arrival is a waypoint, and the next leg's
        // start is not a real maneuver either.
        if (li < legs.length - 1 && isArrival(turn)) continue;
        if (li > 0 && (turn == Turn.start || turn == Turn.startLeft || turn == Turn.startRight)) continue;
        maneuvers.add(_parseManeuver(m, turn, offset));
      }
    }
    final summary = trip['summary'] as Map<String, dynamic>;
    return ArahRoute(
      points: points,
      maneuvers: maneuvers,
      distanceM: ((summary['length'] as num?) ?? 0) * 1000,
      durationS: ((summary['time'] as num?) ?? 0).toDouble(),
      hasToll: summary['has_toll'] == true,
      hasFerry: summary['has_ferry'] == true,
      source: RouteSource.online,
    );
  }

  static Maneuver _parseManeuver(Map<String, dynamic> m, Turn turn, int offset) {
    String firstText(List? l) => (l == null || l.isEmpty) ? '' : ((l.first as Map)['text'] as String? ?? '');
    String joinText(List? l) => l == null ? '' : l.map((e) => (e as Map)['text']).whereType<String>().take(2).join(' / ');

    final names = (m['street_names'] as List?)?.cast<String>() ?? const <String>[];
    // Valhalla puts refs ("E1") and names in the same list; split them.
    final refRe = RegExp(r'^[A-Z]{0,2}\d+[A-Z]?$');
    final name = names.firstWhere((n) => !refRe.hasMatch(n), orElse: () => '');
    final ref = names.firstWhere((n) => refRe.hasMatch(n), orElse: () => '');
    final sign = m['sign'] as Map<String, dynamic>?;
    final lanes = <Lane>[
      for (final l in (m['lanes'] as List? ?? const []))
        Lane(((l as Map)['directions'] as num?)?.toInt() ?? 0, valid: l['valid'] != null, active: l['active'] != null),
    ];
    return Maneuver(
      turn: turn,
      shapeIndex: ((m['begin_shape_index'] as num?)?.toInt() ?? 0) + offset,
      street: name,
      ref: ref,
      exitNumber: firstText(sign?['exit_number_elements'] as List?),
      toward: joinText(sign?['exit_toward_elements'] as List?).isNotEmpty
          ? joinText(sign?['exit_toward_elements'] as List?)
          : joinText(sign?['exit_branch_elements'] as List?),
      roundaboutExit: (m['roundabout_exit_count'] as num?)?.toInt() ?? 0,
      lengthM: ((m['length'] as num?) ?? 0) * 1000,
      timeS: ((m['time'] as num?) ?? 0).toDouble(),
      toll: m['toll'] == true,
      lanes: lanes,
    );
  }
}
