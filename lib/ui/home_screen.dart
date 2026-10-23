// The map you open the app to (app study §S1), with the place card (§S3) and
// route preview (§S4) as bottom panels over it.
import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../config.dart';
import '../core/geo.dart';
import '../core/settings.dart';
import '../nav/nav_engine.dart';
import '../offline/map_style.dart';
import '../routing/route_model.dart';
import '../routing/tolls.dart';
import '../routing/traffic.dart';
import '../search/place.dart';
import 'format.dart';
import 'map_kit.dart';
import 'mochi.dart';
import 'nav_screen.dart';
import 'offline_screen.dart';
import 'report_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'steps_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MapLibreMapController? _map;
  MapLayers? _layers;
  late final _puck = MochiPuck(() => _styleReady ? _layers : null);

  /// Mochi's hello on the home map; hides after a few seconds or on any trip.
  bool _greet = true;
  String? _style;
  String _styleKey = '';
  bool _styleReady = false;
  bool _following = false;
  bool _movedToFix = false;
  StreamSubscription? _fixSub;

  Place? _place; // selected place (place card)
  // Route preview ends, Google Maps-style: either can be changed or swapped.
  // A Place with source 'me' means "your location".
  Place? _from;
  Place? _to;
  final List<Place> _stops = []; // stops between start and end
  List<ArahRoute> _routes = [];
  List<TollEstimate?> _tolls = [];
  int _sel = 0;
  bool _picked = false; // the user chose a route themselves
  bool _routing = false;
  String? _routeError;
  bool _routeOffline = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted && _greet) setState(() => _greet = false);
    });
  }

  Future<void> _start() async {
    final app = context.appRead;
    app.packs.addListener(_refreshStyle);
    app.reports.addListener(_drawReports);
    await _refreshStyle();
    if (await app.location.ensurePermission()) {
      await app.location.start();
      _fixSub = app.location.fixes.listen(_onFix);
      // Indoors the first GPS fix can take a while: start from the last known one.
      final last = await app.location.current();
      if (last != null) _onFix(last);
    }
    app.reports.watch(app.here);
  }

  @override
  void dispose() {
    _puck.dispose();
    _fixSub?.cancel();
    final app = context.appRead;
    app.packs.removeListener(_refreshStyle);
    app.reports.removeListener(_drawReports);
    super.dispose();
  }

  bool get _dark => context.appRead.settings.darkNow;

  /// Online: OpenFreeMap's world map. Offline (or if it can't be fetched): the
  /// installed packs, which only cover Malaysia, Singapore and Brunei.
  Future<void> _refreshStyle() async {
    final app = context.appRead;
    final view = app.settings.mapView;
    final traffic = app.settings.traffic;
    final key = '${app.packs.installed.keys.join(',')}|$_dark|${app.online}|${view.name}|$traffic';
    if (key == _styleKey) return;
    _styleKey = key;
    final online = app.online ? await MapStyles.onlineStyle(dark: _dark, view: view, traffic: traffic) : null;
    final style =
        online ??
        await MapStyles.offlineStyle(app.packs, dark: _dark) ??
        (_dark ? ArahConfig.onlineDarkStyleUrl : ArahConfig.onlineStyleUrl);
    if (!mounted) return;
    setState(() {
      _style = style;
      _styleReady = false;
    });
  }

  void _onFix(Fix fix) {
    final m = _map;
    if (m == null) return;
    _puck.moveTo(fix.pos, fix.headingDeg, glide: const Duration(milliseconds: 600));
    if (!_movedToFix) {
      _movedToFix = true;
      context.appRead.routing.preload(fix.pos);
      if (_place == null) m.animateCamera(CameraUpdate.newLatLngZoom(ll(fix.pos), 15));
    } else if (_following) {
      // Same glide as Mochi, so Mochi stays in the middle.
      m.animateCamera(CameraUpdate.newLatLng(ll(fix.pos)), duration: const Duration(milliseconds: 600));
    }
  }

  Future<void> _onStyleLoaded() async {
    final m = _map;
    if (m == null) return;
    _layers = MapLayers(m);
    await _layers!.install();
    _styleReady = true;
    _puck.redraw();
    await _drawReports();
    await _drawSelection();
    final fix = context.appRead.location.last;
    if (fix != null) _onFix(fix);
  }

  /// Live traffic times for the routes on screen; then the fastest one with
  /// today's traffic is chosen, unless the user already picked one.
  Future<void> _addTraffic(List<ArahRoute> routes) async {
    final times = await Future.wait([for (final r in routes) TrafficEta.along(r.points)]);
    if (!mounted || !identical(routes, _routes)) return;
    setState(() {
      for (var i = 0; i < routes.length; i++) {
        final t = times[i];
        if (t == null) continue;
        routes[i].liveS = t.liveS;
        routes[i].trafficDelayS = t.delayS;
      }
      if (!_picked) _sel = fastestRoute(routes);
    });
    await _drawSelection();
  }

  Future<void> _drawReports() async {
    if (!_styleReady) return;
    await _layers?.showReports(context.appRead.reports.alive());
  }

  Future<void> _drawSelection() async {
    if (!_styleReady || _layers == null) return;
    await _layers!.showRoutes(_routes, _sel);
    final end = _previewing ? _to : _place;
    await _layers!.showPins([
      if (_previewing && !_isMe(_from)) (_from!.pos, 'arah-start'),
      for (final s in _stops) (s.pos, 'arah-stop'),
      if (end != null && !_isMe(end)) (end.pos, 'arah-pin'),
    ]);
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _openSearch({Category? category}) async {
    final app = context.appRead;
    final near = _map?.cameraPosition != null ? geo(_map!.cameraPosition!.target) : app.here;
    final p = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(near: near, startCategory: category),
      ),
    );
    if (p != null) _select(p);
  }

  Future<void> _select(Place p) async {
    setState(() {
      _greet = false;
      _place = p;
      _from = null;
      _to = null;
      _routes = [];
      _stops.clear();
      _previewing = false;
      _routeError = null;
    });
    _drawSelection();
    // Stop following the GPS first: a fix arriving mid-flight would pull the
    // camera back towards you and leave it short of the place.
    _following = false;
    // In a browser the map is resized as the search screen closes, and the
    // resize stops a camera flight part-way; start after it settles.
    if (kIsWeb) await Future<void>.delayed(const Duration(milliseconds: 350));
    _map?.animateCamera(CameraUpdate.newLatLngZoom(ll(p.pos), 16));
  }

  void _clear() {
    setState(() {
      _place = null;
      _from = null;
      _to = null;
      _routes = [];
      _stops.clear();
      _previewing = false;
      _routeError = null;
    });
    _drawSelection();
  }

  Future<void> _longPress(Point<double> _, LatLng at) async {
    HapticFeedback.mediumImpact();
    final app = context.appRead;
    final g = geo(at);
    _select(Place(name: app.tr('Pin dijatuhkan', 'Dropped pin'), pos: g, kind: 'pin', source: 'pin'));
    final named = await app.search.describe(g, isOnline: app.online);
    if (mounted && _place?.pos == g) setState(() => _place = named);
  }

  Place _me() =>
      Place(name: context.appRead.tr('Lokasi anda', 'Your location'), pos: context.appRead.here, source: 'me');
  bool _isMe(Place? p) => p == null || p.source == 'me';

  Future<void> _directions() async {
    final app = context.appRead;
    if (!_previewing) {
      if (_place == null) return;
      _from = _me();
      _to = _place;
    }
    final fix = app.location.last;
    if ((_isMe(_from) || _isMe(_to)) && fix == null) {
      _snack(app.tr('Menunggu GPS…', 'Waiting for GPS…'));
      return;
    }
    final start = _isMe(_from) ? fix!.pos : _from!.pos;
    final end = _isMe(_to) ? fix!.pos : _to!.pos;
    setState(() {
      _previewing = true;
      _routing = true;
      _routeError = null;
    });
    try {
      final r = await app.routing.route(
        [start, ..._stops.map((s) => s.pos), end],
        app.settings.routeOptions,
        headingDeg: _isMe(_from) ? fix!.headingDeg : null,
        offlineOnly: !app.online,
      );
      if (!mounted) return;
      final t = app.tolls;
      setState(() {
        _routes = r.routes;
        _tolls = [for (final rt in r.routes) t?.estimate(rt, app.settings.mode)];
        _sel = 0;
        _picked = false;
        _routing = false;
        _routeOffline = r.usedOffline;
      });
      await _drawSelection();
      if (!r.usedOffline) _addTraffic(r.routes);
      _following = false;
      _map?.animateCamera(fitPoints([for (final rt in _routes) ...rt.points], top: 120, bottom: 420));
    } on RoutingException catch (e) {
      if (!mounted) return;
      setState(() {
        _routing = false;
        _routes = [];
        _routeError = e.busy || e.message == 'busy'
            ? app.tr('Pelayan sibuk, cuba lagi', 'Server busy, try again')
            : app.packs.installed.isEmpty && !app.online
            ? app.tr(
                'Tiada isyarat. Muat turun peta luar talian untuk navigasi tanpa internet.',
                'No signal. Download an offline map to navigate without internet.',
              )
            : app.tr('Tiada laluan ditemui', 'No route found');
      });
      await _drawSelection();
    }
  }

  Future<void> _addStop() async {
    final app = context.appRead;
    final p = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(near: _to?.pos ?? app.here, hint: app.tr('Tambah hentian', 'Add a stop')),
      ),
    );
    if (p == null || _stops.length >= 3) return;
    setState(() => _stops.add(p));
    await _directions();
  }

  /// Change the start (0) or the end (1) of the route.
  Future<void> _editEnd(int which) async {
    final app = context.appRead;
    final current = which == 0 ? _from : _to;
    final p = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          near: current?.pos ?? app.here,
          hint: which == 0
              ? app.tr('Pilih titik mula', 'Choose start')
              : app.tr('Pilih destinasi', 'Choose destination'),
          offerMyLocation: true,
        ),
      ),
    );
    if (p == null) return;
    setState(() => which == 0 ? _from = p : _to = p);
    if (_isMe(_from) && _isMe(_to)) {
      _snack(app.tr('Titik mula dan destinasi sama', 'Start and destination are the same'));
      return;
    }
    await _directions();
  }

  Future<void> _swap() async {
    setState(() {
      final f = _from;
      _from = _to;
      _to = f;
      _stops.setAll(0, _stops.reversed.toList());
    });
    await _directions();
  }

  Future<void> _startNav() async {
    final app = context.appRead;
    if (_routes.isEmpty) return;
    app.speech.unlock();
    var route = _routes[_sel];
    var stops = List.of(_stops);
    final fix = app.location.last;
    final dest = _isMe(_to)
        ? (fix == null ? null : Place(name: app.tr('Lokasi anda', 'Your location'), pos: fix.pos, source: 'pin'))
        : _to;
    if (dest == null) {
      _snack(app.tr('Menunggu GPS…', 'Waiting for GPS…'));
      return;
    }
    // Starting somewhere else: drive to that start first, then carry on —
    // the chosen start becomes the first stop.
    if (!_isMe(_from)) {
      if (fix == null) {
        _snack(app.tr('Menunggu GPS…', 'Waiting for GPS…'));
        return;
      }
      setState(() => _routing = true);
      try {
        final r = await app.routing.route(
          [fix.pos, _from!.pos, ..._stops.map((s) => s.pos), dest.pos],
          app.settings.routeOptions,
          headingDeg: fix.headingDeg,
          alternates: false,
          offlineOnly: !app.online,
        );
        route = r.routes.first;
        stops = [_from!, ..._stops];
      } on RoutingException {
        if (mounted) {
          setState(() => _routing = false);
          _snack(app.tr('Tiada laluan ke titik mula', 'No route to the start point'));
        }
        return;
      }
      if (!mounted) return;
      setState(() => _routing = false);
      _snack(app.tr('Arah akan bawa anda ke ${_from!.name} dahulu', 'Arah will take you to ${_from!.name} first'));
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavScreen(route: route, destination: dest, stops: stops, style: _style!),
      ),
    );
    if (!mounted) return;
    _clear();
    await app.location.start();
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _report() async {
    final app = context.appRead;
    final fix = app.location.last;
    if (fix == null) {
      _snack(app.tr('Menunggu GPS…', 'Waiting for GPS…'));
      return;
    }
    await showReportSheet(context, fix.pos, fix.headingDeg ?? 0);
  }

  /// Map type (standard / satellite / terrain) and theme, like Google Maps' layers sheet.
  Future<void> _layersSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => _LayersSheet(onChanged: _refreshStyle),
    );
  }

  Future<void> _myLocation() async {
    final app = context.appRead;
    final fix = app.location.last;
    if (fix == null) {
      if (!await app.location.ensurePermission()) {
        _snack(app.tr('Benarkan lokasi dalam tetapan telefon', 'Allow location in phone settings'));
        return;
      }
      await app.location.start();
      _fixSub ??= app.location.fixes.listen(_onFix);
      return;
    }
    setState(() => _following = true);
    // One smooth move to you; following stays on until a finger moves the map.
    final zoom = _map?.cameraPosition?.zoom ?? 0;
    _map?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: ll(fix.pos), zoom: zoom < 15 ? 16 : zoom)),
      duration: const Duration(milliseconds: 900),
    );
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.online.toString() != _styleKey.split('|').last && _styleKey.isNotEmpty) {
      // Network changed: the style may switch font source; do it after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStyle());
    }
    final bottomPanel = _previewing
        ? _RoutePreview(
            from: _from ?? _me(),
            to: _to ?? _me(),
            onEditFrom: () => _editEnd(0),
            onEditTo: () => _editEnd(1),
            onSwap: _swap,
            stops: _stops,
            routes: _routes,
            tolls: _tolls,
            selected: _sel,
            loading: _routing,
            error: _routeError,
            offline: _routeOffline,
            onSelect: (i) {
              setState(() {
                _sel = i;
                _picked = true;
              });
              _drawSelection();
            },
            onStart: _startNav,
            onClose: () {
              setState(() {
                _previewing = false;
                _routes = [];
                _stops.clear();
              });
              _drawSelection();
            },
            onAddStop: _stops.length < 3 ? _addStop : null,
            onRemoveStop: (i) {
              setState(() => _stops.removeAt(i));
              _directions();
            },
            onReroute: _directions,
          )
        : _place != null
        ? _PlaceCard(place: _place!, onDirections: _directions, onClose: _clear)
        : null;

    return Scaffold(
      body: Stack(
        children: [
          if (_style != null)
            // A finger on the map stops following you (the camera's own moves don't).
            Listener(
              onPointerDown: (_) {
                if (_following) setState(() => _following = false);
              },
              child: MapLibreMap(
                key: ValueKey(_style.hashCode),
                styleString: _style!,
                initialCameraPosition: CameraPosition(target: ll(app.here), zoom: app.hasFix ? 15 : 11),
                onMapCreated: (c) {
                  _map = c;
                  c.onFeatureTapped.add((_, _, id, layerId, _) {
                    if (layerId == 'arah-route-alt' || layerId == 'arah-route') {
                      final i = int.tryParse(id);
                      if (i != null && i < _routes.length) {
                        setState(() {
                          _sel = i;
                          _picked = true;
                        });
                        _drawSelection();
                      }
                    }
                  });
                },
                onStyleLoadedCallback: _onStyleLoaded,
                // Mochi marks where you are (MochiPuck), not the built-in dot.
                myLocationEnabled: false,
                locationSource: const ManualLocationSource(),
                myLocationRenderMode: MyLocationRenderMode.compass,
                trackCameraPosition: true,
                compassEnabled: true,
                compassViewPosition: CompassViewPosition.topRight,
                compassViewMargins: const Point(16, 190),
                // No (i) on the map: the credits are in Settings → About.
                attributionButtonPosition: AttributionButtonPosition.bottomLeft,
                attributionButtonMargins: const Point(-400, -400),
                onMapLongClick: _longPress,
              ),
            ),
          // Search bar and quick categories.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: ArahColors.shadow(context),
                    ),
                    child: Material(
                      shape: const StadiumBorder(),
                      color: Theme.of(context).colorScheme.surface,
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _openSearch(),
                        child: SizedBox(
                          height: 58,
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              const Mochi(size: 40),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.tr('Nak ke mana hari ni?', 'Where to today?'),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Material(
                                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: context.tr('Tetapan', 'Settings'),
                                  icon: const Icon(Icons.menu_rounded),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_previewing) const SizedBox(height: 10),
                  if (!_previewing)
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        // Let the chips' soft shadows spill out instead of being cut square.
                        clipBehavior: Clip.none,
                        children: [
                          _chip(Icons.home, context.tr('Rumah', 'Home'), () {
                            final h = app.settings.home;
                            h != null
                                ? _select(h)
                                : _snack(
                                    app.tr(
                                      'Pilih tempat, kemudian "Tetapkan Rumah"',
                                      'Pick a place, then "Set as Home"',
                                    ),
                                  );
                          }),
                          _chip(Icons.work, context.tr('Kerja', 'Work'), () {
                            final w = app.settings.work;
                            w != null
                                ? _select(w)
                                : _snack(
                                    app.tr(
                                      'Pilih tempat, kemudian "Tetapkan Kerja"',
                                      'Pick a place, then "Set as Work"',
                                    ),
                                  );
                          }),
                          for (final c in categories.take(4))
                            _chip(c.icon, app.tr(c.ms, c.en), () => _openSearch(category: c)),
                        ],
                      ),
                    ),
                  if (!app.online)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: ArahColors.ink, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              app.packs.installed.isEmpty
                                  ? context.tr('Luar talian — tiada peta dimuat turun', 'Offline — no downloaded map')
                                  : context.tr('Luar talian — guna peta tersimpan', 'Offline — using saved map'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Right-hand buttons.
          Positioned(
            right: 12,
            bottom:
                (bottomPanel != null ? 16 : 32) + MediaQuery.of(context).padding.bottom + (bottomPanel != null ? 0 : 0),
            child: SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.only(bottom: bottomPanel != null ? (_previewing ? 300 : 210) : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _fab(Icons.layers_rounded, context.tr('Jenis peta', 'Map type'), _layersSheet, small: true),
                    const SizedBox(height: 12),
                    _fab(Icons.report_rounded, context.tr('Lapor', 'Report'), _report, color: ArahColors.amber),
                    const SizedBox(height: 12),
                    _fab(
                      _following ? Icons.my_location_rounded : Icons.location_searching_rounded,
                      context.tr('Lokasi saya', 'My location'),
                      _myLocation,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (bottomPanel != null) Positioned(left: 0, right: 0, bottom: 0, child: bottomPanel),
          if (_greet && bottomPanel == null && (kIsWeb || app.packs.installed.isNotEmpty))
            Positioned(
              left: 12,
              bottom: 32 + MediaQuery.of(context).padding.bottom,
              right: 96,
              child: _Greeting(onClose: () => setState(() => _greet = false)),
            ),
          if (!kIsWeb && app.packs.installed.isEmpty && bottomPanel == null)
            Positioned(
              left: 12,
              bottom: 32 + MediaQuery.of(context).padding.bottom,
              right: 84,
              child: _OfflineNudge(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineScreen())),
              ),
            ),
        ],
      ),
    );
  }

  /// A white pill with the icon in a soft pink dot (Mochi chips).
  Widget _chip(IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: ArahColors.shadow(context, blur: 12, y: 4),
        ),
        child: Material(
          color: scheme.surface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(icon, size: 17, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Round button with a soft pink shadow.
  Widget _fab(IconData icon, String tip, VoidCallback onTap, {Color? color, bool small = false}) {
    final scheme = Theme.of(context).colorScheme;
    final size = small ? 50.0 : 62.0;
    return Tooltip(
      message: tip,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: ArahColors.shadow(context, blur: 16, y: 6)),
        child: Material(
          color: color ?? scheme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: small ? 24 : 30, color: color != null ? const Color(0xFF6B4300) : scheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mochi says hello when the app opens; goes away by itself.
class _Greeting extends StatelessWidget {
  final VoidCallback onClose;
  const _Greeting({required this.onClose});
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final hello = h < 12
        ? context.tr('Selamat pagi!', 'Good morning!')
        : h < 15
        ? context.tr('Selamat tengah hari!', 'Good afternoon!')
        : h < 19
        ? context.tr('Selamat petang!', 'Good evening!')
        : context.tr('Selamat malam!', 'Good night!');
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: ArahColors.shadow(context)),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mochi(size: 38),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(hello, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        Text(
                          context.tr('Tekan carian untuk mula', 'Tap search to start a trip'),
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineNudge extends StatelessWidget {
  final VoidCallback onTap;
  const _OfflineNudge({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    elevation: 0,
    borderRadius: BorderRadius.circular(24),
    color: Theme.of(context).colorScheme.surface,
    shadowColor: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Mochi(size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr(
                  'Muat turun peta Malaysia untuk guna tanpa internet',
                  'Download the Malaysia map to use it without internet',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom card for a chosen place (§S3).
class _PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback onDirections;
  final VoidCallback onClose;
  const _PlaceCard({required this.place, required this.onDirections, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    final fav = s.isFavourite(place);
    final d = app.hasFix ? distanceM(app.here, place.pos) : null;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (place.context.isNotEmpty) place.context, if (d != null) fmtKm(d)].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: context.tr('Tutup', 'Close'), icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onDirections,
                  icon: const Icon(Icons.directions),
                  label: Text(context.tr('Arah', 'Directions')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: Icon(fav ? Icons.star : Icons.star_border, size: 18),
                label: Text(fav ? context.tr('Disimpan', 'Saved') : context.tr('Simpan', 'Save')),
                onPressed: () => fav ? s.removeFavourite(place) : s.addFavourite(place),
              ),
              ActionChip(
                avatar: const Icon(Icons.home_outlined, size: 18),
                label: Text(context.tr('Tetapkan Rumah', 'Set as Home')),
                onPressed: () {
                  s.home = place;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(context.tr('Rumah ditetapkan', 'Home set'))));
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.work_outline, size: 18),
                label: Text(context.tr('Tetapkan Kerja', 'Set as Work')),
                onPressed: () {
                  s.work = place;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(context.tr('Kerja ditetapkan', 'Work set'))));
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.copy, size: 18),
                label: Text(context.tr('Salin pautan', 'Copy link')),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          '${place.name}\nhttps://www.openstreetmap.org/?mlat=${place.pos.lat.toStringAsFixed(6)}'
                          '&mlon=${place.pos.lon.toStringAsFixed(6)}#map=17/${place.pos.lat}/${place.pos.lon}',
                    ),
                  );
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(context.tr('Pautan disalin', 'Link copied'))));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Route preview (§S4): mode, stops, up to three routes, start.
class _RoutePreview extends StatelessWidget {
  final Place from, to;
  final VoidCallback onEditFrom, onEditTo, onSwap;
  final List<Place> stops;
  final List<ArahRoute> routes;
  final List<TollEstimate?> tolls;
  final int selected;
  final bool loading;
  final String? error;
  final bool offline;
  final ValueChanged<int> onSelect;
  final VoidCallback onStart, onClose, onReroute;
  final VoidCallback? onAddStop;
  final ValueChanged<int> onRemoveStop;

  const _RoutePreview({
    required this.from,
    required this.to,
    required this.onEditFrom,
    required this.onEditTo,
    required this.onSwap,
    required this.stops,
    required this.routes,
    required this.tolls,
    required this.selected,
    required this.loading,
    required this.error,
    required this.offline,
    required this.onSelect,
    required this.onStart,
    required this.onClose,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onReroute,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    final theme = Theme.of(context);
    final best = fastestRoute(routes);
    final fastest = routes.isEmpty ? 0.0 : routes[best].etaS;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<TravelMode>(
                  segments: [
                    ButtonSegment(
                      value: TravelMode.car,
                      icon: const Icon(Icons.directions_car),
                      label: Text(context.tr('Kereta', 'Car')),
                    ),
                    ButtonSegment(
                      value: TravelMode.motorcycle,
                      icon: const Icon(Icons.two_wheeler),
                      label: Text(context.tr('Motosikal', 'Motorbike')),
                    ),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (v) {
                    s.mode = v.first;
                    onReroute();
                  },
                ),
              ),
              IconButton(
                tooltip: context.tr('Pilihan laluan', 'Route options'),
                icon: const Icon(Icons.tune),
                onPressed: () => _options(context),
              ),
              IconButton(tooltip: context.tr('Tutup', 'Close'), icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 8),
          // From, stops, to — each end can be changed; ⇅ swaps them.
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _EndField(
                      icon: Icons.trip_origin,
                      color: ArahColors.sky,
                      label: context.tr('Dari', 'From'),
                      text: from.name,
                      onTap: onEditFrom,
                    ),
                    for (var i = 0; i < stops.length; i++)
                      _StopRow(icon: Icons.flag_outlined, text: stops[i].name, onRemove: () => onRemoveStop(i)),
                    _EndField(
                      icon: Icons.place,
                      color: ArahColors.brand,
                      label: context.tr('Ke', 'To'),
                      text: to.name,
                      onTap: onEditTo,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('Tukar titik mula dan destinasi', 'Swap start and destination'),
                icon: const Icon(Icons.swap_vert, size: 30),
                onPressed: onSwap,
              ),
            ],
          ),
          if (onAddStop != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddStop,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Tambah hentian', 'Add stop')),
              ),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null && !loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(error!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onReroute, child: Text(context.tr('Cuba lagi', 'Try again'))),
                ],
              ),
            ),
          if (routes.isNotEmpty && !loading) ...[
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = routes[i];
                  final sel = i == selected;
                  final extra = r.etaS - fastest;
                  final tag = i == best
                      ? context.tr('Terpantas', 'Fastest')
                      : extra < 60
                      ? context.tr('Hampir sama', 'About the same')
                      : '+${(extra / 60).round()} min';
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSelect(i),
                    child: Container(
                      width: 156,
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: sel ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surface,
                        border: Border.all(
                          color: sel ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                          width: sel ? 2.5 : 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fmtDuration(r.etaS, app.lang),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: sel ? theme.colorScheme.primary : null,
                            ),
                          ),
                          Row(
                            children: [
                              Text(fmtKm(r.distanceM)),
                              if (i < tolls.length && tolls[i] != null && !tolls[i]!.isEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${tolls[i]!.approximate ? '~' : ''}${fmtRm(tolls[i]!.total)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: theme.brightness == Brightness.light ? ArahColors.toll : ArahColors.amber,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              if (i == best)
                                Container(
                                  margin: const EdgeInsets.only(top: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.auto_awesome_rounded, size: 12, color: theme.colorScheme.onPrimary),
                                      const SizedBox(width: 3),
                                      Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(tag, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                              if (r.trafficDelayS >= 120) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.traffic_rounded, size: 15, color: trafficColor(r.trafficDelayS, r.etaS)),
                                Text(
                                  '+${(r.trafficDelayS / 60).round()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: trafficColor(r.trafficDelayS, r.etaS),
                                  ),
                                ),
                              ],
                              if (r.hasToll && (i >= tolls.length || tolls[i] == null || tolls[i]!.isEmpty)) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.toll, size: 16),
                              ],
                              if (r.hasFerry) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.directions_boat, size: 16),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _RouteInfo(
              route: routes[selected],
              offline: offline,
              toll: selected < tolls.length ? tolls[selected] : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => showStepsSheet(context, routes[selected]),
                  icon: const Icon(Icons.format_list_bulleted_rounded),
                  label: Text(context.tr('Langkah', 'Steps')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Always Start: from somewhere else, Arah guides you to that start first.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.navigation_rounded),
                      label: Text(context.tr('Jom!', "Let's go!")),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _options(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return AnimatedBuilder(
          animation: context.appRead.settings,
          builder: (ctx, _) {
            final s = context.appRead.settings;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(context.appRead.tr('Elak tol', 'Avoid tolls')),
                    value: s.avoidTolls,
                    onChanged: (v) => s.avoidTolls = v,
                  ),
                  SwitchListTile(
                    title: Text(context.appRead.tr('Elak lebuh raya', 'Avoid highways')),
                    value: s.avoidHighways,
                    onChanged: (v) => s.avoidHighways = v,
                  ),
                  SwitchListTile(
                    title: Text(context.appRead.tr('Elak feri', 'Avoid ferries')),
                    value: s.avoidFerries,
                    onChanged: (v) => s.avoidFerries = v,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onReroute();
                      },
                      child: Text(context.appRead.tr('Kira semula laluan', 'Update route')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RouteInfo extends StatelessWidget {
  final ArahRoute route;
  final bool offline;
  final TollEstimate? toll;
  const _RouteInfo({required this.route, required this.offline, this.toll});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    // Reports within 60 m of the route.
    final counts = <String, int>{};
    for (final r in app.reports.alive()) {
      for (var i = 0; i < route.points.length; i += 3) {
        if (distanceM(route.points[i], r.pos) < 60) {
          counts[r.kind.name] = (counts[r.kind.name] ?? 0) + 1;
          break;
        }
      }
    }
    final s = app.settings;
    final camList = s.cameraAlerts
        ? (app.cameras?.along(route, unverified: s.unverifiedCameras) ?? const [])
        : const [];
    final cams = camList.where((c) => c.camera.verified).length;
    final unverified = camList.length - cams;
    final parts = <String>[
      '${context.tr('Tiba', 'Arrive')} ${fmtEta(route.etaS)}',
      if (route.trafficDelayS >= 120)
        context.tr(
          '+${(route.trafficDelayS / 60).round()} min sebab trafik',
          '+${(route.trafficDelayS / 60).round()} min for traffic',
        ),
      if (route.hasToll && (toll == null || toll!.isEmpty))
        context.tr('Ada tol (harga tidak diketahui)', 'Has tolls (price unknown)'),
      if (route.hasFerry) context.tr('Ada feri', 'Has ferry'),
      if (cams > 0) context.tr('$cams kamera laju', cams == 1 ? '1 speed camera' : '$cams speed cameras'),
      if (unverified > 0)
        context.tr(
          '$unverified kamera tidak disahkan',
          unverified == 1 ? '1 unverified camera' : '$unverified unverified cameras',
        ),
      for (final e in counts.entries) '${e.value} ${_kindName(context, e.key)}',
      if (offline) context.tr('Laluan luar talian', 'Offline route'),
    ];
    final t = toll;
    final scheme = Theme.of(context).colorScheme;
    Widget pill(IconData icon, String text, {VoidCallback? onTap, bool strong = false}) => Material(
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(fontSize: strong ? 15 : 13.5, fontWeight: FontWeight.w800),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (t != null && !t.isEmpty)
          pill(
            Icons.toll_rounded,
            '${context.tr('Tol', 'Tolls')} ${t.approximate ? '~' : ''}${fmtRm(t.total)} · '
            '${context.app.settings.mode == TravelMode.motorcycle ? context.tr('motosikal', 'motorbike') : context.tr('kereta', 'car')}',
            onTap: () => _breakdown(context, t),
            strong: true,
          ),
        for (final p in parts) pill(_iconFor(p, context), p),
      ],
    );
  }

  IconData _iconFor(String part, BuildContext context) {
    final p = part.toLowerCase();
    if (p.startsWith(context.tr('tiba', 'arrive').toLowerCase())) return Icons.schedule_rounded;
    if (p.contains(context.tr('kamera', 'camera'))) return Icons.photo_camera_rounded;
    if (p.contains(context.tr('feri', 'ferry'))) return Icons.directions_boat_rounded;
    if (p.contains(context.tr('trafik', 'traffic'))) return Icons.traffic_rounded;
    if (p.contains(context.tr('tol', 'toll'))) return Icons.toll_rounded;
    if (p.contains(context.tr('luar talian', 'offline'))) return Icons.cloud_off_rounded;
    return Icons.campaign_rounded;
  }

  /// Plaza-by-plaza list, with where the prices came from.
  void _breakdown(BuildContext context, TollEstimate t) {
    final app = context.appRead;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(app.tr('Anggaran tol', 'Toll estimate'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final i in t.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.toll),
                  title: Text(i.name),
                  trailing: Text('${i.approximate ? '~' : ''}${fmtRm(i.amount)}', style: const TextStyle(fontSize: 16)),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(app.tr('Jumlah', 'Total'), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text(
                  '${t.approximate ? '~' : ''}${fmtRm(t.total)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                app.tr(
                  'Harga dari LLM dan pemegang konsesi (${app.tolls?.updated ?? '-'}). "~" ialah anggaran ikut jarak. Harga sebenar di plaza mungkin berbeza.',
                  'Rates from LLM and the concessionaires (${app.tolls?.updated ?? '-'}). "~" is estimated by distance. The plaza may charge differently.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _kindName(BuildContext c, String k) => switch (k) {
    'polis' => c.tr('laporan polis', 'police'),
    'kemalangan' => c.tr('kemalangan', 'crash'),
    'kesesakan' => c.tr('kesesakan', 'jam'),
    'bahaya' => c.tr('bahaya', 'hazard'),
    'banjir' => c.tr('banjir', 'flood'),
    _ => c.tr('jalan ditutup', 'closure'),
  };
}

/// A tappable From / To field.
class _EndField extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, text;
  final VoidCallback onTap;
  const _EndField({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
              const SizedBox(width: 10),
              Text('$label  ', style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Icon(Icons.edit_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StopRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRemove;
  const _StopRow({required this.icon, required this.text, this.onRemove});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        ),
        if (onRemove != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      boxShadow: ArahColors.shadow(context, blur: 24, y: -6),
    ),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _LayersSheet extends StatelessWidget {
  final VoidCallback onChanged;
  const _LayersSheet({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    Widget tile(MapView v, IconData icon, String ms, String en) {
      final on = s.mapView == v;
      final scheme = Theme.of(context).colorScheme;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            s.mapView = v;
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? scheme.primary : Colors.transparent, width: 2.5),
                  ),
                  child: Icon(icon, size: 32, color: on ? scheme.primary : null),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(ms, en),
                  style: TextStyle(
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? scheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Jenis peta', 'Map type'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                tile(MapView.standard, Icons.map_outlined, 'Biasa', 'Default'),
                tile(MapView.satellite, Icons.satellite_alt_outlined, 'Satelit', 'Satellite'),
                tile(MapView.terrain, Icons.terrain_outlined, 'Rupa bumi', 'Terrain'),
              ],
            ),
            if (!app.online)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    'Satelit dan rupa bumi perlukan internet; peta luar talian dipaparkan.',
                    'Satellite and terrain need internet; showing the offline map.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (ArahConfig.tomtomKey.isNotEmpty) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.traffic_outlined),
                title: Text(context.tr('Trafik', 'Traffic')),
                subtitle: Text(
                  app.online
                      ? context.tr('Jalan perlahan dan sesak', 'Slow and jammed roads')
                      : context.tr('Perlukan internet', 'Needs internet'),
                ),
                value: s.traffic,
                onChanged: (v) {
                  s.traffic = v;
                  onChanged();
                },
              ),
            ],
            const SizedBox(height: 16),
            Text(context.tr('Tema', 'Theme'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<MapTheme>(
                segments: [
                  ButtonSegment(value: MapTheme.auto, label: Text(context.tr('Auto', 'Auto'))),
                  ButtonSegment(value: MapTheme.light, label: Text(context.tr('Cerah', 'Light'))),
                  ButtonSegment(value: MapTheme.dark, label: Text(context.tr('Gelap', 'Dark'))),
                ],
                selected: {s.theme},
                onSelectionChanged: (v) {
                  s.theme = v.first;
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
