// Builds the map style. With a region pack installed the map is drawn from
// the pack's own file (works with no signal); without one it uses the
// OpenFreeMap style online. MapLibre can't read fonts or icons from Flutter
// assets, so they are copied to app storage once and used as file:// URLs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
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
    return jsonEncode(template);
  }
}
