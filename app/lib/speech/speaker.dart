/// On-device text-to-speech (v0.5): the `listen_pick` exercise and the
/// "pronounce" buttons. [Speaker] is the seam; [TtsSpeaker] runs on
/// `flutter_tts` (Android, iOS, macOS, web; on Windows the plugin is replaced
/// by a copy without its native part, so there is no voice there), and
/// [NullSpeaker] is used under `flutter test` and as the fallback.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Whether a language can be spoken on this device.
enum VoiceStatus {
  /// A usable voice.
  ready,

  /// The engine knows the language, but its voice data isn't on the device
  /// (Android: the voice has the `notInstalled` feature, or speaking failed
  /// with `ERROR_NOT_INSTALLED_YET`). The learner can install it.
  notInstalled,

  /// The engine has no voice for the language at all.
  missing,

  /// No speech here: no engine, the platform has none (Windows, tests), or
  /// the engine didn't answer.
  unavailable,
}

/// Speaks target-language text.
abstract interface class Speaker {
  /// Whether [languageCode] (the course's target language, a BCP-47 base code
  /// such as `it`) can be spoken on this device.
  Future<VoiceStatus> voiceStatus(String languageCode);

  /// Speaks [text]; completes when it is done (or failed). [slow] is the
  /// slow replay (about 60 % of the normal rate).
  Future<void> speak(String text, String languageCode, {bool slow = false});

  Future<void> stop();
}

/// No voice anywhere (tests, unsupported platforms).
class NullSpeaker implements Speaker {
  const NullSpeaker();
  @override
  Future<VoiceStatus> voiceStatus(String languageCode) async => VoiceStatus.unavailable;
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

String _norm(String l) => l.replaceAll('_', '-').toLowerCase();

bool _isLanguage(String locale, String code) {
  final n = _norm(locale);
  return n == code || n.startsWith('$code-');
}

/// The best locale among [available] (as the TTS engine lists them, `it-IT`
/// or `it_IT`) for the language [code]: the code itself, then the preferred
/// region, then `{code}-{CODE}`, then any region of the language. Null when
/// the language has no voice (Sarnami `hns`: none).
String? pickVoiceLocale(String code, Iterable<String> available) {
  final c = code.toLowerCase();
  final list = [
    for (final l in available)
      if (l.trim().isNotEmpty) l,
  ];
  for (final l in list) {
    if (_norm(l) == c) return l;
  }
  final region = (kPreferredVoiceRegion[c] ?? c).toLowerCase();
  for (final want in ['$c-$region', '$c-$c']) {
    for (final l in list) {
      if (_norm(l) == want) return l;
    }
  }
  final regional = [
    for (final l in list)
      if (_norm(l).startsWith('$c-')) l,
  ]..sort();
  return regional.firstOrNull;
}

/// One voice as the Android engine lists it (`FlutterTts.getVoices`).
@immutable
class TtsVoice {
  const TtsVoice({required this.name, required this.locale, this.network = false, this.notInstalled = false});

  final String name;
  final String locale;

  /// Synthesised online (`network_required`): works only with a connection.
  final bool network;

  /// Has `TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED`: listed, but the
  /// data still has to be downloaded (Google's engine lists every language
  /// it can download, so "available" alone doesn't mean it can speak).
  final bool notInstalled;

  /// From the plugin's map (`name`, `locale`, `network_required` "1"/"0",
  /// `features` tab-separated); null when it has no name or locale.
  static TtsVoice? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final locale = raw['locale']?.toString() ?? '';
    if (name.isEmpty || locale.isEmpty) return null;
    final features = (raw['features']?.toString() ?? '').split(RegExp(r'[\t,]')).map((f) => f.trim());
    return TtsVoice(
      name: name,
      locale: locale,
      network: raw['network_required']?.toString() == '1',
      notInstalled: features.contains('notInstalled'),
    );
  }

  /// What `FlutterTts.setVoice` takes.
  Map<String, String> toMap() => {'name': name, 'locale': locale};

  @override
  String toString() => '$name ($locale${network ? ', network' : ''}${notInstalled ? ', not installed' : ''})';
}

/// The voice to use for the language [code] among the engine's [voices]:
/// installed ones only, in the locale [pickVoiceLocale] prefers, an on-device
/// one before a network one. The status says why there is none.
({VoiceStatus status, TtsVoice? voice}) pickVoice(String code, Iterable<TtsVoice> voices) {
  final c = code.toLowerCase();
  final ofLanguage = [
    for (final v in voices)
      if (_isLanguage(v.locale, c)) v,
  ];
  if (ofLanguage.isEmpty) return (status: VoiceStatus.missing, voice: null);
  final installed = [
    for (final v in ofLanguage)
      if (!v.notInstalled) v,
  ];
  if (installed.isEmpty) return (status: VoiceStatus.notInstalled, voice: null);
  final locale = pickVoiceLocale(c, {for (final v in installed) v.locale});
  final inLocale = [
    for (final v in installed)
      if (v.locale == locale) v,
  ];
  final voice = inLocale.firstWhere((v) => !v.network, orElse: () => inLocale.first);
  return (status: VoiceStatus.ready, voice: voice);
}

/// Android `TextToSpeech.ERROR_NOT_INSTALLED_YET`: the voice data is missing.
const int kTtsErrorNotInstalled = -9;

/// Android `AudioAttributes.USAGE_MEDIA` and `CONTENT_TYPE_SPEECH`: speech
/// plays on the media stream (the media volume), like a video or a podcast.
const int kAndroidUsageMedia = 1;
const int kAndroidContentTypeSpeech = 1;

/// The platforms [TtsSpeaker] sets up differently.
enum TtsPlatform { android, ios, other }

TtsPlatform get _currentTtsPlatform {
  if (kIsWeb) return TtsPlatform.other;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => TtsPlatform.android,
    TargetPlatform.iOS => TtsPlatform.ios,
    _ => TtsPlatform.other,
  };
}

/// The voice resolved for a language.
class _Resolved {
  const _Resolved(this.status, {this.locale, this.voice});
  final VoiceStatus status;
  final String? locale;
  final TtsVoice? voice;
}

/// [Speaker] over `flutter_tts`.
///
/// Set-up runs once, before anything else is asked of the engine: wait for
/// each utterance to finish, then the audio output (Android: the media
/// stream; iOS: the playback category, mixing with other audio). Voices are
/// resolved once per language; a failed or timed-out lookup is not cached,
/// so a slow engine start doesn't hide the voice for the whole session.
/// [onVoiceProblem] is told when a language turns out not to be speakable
/// after all (the engine said "not installed" while speaking).
class TtsSpeaker implements Speaker {
  TtsSpeaker({FlutterTts? tts, TtsPlatform? platform, this.onVoiceProblem})
    : _tts = tts ?? FlutterTts(),
      platform = platform ?? _currentTtsPlatform;

  final FlutterTts _tts;
  final TtsPlatform platform;
  final void Function(String languageCode, VoiceStatus status)? onVoiceProblem;

  Future<void>? _setup;
  final Map<String, Future<_Resolved>> _voices = {};
  String? _current;
  double? _currentRate;
  (double, double)? _rates;

  /// Runs once before the first engine call.
  Future<void> _ready() => _setup ??= () async {
    try {
      await _tts.awaitSpeakCompletion(true);
      switch (platform) {
        case TtsPlatform.android:
          await _tts.setAudioAttributes(usage: kAndroidUsageMedia, contentType: kAndroidContentTypeSpeech);
        case TtsPlatform.ios:
          await _tts.setSharedInstance(true);
          await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ]);
        case TtsPlatform.other:
          break;
      }
    } catch (e) {
      debugPrint('[tts] set-up failed: $e');
    }
  }();

  Future<_Resolved> _resolve(String code) {
    final cached = _voices[code];
    if (cached != null) return cached;
    final f = _lookUp(code);
    _voices[code] = f;
    // Don't keep an answer that came from a failure: ask again next time.
    unawaited(
      f.then((r) {
        if (r.status == VoiceStatus.unavailable && identical(_voices[code], f)) _voices.remove(code);
      }),
    );
    return f;
  }

  Future<_Resolved> _lookUp(String code) async {
    await _ready();
    if (platform == TtsPlatform.android) {
      final voices = await _androidVoices();
      if (voices.isNotEmpty) {
        final pick = pickVoice(code, voices);
        debugPrint(
          '[tts] $code: ${pick.status.name}${pick.voice == null ? '' : ', ${pick.voice}'}; '
          'engine voices: ${[for (final v in voices)
            if (_isLanguage(v.locale, code)) v].join('; ')}',
        );
        return _Resolved(pick.status, locale: pick.voice?.locale, voice: pick.voice);
      }
    }
    final List<String> langs;
    try {
      final raw = await _tts.getLanguages.timeout(const Duration(seconds: 4));
      langs = [
        if (raw is Iterable)
          for (final l in raw)
            if (l != null) '$l',
      ];
    } catch (e) {
      debugPrint('[tts] no language list: $e');
      return const _Resolved(VoiceStatus.unavailable);
    }
    if (langs.isEmpty) return const _Resolved(VoiceStatus.unavailable);
    final locale = pickVoiceLocale(code, langs);
    if (locale == null) return const _Resolved(VoiceStatus.missing);
    if (platform == TtsPlatform.android) {
      // Listed is not always usable: the voice data may be missing.
      try {
        final ok = await _tts.isLanguageAvailable(locale).timeout(const Duration(seconds: 3));
        if (ok != true) return const _Resolved(VoiceStatus.notInstalled);
      } catch (_) {
        return const _Resolved(VoiceStatus.unavailable);
      }
    }
    debugPrint('[tts] $code: ready, $locale');
    return _Resolved(VoiceStatus.ready, locale: locale);
  }

  /// The Android engine's voices; empty when it lists none or doesn't answer.
  Future<List<TtsVoice>> _androidVoices() async {
    try {
      final raw = await _tts.getVoices.timeout(const Duration(seconds: 4));
      return [
        if (raw is Iterable)
          for (final m in raw) ?TtsVoice.fromMap(m),
      ];
    } catch (e) {
      debugPrint('[tts] no voice list: $e');
      return const [];
    }
  }

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
  Future<VoiceStatus> voiceStatus(String languageCode) async {
    try {
      return (await _resolve(languageCode)).status;
    } catch (_) {
      return VoiceStatus.unavailable;
    }
  }

  @override
  Future<void> speak(String text, String languageCode, {bool slow = false}) async {
    if (text.trim().isEmpty) return;
    try {
      final v = await _resolve(languageCode);
      if (v.status != VoiceStatus.ready) return;
      await _tts.stop();
      final key = v.voice?.name ?? v.locale;
      if (_current != key) {
        var set = false;
        if (v.voice != null) set = await _tts.setVoice(v.voice!.toMap()) == 1;
        if (!set) await _tts.setLanguage(v.locale!);
        _current = key;
      }
      final (normal, slowRate) = await _rate();
      final rate = slow ? slowRate : normal;
      if (_currentRate != rate) {
        await _tts.setSpeechRate(rate);
        _currentRate = rate;
      }
      final r = await _tts.speak(text).timeout(const Duration(seconds: 30));
      // The patched Android plugin returns the engine's error code (negative).
      if (r is int && r < 0) _failed(languageCode, r);
    } catch (e) {
      debugPrint('[tts] speak failed: $e');
    }
  }

  void _failed(String code, int error) {
    debugPrint('[tts] speaking $code failed: engine error $error');
    if (error != kTtsErrorNotInstalled) return;
    _voices[code] = Future.value(const _Resolved(VoiceStatus.notInstalled));
    _current = null;
    onVoiceProblem?.call(code, VoiceStatus.notInstalled);
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
