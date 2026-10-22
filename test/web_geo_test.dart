// Runs on phones and in Chrome (flutter test --platform chrome test/web_geo_test.dart):
// browsers do integer bit operations in 32 bits, which once broke route shapes.
import 'package:arah/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('polyline decoding keeps negative steps negative', () {
    // Google's documented example: (38.5,-120.2), (40.7,-120.95), (43.252,-126.453).
    final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5);
    expect(pts.map((p) => [p.lat, p.lon]), [
      [38.5, -120.2],
      [40.7, -120.95],
      [43.252, -126.453],
    ]);
  });
}
