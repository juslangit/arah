// Search-as-you-type through Photon (OpenStreetMap data). Nominatim's policy
// forbids autocomplete, Photon is built for it (app study §A3.3, §A3.5).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../core/geo.dart';
import 'place.dart';

class PhotonClient {
  final http.Client _http;
  final String baseUrl;
  final _cache = <String, List<Place>>{};

  PhotonClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? ArahConfig.photonUrl;

  Future<List<Place>> search(String q, {Geo? near, String lang = 'en', int limit = 8, String? osmTag}) async {
    final key = '$q|$osmTag|${near?.lat.toStringAsFixed(2)}|${near?.lon.toStringAsFixed(2)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final params = <String, String>{
      'q': q,
      'limit': '$limit',
      // Photon's 'lang' supports default/en/de/fr; Malay names come through 'default'.
      'lang': lang == 'en' ? 'en' : 'default',
      // Malaysia, plus Singapore and Brunei for cross-border trips.
      'bbox': '99.6,0.85,119.3,7.4',
      if (osmTag != null) 'osm_tag': osmTag,
      if (near != null) ...{'lat': '${near.lat}', 'lon': '${near.lon}', 'location_bias_scale': '0.3'},
    };
    final res = await _http
        .get(Uri.parse('$baseUrl/api').replace(queryParameters: params), headers: {'User-Agent': ArahConfig.serverHeaders['User-Agent']!})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('search HTTP ${res.statusCode}');
    final out = parse(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    _cache[key] = out;
    return out;
  }

  Future<Place?> reverse(Geo p) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/reverse').replace(queryParameters: {'lat': '${p.lat}', 'lon': '${p.lon}', 'limit': '1'}),
            headers: {'User-Agent': ArahConfig.serverHeaders['User-Agent']!})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final list = parse(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    return list.isEmpty ? null : list.first;
  }

  static List<Place> parse(Map<String, dynamic> json) {
    final out = <Place>[];
    for (final f in (json['features'] as List? ?? const [])) {
      final props = (f as Map)['properties'] as Map<String, dynamic>;
      final coords = (f['geometry'] as Map)['coordinates'] as List;
      final street = props['street'] as String?;
      final hn = props['housenumber'] as String?;
      var name = props['name'] as String?;
      if (name == null && street != null) name = hn != null ? '$hn, $street' : street;
      if (name == null) continue;
      final context = <String?>[
        if (props['name'] != null) street,
        props['district'] as String?,
        props['city'] as String?,
        props['state'] as String?,
      ].whereType<String>().where((s) => s.isNotEmpty && s != name).toSet().join(', ');
      out.add(Place(
        name: name,
        kind: (props['osm_value'] as String?) ?? '',
        context: context,
        pos: Geo((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        source: 'online',
      ));
    }
    return out;
  }
}
