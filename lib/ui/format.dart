import '../nav/phrases.dart';

String fmtDuration(double s, Lang l) {
  final mins = (s / 60).round();
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60, m = mins % 60;
  final hh = l == Lang.ms ? 'j' : 'h';
  return m == 0 ? '$h $hh' : '$h $hh $m min';
}

String fmtClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String fmtEta(double s) => fmtClock(DateTime.now().add(Duration(seconds: s.round())));

String fmtKm(double m) => displayDistance(m);
