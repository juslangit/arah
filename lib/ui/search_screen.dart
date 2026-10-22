// Search (app study §S2): type and results appear as you go; empty, it shows
// Home/Work, favourites, recent places and quick categories.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../core/geo.dart';
import '../search/place.dart';
import 'format.dart';

class Category {
  final String ms, en, query, osmTag;
  final IconData icon;
  final List<String> kinds; // offline index kinds
  const Category(this.ms, this.en, this.icon, this.query, this.osmTag, this.kinds);
}

const categories = [
  Category('Stesen minyak', 'Petrol', Icons.local_gas_station, 'petrol', 'amenity:fuel', ['fuel']),
  Category('R&R', 'R&R', Icons.local_cafe, 'R&R', 'highway:services', ['services', 'rest_area']),
  Category('Surau / Masjid', 'Surau / Mosque', Icons.mosque, 'masjid', 'amenity:place_of_worship', [
    'place_of_worship',
  ]),
  Category('Parking', 'Parking', Icons.local_parking, 'parking', 'amenity:parking', ['parking']),
  Category('Makan', 'Food', Icons.restaurant, 'restoran', 'amenity:restaurant', [
    'restaurant',
    'fast_food',
    'cafe',
    'food_court',
  ]),
  Category('Hospital / Klinik', 'Hospital / Clinic', Icons.local_hospital, 'hospital', 'amenity:hospital', [
    'hospital',
    'clinic',
  ]),
  Category('ATM', 'ATM', Icons.atm, 'ATM', 'amenity:atm', ['atm', 'bank']),
  Category('Pengecas EV', 'EV charger', Icons.ev_station, 'charging', 'amenity:charging_station', ['charging_station']),
];

IconData placeIcon(String kind) => switch (kind) {
  'fuel' => Icons.local_gas_station,
  'street' || 'residential' || 'primary' || 'secondary' || 'tertiary' || 'trunk' || 'motorway' => Icons.signpost,
  'city' || 'town' || 'village' || 'suburb' || 'neighbourhood' || 'quarter' || 'hamlet' => Icons.location_city,
  'place_of_worship' => Icons.mosque,
  'restaurant' || 'fast_food' || 'cafe' || 'food_court' => Icons.restaurant,
  'hospital' || 'clinic' || 'doctors' => Icons.local_hospital,
  'parking' => Icons.local_parking,
  'school' || 'university' || 'college' => Icons.school,
  'mall' || 'supermarket' || 'convenience' => Icons.shopping_bag,
  'station' || 'halt' || 'bus_station' => Icons.train,
  'aerodrome' => Icons.flight,
  'hotel' => Icons.hotel,
  'address' => Icons.home_outlined,
  'services' || 'rest_area' => Icons.local_cafe,
  _ => Icons.place,
};

class SearchScreen extends StatefulWidget {
  final Geo near;
  final String? hint;
  final Category? startCategory;

  /// Show "Your location" first, for choosing a route's start or end.
  final bool offerMyLocation;
  const SearchScreen({super.key, required this.near, this.hint, this.startCategory, this.offerMyLocation = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;
  bool _offline = false;
  String _lastQuery = '';
  String? _categoryTitle;

  @override
  void initState() {
    super.initState();
    final c = widget.startCategory;
    if (c != null) WidgetsBinding.instance.addPostFrameCallback((_) => _category(c));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _categoryTitle = null;
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    final app = context.appRead;
    _lastQuery = q;
    setState(() => _loading = true);
    final r = await app.search.search(q, near: widget.near, isOnline: app.online, lang: app.lang.name);
    if (!mounted || q != _lastQuery) return;
    setState(() {
      _results = r.places;
      _offline = r.offline;
      _loading = false;
    });
  }

  Future<void> _category(Category c) async {
    final app = context.appRead;
    _ctl.text = '';
    setState(() {
      _categoryTitle = app.tr(c.ms, c.en);
      _loading = true;
    });
    final r = await app.search.category(c.query, c.osmTag, c.kinds, near: widget.near, isOnline: app.online);
    if (!mounted) return;
    setState(() {
      _results = r.places;
      _offline = r.offline;
      _loading = false;
    });
  }

  void _pick(Place p) {
    if (p.source != 'me') context.appRead.settings.addRecent(p);
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    final showEmpty = _ctl.text.trim().length < 3 && _categoryTitle == null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: (q) => q.trim().isNotEmpty ? _run(q.trim()) : null,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: widget.hint ?? context.tr('Cari tempat atau alamat', 'Search places or addresses'),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_ctl.text.isNotEmpty)
            IconButton(
              tooltip: context.tr('Kosongkan', 'Clear'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _ctl.clear();
                _results = [];
              }),
            ),
        ],
      ),
      body: showEmpty
          ? ListView(
              children: [
                if (!app.online)
                  _Notice(
                    context.tr(
                      'Luar talian — mencari dalam peta yang dimuat turun',
                      'Offline — searching downloaded maps',
                    ),
                  ),
                if (widget.offerMyLocation)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.my_location),
                    ),
                    title: Text(
                      context.tr('Lokasi anda', 'Your location'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      Place(name: app.tr('Lokasi anda', 'Your location'), pos: app.here, source: 'me'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in categories)
                        ActionChip(
                          avatar: Icon(c.icon, size: 18),
                          label: Text(app.tr(c.ms, c.en)),
                          onPressed: () => _category(c),
                        ),
                    ],
                  ),
                ),
                _savedTile(context, Icons.home, context.tr('Rumah', 'Home'), s.home),
                _savedTile(context, Icons.work, context.tr('Kerja', 'Work'), s.work),
                if (s.favourites.isNotEmpty) _Header(context.tr('Kegemaran', 'Favourites')),
                for (final p in s.favourites) _tile(p, icon: Icons.star),
                if (s.recents.isNotEmpty) _Header(context.tr('Terkini', 'Recent')),
                for (final p in s.recents) _tile(p, icon: Icons.history),
              ],
            )
          : Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_offline && !_loading)
                  _Notice(context.tr('Hasil daripada peta luar talian', 'Results from your offline map')),
                if (_categoryTitle != null) _Header(_categoryTitle!),
                Expanded(
                  child: _results.isEmpty && !_loading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              app.packs.installed.isEmpty && !app.online
                                  ? context.tr(
                                      'Tiada isyarat dan tiada peta luar talian. Muat turun peta di Tetapan.',
                                      'No signal and no offline map. Download one in Settings.',
                                    )
                                  : context.tr('Tiada hasil', 'No results'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(itemCount: _results.length, itemBuilder: (_, i) => _tile(_results[i])),
                ),
              ],
            ),
    );
  }

  Widget _savedTile(BuildContext context, IconData icon, String label, Place? p) => ListTile(
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(label),
    subtitle: Text(
      p?.name ??
          context.tr('Belum ditetapkan — pilih tempat, kemudian "Tetapkan"', 'Not set — pick a place, then "Set"'),
    ),
    onTap: p == null ? null : () => _pick(p),
  );

  Widget _tile(Place p, {IconData? icon}) {
    final d = distanceM(widget.near, p.pos);
    return ListTile(
      leading: Icon(icon ?? placeIcon(p.kind)),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: p.context.isEmpty ? null : Text(p.context, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(fmtKm(d), style: Theme.of(context).textTheme.bodySmall),
      onTap: () => _pick(p),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.cloud_off, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
