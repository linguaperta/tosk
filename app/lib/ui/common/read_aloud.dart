/// "Read aloud" for stories and reading-mode texts: speaks a text sentence by
/// sentence with the app's text-to-speech (the media stream, like every
/// pronounce button), at the normal or the slow rate (the listening
/// exercises' 🐢), from any sentence, with play/pause. [ReadAloudController]
/// holds the state, [ReadAloudButtons] are the controls (shown only with a
/// voice for the course language: never for Sarnami or Kinyarwanda).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../speech/speaker.dart';
import '../../speech/speech_providers.dart';
import '../theme/bw_skin.dart';

/// Reads sentences `0 .. count - 1` aloud, one after the other.
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required this.speaker,
    required this.languageCode,
    required this.count,
    required this.textOf,
    this.onSentence,
  });

  final Speaker speaker;
  final String languageCode;

  /// The number of sentences.
  int count;

  /// The text of sentence i.
  final String Function(int i) textOf;

  /// Called when sentence i starts (the reader reveals and scrolls to it).
  final void Function(int i)? onSentence;

  int? _current;
  bool _playing = false;
  bool _slow = false;
  int _run = 0;
  bool _disposed = false;

  /// The sentence being read, or where reading paused (null: not started or done).
  int? get current => _current;
  bool get playing => _playing;

  /// The slow rate (about 60 %).
  bool get slow => _slow;

  /// Reading started (playing or paused on a sentence).
  bool get active => _current != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Plays from sentence [from] (default: where it paused, else the first).
  Future<void> play([int? from]) async {
    if (count <= 0) return;
    final start = (from ?? _current ?? 0).clamp(0, count - 1);
    final run = ++_run;
    if (_playing) await speaker.stop();
    _playing = true;
    _current = start;
    _notify();
    for (var i = start; i < count; i++) {
      if (run != _run || _disposed) return;
      _current = i;
      _notify();
      onSentence?.call(i);
      final text = textOf(i).trim();
      if (text.isEmpty) continue;
      try {
        await speaker.speak(text, languageCode, slow: _slow);
      } catch (_) {
        // A failed sentence doesn't end the reading.
      }
    }
    if (run != _run || _disposed) return;
    _playing = false;
    _current = null;
    _notify();
  }

  /// Pauses on the current sentence (play resumes it from its start).
  Future<void> pause() async {
    if (!_playing) return;
    _run++;
    _playing = false;
    _notify();
    await speaker.stop();
  }

  Future<void> toggle() => _playing ? pause() : play();

  /// Stops and forgets the position.
  Future<void> stop() async {
    final was = _playing || _current != null;
    _run++;
    _playing = false;
    _current = null;
    if (was) {
      _notify();
      await speaker.stop();
    }
  }

  /// Switches the slow rate; a sentence being read starts again at the new rate.
  Future<void> setSlow(bool slow) async {
    if (_slow == slow) return;
    _slow = slow;
    _notify();
    if (_playing) await play(_current);
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    if (_playing || _current != null) unawaited(speaker.stop());
    super.dispose();
  }
}

/// Play/pause and the slow rate, for an app bar (48 dp targets, icons with
/// tooltips; the state is in the icon shape, never in colour alone). Empty
/// without a voice for the course language.
class ReadAloudButtons extends ConsumerWidget {
  const ReadAloudButtons({super.key, required this.controller, this.keyPrefix = 'read-aloud'});
  final ReadAloudController controller;
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canPronounceProvider)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final playing = controller.playing;
        final slow = controller.slow;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('$keyPrefix-slow'),
              tooltip: slow ? 'Normal speed' : 'Slow speed',
              isSelected: slow,
              onPressed: () => unawaited(controller.setSlow(!slow)),
              icon: const Icon(Icons.slow_motion_video),
              selectedIcon: const Icon(Icons.speed),
            ),
            IconButton(
              key: ValueKey(keyPrefix),
              tooltip: playing ? 'Pause reading' : (controller.active ? 'Resume reading aloud' : 'Read aloud'),
              onPressed: () => unawaited(controller.toggle()),
              icon: Icon(playing ? Icons.pause_circle_outline : Icons.play_circle_outline),
            ),
          ],
        );
      },
    );
  }
}

/// The frame of the sentence being read: a box (2 px black in black & white,
/// the primary colour with a light tint in colour), so it never relies on
/// colour alone.
BoxDecoration speakingDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final mono = isMonochrome(scheme);
  return BoxDecoration(
    color: mono ? kBwWhite : scheme.primaryContainer.withValues(alpha: 0.35),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: mono ? kBwBlack : scheme.primary, width: 2),
  );
}
