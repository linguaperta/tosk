/// Sound effects: short synthesized WAVs from `assets/sounds/` (made by
/// `tool/make_sounds.py`), played through preloaded, low-latency pools.
///
/// [SoundService] is what the UI calls; it respects the "Sound effects"
/// setting and fails silently: a platform without audio (or a missing plugin)
/// simply plays nothing. The [AudioBackend] is injectable, so tests use a fake.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The app's sounds.
enum Sfx {
  correct('sounds/correct.wav', 0.9),
  wrong('sounds/wrong.wav', 0.8),
  complete('sounds/complete.wav', 0.9),
  levelUp('sounds/level_up.wav', 0.9),
  bonus('sounds/bonus.wav', 0.8),

  /// The muted tick for selecting an option, tile or chip (already quiet in
  /// the file, and played softer still).
  select('sounds/select.wav', 0.6);

  const Sfx(this.asset, this.volume);

  /// Path under `assets/`.
  final String asset;
  final double volume;
}

/// Plays preloaded sounds. Implementations must never throw from [play].
abstract interface class AudioBackend {
  /// Loads [sounds] so the first [play] has no delay. Safe to call repeatedly.
  Future<void> preload(Iterable<Sfx> sounds);
  Future<void> play(Sfx sfx);
  Future<void> dispose();
}

/// Plays nothing (tests, and platforms where audio failed to start).
class SilentAudioBackend implements AudioBackend {
  const SilentAudioBackend();
  @override
  Future<void> preload(Iterable<Sfx> sounds) async {}
  @override
  Future<void> play(Sfx sfx) async {}
  @override
  Future<void> dispose() async {}
}

/// audioplayers [AudioPool]s, one per sound (several players each, so quick
/// repeats overlap). Sound effects don't take audio focus: the learner's
/// music keeps playing (Android: no focus, sonification usage; iOS: the
/// ambient category, which mixes and respects the silent switch).
class AudioplayersBackend implements AudioBackend {
  AudioplayersBackend();

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final Map<Sfx, Future<AudioPool?>> _pools = {};
  final AudioCache _cache = AudioCache(prefix: 'assets/');
  bool _broken = false;

  Future<AudioPool?> _pool(Sfx s) => _pools[s] ??= () async {
    try {
      return await AudioPool.create(
        source: AssetSource(s.asset),
        maxPlayers: s == Sfx.select ? 4 : 2,
        minPlayers: 1,
        audioCache: _cache,
        audioContext: _context,
      );
    } catch (e) {
      // No audio on this platform (or the plugin is missing): stay silent.
      _broken = true;
      debugPrint('[sound] ${s.name} unavailable: $e');
      return null;
    }
  }();

  @override
  Future<void> preload(Iterable<Sfx> sounds) async {
    for (final s in sounds) {
      if (_broken) return;
      await _pool(s);
    }
  }

  @override
  Future<void> play(Sfx sfx) async {
    if (_broken) return;
    try {
      final pool = await _pool(sfx);
      await pool?.start(volume: sfx.volume);
    } catch (e) {
      debugPrint('[sound] ${sfx.name} failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    for (final f in _pools.values) {
      try {
        await (await f)?.dispose();
      } catch (_) {}
    }
    _pools.clear();
  }
}

/// The UI's entry point. Cheap to create (the backend holds the loaded
/// sounds); [enabled] follows the "Sound effects" setting.
class SoundService {
  SoundService(this.backend, {this.enabled = true});

  final AudioBackend backend;
  final bool enabled;

  /// Loads every sound in the background (call when a session starts).
  void warmUp() {
    if (!enabled) return;
    _quietly(() => backend.preload(Sfx.values));
  }

  void play(Sfx sfx) {
    if (!enabled) return;
    _quietly(() => backend.play(sfx));
  }

  /// Audio must never break the UI: swallow sync and async failures.
  static void _quietly(Future<void> Function() action) {
    try {
      unawaited(action().catchError((Object _) {}));
    } catch (_) {}
  }

  void correct() => play(Sfx.correct);
  void wrong() => play(Sfx.wrong);
  void complete() => play(Sfx.complete);
  void levelUp() => play(Sfx.levelUp);
  void bonus() => play(Sfx.bonus);
  void select() => play(Sfx.select);
}
