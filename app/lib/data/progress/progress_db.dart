/// The progress database (drift). Separate from course packs, so replacing a
/// pack never touches progress. Pure Dart: the executor is passed in
/// (`progress_connection.dart` opens the real file; tests use an in-memory one).
///
/// Times are stored as INTEGER UTC epoch milliseconds (not drift's DateTime
/// columns, which default to whole seconds), so stored states round-trip exactly.
///
/// Schema changes: bump [ProgressDb.currentSchemaVersion], add a step to
/// [ProgressDb.migration]'s `onUpgrade`, run build_runner, and dump the new
/// schema (see docs/data-layer.md).
library;

import 'package:drift/drift.dart';

part 'progress_db.g.dart';

/// Append-only log of graded answers: the single source of truth for progress.
@DataClassName('ReviewLogRow')
@TableIndex(name: 'review_log_facet_at', columns: {#facetId, #at})
@TableIndex(name: 'review_log_at', columns: {#at})
class ReviewLogEntries extends Table {
  @override
  String get tableName => 'review_log';

  TextColumn get id => text()(); // UUID v4
  TextColumn get facetId => text()();
  IntColumn get at => integer()(); // UTC epoch ms
  IntColumn get rating => integer()(); // 1..4
  TextColumn get exerciseType => text()();
  TextColumn get inputMode => text()();
  IntColumn get responseMs => integer()();
  BoolColumn get correct => boolean()();
  TextColumn get answer => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get mode => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Scheduler state per facet, derived from [ReviewLogEntries] (rebuildable).
@DataClassName('FacetStateRow')
@TableIndex(name: 'facet_state_due', columns: {#due})
class FacetStates extends Table {
  @override
  String get tableName => 'facet_state';

  TextColumn get facetId => text()();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get due => integer()(); // UTC epoch ms
  IntColumn get lastReview => integer()(); // UTC epoch ms
  IntColumn get reps => integer()();
  IntColumn get lapses => integer()();
  TextColumn get phase => text()(); // CardPhase.name
  IntColumn get step => integer().nullable()();

  @override
  Set<Column> get primaryKey => {facetId};
}

/// Wrong answers kept for mistake review (and cached explanations later).
@DataClassName('MistakeRow')
@TableIndex(name: 'mistakes_at', columns: {#at})
@TableIndex(name: 'mistakes_facet', columns: {#facetId})
class Mistakes extends Table {
  @override
  String get tableName => 'mistakes';

  TextColumn get id => text()(); // same as the review event id
  TextColumn get facetId => text()();
  IntColumn get at => integer()(); // UTC epoch ms
  TextColumn get exerciseType => text()();
  TextColumn get prompt => text()();
  TextColumn get expected => text()();
  TextColumn get given => text()();
  TextColumn get skillId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get explanation => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key/value settings.
@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Cached AI explanations (schema v2), one per (exercise fingerprint, given
/// answer, reply language). Available offline and in mistake review.
@DataClassName('AiExplanationRow')
class AiExplanations extends Table {
  @override
  String get tableName => 'ai_explanations';

  TextColumn get fingerprint => text()(); // ExplainContext.fingerprint
  TextColumn get given => text()();
  TextColumn get lang => text()();
  TextColumn get body => text()();
  TextColumn get facetId => text().nullable()();
  TextColumn get provider => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC epoch ms

  @override
  Set<Column> get primaryKey => {fingerprint, given, lang};
}

/// Exercises the learner flagged (schema v2), exported as JSON lines
/// (docs/feedback.md).
@DataClassName('FlagRow')
@TableIndex(name: 'flags_created', columns: {#createdAt})
class Flags extends Table {
  @override
  String get tableName => 'flags';

  TextColumn get id => text()(); // UUID v4
  IntColumn get createdAt => integer()(); // UTC epoch ms
  TextColumn get courseId => text()();
  TextColumn get skillId => text().nullable()();
  TextColumn get facetId => text()();
  TextColumn get exerciseType => text()();
  TextColumn get exerciseJson => text()(); // full exercise snapshot
  TextColumn get given => text()();
  TextColumn get expected => text()();
  BoolColumn get correct => boolean()(); // the result: was the answer accepted
  TextColumn get reason => text()(); // comma-separated FlagReason ids
  TextColumn get comment => text().withDefault(const Constant(''))();
  TextColumn get aiVerdict => text().nullable()();
  TextColumn get aiReasoning => text().nullable()();
  TextColumn get appVersion => text().nullable()();
  TextColumn get packVersion => text().nullable()();
  TextColumn get sourceLang => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ReviewLogEntries, FacetStates, Mistakes, Settings, AiExplanations, Flags])
class ProgressDb extends _$ProgressDb {
  ProgressDb(super.executor);

  /// Bump on every schema change and add a migration step below.
  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from > to) {
            // drift also calls onUpgrade for downgrades; refuse instead of
            // silently stamping an older version on a newer schema.
            throw StateError(
              'Progress database is version $from, newer than this app ($to). Update the app.',
            );
          }
          // Run steps in order, one `if (from < N)` per version.
          if (from < 2) {
            // v2: AI explanation cache and exercise flags.
            await m.createTable(aiExplanations);
            await m.createTable(flags);
            await m.createIndex(flagsCreated);
          }
          // facet_state is derived data: a step may also drop and recreate it
          // and the repo's rebuildStates() refills it from review_log.
          // review_log must never lose rows.
        },
      );
}
