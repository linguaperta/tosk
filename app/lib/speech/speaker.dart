/// On-device text-to-speech (v0.5): the `listen_pick` exercise and the
/// "pronounce" buttons. [Speaker] is the seam; [TtsSpeaker] runs on
/// `flutter_tts` (Android, iOS, macOS, web; on Windows the plugin is replaced
/// by a copy without its native part, so there is no voice there), and
/// [NullSpeaker] is used under `flutter test` and as the fallback.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks target-language text.
abstract interface class Speaker {
  /// Whether a voice for [languageCode] (the course's target language, a
  /// BCP-47 base code such as `it`) is available on this device.
  Future<bool> canSpeak(String languageCode);

  /// Speaks [text]; completes when it is done (or failed). [slow] is the
  /// slow replay (about 60 % of the normal rate).
  Future<void> speak(String text, String languageCode, {bool slow = false});

  Future<void> stop();
}

/// No voice anywhere (tests, unsupported platforms).
class NullSpeaker implements Speaker {
  const NullSpeaker();
  @override
  Future<bool> canSpeak(String languageCode) async => false;
  @override
  Future<void> speak(String text, String languageCode, {bool slow = false}) async {}
  @override
  Future<void> stop() async {}
}

/// Regions preferred when a language has several voices (`pt` → `pt-PT`).
const Map<String, String> kPreferredVoiceRegion = {
  'en': 'GB',
  'pt': 'PT',
  'es': 'ES',
  'fr': 'FR',
  'it': 'IT',
  'nl': 'NL',
  'de': 'DE',
  'sv': 'SE',
  'da': 'DK',
  'nb': 'NO',
};

/// The best locale among [available] (as the TTS engine lists them, `it-IT`
/// or `it_IT`) for the language [code]: the code itself, then the preferred
/// region, then `{code}-{CODE}`, then any region of the language. Null when
/// the language has no voice (Sarnami `hns`: none).
String? pickVoiceLocale(String code, Iterable<String> available) {
  final c = code.toLowerCase();
  String norm(String l) => l.replaceAll('_', '-').toLowerCase();
  final list = [for (final l in available) if (l.trim().isNotEmpty) l];
  for (final l in list) {
    if (norm(l) == c) return l;
  }
  final region = (kPreferredVoiceRegion[c] ?? c).toLowerCase();
  for (final want in ['$c-$region', '$c-$c']) {
    for (final l in list) {
      if (norm(l) == want) return l;
    }
  }
  final regional = [for (final l in list) if (norm(l).startsWith('$c-')) l]..sort();
  return regional.firstOrNull;
}

/// [Speaker] over `flutter_tts`.
class TtsSpeaker implements Speaker {
  TtsSpeaker([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  Future<List<String>>? _languages;
  final Map<String, Future<String?>> _voices = {};
  String? _current;
  double? _currentRate;
  (double, double)? _rates;

  Future<List<String>> _langs() => _languages ??= () async {
        try {
          final raw = await _tts.getLanguages.timeout(const Duration(seconds: 4));
          return [if (raw is Iterable) for (final l in raw) if (l != null) '$l'];
        } catch (e) {
          debugPrint('[tts] no language list: $e');
          return const <String>[];
        }
      }();

  /// The engine locale for [code], or null.
  Future<String?> voiceFor(String code) => _voices[code] ??= () async {
        final locale = pickVoiceLocale(code, await _langs());
        if (locale == null) return null;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          // Listed is not always usable: the voice data may be missing.
          try {
            final ok = await _tts.isLanguageAvailable(locale).timeout(const Duration(seconds: 3));
            if (ok != true) return null;
          } catch (_) {
            return null;
          }
        }
        return locale;
      }();

  /// (normal, slow) speech rates for this platform.
  Future<(double, double)> _rate() async => _rates ??= await () async {
        try {
          final r = await _tts.getSpeechRateValidRange.timeout(const Duration(seconds: 2));
          final slow = (r.normal * 0.6).clamp(r.min, r.normal);
          return (r.normal, slow.toDouble());
        } catch (_) {
          // Web: 1.0 is normal there.
          return kIsWeb ? (1.0, 0.6) : (0.5, 0.3);
        }
      }();

  @override
  Future<bool> canSpeak(String languageCode) async {
    try {
      return await voiceFor(languageCode) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text, String languageCode, {bool slow = false}) async {
    if (text.trim().isEmpty) return;
    try {
      final locale = await voiceFor(languageCode);
      if (locale == null) return;
      await _tts.stop();
      if (_current != locale) {
        await _tts.setLanguage(locale);
        _current = locale;
      }
      final (normal, slowRate) = await _rate();
      final rate = slow ? slowRate : normal;
      if (_currentRate != rate) {
        await _tts.setSpeechRate(rate);
        _currentRate = rate;
      }
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(text).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[tts] speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
