// Builds the map style. With a region pack installed the map is drawn from
// the pack's own file (works with no signal); without one it uses the
// OpenFreeMap style online. MapLibre can't read fonts or icons from Flutter
// assets, so they are copied to app storage once and used as file:// URLs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../core/settings.dart';
import 'packs.dart';

class MapStyles {
  static const _fonts = ['Noto Sans Regular', 'Noto Sans Medium', 'Noto Sans Italic'];
  static const _ranges = [
    '0-255',
    '256-511',
    '512-767',
    '768-1023',
    '2816-3071',
    '7680-7935',
    '8192-8447',
    '8448-8703',
    '12288-12543',
    '65280-65535',
  ];
  static String? _assetsDir;

  /// Copies glyphs and sprites out of the APK once per app version.
  static Future<String> _ensureAssets() async {
    if (_assetsDir != null) return _assetsDir!;
    final base = await getApplicationSupportDirectory();
    final dir = '${base.path}/mapassets';
    final marker = File('$dir/.version');
    if (!marker.existsSync() || marker.readAsStringSync() != ArahConfig.appVersion) {
      for (final font in _fonts) {
        Directory('$dir/glyphs/$font').createSync(recursive: true);
        for (final r in _ranges) {
          try {
            final data = await rootBundle.load('assets/glyphs/$font/$r.pbf');
            File('$dir/glyphs/$font/$r.pbf').writeAsBytesSync(data.buffer.asUint8List());
          } catch (_) {}
        }
      }
      Directory('$dir/sprites').createSync(recursive: true);
      for (final f in ['light', 'dark']) {
        for (final s in ['', '@2x']) {
          for (final ext in ['json', 'png']) {
            final data = await rootBundle.load('assets/sprites/$f$s.$ext');
            File('$dir/sprites/$f$s.$ext').writeAsBytesSync(data.buffer.asUint8List());
          }
        }
      }
      marker.writeAsStringSync(ArahConfig.appVersion);
    }
    _assetsDir = dir;
    return dir;
  }

  /// Style JSON for the installed packs, or null when none is installed.
  static Future<String?> offlineStyle(PackManager packs, {bool dark = false, bool online = false}) async {
    final maps = <String>[];
    for (final p in packs.installed.values) {
      final f = packs.fileOf(p, '.pmtiles');
      if (f != null) maps.add(f);
    }
    if (maps.isEmpty) return null;
    final dir = await _ensureAssets();
    final template = jsonDecode(
      await rootBundle.loadString('assets/styles/${dark ? 'dark' : 'light'}.json'),
    ) as Map<String, dynamic>;
    // Online, the full font set covers Chinese and Tamil labels too.
    template['glyphs'] = online
        ? 'https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf'
        : 'file://$dir/glyphs/{fontstack}/{range}.pbf';
    template['sprite'] = 'file://$dir/sprites/${dark ? 'dark' : 'light'}';
    final baseLayers = (template['layers'] as List).cast<Map<String, dynamic>>();
    final sources = <String, dynamic>{};
    final layers = <Map<String, dynamic>>[];
    for (var i = 0; i < maps.length; i++) {
      final id = 'pack$i';
      sources[id] = {
        'type': 'vector',
        'url': 'pmtiles://file://${maps[i]}',
        'attribution': '© OpenStreetMap · Protomaps',
      };
    }
    // Background once, every other layer once per pack (packs don't overlap).
    for (final l in baseLayers) {
      if (l['type'] == 'background') {
        layers.add(l);
        continue;
      }
      for (var i = 0; i < maps.length; i++) {
        final copy = jsonDecode(jsonEncode(l)) as Map<String, dynamic>;
        copy['source'] = 'pack$i';
        if (maps.length > 1) copy['id'] = '${l['id']}_$i';
        layers.add(copy);
      }
    }
    template['sources'] = sources;
    template['layers'] = layers;
    return jsonEncode(palestine(template));
  }

  static final _base = <bool, Map<String, dynamic>>{};
  static final _online = <String, String>{};

  /// OpenFreeMap's style for [view], patched with [palestine]; null if it
  /// can't be fetched.
  static Future<String?> onlineStyle({bool dark = false, MapView view = MapView.standard}) async {
    final key = '$dark|${view.name}';
    final cached = _online[key];
    if (cached != null) return cached;
    var base = _base[dark];
    if (base == null) {
      try {
        final url = dark ? ArahConfig.onlineDarkStyleUrl : ArahConfig.onlineStyleUrl;
        final res = await http.get(Uri.parse(url), headers: ArahConfig.userAgent).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return null;
        base = _base[dark] = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    final style = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    switch (view) {
      case MapView.standard:
        break;
      case MapView.satellite:
        satellite(style);
      case MapView.terrain:
        terrain(style, dark: dark);
    }
    return _online[key] = jsonEncode(palestine(style));
  }

  /// Esri World Imagery under the map's roads, borders and labels (like
  /// Google's satellite view with labels).
  static Map<String, dynamic> satellite(Map<String, dynamic> style) {
    (style['sources'] as Map<String, dynamic>)['arah-satellite'] = {
      'type': 'raster',
      'tiles': ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
      'tileSize': 256,
      'maxzoom': 19,
      'attribution': 'Imagery © Esri, Maxar, Earthstar Geographics',
    };
    final keep = <Map<String, dynamic>>[
      {'id': 'arah-satellite', 'type': 'raster', 'source': 'arah-satellite'},
    ];
    for (final l in (style['layers'] as List).cast<Map<String, dynamic>>()) {
      final layer = l['source-layer'];
      final type = l['type'];
      if (type == 'symbol') {
        final paint = (l['paint'] ??= <String, dynamic>{}) as Map<String, dynamic>;
        if (paint.containsKey('text-color') || (l['layout'] as Map?)?['text-field'] != null) {
          paint['text-color'] = '#ffffff';
          paint['text-halo-color'] = 'rgba(0,0,0,0.85)';
          paint['text-halo-width'] = 1.4;
        }
        keep.add(l);
      } else if (type == 'line' &&
          (layer == 'boundary' || (layer == 'transportation' && !'${l['id']}'.contains('casing')))) {
        final paint = (l['paint'] ??= <String, dynamic>{}) as Map<String, dynamic>;
        paint['line-opacity'] = layer == 'boundary' ? 0.9 : 0.45;
        if (layer == 'boundary') paint['line-color'] = '#ffffff';
        keep.add(l);
      }
    }
    style['layers'] = keep;
    return style;
  }

  /// Hill shading from the AWS Terrain Tiles elevation data (open data), under
  /// the roads and labels.
  static Map<String, dynamic> terrain(Map<String, dynamic> style, {bool dark = false}) {
    (style['sources'] as Map<String, dynamic>)['arah-dem'] = {
      'type': 'raster-dem',
      'tiles': ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'maxzoom': 15,
      'encoding': 'terrarium',
      'attribution': 'Elevation: Mapzen, AWS Terrain Tiles',
    };
    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    // Above land and water fills, below roads, buildings and labels.
    var at = layers.indexWhere((l) => l['source-layer'] == 'transportation' || l['source-layer'] == 'aeroway');
    if (at < 0) at = layers.length;
    layers.insert(at, {
      'id': 'arah-hillshade',
      'type': 'hillshade',
      'source': 'arah-dem',
      'paint': {
        'hillshade-exaggeration': dark ? 0.35 : 0.55,
        'hillshade-shadow-color': dark ? '#000000' : '#5a5040',
        'hillshade-highlight-color': dark ? '#3a3a3a' : '#ffffff',
        'hillshade-accent-color': dark ? '#111111' : '#6b5d45',
      },
    });
    style['layers'] = layers;
    return style;
  }

  /// Around Palestine (with the Golan): labels here are built from the Latin
  /// name and the Arabic name, never the Hebrew one. A style can't test which
  /// alphabet a name is in, and the tiles put Hebrew in name, name:nonlatin
  /// and even name_en, so the switch is by area. name:latin is never Hebrew.
  static const _palestineArea = {
    'type': 'Polygon',
    'coordinates': [
      [
        [33.9, 29.3],
        [36.1, 29.3],
        [36.1, 33.6],
        [33.9, 33.6],
        [33.9, 29.3],
      ],
    ],
  };

  /// Where the one big "Palestine" label goes: the middle of the whole country.
  static const _palestineLabel = [34.95, 31.35];

  /// Malaysia does not recognise Israel: the map shows the whole of it as
  /// Palestine, in English and Arabic.
  ///  - The tiles' Israel (IL) and Palestinian Territories (PS) country labels
  ///    are hidden; one large "Palestine / فلسطين" label sits over the middle.
  ///  - Inside [_palestineArea] every label is Latin + Arabic, no Hebrew.
  ///  - The lines between Israel and the West Bank / Gaza are not drawn: the
  ///    country borders with ISR on one side and no country on the other (the
  ///    tiles give Palestine no code). Borders with Jordan, Egypt, Lebanon and
  ///    Syria stay.
  static Map<String, dynamic> palestine(Map<String, dynamic> style) {
    const ilOrPs = [
      'any',
      [
        'in',
        [
          'coalesce',
          ['get', 'iso_a2'],
          '',
        ],
        [
          'literal',
          ['IL', 'PS'],
        ],
      ],
      [
        'in',
        [
          'coalesce',
          ['get', 'name:en'],
          ['get', 'name_en'],
          '',
        ],
        [
          'literal',
          ['Israel', 'Palestinian Territories'],
        ],
      ],
    ];
    const side = ['ISR', 'PSE', ''];
    final innerLine = [
      'all',
      [
        '==',
        [
          'to-number',
          ['get', 'admin_level'],
        ],
        2,
      ],
      [
        'in',
        [
          'coalesce',
          ['get', 'adm0_l'],
          '',
        ],
        ['literal', side],
      ],
      [
        'in',
        [
          'coalesce',
          ['get', 'adm0_r'],
          '',
        ],
        ['literal', side],
      ],
      [
        'any',
        [
          'in',
          [
            'coalesce',
            ['get', 'adm0_l'],
            '',
          ],
          [
            'literal',
            ['ISR', 'PSE'],
          ],
        ],
        [
          'in',
          [
            'coalesce',
            ['get', 'adm0_r'],
            '',
          ],
          [
            'literal',
            ['ISR', 'PSE'],
          ],
        ],
      ],
    ];
    // Latin name, then the Arabic one on a second line when there is one.
    const latin = [
      'coalesce',
      ['get', 'name:latin'],
      ['get', 'name:en'],
      '',
    ];
    const latinArabic = [
      'case',
      [
        'all',
        ['has', 'name:ar'],
        [
          '!=',
          ['get', 'name:ar'],
          latin,
        ],
      ],
      [
        'concat',
        latin,
        '\n',
        ['get', 'name:ar'],
      ],
      latin,
    ];
    const inArea = ['within', _palestineArea];
    Object? and(Object? filter, Object extra) => filter == null ? extra : ['all', filter, extra];

    final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
    final out = <Map<String, dynamic>>[];
    Map<String, dynamic>? countryLayer;
    var lastPlace = -1;
    for (final l in layers) {
      final layer = l['source-layer'];
      final filter = l['filter'];
      // Legacy filters (Protomaps style: ["==", "kind", "country"]) can't be
      // mixed with expressions, so they get the legacy form.
      final legacy = filter is List && filter.length > 1 && filter[1] is String;
      final layout = l['layout'] as Map<String, dynamic>?;
      final isCountry =
          (layer == 'place' || layer == 'places') && l['type'] == 'symbol' && '${l['id']}'.contains('countr');
      if (isCountry) {
        countryLayer ??= l;
        l['filter'] = legacy
            ? [
                'all',
                filter,
                ['!in', 'name:en', 'Israel', 'Palestinian Territories'],
                ['!in', 'iso_a2', 'IL', 'PS'],
              ]
            : and(filter, ['!', ilOrPs]);
        out.add(l);
      } else if (layer == 'boundary' && l['type'] == 'line' && !legacy) {
        l['filter'] = and(filter, ['!', innerLine]);
        out.add(l);
      } else if (l['type'] == 'symbol' &&
          jsonEncode(layout?['text-field'] ?? '').contains('name') &&
          !legacy &&
          layer != null) {
        // Road shields show the road number (ref), not a name: left alone.
        // Two copies: the original outside the area, Latin + Arabic inside it.
        final inside = jsonDecode(jsonEncode(l)) as Map<String, dynamic>;
        inside['id'] = '${l['id']}-ps';
        inside['filter'] = and(filter, inArea);
        (inside['layout'] as Map<String, dynamic>)['text-field'] = latinArabic;
        l['filter'] = and(filter, ['!', inArea]);
        out
          ..add(l)
          ..add(inside);
      } else {
        out.add(l);
      }
      if (layer == 'place' || layer == 'places') lastPlace = out.length - 1;
    }

    // The one big label, drawn over everything else in its area like a
    // country name on a paper map, fading as you zoom in.
    final font = (countryLayer?['layout'] as Map?)?['text-font'] ?? ['Noto Sans Bold'];
    (style['sources'] as Map<String, dynamic>)['arah-palestine'] = {
      'type': 'geojson',
      'data': {
        'type': 'Feature',
        'properties': {'name': 'Palestine\nفلسطين'},
        'geometry': {'type': 'Point', 'coordinates': _palestineLabel},
      },
    };
    final dark = '${(countryLayer?['paint'] as Map?)?['text-halo-color']}'.contains('0,0,0');
    out.insert(lastPlace + 1, {
      'id': 'arah-palestine',
      'type': 'symbol',
      'source': 'arah-palestine',
      'minzoom': 2,
      'maxzoom': 10,
      'layout': {
        'text-field': ['get', 'name'],
        'text-font': font,
        'text-size': [
          'interpolate',
          ['linear'],
          ['zoom'],
          2,
          13,
          4,
          20,
          6,
          30,
          8,
          42,
          10,
          52,
        ],
        'text-letter-spacing': 0.12,
        'text-line-height': 1.25,
        'text-allow-overlap': true,
        'text-ignore-placement': true,
      },
      'paint': {
        'text-color': dark ? '#d8d8d8' : '#1f1f1f',
        'text-halo-color': dark ? 'rgba(0,0,0,0.75)' : 'rgba(255,255,255,0.85)',
        'text-halo-width': 1.6,
        'text-opacity': [
          'interpolate',
          ['linear'],
          ['zoom'],
          2,
          1,
          6,
          0.9,
          8,
          0.6,
          10,
          0.35,
        ],
      },
    });
    style['layers'] = out;
    return style;
  }
}
