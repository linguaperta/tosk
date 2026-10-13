/// Hooks for features that ship later (handwriting, AI explanations).
/// Only the local/null implementations exist in v1.
library;

import 'package:meta/meta.dart';

import '../models/exercise.dart';
import '../models/progress.dart';

/// A way of entering a free-text answer: keyboard now, handwriting (ink) later.
///
/// The UI owns the widget; this interface is what the engine sees. A
/// recognizer (ink) produces several candidates, best first; the engine
/// accepts the answer if the expected text is among the top [topK].
abstract interface class AnswerInput {
  InputMode get mode;

  /// Whether this input works on the current device (e.g. an ink model is downloaded).
  bool get isAvailable;

  /// How many recognizer candidates count (1 for a keyboard).
  int get topK;

  /// Wraps raw input into an answer for `PracticeSession.submit`.
  /// [candidates] are best-first; for a keyboard it is just the typed text.
  TextAnswer toAnswer(List<String> candidates);
}

/// Keyboard input: one candidate, the typed text.
class KeyboardAnswerInput implements AnswerInput {
  const KeyboardAnswerInput();
  @override
  InputMode get mode => InputMode.keyboard;
  @override
  bool get isAvailable => true;
  @override
  int get topK => 1;
  @override
  TextAnswer toAnswer(List<String> candidates) =>
      TextAnswer(candidates.isEmpty ? '' : candidates.first, inputMode: InputMode.keyboard);
}

/// Base for recognizers (ink): keeps the top [topK] candidates.
abstract class RecognizerAnswerInput implements AnswerInput {
  const RecognizerAnswerInput({this.topK = 3});
  @override
  final int topK;
  @override
  InputMode get mode => InputMode.ink;
  @override
  TextAnswer toAnswer(List<String> candidates) {
    final top = candidates.take(topK).toList();
    return TextAnswer(
      top.isEmpty ? '' : top.first,
      inputMode: InputMode.ink,
      candidates: top.length > 1 ? top.sublist(1) : const [],
    );
  }
}

/// Everything an explainer (or mistake review) needs about one wrong answer.
@immutable
class MistakeContext {
  const MistakeContext({
    required this.courseId,
    required this.facetId,
    required this.exerciseType,
    required this.prompt,
    required this.expected,
    required this.given,
    required this.sourceLang,
    required this.targetLang,
    this.skillId,
    this.note,
    this.sentenceId,
    this.at,
  });

  final String courseId;
  final String facetId;
  final ExerciseType exerciseType;

  /// Human-readable exercise (instruction + prompt), in the source language.
  final String prompt;
  final String expected;
  final String given;
  final String sourceLang; // 'en' | 'nl'
  final String targetLang; // course target language
  final String? skillId;

  /// Grammar note markdown for the skill (offline fallback for the explainer).
  final String? note;
  final String? sentenceId;
  final DateTime? at;

  /// Stable cache key "per item and error" for explanations.
  String get cacheKey => '$facetId|${exerciseType.id}|$expected|$given';
}

/// Explains a mistake ("Why?"). Streams the reply in chunks.
abstract interface class Explainer {
  bool get isAvailable;
  Stream<String> explain(MistakeContext ctx);
}

/// The only explainer in v1: unavailable, explains nothing. The UI hides "Why?".
class NullExplainer implements Explainer {
  const NullExplainer();
  @override
  bool get isAvailable => false;
  @override
  Stream<String> explain(MistakeContext ctx) => const Stream.empty();
}
