// Spoken and written turn instructions in Bahasa Malaysia and English.
// Valhalla has no Malay narration, so Arah builds every sentence itself from
// the maneuver's type, road name, exit sign and roundabout exit number.
import '../routing/route_model.dart';

enum Lang { ms, en }

const _ordMs = ['pertama', 'kedua', 'ketiga', 'keempat', 'kelima', 'keenam', 'ketujuh', 'kelapan', 'kesembilan'];
const _ordEn = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth'];

String _ordinal(int n, Lang l) {
  final list = l == Lang.ms ? _ordMs : _ordEn;
  if (n >= 1 && n <= list.length) return list[n - 1];
  return l == Lang.ms ? 'ke-$n' : '${n}th';
}

/// The bare action: "belok kanan" / "turn right".
String action(Maneuver m, Lang l) {
  final ms = l == Lang.ms;
  switch (m.turn) {
    case Turn.start:
    case Turn.startLeft:
    case Turn.startRight:
      return ms ? 'mula perjalanan' : 'start';
    case Turn.destination:
      return ms ? 'anda telah tiba' : 'you have arrived';
    case Turn.destinationLeft:
      return ms ? 'destinasi di sebelah kiri' : 'your destination is on the left';
    case Turn.destinationRight:
      return ms ? 'destinasi di sebelah kanan' : 'your destination is on the right';
    case Turn.becomes:
    case Turn.straight:
    case Turn.stayStraight:
    case Turn.rampStraight:
      return ms ? 'terus' : 'continue straight';
    case Turn.slightRight:
      return ms ? 'ikut kanan' : 'bear right';
    case Turn.slightLeft:
      return ms ? 'ikut kiri' : 'bear left';
    case Turn.right:
      return ms ? 'belok kanan' : 'turn right';
    case Turn.left:
      return ms ? 'belok kiri' : 'turn left';
    case Turn.sharpRight:
      return ms ? 'belok tajam ke kanan' : 'turn sharp right';
    case Turn.sharpLeft:
      return ms ? 'belok tajam ke kiri' : 'turn sharp left';
    case Turn.uturnRight:
    case Turn.uturnLeft:
      return ms ? 'buat pusingan U' : 'make a U-turn';
    case Turn.rampRight:
      return ms ? 'ambil susur kanan' : 'take the ramp on the right';
    case Turn.rampLeft:
      return ms ? 'ambil susur kiri' : 'take the ramp on the left';
    case Turn.exitRight:
      return ms ? 'keluar di sebelah kanan' : 'take the exit on the right';
    case Turn.exitLeft:
      return ms ? 'keluar di sebelah kiri' : 'take the exit on the left';
    case Turn.stayRight:
      return ms ? 'kekal di sebelah kanan' : 'keep right';
    case Turn.stayLeft:
      return ms ? 'kekal di sebelah kiri' : 'keep left';
    case Turn.merge:
      return ms ? 'masuk ke jalan utama' : 'merge';
    case Turn.mergeLeft:
      return ms ? 'masuk ke kiri' : 'merge left';
    case Turn.mergeRight:
      return ms ? 'masuk ke kanan' : 'merge right';
    case Turn.roundaboutEnter:
      if (m.roundaboutExit > 0) {
        return ms
            ? 'di bulatan, ambil susur keluar ${_ordinal(m.roundaboutExit, l)}'
            : 'at the roundabout, take the ${_ordinal(m.roundaboutExit, l)} exit';
      }
      return ms ? 'masuk bulatan' : 'enter the roundabout';
    case Turn.roundaboutExit:
      return ms ? 'keluar dari bulatan' : 'exit the roundabout';
    case Turn.ferryEnter:
      return ms ? 'naik feri' : 'board the ferry';
    case Turn.ferryExit:
      return ms ? 'turun dari feri' : 'leave the ferry';
  }
}

/// "ke Jalan Ampang" / "arah Seremban" — the destination of the maneuver.
String target(Maneuver m, Lang l, {bool spoken = true}) {
  final ms = l == Lang.ms;
  if (isArrival(m.turn) || m.turn == Turn.start) return '';
  final isExit = m.turn == Turn.exitLeft || m.turn == Turn.exitRight || m.turn == Turn.rampLeft || m.turn == Turn.rampRight;
  if (isExit && m.toward.isNotEmpty) return ms ? 'arah ${m.toward}' : 'towards ${m.toward}';
  if (m.street.isNotEmpty) return ms ? 'ke ${m.street}' : 'onto ${m.street}';
  // Spoken refs read better spelled out: "E1" → "E 1".
  if (m.ref.isNotEmpty) {
    final ref = spoken ? m.ref.replaceAllMapped(RegExp(r'([A-Z])(\d)'), (x) => '${x[1]} ${x[2]}') : m.ref;
    return ms ? 'ke $ref' : 'onto $ref';
  }
  if (m.toward.isNotEmpty) return ms ? 'arah ${m.toward}' : 'towards ${m.toward}';
  return '';
}

/// Distance as spoken: "300 meter" / "1.5 kilometer" (BM), "300 metres" (EN).
String spokenDistance(double m, Lang l) {
  final ms = l == Lang.ms;
  if (m >= 1000) {
    final km = m / 1000;
    // Whole kilometres from 2 up; halves below ("1.5").
    final half = km >= 2 ? km.roundToDouble() : (km * 2).round() / 2;
    final txt = half == half.roundToDouble() ? half.toInt().toString() : half.toString();
    return ms ? '$txt kilometer' : '$txt ${txt == '1' ? 'kilometre' : 'kilometres'}';
  }
  final rounded = m >= 100 ? (m / 50).round() * 50 : (m / 10).round() * 10;
  return ms ? '$rounded meter' : '$rounded metres';
}

/// Distance as shown on screen: "1.2 km", "450 m", "80 m".
String displayDistance(double m) {
  if (m >= 1000) {
    final km = m / 1000;
    return km >= 10 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
  }
  if (m >= 100) return '${(m / 50).round() * 50} m';
  return '${(m / 10).round() * 10} m';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _join(List<String> parts) => parts.where((p) => p.isNotEmpty).join(' ');

/// A full spoken prompt. [distanceM] null means "now".
String spokenPrompt(Maneuver m, Lang l, {double? distanceM, Maneuver? then, double? thenGapM}) {
  final ms = l == Lang.ms;
  final lead = distanceM == null ? '' : (ms ? 'Dalam ${spokenDistance(distanceM, l)},' : 'In ${spokenDistance(distanceM, l)},');
  var s = _join([lead, action(m, l), target(m, l)]);
  if (then != null) {
    final gap = (thenGapM != null && thenGapM >= 50) ? (ms ? 'dalam ${spokenDistance(thenGapM, l)}' : 'in ${spokenDistance(thenGapM, l)}') : '';
    s = '$s, ${_join([ms ? 'kemudian' : 'then', gap, action(then, l)])}';
  }
  return '${_cap(s)}.';
}

/// Banner text without distance: "Belok kanan ke Jalan Ampang".
String bannerText(Maneuver m, Lang l) => _cap(_join([action(m, l), target(m, l, spoken: false)]));

String recalculating(Lang l) => l == Lang.ms ? 'Mengira semula laluan.' : 'Recalculating.';

String continueFor(double m, Lang l) =>
    l == Lang.ms ? 'Teruskan sejauh ${spokenDistance(m, l)}.' : 'Continue for ${spokenDistance(m, l)}.';

String arrivalSoon(Maneuver m, double d, Lang l) {
  final side = m.turn == Turn.destinationLeft
      ? (l == Lang.ms ? ' di sebelah kiri' : ' on the left')
      : m.turn == Turn.destinationRight
          ? (l == Lang.ms ? ' di sebelah kanan' : ' on the right')
          : '';
  return l == Lang.ms
      ? 'Destinasi$side dalam ${spokenDistance(d, l)}.'
      : 'Your destination is$side in ${spokenDistance(d, l)}.';
}

String arrived(Lang l) => l == Lang.ms ? 'Anda telah tiba.' : 'You have arrived.';
