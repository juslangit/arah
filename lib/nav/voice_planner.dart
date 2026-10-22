// Decides when to speak. Each maneuver gets at most three prompts — early,
// "in X m", and "now" — at distances that grow with speed (app study §C3.3,
// after OsmAnd's AnnounceTimeDistances and Organic Maps).
import 'dart:math' as math;

import '../routing/route_model.dart';
import 'nav_engine.dart';
import 'phrases.dart';

class PromptDistances {
  final double early; // 0 = no early prompt in this band
  final double mid;
  final double now;
  const PromptDistances(this.early, this.mid, this.now);
}

/// Speed bands for Malaysian roads: taman/jam, town arterials,
/// federal roads, expressways.
PromptDistances distancesFor(double speedKmh, {double timing = 1.0, bool bluetooth = false}) {
  PromptDistances d;
  if (speedKmh < 30) {
    d = const PromptDistances(0, 150, 30);
  } else if (speedKmh < 60) {
    d = const PromptDistances(0, 300, 80);
  } else if (speedKmh < 90) {
    d = const PromptDistances(1000, 500, 150);
  } else {
    d = const PromptDistances(2000, 1000, 250);
  }
  // Bluetooth car audio starts late; speak 1.5 s earlier.
  final lead = bluetooth ? speedKmh / 3.6 * 1.5 : 0.0;
  return PromptDistances(
    d.early == 0 ? 0 : d.early * timing + lead,
    d.mid * timing + lead,
    d.now * timing + lead,
  );
}

class VoicePrompt {
  final String text;
  final bool urgent; // "now" prompts may cut off whatever is playing
  const VoicePrompt(this.text, {this.urgent = false});
}

class VoicePlanner {
  final ArahRoute route;
  Lang lang;
  double timing; // 1.5 early, 1.0 normal, 0.5 late
  bool bluetooth;

  final _done = <int, Set<String>>{}; // maneuver index → stages spoken
  final _speeds = <double>[];
  DateTime? _lastSpoken;
  int _lastNext = -2;
  bool _arrivalSoonSaid = false;
  bool _arrivedSaid = false;

  VoicePlanner(this.route, {this.lang = Lang.ms, this.timing = 1.0, this.bluetooth = false});

  /// Smoothed over the last five fixes, about five seconds at 1 Hz.
  double _smooth(double kmh) {
    _speeds.add(kmh);
    if (_speeds.length > 5) _speeds.removeAt(0);
    return _speeds.reduce((a, b) => a + b) / _speeds.length;
  }

  VoicePrompt? next(NavUpdate u, DateTime now) {
    final v = _smooth(u.speedKmh);
    final ms = route.maneuvers;

    if (u.event == NavEvent.arrived) {
      if (_arrivedSaid) return null;
      _arrivedSaid = true;
      return _say(arrived(lang), now, urgent: true);
    }
    if (u.nextIndex < 0) return null;
    final m = ms[u.nextIndex];
    final stages = _done.putIfAbsent(u.nextIndex, () => <String>{});
    final d = distancesFor(v, timing: timing, bluetooth: bluetooth);

    // A maneuver just became "next": skip early/mid stages it is already past.
    if (u.nextIndex != _lastNext) {
      final justPassed = _lastNext >= 0;
      _lastNext = u.nextIndex;
      if (u.toNextM < d.mid * 1.5) stages.add('early');
      if (u.toNextM < d.now + 12) stages.add('mid');
      // Long stretch ahead: say how far once.
      if (justPassed && u.toNextM > 3000 && !isArrival(m.turn)) {
        return _say(continueFor(u.toNextM, lang), now);
      }
    }

    if (isArrival(m.turn)) {
      final soon = math.max(12, v / 3.6 * 5) + 50;
      if (!_arrivalSoonSaid && u.toNextM <= soon && u.toNextM > 20) {
        _arrivalSoonSaid = true;
        return _say(arrivalSoon(m, u.toNextM, lang), now);
      }
      return null;
    }

    final then = u.thenIndex >= 0 ? ms[u.thenIndex] : null;
    final secondsAway = v > 1 ? u.toNextM / (v / 3.6) : double.infinity;

    // "Now" — includes a 12 m positioning tolerance.
    if (!stages.contains('now') && u.toNextM <= d.now + 12) {
      stages..add('now')..add('mid')..add('early');
      return _say(spokenPrompt(m, lang, then: then, thenGapM: u.thenGapM), now, urgent: true);
    }
    // "In X m" — skipped when fewer than 15 s remain (the now prompt follows).
    if (!stages.contains('mid') && u.toNextM <= d.mid) {
      stages..add('mid')..add('early');
      if (secondsAway < 15) return null;
      return _say(spokenPrompt(m, lang, distanceM: u.toNextM), now);
    }
    if (d.early > 0 && !stages.contains('early') && u.toNextM <= d.early) {
      stages.add('early');
      return _say(spokenPrompt(m, lang, distanceM: u.toNextM), now);
    }
    return null;
  }

  VoicePrompt? _say(String text, DateTime now, {bool urgent = false}) {
    // Never two prompts within 4 s, except one that cannot wait.
    if (!urgent && _lastSpoken != null && now.difference(_lastSpoken!) < const Duration(seconds: 4)) return null;
    _lastSpoken = now;
    return VoicePrompt(text, urgent: urgent);
  }
}
