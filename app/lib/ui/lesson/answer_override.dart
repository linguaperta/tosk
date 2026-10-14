/// "I was right": after an auto-graded wrong verdict the learner can count
/// the answer as right. The engine writes an override event (see
/// `kOverrideType` in core: the answer is replayed as Good, its mistake is
/// resolved, no re-ask), and the exercise is flagged for review.
///
/// Flag storage: until the flags table exists (another v0.3 branch), an
/// override is kept as a small JSON record in the settings key
/// [kOverrideFlagsKey] (the newest [kMaxOverrideFlags]); a progress backup
/// carries it along.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../engine/debug/exercise_printer.dart' show exercisePrompt;

/// Settings key of the stored override flags (a JSON array, newest last).
const String kOverrideFlagsKey = 'feedback.overrides';
const int kMaxOverrideFlags = 200;

/// Stores one override flag: the exercise, both answers and the overridden
/// event ids, so the exercise can be checked later.
Future<void> saveOverrideFlag(
  ProgressStore store, {
  required String courseId,
  required Exercise exercise,
  required Result result,
  required List<ReviewEvent> overrides,
  required DateTime at,
  String? packVersion,
}) async {
  List<Object?> list;
  try {
    list = (jsonDecode(await store.getSetting(kOverrideFlagsKey) ?? '[]') as List).toList();
  } catch (_) {
    list = [];
  }
  list.add({
    'reason': 'answer_wrong',
    'comment': 'I was right (override)',
    'at': at.toUtc().toIso8601String(),
    'course_id': courseId,
    'skill_id': ?exercise.skillId,
    'facet_id': exercise.facetId,
    'exercise_type': exercise.type.id,
    'prompt': exercisePrompt(exercise),
    'given': result.given,
    'expected': result.expected,
    'overridden_events': [for (final o in overrides) o.overriddenId],
    'pack_version': ?packVersion,
  });
  if (list.length > kMaxOverrideFlags) list = list.sublist(list.length - kMaxOverrideFlags);
  await store.setSetting(kOverrideFlagsKey, jsonEncode(list));
}

/// The stored override flags, oldest first.
Future<List<Map<String, Object?>>> overrideFlags(ProgressStore store) async {
  try {
    return [
      for (final e in jsonDecode(await store.getSetting(kOverrideFlagsKey) ?? '[]') as List)
        (e as Map).cast<String, Object?>(),
    ];
  } catch (_) {
    return const [];
  }
}

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
