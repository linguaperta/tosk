/// Hooks for optional features (handwriting, AI explanations). The core holds
/// the interfaces and the local/null implementations; AI explainers live in `lib/ai/`.
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

/// Everything an explainer needs about one checked answer, right or wrong.
///
/// [MistakeContext] is the wrong-answer case the engine stores for mistake
/// review; the lesson player builds a plain [ExplainContext] for right answers
/// ("Explain answer with AI" works on both).
@immutable
class ExplainContext {
  const ExplainContext({
    required this.courseId,
    required this.facetId,
    required this.exerciseType,
    required this.prompt,
    required this.expected,
    required this.given,
    required this.sourceLang,
    required this.targetLang,
    this.correct = false,
    this.skillId,
    this.note,
    this.sentenceId,
    this.at,
    this.options = const [],
    this.accepted = const [],
    this.instruction,
    this.explainLang,
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

  /// Whether the answer was accepted.
  final bool correct;

  /// Grammar note markdown for the skill (offline fallback for the explainer).
  final String? note;
  final String? sentenceId;
  final DateTime? at;

  /// The choices shown (options, endings, tiles), when the exercise had any.
  final List<String> options;

  /// Every accepted answer besides [expected] (alternative spellings, word orders).
  final List<String> accepted;

  /// The exercise's instruction line on its own, when known.
  final String? instruction;

  /// Language the explanation should be written in; null means [sourceLang].
  final String? explainLang;

  /// The language to explain in.
  String get replyLang => explainLang ?? sourceLang;

  /// Identifies the exercise independently of the session (no exercise id):
  /// the same item, type, prompt and expected answer give the same key. Mistake
  /// review can compute it from a stored [MistakeRecord].
  String get fingerprint => stableHash('$facetId|${exerciseType.id}|$prompt|$expected');

  /// Stable cache key "per item and error" for explanations.
  String get cacheKey => '$facetId|${exerciseType.id}|$expected|$given';

  ExplainContext copyWith({String? explainLang, String? note}) => ExplainContext(
    courseId: courseId,
    facetId: facetId,
    exerciseType: exerciseType,
    prompt: prompt,
    expected: expected,
    given: given,
    sourceLang: sourceLang,
    targetLang: targetLang,
    correct: correct,
    skillId: skillId,
    note: note ?? this.note,
    sentenceId: sentenceId,
    at: at,
    options: options,
    accepted: accepted,
    instruction: instruction,
    explainLang: explainLang ?? this.explainLang,
  );
}

/// Everything an explainer (or mistake review) needs about one wrong answer.
@immutable
class MistakeContext extends ExplainContext {
  const MistakeContext({
    required super.courseId,
    required super.facetId,
    required super.exerciseType,
    required super.prompt,
    required super.expected,
    required super.given,
    required super.sourceLang,
    required super.targetLang,
    super.skillId,
    super.note,
    super.sentenceId,
    super.at,
    super.options,
    super.accepted,
    super.instruction,
    super.explainLang,
  }) : super(correct: false);
}

/// A short, platform-independent hash of [text] (two 32-bit FNV-1a passes over
/// its UTF-16 code units, as 16 hex digits). Uses only 32-bit-safe arithmetic,
/// so the web build computes the same value as native.
String stableHash(String text) {
  int fnv(int seed) {
    var h = seed;
    for (final c in text.codeUnits) {
      h = (h ^ c) & 0xFFFFFFFF;
      // h * 16777619 mod 2^32, split so no intermediate exceeds 2^53.
      h = (((h << 24) & 0xFFFFFFFF) + h * 403) & 0xFFFFFFFF;
    }
    return h;
  }

  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return hex(fnv(0x811C9DC5)) + hex(fnv(0x050C5D1F));
}

/// Explains an answer ("Why?", "Explain answer with AI"). Streams the reply in
/// chunks. A [MistakeContext] is an [ExplainContext].
abstract interface class Explainer {
  bool get isAvailable;
  Stream<String> explain(ExplainContext ctx);
}

/// The default explainer: unavailable, explains nothing. The UI hides the
/// explain buttons. An AI explainer replaces it once a provider is configured.
class NullExplainer implements Explainer {
  const NullExplainer();
  @override
  bool get isAvailable => false;
  @override
  Stream<String> explain(ExplainContext ctx) => const Stream.empty();
}
