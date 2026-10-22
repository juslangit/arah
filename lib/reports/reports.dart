// Waze-style community reports. Each kind has its own lifetime; "Masih ada?"
// answers from drivers passing in the same direction extend or remove it
// (app study §C3.4). Shared through Supabase when configured; until then
// reports stay on this phone so the feature still works for one user.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/geo.dart';

enum ReportKind { polis, kemalangan, kesesakan, bahaya, banjir, ditutup }

class ReportRule {
  final Duration life, extend, cap;
  final int noVotesToRemove;
  const ReportRule(this.life, this.extend, this.cap, this.noVotesToRemove);
}

const _h = Duration(hours: 1);

/// Lifetimes per kind (and per hazard sub-type), from the app study.
ReportRule ruleFor(ReportKind k, String sub) {
  switch (k) {
    case ReportKind.polis:
      return const ReportRule(Duration(minutes: 60), Duration(minutes: 30), Duration(hours: 2), 2);
    case ReportKind.kemalangan:
      return const ReportRule(Duration(minutes: 60), Duration(minutes: 30), Duration(hours: 3), 2);
    case ReportKind.kesesakan:
      return const ReportRule(Duration(minutes: 30), Duration(minutes: 15), Duration(hours: 2), 2);
    case ReportKind.banjir:
      return const ReportRule(Duration(hours: 3), _h, Duration(hours: 12), 2);
    case ReportKind.ditutup:
      return const ReportRule(Duration(hours: 2), _h, Duration(hours: 24), 3);
    case ReportKind.bahaya:
      switch (sub) {
        case 'bahu':
          return const ReportRule(Duration(minutes: 30), Duration(minutes: 15), Duration(hours: 2), 1);
        case 'lubang':
          return const ReportRule(Duration(days: 7), Duration(days: 7), Duration(days: 30), 3);
        case 'lampu':
          return const ReportRule(Duration(hours: 4), Duration(hours: 2), Duration(hours: 12), 2);
        case 'kerja':
          return const ReportRule(Duration(hours: 24), Duration(hours: 24), Duration(days: 14), 3);
        default:
          return const ReportRule(Duration(minutes: 60), Duration(minutes: 30), Duration(hours: 3), 2);
      }
  }
}

class Report {
  final String id;
  final ReportKind kind;
  final String sub;
  final Geo pos;
  final double heading;
  final DateTime created;
  DateTime expires;
  int yes, no;
  final bool mine;

  Report({
    required this.id,
    required this.kind,
    required this.sub,
    required this.pos,
    required this.heading,
    required this.created,
    required this.expires,
    this.yes = 0,
    this.no = 0,
    this.mine = false,
  });

  bool get confirmed => yes >= 2;
  bool alive(DateTime now) => expires.isAfter(now);

  /// Past half its life → drawn faded on the map.
  bool faded(DateTime now) => now.difference(created) > expires.difference(created) * 0.5;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'sub': sub,
    'lat': pos.lat,
    'lon': pos.lon,
    'heading': heading,
    'created_at': created.toIso8601String(),
    'expires_at': expires.toIso8601String(),
    'yes': yes,
    'no': no,
    'mine': mine,
  };

  factory Report.fromJson(Map<String, dynamic> j) => Report(
    id: '${j['id']}',
    kind: ReportKind.values.byName(j['kind'] as String),
    sub: j['sub'] as String? ?? '',
    pos: Geo((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
    heading: (j['heading'] as num?)?.toDouble() ?? 0,
    created: DateTime.parse(j['created_at'] as String).toLocal(),
    expires: DateTime.parse(j['expires_at'] as String).toLocal(),
    yes: (j['yes'] as num?)?.toInt() ?? 0,
    no: (j['no'] as num?)?.toInt() ?? 0,
    mine: j['mine'] == true,
  );
}

/// Applies a "still there?" answer the same way the server does.
void applyVote(Report r, bool stillThere, DateTime now) {
  final rule = ruleFor(r.kind, r.sub);
  if (stillThere) {
    r.yes++;
    final ext = r.expires.add(rule.extend);
    final cap = r.created.add(rule.cap);
    r.expires = ext.isAfter(cap) ? cap : ext;
  } else {
    r.no++;
    if (r.mine || r.no >= rule.noVotesToRemove) {
      r.expires = now;
    } else if (r.kind == ReportKind.kesesakan) {
      r.expires = r.expires.subtract(const Duration(minutes: 15));
    }
  }
}

class ReportsService extends ChangeNotifier {
  final SharedPreferences _prefs;
  final List<Report> reports = [];
  final Set<String> _asked = {}; // reports this phone was already asked about
  final List<DateTime> _sentTimes = [];
  bool get shared => _client != null;
  SupabaseClient? _client;
  Timer? _poll;
  Geo? _lastCentre;

  ReportsService._(this._prefs);

  static Future<ReportsService> create() async {
    final s = ReportsService._(await SharedPreferences.getInstance());
    s._loadLocal();
    if (ArahConfig.supabaseUrl.isNotEmpty && ArahConfig.supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: ArahConfig.supabaseUrl, anonKey: ArahConfig.supabaseAnonKey);
        final c = Supabase.instance.client;
        // An anonymous session per phone: votes and rate limits count per device
        // without asking anyone to sign up.
        if (c.auth.currentSession == null) await c.auth.signInAnonymously();
        s._client = c;
      } catch (e) {
        debugPrint('reports: Supabase unavailable, local only ($e)');
      }
    }
    return s;
  }

  void _loadLocal() {
    final raw = _prefs.getString('reports');
    if (raw == null) return;
    final now = DateTime.now();
    for (final j in jsonDecode(raw) as List) {
      final r = Report.fromJson(j as Map<String, dynamic>);
      if (r.alive(now)) reports.add(r);
    }
  }

  void _saveLocal() {
    if (shared) return;
    _prefs.setString('reports', jsonEncode([for (final r in reports) r.toJson()]));
  }

  /// Anti-abuse: at most 10 reports an hour from one phone.
  bool get canSend {
    final now = DateTime.now();
    _sentTimes.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    return _sentTimes.length < 10;
  }

  Future<Report?> send(ReportKind kind, String sub, Geo pos, double heading) async {
    if (!canSend) return null;
    _sentTimes.add(DateTime.now());
    final now = DateTime.now();
    if (_client != null) {
      try {
        final row = await _client!.rpc(
          'create_report',
          params: {'p_kind': kind.name, 'p_sub': sub, 'p_lat': pos.lat, 'p_lon': pos.lon, 'p_heading': heading},
        );
        final r = Report.fromJson({...(row as Map<String, dynamic>), 'mine': true});
        reports.add(r);
        notifyListeners();
        return r;
      } catch (e) {
        debugPrint('reports: send failed ($e)');
        return null;
      }
    }
    final r = Report(
      id: 'local-${now.microsecondsSinceEpoch}',
      kind: kind,
      sub: sub,
      pos: pos,
      heading: heading,
      created: now,
      expires: now.add(ruleFor(kind, sub).life),
      mine: true,
    );
    reports.add(r);
    _saveLocal();
    notifyListeners();
    return r;
  }

  Future<void> vote(Report r, bool stillThere) async {
    _asked.add(r.id);
    if (_client != null && !r.id.startsWith('local-')) {
      try {
        await _client!.rpc('vote_report', params: {'p_id': r.id, 'p_still_there': stillThere});
      } catch (_) {}
    }
    applyVote(r, stillThere, DateTime.now());
    reports.removeWhere((x) => !x.alive(DateTime.now()));
    _saveLocal();
    notifyListeners();
  }

  bool asked(Report r) => _asked.contains(r.id);

  List<Report> alive() {
    final now = DateTime.now();
    return reports.where((r) => r.alive(now)).toList();
  }

  /// Fetch shared reports around the map centre now and every minute.
  void watch(Geo centre) {
    _lastCentre = centre;
    if (_client == null) return;
    _poll ??= Timer.periodic(const Duration(minutes: 1), (_) => _fetch());
    _fetch();
  }

  Future<void> _fetch() async {
    final c = _lastCentre;
    if (_client == null || c == null) return;
    try {
      final rows = await _client!.rpc('reports_near', params: {'p_lat': c.lat, 'p_lon': c.lon, 'p_km': 60});
      reports
        ..clear()
        ..addAll([for (final j in rows as List) Report.fromJson(j as Map<String, dynamic>)]);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
