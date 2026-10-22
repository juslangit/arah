// Turn-by-turn navigation (app study §S5): a Waze/Google Maps hybrid. Big
// next-turn banner, lanes, speedometer with speed limit, ETA bar, report
// button within thumb reach, automatic reroute, report alerts with
// "Masih ada?" confirmation, and arrival.
import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/geo.dart';
import '../nav/nav_engine.dart';
import '../nav/phrases.dart';
import '../nav/voice_planner.dart';
import '../reports/reports.dart';
import '../routing/route_model.dart';
import '../search/place.dart';
import 'format.dart';
import 'lanes.dart';
import 'map_kit.dart';
import 'report_sheet.dart';
import 'steps_sheet.dart';

class NavScreen extends StatefulWidget {
  final ArahRoute route;
  final Place destination;
  final List<Place> stops;
  final String style;
  const NavScreen({super.key, required this.route, required this.destination, required this.stops, required this.style});

  @override
  State<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends State<NavScreen> {
  late ArahRoute _route;
  late NavEngine _engine;
  late VoicePlanner _voice;
  NavUpdate? _u;
  MapLibreMapController? _map;
  MapLayers? _layers;
  bool _styleReady = false;
  StreamSubscription<Fix>? _sub;

  bool _following = true;
  bool _overview = false;
  DateTime _lastTouch = DateTime.now();
  Timer? _recenterTimer;

  bool _rerouting = false;
  int _rerouteCount = 0;
  DateTime _nextRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _onRouteSince = DateTime.now();
  DateTime? _lastRecalcSpoken;
  bool _offlineRoute = false;

  Report? _alert; // approaching
  Report? _ask; // just passed: "Masih ada?"
  Timer? _askTimer;
  final _alerted = <String>{};

  late List<Place> _stopsLeft;
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    _stopsLeft = List.of(widget.stops);
    _setRoute(widget.route);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGps());
    _recenterTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Google Maps behaviour: back to following 10 s after the last touch.
      if (!_following && !_overview && DateTime.now().difference(_lastTouch) > const Duration(seconds: 10)) {
        setState(() => _following = true);
      }
    });
  }

  void _setRoute(ArahRoute r) {
    final s = context.appRead.settings;
    _route = r;
    _engine = NavEngine(r);
    _voice = VoicePlanner(r, lang: s.lang, timing: s.voiceTiming, bluetooth: s.bluetoothDelay);
    _offlineRoute = r.source == RouteSource.offline;
  }

  Future<void> _startGps() async {
    final app = context.appRead;
    await app.location.start(
      navigating: true,
      title: 'Arah',
      text: app.tr('Menavigasi ke ${widget.destination.name}', 'Navigating to ${widget.destination.name}'),
    );
    _sub = app.location.fixes.listen(_onFix);
    final s = app.settings;
    if (s.sound == 0) {
      final first = _route.maneuvers.isNotEmpty ? _route.maneuvers.first : null;
      final next = _route.maneuvers.length > 1 ? _route.maneuvers[1] : null;
      if (first != null && next != null) {
        final head = first.label.isNotEmpty ? app.tr('Ikut ${first.label}.', 'Head along ${first.label}.') : '';
        unawaited(
          app.speech.say(
            '$head ${spokenPrompt(next, app.lang, distanceM: next.shapeIndex < _route.cumDist.length ? _route.cumDist[next.shapeIndex] : null)}',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recenterTimer?.cancel();
    _askTimer?.cancel();
    WakelockPlus.disable();
    context.appRead.speech.stop();
    super.dispose();
  }

  // ---- every GPS fix --------------------------------------------------------

  void _onFix(Fix fix) {
    if (_arrived) return;
    final u = _engine.update(fix);
    final app = context.appRead;
    setState(() => _u = u);

    _map?.updateManualLocation(
      ManualLocationUpdate(
        target: ll(u.position),
        bearing: u.bearingDeg,
        horizontalAccuracy: fix.accuracyM,
        speed: fix.speedMps < 0 ? null : fix.speedMps,
      ),
    );
    if (_following && !_overview) _camera(u);
    _drawRemaining(u);
    _passStops(u);

    if (u.onRoute) {
      if (DateTime.now().difference(_onRouteSince) > const Duration(minutes: 2)) _rerouteCount = 0;
    } else {
      _onRouteSince = DateTime.now();
    }

    // Voice.
    final p = _voice.next(u, fix.time);
    if (p != null && app.settings.sound == 0) app.speech.say(p.text, interrupt: p.urgent);

    if (u.event == NavEvent.arrived) {
      _arrive();
      return;
    }
    if (u.event == NavEvent.offRoute) _reroute(fix);
    _checkReports(u, fix);
  }

  void _camera(NavUpdate u) {
    final kmh = u.speedKmh;
    final zoom = kmh < 30
        ? 17.0
        : kmh < 70
        ? 16.0
        : 15.0;
    // Put the car in the lower third: aim the camera a little ahead of it.
    final mPerDp = 40075016 * math.cos(u.position.lat * math.pi / 180) / (512 * math.pow(2, zoom));
    final ahead = MediaQuery.of(context).size.height * 0.18 * mPerDp;
    final rad = u.bearingDeg * math.pi / 180;
    final target = Geo(
      u.position.lat + ahead * math.cos(rad) / 111195,
      u.position.lon + ahead * math.sin(rad) / (111195 * math.cos(u.position.lat * math.pi / 180)),
    );
    _map?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: ll(target), zoom: zoom, bearing: u.bearingDeg, tilt: 50)),
      duration: const Duration(milliseconds: 950),
    );
  }

  void _drawRemaining(NavUpdate u) {
    if (!_styleReady) return;
    final cum = _route.cumDist;
    var i = 0;
    var lo = 0, hi = cum.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= u.travelledM) {
        i = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    _layers?.showRemaining([u.position, ..._route.points.skip(i + 1)]);
  }

  void _passStops(NavUpdate u) {
    if (_stopsLeft.isEmpty) return;
    final s = _stopsLeft.first;
    if (distanceM(u.position, s.pos) < 40) {
      setState(() => _stopsLeft.removeAt(0));
      final app = context.appRead;
      if (app.settings.sound == 0) app.speech.say(app.tr('Anda telah tiba di hentian ${s.name}.', 'You have reached ${s.name}.'));
    }
  }

  Future<void> _reroute(Fix fix) async {
    if (_rerouting || DateTime.now().isBefore(_nextRerouteAt)) return;
    final app = context.appRead;
    setState(() => _rerouting = true);
    final now = DateTime.now();
    if (app.settings.sound == 0 &&
        (_lastRecalcSpoken == null || now.difference(_lastRecalcSpoken!) > const Duration(seconds: 10))) {
      _lastRecalcSpoken = now;
      app.speech.say(recalculating(app.lang));
    }
    // Back-off: 3 s, then x1.5 each time, at most 60 s (OsmAnd-style).
    final gap = math.min(60.0, 3 * math.pow(1.5, _rerouteCount)).toDouble();
    _rerouteCount++;
    _nextRerouteAt = now.add(Duration(milliseconds: (gap * 1000).round()));
    try {
      final r = await app.routing.route(
        [fix.pos, ..._stopsLeft.map((s) => s.pos), widget.destination.pos],
        app.settings.routeOptions,
        headingDeg: fix.headingDeg,
        alternates: false,
        offlineOnly: !app.online,
      );
      if (!mounted) return;
      setState(() => _setRoute(r.routes.first));
    } catch (_) {
      // Keep the old route on screen; the next off-route fix tries again.
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  void _checkReports(NavUpdate u, Fix fix) {
    final app = context.appRead;
    final cum = _route.cumDist;
    final warnAt = u.speedKmh > 60 ? 500.0 : 300.0;
    Report? ahead;
    for (final r in app.reports.alive()) {
      // Where along the route is it (if it's on it at all)?
      var bestI = -1;
      var bestD = 60.0;
      for (var i = 0; i < _route.points.length; i += 2) {
        final d = distanceM(_route.points[i], r.pos);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      if (bestI < 0) continue;
      final dist = cum[bestI] - u.travelledM;
      if (dist > 0 && dist < warnAt && !_alerted.contains(r.id)) {
        _alerted.add(r.id);
        ahead = r;
        if (app.settings.sound < 2 &&
            (r.kind == ReportKind.polis ||
                r.kind == ReportKind.kemalangan ||
                r.kind == ReportKind.banjir ||
                r.kind == ReportKind.ditutup)) {
          app.speech.say(_aheadPhrase(app, r));
        }
      }
      // Just passed it, same direction, sensible speed: ask once.
      final sameWay = fix.headingDeg == null || angleDiff(r.heading, fix.headingDeg!).abs() < 45;
      if (dist < -20 && dist > -150 && !r.mine && !app.reports.asked(r) && sameWay && u.speedKmh < 120 && _ask == null) {
        _askAbout(r);
      }
    }
    if (ahead != null) {
      setState(() => _alert = ahead);
      Future.delayed(const Duration(seconds: 12), () {
        if (mounted && _alert == ahead) setState(() => _alert = null);
      });
    }
  }

  String _aheadPhrase(AppState app, Report r) => switch (r.kind) {
    ReportKind.polis => app.tr('Polis dilaporkan di hadapan.', 'Police reported ahead.'),
    ReportKind.kemalangan => app.tr('Kemalangan dilaporkan di hadapan.', 'Crash reported ahead.'),
    ReportKind.banjir => app.tr('Banjir dilaporkan di hadapan.', 'Flooding reported ahead.'),
    ReportKind.ditutup => app.tr('Jalan ditutup dilaporkan di hadapan.', 'Road closure reported ahead.'),
    ReportKind.kesesakan => app.tr('Kesesakan di hadapan.', 'Traffic jam ahead.'),
    ReportKind.bahaya => app.tr('Bahaya di hadapan.', 'Hazard ahead.'),
  };

  void _askAbout(Report r) {
    setState(() => _ask = r);
    _askTimer?.cancel();
    // No answer in 8 s counts as no vote.
    _askTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _ask == r) setState(() => _ask = null);
    });
  }

  void _answer(bool still) {
    final r = _ask;
    if (r == null) return;
    context.appRead.reports.vote(r, still);
    setState(() => _ask = null);
  }

  void _arrive() {
    setState(() => _arrived = true);
    context.appRead.location.start(); // drop the navigation notification
  }

  // ---- UI -------------------------------------------------------------------

  Future<void> _onStyleLoaded() async {
    final m = _map;
    if (m == null) return;
    _layers = MapLayers(m);
    await _layers!.install();
    _styleReady = true;
    await _layers!.showReports(context.appRead.reports.alive());
    await _layers!.showPins([for (final s in _stopsLeft) (s.pos, 'arah-stop'), (widget.destination.pos, 'arah-pin')]);
    await _layers!.showRoutes([_route], 0);
    final fix = context.appRead.location.last;
    if (fix != null) _onFix(fix);
  }

  void _toggleOverview() {
    setState(() {
      _overview = !_overview;
      _following = !_overview;
    });
    if (_overview) {
      _map?.animateCamera(fitPoints(_route.points, top: 220, bottom: 200));
    } else if (_u != null) {
      _camera(_u!);
    }
  }

  void _cycleSound() {
    final s = context.appRead.settings;
    s.sound = (s.sound + 1) % 3;
    if (s.sound != 0) context.appRead.speech.stop();
  }

  Future<void> _end() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Tamatkan navigasi?', 'End navigation?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Teruskan', 'Keep going'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Tamat', 'End'))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final u = _u;
    final ms = _route.maneuvers;
    final next = u != null && u.nextIndex >= 0 ? ms[u.nextIndex] : (ms.length > 1 ? ms[1] : null);
    final then = u != null && u.thenIndex >= 0 ? ms[u.thenIndex] : null;
    final toNext = u?.toNextM ?? (next != null ? _route.cumDist[next.shapeIndex.clamp(0, _route.cumDist.length - 1)] : 0);
    final remainingS = u?.remainingS ?? _route.durationS;
    final remainingM = u?.remainingM ?? _route.distanceM;
    final pad = MediaQuery.of(context).padding;

    return PopScope(
      canPop: _arrived,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Listener(
              onPointerDown: (_) {
                _lastTouch = DateTime.now();
                if (_following) setState(() => _following = false);
              },
              child: MapLibreMap(
                styleString: widget.style,
                initialCameraPosition: CameraPosition(target: ll(app.location.last?.pos ?? _route.start), zoom: 16, tilt: 50),
                onMapCreated: (c) => _map = c,
                onStyleLoadedCallback: _onStyleLoaded,
                myLocationEnabled: true,
                locationSource: const ManualLocationSource(),
                myLocationRenderMode: MyLocationRenderMode.gps,
                compassEnabled: false,
                attributionButtonPosition: AttributionButtonPosition.bottomLeft,
                attributionButtonMargins: Point(8, 120 + pad.bottom),
              ),
            ),

            // Top: next maneuver banner, "then" strip, lanes, alerts.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (next != null && !_arrived) _Banner(maneuver: next, distanceM: toNext, lang: app.lang, topPad: pad.top),
                  if (then != null && !_arrived) _ThenStrip(maneuver: then),
                  if (next != null && next.lanes.isNotEmpty && toNext <= 500 && !_arrived) LaneRow(lanes: next.lanes),
                  if (_rerouting) _Pill(icon: Icons.sync, text: context.tr('Mengira semula laluan…', 'Recalculating…')),
                  if (u?.gpsWeak == true) _Pill(icon: Icons.gps_off, text: context.tr('Isyarat GPS lemah', 'Weak GPS signal')),
                  if (!app.online)
                    _Pill(
                      icon: Icons.cloud_off,
                      text: _offlineRoute
                          ? context.tr('Luar talian — laluan dari peta tersimpan', 'Offline — route from saved map')
                          : context.tr('Luar talian', 'Offline'),
                    ),
                  if (_alert != null) _AlertCard(report: _alert!, onClose: () => setState(() => _alert = null)),
                  if (_ask != null) _AskCard(report: _ask!, onAnswer: _answer),
                ],
              ),
            ),

            // Bottom-left: speedometer and speed-limit sign.
            if (!_arrived)
              Positioned(
                left: 12,
                bottom: 104 + pad.bottom,
                child: _Speedo(
                  kmh: u?.speedKmh ?? 0,
                  limit: app.settings.showSpeedLimit ? (u?.speedLimitKmh ?? 0) : 0,
                  margin: app.settings.speedingMargin,
                ),
              ),

            // Right: sound, report, overview.
            if (!_arrived)
              Positioned(
                right: 12,
                bottom: 104 + pad.bottom,
                child: Column(
                  children: [
                    _RoundBtn(
                      icon: [Icons.volume_up, Icons.campaign_outlined, Icons.volume_off][app.settings.sound],
                      tip: [
                        context.tr('Bunyi', 'Sound on'),
                        context.tr('Amaran sahaja', 'Alerts only'),
                        context.tr('Senyap', 'Muted'),
                      ][app.settings.sound],
                      onTap: _cycleSound,
                    ),
                    const SizedBox(height: 12),
                    _RoundBtn(
                      icon: Icons.report_gmailerrorred,
                      tip: context.tr('Lapor', 'Report'),
                      big: true,
                      color: ArahColors.amber,
                      onTap: () {
                        final f = app.location.last;
                        if (f != null) showReportSheet(context, f.pos, f.headingDeg ?? u?.bearingDeg ?? 0, driving: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    _RoundBtn(
                      icon: _overview ? Icons.navigation : Icons.route,
                      tip: context.tr('Gambaran laluan', 'Route overview'),
                      onTap: _toggleOverview,
                    ),
                  ],
                ),
              ),

            if (!_following && !_overview && !_arrived)
              Positioned(
                left: 0,
                right: 0,
                bottom: 112 + pad.bottom,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _following = true);
                      if (_u != null) _camera(_u!);
                    },
                    icon: const Icon(Icons.navigation),
                    label: Text(context.tr('Pusat semula', 'Re-centre')),
                  ),
                ),
              ),

            // Bottom: ETA bar, or the arrival card.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _arrived
                  ? _ArrivalCard(place: widget.destination, onDone: () => Navigator.pop(context))
                  : _EtaBar(
                      remainingS: remainingS,
                      remainingM: remainingM,
                      lang: app.lang,
                      onEnd: _end,
                      onSteps: () => showStepsSheet(context, _route, fromIndex: u?.nextIndex ?? 0),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Maneuver maneuver;
  final double distanceM;
  final Lang lang;
  final double topPad;
  const _Banner({required this.maneuver, required this.distanceM, required this.lang, required this.topPad});

  @override
  Widget build(BuildContext context) {
    final exit = maneuver.exitNumber.isNotEmpty ? '${lang == Lang.ms ? 'Keluar' : 'Exit'} ${maneuver.exitNumber}' : '';
    final roadText = maneuver.label;
    return Container(
      width: double.infinity,
      color: ArahColors.banner,
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 14),
      child: Row(
        children: [
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(turnIcon(maneuver), color: Colors.white, size: 56),
                  if (maneuver.roundaboutExit > 0)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.white,
                        child: Text(
                          '${maneuver.roundaboutExit}',
                          style: const TextStyle(color: ArahColors.banner, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                displayDistance(distanceM),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (exit.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: ArahColors.amber, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      exit,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                  ),
                Text(
                  roadText.isNotEmpty ? roadText : bannerText(maneuver, lang),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
                ),
                if (roadText.isNotEmpty)
                  Text(
                    bannerText(maneuver, lang).replaceAll(roadText, '').trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThenStrip extends StatelessWidget {
  final Maneuver maneuver;
  const _ThenStrip({required this.maneuver});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      decoration: const BoxDecoration(
        color: ArahColors.brandDark,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('Kemudian', 'Then'),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Icon(turnIcon(maneuver), color: Colors.white, size: 26),
        ],
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ],
    ),
  );
}

class _AlertCard extends StatelessWidget {
  final Report report;
  final VoidCallback onClose;
  const _AlertCard({required this.report, required this.onClose});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: reportColor(report.kind),
        child: Icon(reportIcon(report.kind), color: Colors.white),
      ),
      title: Text(reportName(context, report.kind), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      subtitle: Text(
        [
          context.tr('di hadapan', 'ahead'),
          if (report.confirmed) context.tr('Disahkan', 'Confirmed'),
          '${DateTime.now().difference(report.created).inMinutes} min',
        ].join(' · '),
      ),
      trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
    ),
  );
}

class _AskCard extends StatelessWidget {
  final Report report;
  final ValueChanged<bool> onAnswer;
  const _AskCard({required this.report, required this.onAnswer});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: reportColor(report.kind),
            child: Icon(reportIcon(report.kind), color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${reportName(context, report.kind)} — ${context.tr('masih ada?', 'still there?')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 56)),
            onPressed: () => onAnswer(true),
            child: Text(context.tr('Ya', 'Yes')),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(72, 56)),
            onPressed: () => onAnswer(false),
            child: Text(context.tr('Tiada', 'Gone')),
          ),
        ],
      ),
    ),
  );
}

class _Speedo extends StatelessWidget {
  final double kmh;
  final int limit;
  final int margin;
  const _Speedo({required this.kmh, required this.limit, required this.margin});
  @override
  Widget build(BuildContext context) {
    final speeding = limit > 0 && kmh > limit + margin;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: speeding ? ArahColors.warn : Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${kmh.round()}',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1, color: speeding ? Colors.white : null),
              ),
              Text(context.tr('km/j', 'km/h'), style: TextStyle(fontSize: 12, color: speeding ? Colors.white : null)),
            ],
          ),
        ),
        if (limit > 0) ...[
          const SizedBox(width: 6),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: ArahColors.warn, width: 6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$limit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
            ),
          ),
        ],
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool big;
  final Color? color;
  const _RoundBtn({required this.icon, required this.tip, required this.onTap, this.big = false, this.color});
  @override
  Widget build(BuildContext context) {
    final size = big ? 68.0 : 54.0;
    return Tooltip(
      message: tip,
      child: Material(
        shape: const CircleBorder(),
        elevation: 4,
        color: color ?? Theme.of(context).colorScheme.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: big ? 34 : 26, color: color != null ? Colors.black : null),
          ),
        ),
      ),
    );
  }
}

class _EtaBar extends StatelessWidget {
  final double remainingS, remainingM;
  final Lang lang;
  final VoidCallback onEnd, onSteps;
  const _EtaBar({
    required this.remainingS,
    required this.remainingM,
    required this.lang,
    required this.onEnd,
    required this.onSteps,
  });

  @override
  Widget build(BuildContext context) => Material(
    elevation: 12,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: context.tr('Tamat', 'End'),
              iconSize: 28,
              onPressed: onEnd,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: InkWell(
                onTap: onSteps,
                child: Column(
                  children: [
                    Text(
                      fmtEta(remainingS),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                        height: 1.1,
                      ),
                    ),
                    Text('${fmtDuration(remainingS, lang)} · ${fmtKm(remainingM)}', style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: context.tr('Langkah', 'Steps'),
              iconSize: 28,
              onPressed: onSteps,
              icon: const Icon(Icons.list),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ArrivalCard extends StatelessWidget {
  final Place place;
  final VoidCallback onDone;
  const _ArrivalCard({required this.place, required this.onDone});
  @override
  Widget build(BuildContext context) {
    final s = context.app.settings;
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.flag_circle, size: 48, color: ArahColors.brand),
              const SizedBox(height: 8),
              Text(
                context.tr('Anda telah tiba', 'You have arrived'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(place.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: s.isFavourite(place) ? null : () => s.addFavourite(place),
                      icon: const Icon(Icons.star_border),
                      label: Text(context.tr('Simpan', 'Save')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(onPressed: onDone, child: Text(context.tr('Selesai', 'Done'))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
