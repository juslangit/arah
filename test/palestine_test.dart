import 'dart:convert';
import 'dart:io';

import 'package:arah/offline/map_style.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cut-down OpenMapTiles style (OpenFreeMap liberty) and the bundled Protomaps one.
Map<String, dynamic> omt() => jsonDecode(jsonEncode(_omt)) as Map<String, dynamic>;

const _omt = {
  'version': 8,
  'sources': {},
  'layers': [
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
      },
    },
    {
      'id': 'label_city',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'layout': {'text-field': '{name}'},
    },
  ],
};

void main() {
  test('Israel label reads Palestine; the PS label and inner lines are hidden', () {
    final s = MapStyles.palestine(omt());
    final layers = (s['layers'] as List).cast<Map<String, dynamic>>();
    final country = layers.firstWhere((l) => l['id'] == 'label_country_2');
    final text = jsonEncode(country['layout']['text-field']);
    expect(text, contains('"IL"'));
    expect(text, contains('"Palestine"'));
    expect(jsonEncode(country['filter']), contains('"PS"'));
    final border = jsonEncode(layers.firstWhere((l) => l['id'] == 'boundary_2')['filter']);
    expect(border, contains('"ISR"'));
    expect(border, contains('"adm0_l"'));
    // Other labels untouched.
    expect(layers.firstWhere((l) => l['id'] == 'label_city')['layout']['text-field'], '{name}');
  });

  test('bundled Protomaps style: country label patched with a legacy filter', () {
    final s = MapStyles.palestine(
      jsonDecode(File('assets/styles/light.json').readAsStringSync()) as Map<String, dynamic>,
    );
    final c = (s['layers'] as List).cast<Map<String, dynamic>>().firstWhere((l) => l['id'] == 'places_country');
    expect(jsonEncode(c['layout']['text-field']), contains('"Palestine"'));
    expect(c['filter'], [
      'all',
      ['==', 'kind', 'country'],
      ['!=', 'name:en', 'Palestinian Territories'],
      ['!=', 'iso_a2', 'PS'],
    ]);
  });

  // Writes the real OpenFreeMap styles, patched, for a browser check (PALESTINE_DIR).
  final dir = Platform.environment['PALESTINE_DIR'];
  test('patch the downloaded OpenFreeMap styles', () {
    for (final name in ['liberty', 'dark']) {
      final src = jsonDecode(File('$dir/$name.json').readAsStringSync()) as Map<String, dynamic>;
      File('$dir/$name.patched.json').writeAsStringSync(jsonEncode(MapStyles.palestine(src)));
    }
  }, skip: dir == null);
}
