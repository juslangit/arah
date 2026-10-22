// Speaks prompts with the phone's own text-to-speech engine. Malay voice
// (ms-MY) when the phone has one, Indonesian as the closest fallback for
// Malay text, English (en-GB) otherwise.
import 'package:flutter_tts/flutter_tts.dart';

import 'phrases.dart';

class Speech {
  final FlutterTts _tts = FlutterTts();
  Lang _lang = Lang.ms;
  String? activeLocale;
  bool ready = false;

  Future<void> init(Lang lang, {double volume = 1.0}) async {
    _lang = lang;
    await _tts.awaitSpeakCompletion(false);
    await _tts.setVolume(volume);
    await _tts.setSpeechRate(0.5);
    // Navigation voice ducks music instead of stopping it.
    try {
      await _tts.setAudioAttributesForNavigation();
    } catch (_) {}
    final langs = ((await _tts.getLanguages) as List?)?.map((e) => '$e'.replaceAll('_', '-')).toList() ?? [];
    final wanted = lang == Lang.ms ? ['ms-MY', 'ms', 'id-ID', 'id', 'en-GB', 'en-US'] : ['en-GB', 'en-US', 'en'];
    for (final w in wanted) {
      final match = langs.where((l) => l.toLowerCase() == w.toLowerCase()).firstOrNull;
      if (match != null) {
        await _tts.setLanguage(match);
        activeLocale = match;
        break;
      }
    }
    ready = true;
  }

  /// True when Malay text will be read by a non-Malay voice.
  bool get malayFallback => _lang == Lang.ms && !(activeLocale ?? '').toLowerCase().startsWith('ms');

  Future<void> say(String text, {bool interrupt = false}) async {
    if (!ready) return;
    if (interrupt) await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> setVolume(double v) => _tts.setVolume(v);
  Future<void> stop() => _tts.stop();
}
