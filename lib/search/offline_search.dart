// Search inside a downloaded region pack: an SQLite full-text index of every
// named place, street and address in it (built by tools/data/build_pack.py).
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../core/geo.dart';
import 'place.dart';

class OfflineSearch {
  final Database _db;
  OfflineSearch._(this._db);

  static OfflineSearch open(String path) => OfflineSearch._(sqlite3.open(path, mode: OpenMode.readOnly));

  void close() => _db.close();

  /// Common Malaysian shorthand people type, expanded before searching.
  static const _aliases = {
    'jln': 'jalan',
    'tmn': 'taman',
    'kg': 'kampung',
    'kpg': 'kampung',
    'lrg': 'lorong',
    'bdr': 'bandar',
    'sg': 'sungai',
    'bkt': 'bukit',
    'pjy': 'putrajaya',
    'kl': 'kuala lumpur',
    'pj': 'petaling jaya',
    'jb': 'johor bahru',
    'kk': 'kota kinabalu',
  };

  /// Turns "jln ampang" into an FTS5 query: each word a prefix, all required.
  static String toFtsQuery(String q) {
    final words = q
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .expand((w) => (_aliases[w] ?? w).split(' '))
        .toList();
    return words.map((w) => '"$w"*').join(' ');
  }

  List<Place> search(String q, {Geo? near, int limit = 8}) {
    final fts = toFtsQuery(q);
    if (fts.isEmpty) return const [];
    // Pull more than needed, then rank by text match, importance and distance.
    final rows = _db.select(
      'SELECT p.name, p.kind, p.context, p.lat, p.lon, p.rank, bm25(place_fts, 10.0, 3.0, 1.0) AS score '
      'FROM place_fts JOIN place p ON p.id = place_fts.rowid '
      'WHERE place_fts MATCH ? ORDER BY score LIMIT 200',
      [fts],
    );
    final lower = q.toLowerCase().trim();
    final scored = <(double, Place)>[];
    for (final r in rows) {
      final pos = Geo(r['lat'] as double, r['lon'] as double);
      final name = r['name'] as String;
      var s = -(r['score'] as double) + (r['rank'] as int) / 20.0;
      if (name.toLowerCase() == lower) s += 4;
      if (name.toLowerCase().startsWith(lower)) s += 2;
      if (near != null) {
        // Closer is better: a gentle log falloff so a famous place far away can still win.
        final km = distanceM(near, pos) / 1000;
        s -= math.log(1 + km) * 0.8;
      }
      scored.add((s, Place(name: name, kind: r['kind'] as String, context: r['context'] as String, pos: pos, source: 'offline')));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final out = <Place>[];
    final seen = <String>{};
    for (final (_, p) in scored) {
      // The same street appears once per kilometre; show it once per area.
      if (!seen.add('${p.name}|${p.context}')) continue;
      out.add(p);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Places of the given kinds nearest to [near], widening the search box
  /// until enough are found.
  List<Place> byKind(List<String> kinds, Geo near, {int limit = 15}) {
    final marks = List.filled(kinds.length, '?').join(',');
    for (final km in [5.0, 20.0, 60.0]) {
      final d = km / 111.0;
      final rows = _db.select(
        'SELECT name, kind, context, lat, lon FROM place WHERE kind IN ($marks) '
        'AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
        [...kinds, near.lat - d, near.lat + d, near.lon - d, near.lon + d],
      );
      if (rows.length >= limit || km == 60.0) {
        final out = [
          for (final r in rows)
            Place(
                name: r['name'] as String,
                kind: r['kind'] as String,
                context: r['context'] as String,
                pos: Geo(r['lat'] as double, r['lon'] as double),
                source: 'offline'),
        ]..sort((a, b) => distanceM(near, a.pos).compareTo(distanceM(near, b.pos)));
        return out.take(limit).toList();
      }
    }
    return const [];
  }

  /// Nearest named thing to a point, for a dropped pin when offline.
  Place? nearest(Geo p) {
    final d = 0.003;
    final rows = _db.select(
      'SELECT name, kind, context, lat, lon FROM place WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      [p.lat - d, p.lat + d, p.lon - d, p.lon + d],
    );
    Place? best;
    var bd = double.infinity;
    for (final r in rows) {
      final pos = Geo(r['lat'] as double, r['lon'] as double);
      final dist = distanceM(p, pos);
      if (dist < bd) {
        bd = dist;
        best = Place(name: r['name'] as String, kind: r['kind'] as String, context: r['context'] as String, pos: pos, source: 'offline');
      }
    }
    return best;
  }
}
