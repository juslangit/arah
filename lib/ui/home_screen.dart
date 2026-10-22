// The map you open the app to (app study §S1), with the place card (§S3) and
// route preview (§S4) as bottom panels over it.
import 'dart:async';
import 'dart:math' show Point;

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
import '../search/place.dart';
import 'format.dart';
import 'map_kit.dart';
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
  bool _routing = false;
  String? _routeError;
  bool _routeOffline = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
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
    _fixSub?.cancel();
    final app = context.appRead;
    app.packs.removeListener(_refreshStyle);
    app.reports.removeListener(_drawReports);
    super.dispose();
  }

  bool get _dark {
    final t = context.appRead.settings.theme;
    if (t == MapTheme.auto) {
      final h = DateTime.now().hour;
      return h >= 19 || h < 7;
    }
    return t == MapTheme.dark;
  }

  /// Offline pack style when one is installed, OpenFreeMap otherwise.
  Future<void> _refreshStyle() async {
    final app = context.appRead;
    final key = '${app.packs.installed.keys.join(',')}|$_dark|${app.online}';
    if (key == _styleKey) return;
    _styleKey = key;
    final offline = await MapStyles.offlineStyle(app.packs, dark: _dark, online: app.online);
    final style = offline ?? (_dark ? 'https://tiles.openfreemap.org/styles/dark' : ArahConfig.onlineStyleUrl);
    if (!mounted) return;
    setState(() {
      _style = style;
      _styleReady = false;
    });
  }

  void _onFix(Fix fix) {
    final m = _map;
    if (m == null) return;
    m.updateManualLocation(
      ManualLocationUpdate(
        target: ll(fix.pos),
        horizontalAccuracy: fix.accuracyM,
        bearing: fix.headingDeg,
        speed: fix.speedMps < 0 ? null : fix.speedMps,
      ),
    );
    if (!_movedToFix) {
      _movedToFix = true;
      context.appRead.routing.preload(fix.pos);
      if (_place == null) m.animateCamera(CameraUpdate.newLatLngZoom(ll(fix.pos), 15));
    } else if (_following) {
      m.animateCamera(CameraUpdate.newLatLng(ll(fix.pos)));
    }
  }

  Future<void> _onStyleLoaded() async {
    final m = _map;
    if (m == null) return;
    _layers = MapLayers(m);
    await _layers!.install();
    _styleReady = true;
    await _drawReports();
    await _drawSelection();
    final fix = context.appRead.location.last;
    if (fix != null) _onFix(fix);
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

  void _select(Place p) {
    setState(() {
      _place = p;
      _from = null;
      _to = null;
      _routes = [];
      _stops.clear();
      _previewing = false;
      _routeError = null;
    });
    _drawSelection();
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

  Place _me() => Place(name: context.appRead.tr('Lokasi anda', 'Your location'), pos: context.appRead.here, source: 'me');
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
        _routing = false;
        _routeOffline = r.usedOffline;
      });
      await _drawSelection();
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
          hint: which == 0 ? app.tr('Pilih titik mula', 'Choose start') : app.tr('Pilih destinasi', 'Choose destination'),
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

  void _cycleTheme() {
    final s = context.appRead.settings;
    s.theme = MapTheme.values[(s.theme.index + 1) % MapTheme.values.length];
    _refreshStyle();
    _snack(switch (s.theme) {
      MapTheme.auto => context.appRead.tr('Tema peta: auto (gelap waktu malam)', 'Map theme: auto (dark at night)'),
      MapTheme.light => context.appRead.tr('Tema peta: cerah', 'Map theme: light'),
      MapTheme.dark => context.appRead.tr('Tema peta: gelap', 'Map theme: dark'),
    });
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
    _map?.animateCamera(CameraUpdate.newLatLngZoom(ll(fix.pos), 16));
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
              setState(() => _sel = i);
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
            MapLibreMap(
              key: ValueKey(_style.hashCode),
              styleString: _style!,
              initialCameraPosition: CameraPosition(target: ll(app.here), zoom: app.hasFix ? 15 : 11),
              onMapCreated: (c) {
                _map = c;
                c.onFeatureTapped.add((_, _, id, layerId, _) {
                  if (layerId == 'arah-route-alt' || layerId == 'arah-route') {
                    final i = int.tryParse(id);
                    if (i != null && i < _routes.length) {
                      setState(() => _sel = i);
                      _drawSelection();
                    }
                  }
                });
              },
              onStyleLoadedCallback: _onStyleLoaded,
              myLocationEnabled: true,
              locationSource: const ManualLocationSource(),
              myLocationRenderMode: MyLocationRenderMode.compass,
              trackCameraPosition: true,
              compassEnabled: true,
              compassViewPosition: CompassViewPosition.topRight,
              compassViewMargins: const Point(16, 190),
              attributionButtonPosition: AttributionButtonPosition.bottomLeft,
              onMapLongClick: _longPress,
              onCameraMove: (_) {
                if (_following) setState(() => _following = false);
              },
            ),
          // Search bar and quick categories.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(28),
                    color: Theme.of(context).colorScheme.surface,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => _openSearch(),
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            const SizedBox(width: 18),
                            Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.tr('Cari tempat', 'Search here'),
                                style: TextStyle(fontSize: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('Tetapan', 'Settings'),
                              icon: const Icon(Icons.menu),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_previewing) const SizedBox(height: 8),
                  if (!_previewing)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip(Icons.home, context.tr('Rumah', 'Home'), () {
                            final h = app.settings.home;
                            h != null
                                ? _select(h)
                                : _snack(app.tr('Pilih tempat, kemudian "Tetapkan Rumah"', 'Pick a place, then "Set as Home"'));
                          }),
                          _chip(Icons.work, context.tr('Kerja', 'Work'), () {
                            final w = app.settings.work;
                            w != null
                                ? _select(w)
                                : _snack(app.tr('Pilih tempat, kemudian "Tetapkan Kerja"', 'Pick a place, then "Set as Work"'));
                          }),
                          for (final c in categories.take(4)) _chip(c.icon, app.tr(c.ms, c.en), () => _openSearch(category: c)),
                        ],
                      ),
                    ),
                  if (!app.online)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              app.packs.installed.isEmpty
                                  ? context.tr('Luar talian — tiada peta dimuat turun', 'Offline — no downloaded map')
                                  : context.tr('Luar talian — guna peta tersimpan', 'Offline — using saved map'),
                              style: const TextStyle(color: Colors.white),
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
            bottom: (bottomPanel != null ? 16 : 32) + MediaQuery.of(context).padding.bottom + (bottomPanel != null ? 0 : 0),
            child: SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.only(bottom: bottomPanel != null ? (_previewing ? 300 : 210) : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _fab(Icons.layers_outlined, context.tr('Tema peta', 'Map theme'), _cycleTheme, small: true),
                    const SizedBox(height: 12),
                    _fab(Icons.report_gmailerrorred, context.tr('Lapor', 'Report'), _report, color: ArahColors.amber),
                    const SizedBox(height: 12),
                    _fab(
                      _following ? Icons.my_location : Icons.location_searching,
                      context.tr('Lokasi saya', 'My location'),
                      _myLocation,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (bottomPanel != null) Positioned(left: 0, right: 0, bottom: 0, child: bottomPanel),
          if (app.packs.installed.isEmpty && bottomPanel == null)
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

  Widget _chip(IconData icon, String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      elevation: 2,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const StadiumBorder(),
    ),
  );

  Widget _fab(IconData icon, String tip, VoidCallback onTap, {Color? color, bool small = false}) => SizedBox(
    width: small ? 48 : 60,
    height: small ? 48 : 60,
    child: FloatingActionButton(
      heroTag: tip,
      tooltip: tip,
      onPressed: onTap,
      backgroundColor: color ?? Theme.of(context).colorScheme.surface,
      foregroundColor: color != null ? Colors.black : Theme.of(context).colorScheme.primary,
      child: Icon(icon, size: small ? 22 : 28),
    ),
  );
}

class _OfflineNudge extends StatelessWidget {
  final VoidCallback onTap;
  const _OfflineNudge({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    borderRadius: BorderRadius.circular(16),
    color: Theme.of(context).colorScheme.surface,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.download_for_offline, color: Theme.of(context).colorScheme.primary),
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
                    Text(place.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Rumah ditetapkan', 'Home set'))));
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.work_outline, size: 18),
                label: Text(context.tr('Tetapkan Kerja', 'Set as Work')),
                onPressed: () {
                  s.work = place;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Kerja ditetapkan', 'Work set'))));
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
    final fastest = routes.isEmpty ? 0.0 : routes.map((r) => r.durationS).reduce((a, b) => a < b ? a : b);

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
                      color: ArahColors.route,
                      label: context.tr('Dari', 'From'),
                      text: from.name,
                      onTap: onEditFrom,
                    ),
                    for (var i = 0; i < stops.length; i++)
                      _StopRow(icon: Icons.flag_outlined, text: stops[i].name, onRemove: () => onRemoveStop(i)),
                    _EndField(
                      icon: Icons.place,
                      color: ArahColors.warn,
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
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = routes[i];
                  final sel = i == selected;
                  final extra = r.durationS - fastest;
                  final tag = i == 0
                      ? context.tr('Terpantas', 'Fastest')
                      : extra < 60
                      ? context.tr('Hampir sama', 'About the same')
                      : '+${(extra / 60).round()} min';
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelect(i),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: sel ? ArahColors.route : theme.dividerColor, width: sel ? 2.5 : 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fmtDuration(r.durationS, app.lang),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: sel ? ArahColors.route : null),
                          ),
                          Row(
                            children: [
                              Text(fmtKm(r.distanceM)),
                              if (i < tolls.length && tolls[i] != null && !tolls[i]!.isEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${tolls[i]!.approximate ? '~' : ''}${fmtRm(tolls[i]!.total)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: ArahColors.amber),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              Text(tag, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                              if (r.hasToll && (i >= tolls.length || tolls[i] == null || tolls[i]!.isEmpty)) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.toll, size: 16),
                              ],
                              if (r.hasFerry) ...[const SizedBox(width: 6), const Icon(Icons.directions_boat, size: 16)],
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
            _RouteInfo(route: routes[selected], offline: offline, toll: selected < tolls.length ? tolls[selected] : null),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => showStepsSheet(context, routes[selected]),
                  icon: const Icon(Icons.list),
                  label: Text(context.tr('Langkah', 'Steps')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Always Start: from somewhere else, Arah guides you to that start first.
                  child: FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.navigation),
                    label: Text(context.tr('Mula', 'Start')),
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
    final cams = app.settings.cameraAlerts ? (app.cameras?.along(route).length ?? 0) : 0;
    final parts = <String>[
      '${context.tr('Tiba', 'Arrive')} ${fmtEta(route.durationS)}',
      if (route.hasToll && (toll == null || toll!.isEmpty))
        context.tr('Ada tol (harga tidak diketahui)', 'Has tolls (price unknown)'),
      if (route.hasFerry) context.tr('Ada feri', 'Has ferry'),
      if (cams > 0) context.tr('$cams kamera laju', cams == 1 ? '1 speed camera' : '$cams speed cameras'),
      for (final e in counts.entries) '${e.value} ${_kindName(context, e.key)}',
      if (offline) context.tr('Laluan luar talian', 'Offline route'),
    ];
    final t = toll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t != null && !t.isEmpty)
          InkWell(
            onTap: () => _breakdown(context, t),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.toll, size: 20, color: ArahColors.amber),
                  const SizedBox(width: 6),
                  Text(
                    '${context.tr('Tol', 'Tolls')} ${t.approximate ? '~' : ''}${fmtRm(t.total)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.app.settings.mode == TravelMode.motorcycle
                        ? context.tr('motosikal', 'motorbike')
                        : context.tr('kereta (Kelas 1)', 'car (Class 1)'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        Text(parts.join(' · '), style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
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
  const _EndField({required this.icon, required this.color, required this.label, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Text('$label  ', style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              ),
              const Icon(Icons.edit_outlined, size: 18),
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
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Material(
    elevation: 12,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: SafeArea(
      top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 12), child: child),
    ),
  );
}
