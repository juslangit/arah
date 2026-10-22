import '../core/geo.dart';

/// One search result or saved place.
class Place {
  final String name;
  final String kind; // 'fuel', 'street', 'town', 'address', 'pin', ...
  final String context; // "Jalan Ampang, Kuala Lumpur"
  final Geo pos;
  final String source; // 'online', 'offline', 'saved', 'pin'

  const Place({required this.name, required this.pos, this.kind = '', this.context = '', this.source = 'online'});

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind,
    'context': context,
    'lat': pos.lat,
    'lon': pos.lon,
    'source': source,
  };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    name: j['name'] as String,
    kind: j['kind'] as String? ?? '',
    context: j['context'] as String? ?? '',
    pos: Geo((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
    source: j['source'] as String? ?? 'saved',
  );
}
