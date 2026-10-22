// Everything Arah remembers on the phone: settings, Home/Work, favourites
// and recent searches. Nothing leaves the phone (no trip history kept).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nav/phrases.dart';
import 'geo.dart';
import '../routing/route_model.dart';
import '../search/place.dart';

enum MapTheme { auto, light, dark }

class Settings extends ChangeNotifier {
  final SharedPreferences _p;
  Settings._(this._p);
  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _set(() => _p.setBool('onboarded', v));

  Lang get lang => _p.getString('lang') == 'en' ? Lang.en : Lang.ms;
  set lang(Lang v) => _set(() => _p.setString('lang', v.name));

  TravelMode get mode => _p.getString('mode') == 'motorcycle' ? TravelMode.motorcycle : TravelMode.car;
  set mode(TravelMode v) => _set(() => _p.setString('mode', v.name));

  bool get avoidTolls => _p.getBool('avoidTolls') ?? false;
  set avoidTolls(bool v) => _set(() => _p.setBool('avoidTolls', v));
  bool get avoidHighways => _p.getBool('avoidHighways') ?? false;
  set avoidHighways(bool v) => _set(() => _p.setBool('avoidHighways', v));
  bool get avoidFerries => _p.getBool('avoidFerries') ?? false;
  set avoidFerries(bool v) => _set(() => _p.setBool('avoidFerries', v));

  RouteOptions get routeOptions =>
      RouteOptions(mode: mode, avoidTolls: avoidTolls, avoidHighways: avoidHighways, avoidFerries: avoidFerries);

  /// Voice prompt timing: 1.5 early, 1.0 normal, 0.5 late.
  double get voiceTiming => _p.getDouble('voiceTiming') ?? 1.0;
  set voiceTiming(double v) => _set(() => _p.setDouble('voiceTiming', v));
  bool get bluetoothDelay => _p.getBool('btDelay') ?? true;
  set bluetoothDelay(bool v) => _set(() => _p.setBool('btDelay', v));
  double get voiceVolume => _p.getDouble('voiceVolume') ?? 1.0;
  set voiceVolume(double v) => _set(() => _p.setDouble('voiceVolume', v));

  /// 0 = sound on, 1 = alerts only, 2 = muted.
  int get sound => _p.getInt('sound') ?? 0;
  set sound(int v) => _set(() => _p.setInt('sound', v));

  MapTheme get theme => MapTheme.values[_p.getInt('theme') ?? 0];
  set theme(MapTheme v) => _set(() => _p.setInt('theme', v.index));

  /// Warn about fixed speed and red-light cameras ahead.
  bool get cameraAlerts => _p.getBool('cameraAlerts') ?? true;
  set cameraAlerts(bool v) => _set(() => _p.setBool('cameraAlerts', v));
  bool get showSpeedLimit => _p.getBool('speedLimit') ?? true;
  set showSpeedLimit(bool v) => _set(() => _p.setBool('speedLimit', v));

  /// km/h over the limit before the speedometer turns red.
  int get speedingMargin => _p.getInt('speedingMargin') ?? 5;
  set speedingMargin(int v) => _set(() => _p.setInt('speedingMargin', v));
  bool get wifiOnlyDownloads => _p.getBool('wifiOnly') ?? true;
  set wifiOnlyDownloads(bool v) => _set(() => _p.setBool('wifiOnly', v));

  /// Pretend there's no internet, to check offline maps before a trip.
  bool get forceOffline => _p.getBool('forceOffline') ?? false;
  set forceOffline(bool v) => _set(() => _p.setBool('forceOffline', v));

  Place? get home => _place('home');
  set home(Place? v) => _setPlace('home', v);
  Place? get work => _place('work');
  set work(Place? v) => _setPlace('work', v);

  List<Place> get favourites => _places('favourites');
  List<Place> get recents => _places('recents');

  void addFavourite(Place p) {
    final list = favourites..removeWhere((x) => _same(x, p));
    list.insert(0, p);
    _savePlaces('favourites', list);
  }

  void removeFavourite(Place p) => _savePlaces('favourites', favourites..removeWhere((x) => _same(x, p)));
  bool isFavourite(Place p) => favourites.any((x) => _same(x, p));

  void addRecent(Place p) {
    final list = recents..removeWhere((x) => _same(x, p));
    list.insert(0, p);
    _savePlaces('recents', list.take(20).toList());
  }

  void clearRecents() => _savePlaces('recents', []);

  /// Same name within 300 m is the same place (online and offline search can
  /// put one mall's pin a little apart).
  bool _same(Place a, Place b) => a.name == b.name && distanceM(a.pos, b.pos) < 300;

  Place? _place(String k) {
    final s = _p.getString(k);
    return s == null ? null : Place.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  void _setPlace(String k, Place? v) => _set(() => v == null ? _p.remove(k) : _p.setString(k, jsonEncode(v.toJson())));

  List<Place> _places(String k) => [
    for (final s in _p.getStringList(k) ?? const <String>[]) Place.fromJson(jsonDecode(s) as Map<String, dynamic>),
  ];

  void _savePlaces(String k, List<Place> v) => _set(() => _p.setStringList(k, [for (final x in v) jsonEncode(x.toJson())]));

  void _set(Future<bool> Function() f) {
    f();
    notifyListeners();
  }
}
