import 'dart:convert';
import 'dart:io';

import 'package:arah/offline/map_style.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cut-down OpenMapTiles style (OpenFreeMap liberty) and the bundled Protomaps one.
Map<String, dynamic> omt() => jsonDecode(jsonEncode(_omt)) as Map<String, dynamic>;

const _omt = {
  'version': 8,
  'sources': {'openmaptiles': {}},
  'layers': [
    {'id': 'background', 'type': 'background'},
    {'id': 'water', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'water'},
    {'id': 'road_minor', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation'},
    {
      'id': 'boundary_2',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'boundary',
      'filter': [
        'all',
        [
          '==',
          ['get', 'admin_level'],
          2,
        ],
        [
          '!=',
          ['get', 'maritime'],
          1,
        ],
      ],
    },
    {
      'id': 'label_city',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'layout': {
        'text-field': [
          'coalesce',
          ['get', 'name:nonlatin'],
          ['get', 'name'],
        ],
      },
    },
    {
      'id': 'label_country_2',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'filter': [
        '==',
        ['get', 'class'],
        'country',
      ],
      'layout': {
        'text-field': [
          'coalesce',
          ['get', 'name_en'],
          ['get', 'name'],
        ],
        'text-font': ['Noto Sans Bold'],
      },
      'paint': {'text-color': '#000', 'text-halo-color': '#fff'},
    },
  ],
};

List<Map<String, dynamic>> layersOf(Map<String, dynamic> s) => (s['layers'] as List).cast<Map<String, dynamic>>();

void main() {
  test('one big Palestine label in English and Arabic; IL and PS labels hidden', () {
    final s = MapStyles.palestine(omt());
    final big = layersOf(s).firstWhere((l) => l['id'] == 'arah-palestine');
    expect(big['source'], 'arah-palestine');
    expect(jsonEncode(s['sources']['arah-palestine']), contains('Palestine\\nفلسطين'));
    expect(big['layout']['text-font'], ['Noto Sans Bold']);
    final country = jsonEncode(layersOf(s).firstWhere((l) => l['id'] == 'label_country_2')['filter']);
    expect(country, contains('"IL"'));
    expect(country, contains('"PS"'));
    // Drawn above the other place labels.
    final ids = layersOf(s).map((l) => l['id']).toList();
    expect(ids.indexOf('arah-palestine'), greaterThan(ids.indexOf('label_city')));
  });

  test('labels around Palestine are Latin + Arabic, never the Hebrew fields', () {
    final ls = layersOf(MapStyles.palestine(omt()));
    final inside = ls.firstWhere((l) => l['id'] == 'label_city-ps');
    final text = jsonEncode(inside['layout']['text-field']);
    expect(text, contains('name:latin'));
    expect(text, contains('name:ar'));
    expect(text, isNot(contains('nonlatin')));
    expect(text, isNot(contains('"name"]')));
    expect(jsonEncode(inside['filter']), contains('within'));
    // The original keeps its text outside the area.
    final outside = ls.firstWhere((l) => l['id'] == 'label_city');
    expect(jsonEncode(outside['filter']), contains('["!",["within"'));
  });

  test('inner West Bank / Gaza lines are hidden', () {
    final border = jsonEncode(
      layersOf(MapStyles.palestine(omt())).firstWhere((l) => l['id'] == 'boundary_2')['filter'],
    );
    expect(border, contains('"ISR"'));
    expect(border, contains('"adm0_l"'));
  });

  test('satellite: imagery first, fills dropped, roads and labels kept', () {
    final ids = layersOf(MapStyles.satellite(omt())).map((l) => l['id']).toList();
    expect(ids.first, 'arah-satellite');
    expect(ids, isNot(contains('water')));
    expect(ids, isNot(contains('background')));
    expect(ids, containsAll(['road_minor', 'boundary_2', 'label_city']));
  });

  test('terrain: hillshade below the roads', () {
    final ids = layersOf(MapStyles.terrain(omt())).map((l) => l['id']).toList();
    expect(ids.indexOf('arah-hillshade'), ids.indexOf('road_minor') - 1);
    expect(ids.indexOf('arah-hillshade'), greaterThan(ids.indexOf('water')));
  });

  test('bundled Protomaps style: country labels filtered with a legacy filter', () {
    final s = MapStyles.palestine(
      jsonDecode(File('assets/styles/light.json').readAsStringSync()) as Map<String, dynamic>,
    );
    final c = layersOf(s).firstWhere((l) => l['id'] == 'places_country');
    expect(c['filter'], [
      'all',
      ['==', 'kind', 'country'],
      ['!in', 'name:en', 'Israel', 'Palestinian Territories'],
      ['!in', 'iso_a2', 'IL', 'PS'],
    ]);
  });

  // Writes the real OpenFreeMap styles, patched, for a browser check (PALESTINE_DIR).
  final dir = Platform.environment['PALESTINE_DIR'];
  test('patch the downloaded OpenFreeMap styles', () {
    for (final name in ['liberty', 'dark']) {
      Map<String, dynamic> src() => jsonDecode(File('$dir/$name.json').readAsStringSync()) as Map<String, dynamic>;
      File('$dir/$name.patched.json').writeAsStringSync(jsonEncode(MapStyles.palestine(src())));
      File('$dir/$name.satellite.json').writeAsStringSync(jsonEncode(MapStyles.palestine(MapStyles.satellite(src()))));
      File('$dir/$name.terrain.json')
          .writeAsStringSync(jsonEncode(MapStyles.palestine(MapStyles.terrain(src(), dark: name == 'dark'))));
    }
  }, skip: dir == null);
}
