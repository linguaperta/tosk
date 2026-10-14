/// "I was right": after an auto-graded wrong verdict the learner can count
/// the answer as right. The engine writes an override event (see
/// `kOverrideType` in core: the answer is replayed as Good, its mistake is
/// resolved, no re-ask), and the exercise is flagged for review.
///
/// The flag goes to the progress DB's `flags` table ([FlagRecord], see
/// docs/feedback.md) with reason "answer_wrong" and [kOverrideComment].
library;

import 'package:flutter/material.dart';

import '../../app_version.dart';
import '../../core/core.dart';
import '../../feedback/exercise_snapshot.dart';

/// The flag stored with an override: reason "The answer is wrong", the
/// comment [kOverrideComment] and the full exercise snapshot, so the
/// exercise can be checked like any other flag (Settings, Feedback & flags).
FlagRecord overrideFlag({
  required String id,
  required DateTime at,
  required String courseId,
  required Exercise exercise,
  required Result result,
  required List<ReviewEvent> overrides,
  String? packVersion,
  String? sourceLang,
}) => FlagRecord(
  id: id,
  createdAt: at.toUtc(),
  courseId: courseId,
  skillId: exercise.skillId,
  facetId: exercise.facetId,
  exerciseType: exercise.type.id,
  exercise: exerciseToJson(exercise),
  given: result.given,
  expected: result.expected,
  correct: false,
  reasons: const [FlagReason.answerWrong],
  comment: overrides.isEmpty
      ? kOverrideComment
      : '$kOverrideComment (overridden events: ${overrides.map((o) => o.overriddenId).join(', ')})',
  appVersion: kAppVersion,
  packVersion: packVersion,
  sourceLang: sourceLang,
);

/// Comment of an automatic "I was right" flag.
const String kOverrideComment = 'I was right: the learner counted this answer as correct';

/// The verdict shown after an override: right, with the same answers.
Result overriddenResult(Result r) => Result(
  correct: true,
  expected: r.expected,
  given: r.given,
  outcomes: [
    for (final o in r.outcomes)
      FacetOutcome(facetId: o.facetId, correct: true, rating: o.correct ? o.rating : Rating.good),
  ],
  cellCorrect: r.cellCorrect,
);

/// Asks "Count my answer as correct?"; true when confirmed.
Future<bool> confirmOverride(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('override-dialog'),
        title: const Text('Count my answer as correct?'),
        content: const Text(
          'It counts as right for your progress, leaves your mistakes list, and the exercise '
          'is flagged so it can be checked.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('override-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('override-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Count as correct'),
          ),
        ],
      ),
    ) ??
    false;
