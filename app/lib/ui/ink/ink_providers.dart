/// Riverpod wiring of handwriting input (v0.5): the recognizer, whether ink
/// mode is on, and the active course's recognition model (status, download).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/test_env.dart';
import '../../ink/ink_recognizer.dart';
import '../../ink/mlkit_ink_recognizer.dart';
import '../../providers.dart' show courseDataProvider;
import '../settings/learner_settings.dart';

/// The handwriting recognizer: ML Kit on Android and iOS; none on the web,
/// desktop and under `flutter test` (tests override it with a fake).
final inkRecognizerProvider = Provider<InkRecognizer>((ref) {
  if (runningInFlutterTest || !mlKitInkPlatform) return const UnavailableInkRecognizer();
  return MlKitInkRecognizer();
});

/// Whether handwriting can be offered at all (Settings shows "Handwrite").
final inkSupportedProvider = Provider<bool>((ref) => ref.watch(inkRecognizerProvider).platformSupported);

/// Handwriting is on: chosen in Settings and supported here. (A setting
/// restored from a backup on a desktop falls back to tap.)
final inkModeProvider = Provider<bool>(
  (ref) => ref.watch(handwritingPrefProvider) && ref.watch(inkSupportedProvider),
);

@immutable
class InkModelState {
  const InkModelState({required this.status, this.tag, this.target, this.message});

  static const checking = InkModelState(status: InkModelStatus.checking);

  final InkModelStatus status;

  /// The recognition model (BCP-47 tag), e.g. `it`, `nl` for Sarnami.
  final String? tag;

  /// The course's target language.
  final String? target;
  final String? message;

  bool get ready => status == InkModelStatus.ready;

  InkModelState copyWith({InkModelStatus? status, String? message}) =>
      InkModelState(status: status ?? this.status, tag: tag, target: target, message: message);
}

/// The active course's handwriting model: which one, and whether it is on
/// the device. `download()` fetches it (ML Kit keeps it for offline use).
final inkModelProvider = NotifierProvider<InkModelController, InkModelState>(InkModelController.new);

class InkModelController extends Notifier<InkModelState> {
  @override
  InkModelState build() {
    final recognizer = ref.watch(inkRecognizerProvider);
    final target = ref.watch(courseDataProvider.select((c) => c.value?.meta.target));
    if (!recognizer.platformSupported) return const InkModelState(status: InkModelStatus.unsupported);
    if (target == null) return InkModelState.checking;
    unawaited(_check(recognizer, target));
    return InkModelState(status: InkModelStatus.checking, target: target);
  }

  Future<void> _check(InkRecognizer r, String target) async {
    InkModelState result = InkModelState(status: InkModelStatus.unsupported, target: target);
    for (final tag in inkLanguageTags(target)) {
      try {
        final s = await r.modelStatus(tag);
        if (s == InkModelStatus.unsupported) continue;
        result = InkModelState(status: s, tag: tag, target: target);
        break;
      } catch (e) {
        result = InkModelState(status: InkModelStatus.error, tag: tag, target: target, message: '$e');
        break;
      }
    }
    if (state.target == target && state.status == InkModelStatus.checking) state = result;
  }

  /// Checks again (after an error).
  Future<void> refresh() async {
    final target = state.target;
    if (target == null) return;
    state = InkModelState(status: InkModelStatus.checking, target: target);
    await _check(ref.read(inkRecognizerProvider), target);
  }

  /// Downloads the model (about 20 MB).
  Future<void> download() async {
    final tag = state.tag;
    if (tag == null || state.status == InkModelStatus.downloading || state.ready) return;
    state = state.copyWith(status: InkModelStatus.downloading);
    try {
      await ref.read(inkRecognizerProvider).downloadModel(tag);
      if (state.tag == tag) state = state.copyWith(status: InkModelStatus.ready);
    } catch (e) {
      if (state.tag == tag) state = state.copyWith(status: InkModelStatus.error, message: '$e');
    }
  }

  /// Deletes the model (Settings).
  Future<void> delete() async {
    final tag = state.tag;
    if (tag == null) return;
    try {
      await ref.read(inkRecognizerProvider).deleteModel(tag);
    } catch (_) {}
    if (state.tag == tag) state = state.copyWith(status: InkModelStatus.missing);
  }
}

/// Display name of a recognition model tag.
String inkModelName(String tag) => switch (tag.split('-').first) {
      'it' => 'Italian',
      'nl' => 'Dutch',
      'es' => 'Spanish',
      'pt' => 'Portuguese',
      'fr' => 'French',
      'eo' => 'Esperanto',
      'sv' => 'Swedish',
      'nb' || 'no' => 'Norwegian',
      'da' => 'Danish',
      'de' => 'German',
      'en' => 'English',
      _ => tag,
    };
