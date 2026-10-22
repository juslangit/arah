// The web build has no offline packs (no file system, no native SQLite), so
// offline search is never opened there. Same API as offline_search.dart.
import '../core/geo.dart';
import 'place.dart';

class OfflineSearch {
  OfflineSearch._();

  static OfflineSearch open(String path) => throw UnsupportedError('Offline search is not available on the web');

  void close() {}

  List<Place> search(String q, {Geo? near, int limit = 8}) => const [];

  List<Place> byKind(List<String> kinds, Geo near, {int limit = 15}) => const [];

  Place? nearest(Geo p) => null;
}
