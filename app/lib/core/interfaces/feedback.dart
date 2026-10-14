/// Storage contracts for AI explanations and exercise flags. Implemented by
/// the data layer (`data/progress/feedback_store.dart`, drift tables in the
/// progress database) and by an in-memory store for tests and the defaults.
library;

import 'package:meta/meta.dart';

/// A cached AI explanation, keyed by (exercise fingerprint, given answer,
/// reply language). See [ExplainContext.fingerprint].
@immutable
class CachedExplanation {
  const CachedExplanation({
    required this.fingerprint,
    required this.given,
    required this.lang,
    required this.text,
    required this.createdAt,
    this.facetId,
    this.provider,
    this.model,
  });

  final String fingerprint;
  final String given;
  final String lang;
  final String text;
  final DateTime createdAt;
  final String? facetId;
  final String? provider;
  final String? model;
}

/// Explanations survive restarts, so they work offline and in mistake review.
abstract interface class ExplanationCache {
  Future<CachedExplanation?> explanation(String fingerprint, String given, String lang);

  /// Inserts or replaces.
  Future<void> saveExplanation(CachedExplanation explanation);
}

/// Why a learner flagged an exercise.
enum FlagReason {
  answerWrong('answer_wrong', 'The answer is wrong'),
  multipleAnswers('multiple_answers', 'Multiple answers are possible'),
  unclear('unclear', 'Unclear / confusing'),
  translationWrong('translation_wrong', 'Translation is wrong'),
  other('other', 'Other');

  const FlagReason(this.id, this.label);

  /// Stored and exported id.
  final String id;

  /// English label for the chip.
  final String label;

  static FlagReason? byId(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// The AI's judgement of a flag ("Confer with AI").
enum FlagVerdict {
  exerciseWrong('exercise_wrong', 'The exercise is wrong'),
  ambiguous('ambiguous', 'The exercise is ambiguous'),
  exerciseCorrect('exercise_correct', 'The exercise is correct');

  const FlagVerdict(this.id, this.label);
  final String id;
  final String label;

  static FlagVerdict? byId(String? id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// One flagged exercise, with everything needed to reproduce it.
@immutable
class FlagRecord {
  const FlagRecord({
    required this.id,
    required this.createdAt,
    required this.courseId,
    required this.facetId,
    required this.exerciseType,
    required this.exercise,
    required this.given,
    required this.expected,
    required this.correct,
    required this.reasons,
    this.skillId,
    this.comment = '',
    this.aiVerdict,
    this.aiReasoning,
    this.appVersion,
    this.packVersion,
    this.sourceLang,
  });

  final String id; // UUID v4
  final DateTime createdAt;
  final String courseId;
  final String? skillId;
  final String facetId;
  final String exerciseType;

  /// Full snapshot of the exercise (`feedback/exercise_snapshot.dart`).
  final Map<String, Object?> exercise;

  /// The learner's answer as text, the canonical expected answer, and whether
  /// the answer was accepted.
  final String given;
  final String expected;
  final bool correct;

  /// One or more reasons (at least one when submitted from the sheet).
  final List<FlagReason> reasons;
  final String comment;
  final FlagVerdict? aiVerdict;
  final String? aiReasoning;
  final String? appVersion;
  final String? packVersion;
  final String? sourceLang;
}

/// Flags stay on the device until exported.
abstract interface class FlagStore {
  Future<void> saveFlag(FlagRecord flag);

  /// Most recent first.
  Future<List<FlagRecord>> flags({String? courseId});
  Future<void> deleteFlag(String id);
}
