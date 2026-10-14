/// AI explanation cache and exercise flags in the progress database
/// (`ai_explanations`, `flags`; schema v2). Pure Dart.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/core.dart';
import 'progress_db.dart';

/// Both feedback stores in one object (they share the progress database).
abstract interface class FeedbackStore implements ExplanationCache, FlagStore {}

class DriftFeedbackStore implements FeedbackStore {
  DriftFeedbackStore(this.db);
  final ProgressDb db;

  @override
  Future<CachedExplanation?> explanation(String fingerprint, String given, String lang) async {
    final t = db.aiExplanations;
    final row = await (db.select(t)
          ..where((r) => r.fingerprint.equals(fingerprint) & r.given.equals(given) & r.lang.equals(lang)))
        .getSingleOrNull();
    if (row == null) return null;
    return CachedExplanation(
      fingerprint: row.fingerprint,
      given: row.given,
      lang: row.lang,
      text: row.body,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
      facetId: row.facetId,
      provider: row.provider,
      model: row.model,
    );
  }

  @override
  Future<void> saveExplanation(CachedExplanation e) => db
      .into(db.aiExplanations)
      .insertOnConflictUpdate(
        AiExplanationsCompanion.insert(
          fingerprint: e.fingerprint,
          given: e.given,
          lang: e.lang,
          body: e.text,
          facetId: Value(e.facetId),
          provider: Value(e.provider),
          model: Value(e.model),
          createdAt: e.createdAt.toUtc().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> saveFlag(FlagRecord f) => db
      .into(db.flags)
      .insertOnConflictUpdate(
        FlagsCompanion.insert(
          id: f.id,
          createdAt: f.createdAt.toUtc().millisecondsSinceEpoch,
          courseId: f.courseId,
          skillId: Value(f.skillId),
          facetId: f.facetId,
          exerciseType: f.exerciseType,
          exerciseJson: jsonEncode(f.exercise),
          given: f.given,
          expected: f.expected,
          correct: f.correct,
          reason: f.reasons.map((r) => r.id).join(','),
          comment: Value(f.comment),
          aiVerdict: Value(f.aiVerdict?.id),
          aiReasoning: Value(f.aiReasoning),
          appVersion: Value(f.appVersion),
          packVersion: Value(f.packVersion),
          sourceLang: Value(f.sourceLang),
        ),
      );

  @override
  Future<List<FlagRecord>> flags({String? courseId}) async {
    final q = db.select(db.flags)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)]);
    if (courseId != null) q.where((t) => t.courseId.equals(courseId));
    return [for (final r in await q.get()) _flag(r)];
  }

  @override
  Future<void> deleteFlag(String id) => (db.delete(db.flags)..where((t) => t.id.equals(id))).go();

  static FlagRecord _flag(FlagRow r) {
    Map<String, Object?> exercise;
    try {
      exercise = (jsonDecode(r.exerciseJson) as Map).cast<String, Object?>();
    } catch (_) {
      exercise = {'unreadable': r.exerciseJson};
    }
    return FlagRecord(
      id: r.id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
      courseId: r.courseId,
      skillId: r.skillId,
      facetId: r.facetId,
      exerciseType: r.exerciseType,
      exercise: exercise,
      given: r.given,
      expected: r.expected,
      correct: r.correct,
      reasons: [for (final id in r.reason.split(',')) ?FlagReason.byId(id)],
      comment: r.comment,
      aiVerdict: FlagVerdict.byId(r.aiVerdict),
      aiReasoning: r.aiReasoning,
      appVersion: r.appVersion,
      packVersion: r.packVersion,
      sourceLang: r.sourceLang,
    );
  }
}

/// Same semantics in memory (tests, and the defaults without a data layer).
class InMemoryFeedbackStore implements FeedbackStore {
  final Map<String, CachedExplanation> _explanations = {};
  final Map<String, FlagRecord> _flags = {};

  static String _key(String f, String g, String l) => '$f\u0000$g\u0000$l';

  @override
  Future<CachedExplanation?> explanation(String fingerprint, String given, String lang) async =>
      _explanations[_key(fingerprint, given, lang)];

  @override
  Future<void> saveExplanation(CachedExplanation e) async => _explanations[_key(e.fingerprint, e.given, e.lang)] = e;

  @override
  Future<void> saveFlag(FlagRecord flag) async => _flags[flag.id] = flag;

  @override
  Future<List<FlagRecord>> flags({String? courseId}) async {
    final list = [
      for (final f in _flags.values)
        if (courseId == null || f.courseId == courseId) f,
    ];
    list.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return list;
  }

  @override
  Future<void> deleteFlag(String id) async => _flags.remove(id);
}
