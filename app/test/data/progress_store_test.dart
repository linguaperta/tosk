import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/progress/replay.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sample_log.dart';

typedef StoreFactory = Future<(ProgressStore, Future<void> Function())> Function();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final factories = <String, StoreFactory>{
    'ProgressRepo (drift)': () async {
      final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
      return (repo as ProgressStore, repo.close);
    },
    'InMemoryProgressStore': () async => (InMemoryProgressStore() as ProgressStore, () async {}),
  };

  for (final MapEntry(key: name, value: make) in factories.entries) {
    group(name, () {
      late ProgressStore store;
      late Future<void> Function() close;
      setUp(() async => (store, close) = await make());
      tearDown(() => close());

      test('record appends and updates state; idempotent per event id', () async {
        final e = sampleLog(count: 1).single;
        final s1 = await store.record(e);
        expect(s1.reps, 1);
        expect(await store.state(e.facetId), s1);
        final again = await store.record(e);
        expect(again, s1);
        expect((await store.log()).length, 1);
      });

      test('rebuildStates reproduces stored states exactly (out-of-order insertion)', () async {
        final log = sampleLog();
        final shuffled = List.of(log)..shuffle(Random(7));
        for (final e in shuffled) {
          await store.record(e);
        }
        final before = await store.allStates();
        expect(before.length, greaterThan(20));
        await store.rebuildStates();
        final after = await store.allStates();
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          expect(after[i], before[i], reason: before[i].facetId);
        }
        // And they equal an independent replay in (at, id) order.
        final expected = replayLog(FsrsScheduler(), log);
        expect({for (final s in after) s.facetId: s}, expected);
        // The log comes back in (at, id) order.
        final stored = await store.log();
        expect(stored.length, log.length);
        for (var i = 1; i < stored.length; i++) {
          expect(compareEvents(stored[i - 1], stored[i]), lessThan(0));
        }
      });

      test('in-order recording returns the same states as replay', () async {
        final log = sampleLog(seed: 3, count: 300)..sort(compareEvents);
        final returned = <String, FacetState>{};
        for (final e in log) {
          returned[e.facetId] = await store.record(e);
        }
        expect(returned, replayLog(FsrsScheduler(), log));
      });

      test('states(), allStates(courseId), log filters', () async {
        for (final e in sampleLog(count: 200)) {
          await store.record(e);
        }
        final it = await store.allStates(courseId: 'it');
        final nl = await store.allStates(courseId: 'nl');
        final all = await store.allStates();
        expect(it.every((s) => s.facetId.startsWith('it:')), isTrue);
        expect(nl.map((s) => s.facetId), ['nl:huis#rec']);
        expect(it.length + nl.length, all.length);
        final picked = await store.states(['it:w0#rec', 'it:w1#prod', 'it:nope#rec']);
        expect(picked.keys.toSet(), {'it:w0#rec', 'it:w1#prod'});
        final since = DateTime.utc(2026, 8, 1);
        final recent = await store.log(since: since, courseId: 'it');
        expect(recent.every((e) => !e.at.isBefore(since) && e.facetId.startsWith('it:')), isTrue);
        final one = await store.log(facetId: 'it:w0#rec');
        expect(one.every((e) => e.facetId == 'it:w0#rec'), isTrue);
        expect(one, isNotEmpty);
      });

      test('event times are normalized to UTC milliseconds', () async {
        final e = ReviewEvent(
          id: 'e1',
          facetId: 'it:x#rec',
          at: DateTime.utc(2026, 1, 1, 12, 0, 0, 5, 999), // with microseconds
          rating: Rating.good,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 1000,
          correct: true,
        );
        final s = await store.record(e);
        expect(s.lastReview, DateTime.utc(2026, 1, 1, 12, 0, 0, 5));
        expect((await store.log()).single.at, DateTime.utc(2026, 1, 1, 12, 0, 0, 5));
        await store.rebuildStates();
        expect(await store.state('it:x#rec'), s);
      });

      test('mistakes and settings', () async {
        final t = DateTime.utc(2026, 2, 1);
        for (var i = 0; i < 5; i++) {
          await store.saveMistake(MistakeRecord(
            id: 'm$i',
            facetId: i.isEven ? 'it:a#prod' : 'nl:b#prod',
            at: t.add(Duration(minutes: i)),
            exerciseType: 'cloze',
            prompt: 'p$i',
            expected: 'x',
            given: 'y',
            skillId: i == 0 ? 'food' : null,
          ));
        }
        final it = await store.mistakes(courseId: 'it');
        expect(it.map((m) => m.id), ['m4', 'm2', 'm0']);
        expect(it.last.skillId, 'food');
        expect((await store.mistakes(limit: 2)).map((m) => m.id), ['m4', 'm3']);

        expect(await store.getSetting('sourceLang'), isNull);
        await store.setSetting('sourceLang', 'nl');
        expect(await store.getSetting('sourceLang'), 'nl');
        await store.setSetting('sourceLang', 'en');
        expect(await store.getSetting('sourceLang'), 'en');
        await store.setSetting('sourceLang', null);
        expect(await store.getSetting('sourceLang'), isNull);
      });
    });
  }

  test('importEvents merges by id and replays touched facets (both stores)', () async {
    final log = sampleLog(seed: 11, count: 400);
    final half1 = log.sublist(0, 250);
    final half2 = log.sublist(150); // overlaps 150..250
    final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
    addTearDown(repo.close);
    final mem = InMemoryProgressStore();
    for (final e in half1) {
      await repo.record(e);
      await mem.record(e);
    }
    expect(await repo.importEvents(half2), 150);
    expect(await mem.importEvents(half2), 150);
    expect(await repo.importEvents(half2), 0);
    expect(await repo.logCount(), 400);
    final expected = replayLog(FsrsScheduler(), log);
    expect({for (final s in await repo.allStates()) s.facetId: s}, expected);
    expect({for (final s in await mem.allStates()) s.facetId: s}, expected);
  });

  group('schema', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('tosk_progress_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('file database persists across reopen at the current version', () async {
      final file = File('${tmp.path}/progress.sqlite');
      final e = sampleLog(count: 1).single;
      var repo = ProgressRepo(ProgressDb(NativeDatabase(file)));
      final s = await repo.record(e);
      await repo.close();
      repo = ProgressRepo(ProgressDb(NativeDatabase(file)));
      expect(await repo.state(e.facetId), s);
      final v = await repo.db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.single, ProgressDb.currentSchemaVersion);
      // The expected tables and indexes exist.
      final names = (await repo.db
              .customSelect("SELECT name FROM sqlite_master WHERE type IN ('table','index')")
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(names, containsAll(['review_log', 'facet_state', 'mistakes', 'settings',
          'review_log_facet_at', 'review_log_at', 'facet_state_due']));
      await repo.close();
    });

    test('refuses a database from a newer app version', () async {
      final file = File('${tmp.path}/progress.sqlite');
      final repo = ProgressRepo(ProgressDb(NativeDatabase(file)));
      await repo.setSetting('k', 'v');
      await repo.db.customStatement('PRAGMA user_version = 99');
      await repo.close();
      final newer = ProgressRepo(ProgressDb(NativeDatabase(file)));
      await expectLater(newer.getSetting('k'), throwsA(isA<StateError>()));
      await newer.close();
    });
  });

  test('dueStates uses the due index and course filter', () async {
    final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
    addTearDown(repo.close);
    for (final e in sampleLog(count: 200)) {
      await repo.record(e);
    }
    final now = DateTime.utc(2026, 9, 1);
    final due = await repo.dueStates(now: now, courseId: 'it');
    final all = await repo.allStates(courseId: 'it');
    expect(due.length, all.where((s) => s.isDue(now)).length);
    for (var i = 1; i < due.length; i++) {
      expect(due[i - 1].due.isAfter(due[i].due), isFalse);
    }
  });
}
