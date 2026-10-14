/// Drift-backed [ProgressStore]. Pure Dart (the [ProgressDb] executor is injected).
///
/// * `review_log` is append-only and the single source of truth.
/// * [record] appends and updates `facet_state` in one transaction. Events may
///   arrive out of order (sync merges, imports): an event older than the
///   facet's latest is inserted and that facet is replayed from its log, so
///   stored states always equal a full replay in `(at, id)` order.
/// * Recording the same event id twice is a no-op.
library;

import 'package:drift/drift.dart';

import '../../core/core.dart';
import '../fsrs/fsrs_scheduler.dart';
import '../sync/progress_backup.dart' show SettingsLister;
import 'event_importer.dart';
import 'progress_db.dart';
import 'replay.dart';

class ProgressRepo implements ProgressStore, EventImporter, SettingsLister {
  ProgressRepo(this.db, {Scheduler? scheduler}) : scheduler = scheduler ?? FsrsScheduler();

  final ProgressDb db;
  final Scheduler scheduler;

  /// SQLite has a bound-variable limit; `IN (...)` lists are chunked below it.
  static const int _chunk = 500;

  Future<void> close() => db.close();

  // ------------------------------------------------------------------ record

  @override
  Future<FacetState> record(ReviewEvent event) {
    final e = normalizeEvent(event);
    return db.transaction(() async {
      final log = db.reviewLogEntries;
      final dup = await (db.select(log)..where((t) => t.id.equals(e.id))).getSingleOrNull();
      if (dup != null) {
        return (await state(e.facetId)) ?? (await _replayFacet(e.facetId))!;
      }
      final latest = await (db.select(log)
            ..where((t) => t.facetId.equals(e.facetId))
            ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
      await db.into(log).insert(eventToRow(e));

      final previous = latest == null ? null : await state(e.facetId);
      final inOrder = latest == null ||
          compareEventKeys(e.at.millisecondsSinceEpoch, e.id, latest.at, latest.id) > 0;
      // An override rewrites an earlier event: always replay the facet.
      if (inOrder && !e.isOverride && (latest == null || previous != null)) {
        final next = scheduler.review(e.facetId, previous, e.rating, e.at);
        await db.into(db.facetStates).insertOnConflictUpdate(stateToRow(next));
        return next;
      }
      return (await _replayFacet(e.facetId))!;
    });
  }

  /// Merges [events] (sync pull, file import): inserts ids not yet present and
  /// replays only the facets that received new events. Returns the count added.
  @override
  Future<int> importEvents(Iterable<ReviewEvent> events) {
    final list = events.map(normalizeEvent).toList();
    if (list.isEmpty) return Future.value(0);
    return db.transaction(() async {
      final existing = <String>{};
      final ids = list.map((e) => e.id).toList();
      for (var i = 0; i < ids.length; i += _chunk) {
        final chunk = ids.sublist(i, i + _chunk > ids.length ? ids.length : i + _chunk);
        final q = db.selectOnly(db.reviewLogEntries)
          ..addColumns([db.reviewLogEntries.id])
          ..where(db.reviewLogEntries.id.isIn(chunk));
        existing.addAll(await q.map((r) => r.read(db.reviewLogEntries.id)!).get());
      }
      final fresh = <String, ReviewEvent>{
        for (final e in list)
          if (!existing.contains(e.id)) e.id: e,
      };
      if (fresh.isEmpty) return 0;
      await db.batch((b) => b.insertAll(db.reviewLogEntries, fresh.values.map(eventToRow)));
      for (final f in {for (final e in fresh.values) e.facetId}) {
        await _replayFacet(f);
      }
      return fresh.length;
    });
  }

  /// Recomputes one facet's state from its log and stores it. Call inside a transaction.
  Future<FacetState?> _replayFacet(String facetId) async {
    final rows = await (db.select(db.reviewLogEntries)
          ..where((t) => t.facetId.equals(facetId))
          ..orderBy([(t) => OrderingTerm.asc(t.at), (t) => OrderingTerm.asc(t.id)]))
        .get();
    final s = foldFacet(scheduler, facetId, rows.map(rowToEvent));
    if (s == null) {
      await (db.delete(db.facetStates)..where((t) => t.facetId.equals(facetId))).go();
    } else {
      await db.into(db.facetStates).insertOnConflictUpdate(stateToRow(s));
    }
    return s;
  }

  @override
  Future<void> rebuildStates() => db.transaction(() async {
        final rows = await (db.select(db.reviewLogEntries)
              ..orderBy([(t) => OrderingTerm.asc(t.at), (t) => OrderingTerm.asc(t.id)]))
            .get();
        final states = <String, FacetState>{};
        for (final e in applyOverrides(rows.map(rowToEvent).toList())) {
          states[e.facetId] = scheduler.review(e.facetId, states[e.facetId], e.rating, e.at);
        }
        await db.delete(db.facetStates).go();
        await db.batch((b) => b.insertAll(db.facetStates, states.values.map(stateToRow)));
      });

  // ------------------------------------------------------------------ states

  @override
  Future<FacetState?> state(String facetId) async {
    final row = await (db.select(db.facetStates)..where((t) => t.facetId.equals(facetId)))
        .getSingleOrNull();
    return row == null ? null : rowToState(row);
  }

  @override
  Future<Map<String, FacetState>> states(Iterable<String> facetIds) async {
    final ids = facetIds.toSet().toList();
    final out = <String, FacetState>{};
    for (var i = 0; i < ids.length; i += _chunk) {
      final chunk = ids.sublist(i, i + _chunk > ids.length ? ids.length : i + _chunk);
      final rows =
          await (db.select(db.facetStates)..where((t) => t.facetId.isIn(chunk))).get();
      for (final r in rows) {
        out[r.facetId] = rowToState(r);
      }
    }
    return out;
  }

  @override
  Future<List<FacetState>> allStates({String? courseId}) async {
    final q = db.select(db.facetStates)..orderBy([(t) => OrderingTerm.asc(t.facetId)]);
    if (courseId != null) {
      final (lo, hi) = courseIdRange(courseId);
      q.where((t) => t.facetId.isBiggerOrEqualValue(lo) & t.facetId.isSmallerThanValue(hi));
    }
    return (await q.get()).map(rowToState).toList();
  }

  /// Facets due at [now] (most overdue first), optionally per course.
  Future<List<FacetState>> dueStates({required DateTime now, String? courseId, int? limit}) async {
    final q = db.select(db.facetStates)
      ..where((t) => t.due.isSmallerOrEqualValue(now.millisecondsSinceEpoch))
      ..orderBy([(t) => OrderingTerm.asc(t.due), (t) => OrderingTerm.asc(t.facetId)]);
    if (courseId != null) {
      final (lo, hi) = courseIdRange(courseId);
      q.where((t) => t.facetId.isBiggerOrEqualValue(lo) & t.facetId.isSmallerThanValue(hi));
    }
    if (limit != null) q.limit(limit);
    return (await q.get()).map(rowToState).toList();
  }

  // ------------------------------------------------------------------ log

  @override
  Future<List<ReviewEvent>> log({DateTime? since, String? courseId, String? facetId}) async {
    final q = db.select(db.reviewLogEntries)
      ..orderBy([(t) => OrderingTerm.asc(t.at), (t) => OrderingTerm.asc(t.id)]);
    if (since != null) q.where((t) => t.at.isBiggerOrEqualValue(since.millisecondsSinceEpoch));
    if (facetId != null) q.where((t) => t.facetId.equals(facetId));
    if (courseId != null) {
      final (lo, hi) = courseIdRange(courseId);
      q.where((t) => t.facetId.isBiggerOrEqualValue(lo) & t.facetId.isSmallerThanValue(hi));
    }
    return (await q.get()).map(rowToEvent).toList();
  }

  /// Number of events in the log.
  Future<int> logCount() async {
    final c = db.reviewLogEntries.id.count();
    final q = db.selectOnly(db.reviewLogEntries)..addColumns([c]);
    return (await q.map((r) => r.read(c)).getSingle()) ?? 0;
  }

  // ------------------------------------------------------------------ mistakes

  @override
  Future<List<MistakeRecord>> mistakes({String? courseId, int limit = 100}) async {
    final q = db.select(db.mistakes)
      ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    if (courseId != null) {
      final (lo, hi) = courseIdRange(courseId);
      q.where((t) => t.facetId.isBiggerOrEqualValue(lo) & t.facetId.isSmallerThanValue(hi));
    }
    return (await q.get())
        .map((r) => MistakeRecord(
              id: r.id,
              facetId: r.facetId,
              at: DateTime.fromMillisecondsSinceEpoch(r.at, isUtc: true),
              exerciseType: r.exerciseType,
              prompt: r.prompt,
              expected: r.expected,
              given: r.given,
              skillId: r.skillId,
              note: r.note,
              explanation: r.explanation,
            ))
        .toList();
  }

  @override
  Future<void> saveMistake(MistakeRecord m) => db.into(db.mistakes).insertOnConflictUpdate(
        MistakesCompanion.insert(
          id: m.id,
          facetId: m.facetId,
          at: m.at.millisecondsSinceEpoch,
          exerciseType: m.exerciseType,
          prompt: m.prompt,
          expected: m.expected,
          given: m.given,
          skillId: Value(m.skillId),
          note: Value(m.note),
          explanation: Value(m.explanation),
        ),
      );

  // ------------------------------------------------------------------ settings

  @override
  Future<String?> getSetting(String key) async {
    final row =
        await (db.select(db.settings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<Map<String, String>> allSettings() async => {
        for (final r in await db.select(db.settings).get()) r.key: r.value,
      };

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.settings)..where((t) => t.key.equals(key))).go();
    } else {
      await db.into(db.settings).insertOnConflictUpdate(SettingRow(key: key, value: value));
    }
  }
}

// -------------------------------------------------------------------- mapping

ReviewLogEntriesCompanion eventToRow(ReviewEvent e) => ReviewLogEntriesCompanion.insert(
      id: e.id,
      facetId: e.facetId,
      at: e.at.millisecondsSinceEpoch,
      rating: e.rating.value,
      exerciseType: e.exerciseType,
      inputMode: e.inputMode.name,
      responseMs: e.responseMs,
      correct: e.correct,
      answer: Value(e.answer),
      sessionId: Value(e.sessionId),
      mode: Value(e.mode),
    );

ReviewEvent rowToEvent(ReviewLogRow r) => ReviewEvent(
      id: r.id,
      facetId: r.facetId,
      at: DateTime.fromMillisecondsSinceEpoch(r.at, isUtc: true),
      rating: Rating.fromValue(r.rating),
      exerciseType: r.exerciseType,
      inputMode: InputMode.values.asNameMap()[r.inputMode] ?? InputMode.tap,
      responseMs: r.responseMs,
      correct: r.correct,
      answer: r.answer,
      sessionId: r.sessionId,
      mode: r.mode,
    );

/// A companion (not a data class): data classes drop null fields on upsert
/// (`nullToAbsent`), which would leave a stale `step` behind.
FacetStatesCompanion stateToRow(FacetState s) => FacetStatesCompanion.insert(
      facetId: s.facetId,
      stability: s.stability,
      difficulty: s.difficulty,
      due: s.due.millisecondsSinceEpoch,
      lastReview: s.lastReview.millisecondsSinceEpoch,
      reps: s.reps,
      lapses: s.lapses,
      phase: s.phase.name,
      step: Value(s.step),
    );

FacetState rowToState(FacetStateRow r) => FacetState(
      facetId: r.facetId,
      stability: r.stability,
      difficulty: r.difficulty,
      due: DateTime.fromMillisecondsSinceEpoch(r.due, isUtc: true),
      lastReview: DateTime.fromMillisecondsSinceEpoch(r.lastReview, isUtc: true),
      reps: r.reps,
      lapses: r.lapses,
      phase: CardPhase.values.byName(r.phase),
      step: r.step,
    );
