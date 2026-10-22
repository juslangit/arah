// Online search when there's signal, the downloaded pack's index otherwise
// (or when the server is slow). Results always say where they came from.
import 'dart:async';

import '../core/geo.dart';
import '../offline/packs.dart';
import 'offline_search.dart' if (dart.library.js_interop) 'offline_search_web.dart';
import 'photon_client.dart';
import 'place.dart';

class SearchResult {
  final List<Place> places;
  final bool offline;
  const SearchResult(this.places, {this.offline = false});
}

class SearchService {
  final PackManager packs;
  final PhotonClient online;
  final _offline = <String, OfflineSearch>{};

  SearchService(this.packs, {PhotonClient? online}) : online = online ?? PhotonClient();

  OfflineSearch? _indexFor(Geo? near) {
    final pack = near != null ? packs.packAt(near) : packs.installed.values.firstOrNull;
    if (pack == null) return null;
    final file = packs.fileOf(pack, '.search');
    if (file == null) return null;
    return _offline[file] ??= OfflineSearch.open(file);
  }

  /// Searches every installed pack, nearest pack first.
  List<Place> _offlineSearch(String q, Geo? near) {
    final out = <Place>[];
    final first = _indexFor(near);
    if (first != null) out.addAll(first.search(q, near: near));
    for (final pack in packs.installed.values) {
      final file = packs.fileOf(pack, '.search');
      if (file == null) continue;
      final idx = _offline[file] ??= OfflineSearch.open(file);
      if (identical(idx, first)) continue;
      out.addAll(idx.search(q, near: near, limit: 4));
    }
    return out;
  }

  Future<SearchResult> search(String q, {Geo? near, bool isOnline = true, String lang = 'en'}) async {
    if (isOnline) {
      try {
        return SearchResult(await online.search(q, near: near, lang: lang));
      } catch (_) {
        // Fall through to offline.
      }
    }
    return SearchResult(_offlineSearch(q, near), offline: true);
  }

  /// Category search ("Stesen minyak"): by OSM tag online, by kind offline.
  Future<SearchResult> category(
    String query,
    String osmTag,
    List<String> kinds, {
    required Geo near,
    bool isOnline = true,
  }) async {
    if (isOnline) {
      try {
        return SearchResult(await online.search(query, near: near, osmTag: osmTag, limit: 15));
      } catch (_) {}
    }
    final idx = _indexFor(near);
    return SearchResult(idx?.byKind(kinds, near) ?? const [], offline: true);
  }

  Future<Place> describe(Geo p, {bool isOnline = true}) async {
    if (isOnline) {
      try {
        final r = await online.reverse(p);
        if (r != null) return Place(name: r.name, kind: r.kind, context: r.context, pos: p, source: 'pin');
      } catch (_) {}
    }
    final near = _indexFor(p)?.nearest(p);
    return Place(
      name: near != null ? 'Dekat ${near.name}' : '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
      kind: 'pin',
      context: near?.context ?? '',
      pos: p,
      source: 'pin',
    );
  }
}
