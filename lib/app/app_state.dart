// The services every screen needs, created once at start-up and handed down
// the widget tree. context.app gives any screen access; context.tr('BM', 'EN')
// picks the string for the chosen language.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geo.dart';
import '../core/location.dart';
import '../core/settings.dart';
import '../nav/phrases.dart';
import '../nav/speech.dart';
import '../offline/packs.dart';
import '../reports/reports.dart';
import '../routing/routing_service.dart';
import '../routing/tolls.dart';
import '../search/search_service.dart';

class AppState extends ChangeNotifier {
  final Settings settings;
  final PackManager packs;
  final RoutingService routing;
  final SearchService search;
  final ReportsService reports;
  final LocationService location = LocationService();
  final Speech speech = Speech();
  bool _netOnline = true;
  bool get online => _netOnline && !settings.forceOffline;
  StreamSubscription<List<ConnectivityResult>>? _net;
  bool onWifi = false;

  /// Toll prices (assets/tolls.json); null if the table failed to load.
  TollData? tolls;

  AppState._(this.settings, this.packs, this.routing, this.search, this.reports) {
    settings.addListener(notifyListeners);
    packs.addListener(notifyListeners);
  }

  static Future<AppState> create() async {
    final settings = await Settings.load();
    final packs = await PackManager.create();
    final reports = await ReportsService.create();
    final s = AppState._(settings, packs, RoutingService(packs), SearchService(packs), reports);
    await s._watchNetwork();
    try {
      s.tolls = TollData.parse(await rootBundle.loadString('assets/tolls.json'));
    } catch (_) {}
    unawaited(packs.refreshCatalog());
    unawaited(s.speech.init(settings.lang, volume: settings.voiceVolume));
    return s;
  }

  Future<void> _watchNetwork() async {
    void apply(List<ConnectivityResult> r) {
      final was = online;
      _netOnline = r.any((x) => x != ConnectivityResult.none);
      onWifi = r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
      if (was != online) notifyListeners();
    }

    apply(await Connectivity().checkConnectivity());
    _net = Connectivity().onConnectivityChanged.listen(apply);
  }

  Lang get lang => settings.lang;
  String tr(String ms, String en) => settings.lang == Lang.ms ? ms : en;

  Future<void> setLang(Lang l) async {
    settings.lang = l;
    await speech.init(l, volume: settings.voiceVolume);
  }

  /// Best known position: last GPS fix, else the middle of KL.
  Geo get here => location.last?.pos ?? const Geo(3.1478, 101.6953);
  bool get hasFix => location.last != null;

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
  String tr(String ms, String en) => AppScope.of(this).tr(ms, en);
}
