// One place the app asks for routes. Online (Valhalla) first, because it
// knows turn restrictions and gives alternatives; the phone's own router
// when there's no signal or the server fails. The offline router lives in a
// background isolate so a long search never freezes the map.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../core/geo.dart';
import '../offline/packs.dart';
import 'offline_router.dart';
import 'road_graph.dart';
import 'route_model.dart';
import 'valhalla_client.dart';

class RouteResult {
  final List<ArahRoute> routes;
  final bool usedOffline;
  final String? onlineError;
  const RouteResult(this.routes, {this.usedOffline = false, this.onlineError});
}

class RoutingService {
  final ValhallaClient online;
  final PackManager packs;
  final _workers = <String, _Worker>{};

  RoutingService(this.packs, {ValhallaClient? online}) : online = online ?? ValhallaClient();

  Future<RouteResult> route(List<Geo> stops, RouteOptions o,
      {double? headingDeg, bool alternates = true, bool offlineOnly = false}) async {
    String? onlineError;
    if (!offlineOnly) {
      try {
        final routes = await online.route(stops, o, alternates: alternates, headingDeg: headingDeg);
        _fillLimitsLater(routes.first);
        return RouteResult(routes);
      } on RoutingException catch (e) {
        onlineError = e.busy ? 'busy' : e.message;
      }
    }
    final w = await _workerFor(stops.first);
    if (w == null) {
      throw RoutingException(onlineError ?? 'no offline map for this area');
    }
    final r = await w.route(stops, o);
    return RouteResult([r], usedOffline: true, onlineError: onlineError);
  }

  /// Speed limits come from OpenStreetMap's maxspeed in the offline roads.
  void _fillLimitsLater(ArahRoute r) async {
    final w = await _workerFor(r.start);
    if (w == null) return;
    try {
      r.speedLimits = await w.limits(r.points);
    } catch (_) {}
  }

  Future<_Worker?> _workerFor(Geo p) async {
    final pack = packs.packAt(p);
    if (pack == null) return null;
    final file = packs.fileOf(pack, '.roads');
    if (file == null) return null;
    return _workers[file] ??= await _Worker.spawn(file);
  }

  /// Warm the router for where the user is, so the first offline route is quick.
  Future<void> preload(Geo p) async => _workerFor(p);
}

class _Worker {
  final SendPort _send;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;
  _Worker(this._send, ReceivePort rp) {
    rp.listen((msg) {
      final (id, result) = msg as (int, Object?);
      final c = _pending.remove(id);
      if (result is RoutingException) {
        c?.completeError(result);
      } else if (result is String) {
        c?.completeError(RoutingException(result));
      } else {
        c?.complete(result);
      }
    });
  }

  static Future<_Worker> spawn(String path) async {
    final rp = ReceivePort();
    final ready = Completer<SendPort>();
    final w = rp.asBroadcastStream();
    w.first.then((m) => ready.complete(m as SendPort));
    await Isolate.spawn(_main, (rp.sendPort, path));
    final send = await ready.future;
    final rp2 = ReceivePort();
    send.send(rp2.sendPort);
    return _Worker(send, rp2);
  }

  Future<ArahRoute> route(List<Geo> stops, RouteOptions o) async => (await _call(('route', stops, o))) as ArahRoute;
  Future<List<int>> limits(List<Geo> pts) async => (await _call(('limits', pts, null))) as List<int>;

  Future<Object?> _call((String, List<Geo>, RouteOptions?) req) {
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send.send((id, req));
    return c.future;
  }

  static void _main((SendPort, String) init) {
    final (reply0, path) = init;
    final inbox = ReceivePort();
    reply0.send(inbox.sendPort);
    SendPort? reply;
    OfflineRouter? router;
    // One synchronous handler: requests queue up in order, none get lost
    // while the road file is still loading.
    inbox.listen((m) {
      if (m is SendPort) {
        reply = m;
        return;
      }
      final (id, (kind, pts, opts)) = m as (int, (String, List<Geo>, RouteOptions?));
      try {
        router ??= OfflineRouter(RoadGraph.parse(File(path).readAsBytesSync()));
        if (kind == 'route') {
          reply!.send((id, router!.routeVia(pts, opts!)));
        } else {
          reply!.send((id, _limits(router!, pts)));
        }
      } on RoutingException catch (e) {
        reply!.send((id, e));
      } catch (e) {
        reply!.send((id, '$e'));
      }
    });
  }

  /// One lookup every ~50 m; points in between take the last value.
  static List<int> _limits(OfflineRouter r, List<Geo> pts) {
    final out = List<int>.filled(pts.length, 0);
    const o = RouteOptions();
    var lastAt = -1;
    var last = 0;
    for (var i = 0; i < pts.length; i++) {
      if (lastAt < 0 || distanceM(pts[lastAt], pts[i]) > 50) {
        final s = r.snap(pts[i], o, maxM: 30);
        last = s == null ? 0 : r.g.edgeMaxspeed[s.edge];
        lastAt = i;
      }
      out[i] = last;
    }
    return out;
  }
}
