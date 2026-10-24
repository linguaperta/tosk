// "Reset this skill" (engine/skill_reset.dart): reset events in the review
// log, replayed by every store and by progression, carried by sync, undone.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart' as data;
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/progress/replay.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
const _elapsed = Duration(seconds: 8);

typedef _Store = ProgressStore;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final it = italianCourse();
  final scheduler = FsrsScheduler();

  final stores = <String, Future<(_Store, Future<void> Function())> Function()>{
    'ProgressRepo (drift)': () async {
      final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()), scheduler: scheduler);
      return (repo as _Store, repo.close);
    },
    'InMemoryProgressStore': () async => (data.InMemoryProgressStore(scheduler: scheduler) as _Store, () async {}),
  };

  for (final MapEntry(key: name, value: make) in stores.entries) {
    group(name, () {
      late _Store store;
      late Future<void> Function() close;
      var clock = _now;
      setUp(() async {
        (store, close) = await make();
        clock = _now;
      });
      tearDown(() => close());

      EngineSessionFactory factory({int seed = 1}) => EngineSessionFactory(
            course: it,
            store: store,
            scheduler: scheduler,
            options: SessionOptions(sourceLang: 'en', seed: seed),
            clock: () => clock,
          );

      Future<void> testOut(String skill) async {
        final s = await factory().testOut(skill);
        for (var e = await s.next(); e != null; e = await s.next()) {
          await s.submit(e, correctAnswer(e), elapsed: _elapsed);
          clock = clock.add(const Duration(seconds: 10));
        }
        expect(s.outcome!.passed, isTrue);
      }

      Future<Map<String, SkillProgress>> tiers() =>
          ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock).skillTiers(clock);

      Future<Map<String, FacetState>> states() async => {for (final s in await store.allStates()) s.facetId: s};

      test('reset: the facets are new again, tiers drop, rebuild reproduces it, history is kept', () async {
        await testOut('saluti');
        expect((await tiers())['saluti']!.tier, SkillTier.bronze);
        final xpBefore = (await ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock)
                .profile(clock))
            .totalXp;
        final logBefore = (await store.log()).length;
        clock = clock.add(const Duration(minutes: 5));
        final resets = await resetSkills(store, it, ['saluti'], now: clock);
        expect(resets, isNotEmpty);
        expect(resets.every((e) => e.isReset && e.answer == 'saluti' && e.mode == kResetMode), isTrue);
        final facets = {for (final f in it.skillFacets('saluti')) f.facetId};
        expect(resets.map((e) => e.facetId).toSet(), facets);
        final after = await states();
        expect(after.keys.where(facets.contains), isEmpty);
        // The answer history stays in the log; XP and reviews are unchanged.
        expect((await store.log()).length, logBefore + resets.length);
        final svc = ProgressionService(store: store, scheduler: scheduler, course: it, clock: () => clock);
        expect((await svc.profile(clock)).totalXp, xpBefore);
        expect((await tiers())['saluti']!.tier, isNot(SkillTier.bronze));
        expect((await tiers())['saluti']!.tier.index, lessThan(SkillTier.started.index));
        // A full replay agrees with the incremental one.
        await store.rebuildStates();
        expect(await states(), after);
        expect(replayLog(scheduler, await store.log()), after);
      });

      test('nothing studied: nothing to reset', () async {
        expect(await resettableFacets(store, it, ['cibo']), isEmpty);
        expect(await resetSkills(store, it, ['cibo'], now: clock), isEmpty);
      });

      test('undo: everything as before the reset', () async {
        await testOut('saluti');
        final before = await states();
        final tiersBefore = (await tiers()).map((k, v) => MapEntry(k, v.tier));
        clock = clock.add(const Duration(minutes: 1));
        final resets = await resetSkills(store, it, ['saluti'], now: clock);
        clock = clock.add(const Duration(seconds: 3));
        final undo = await undoReset(store, resets, now: clock);
        expect(undo.length, resets.length);
        expect(undo.every((e) => e.isResetUndo), isTrue);
        expect(await states(), before);
        expect((await tiers()).map((k, v) => MapEntry(k, v.tier)), tiersBefore);
        await store.rebuildStates();
        expect(await states(), before);
      });

      test('lessons introduce the reset words again; later answers build from scratch', () async {
        await testOut('saluti');
        clock = clock.add(const Duration(minutes: 1));
        await resetSkills(store, it, ['saluti'], now: clock);
        clock = clock.add(const Duration(minutes: 1));
        final lesson = await factory().lesson('saluti', length: 5);
        final e = (await lesson.next())!;
        final f = e.facetIds.first;
        expect(lesson.states.containsKey(f), isFalse, reason: 'a new facet in the lesson');
        await lesson.submit(e, correctAnswer(e), elapsed: _elapsed);
        final st = (await store.state(f))!;
        expect(st.reps, 1, reason: 'the first review after the reset');
        await store.rebuildStates();
        expect((await store.state(f))!.reps, 1);
      });

      test('a whole unit', () async {
        await testOut('saluti');
        await testOut('persone');
        final unit = [for (final s in it.skills) if (s.unitId == 'u1') s.id];
        final resets = await resetSkills(store, it, unit, now: clock.add(const Duration(minutes: 1)));
        final facets = {for (final s in unit) for (final f in it.skillFacets(s)) f.facetId};
        expect((await states()).keys.where(facets.contains), isEmpty);
        expect(resets.map((e) => e.sessionId).toSet().length, 1);
      });
    });
  }

  group('replay rules', () {
    ReviewEvent ev(String id, int sec, {String type = 'flashcard', Rating rating = Rating.good, String? answer}) => ReviewEvent(
          id: id,
          facetId: 'it:ciao#rec',
          at: _now.add(Duration(seconds: sec)),
          rating: rating,
          exerciseType: type,
          inputMode: InputMode.self,
          responseMs: 0,
          correct: rating != Rating.again,
          answer: answer,
        );

    test('a reset clears; later events start from scratch; an undo cancels it; any order', () {
      final log = [
        ev('a', 0),
        ev('b', 600),
        ev('r', 700, type: kResetType),
        ev('c', 800),
      ];
      final s = replayLog(scheduler, log)['it:ciao#rec']!;
      expect(s, scheduler.review('it:ciao#rec', null, Rating.good, _now.add(const Duration(seconds: 800))));
      expect(replayLog(scheduler, log.reversed)['it:ciao#rec'], s);
      expect(replayLog(scheduler, log.take(3))['it:ciao#rec'], isNull);
      final undone = [...log, ev('u', 900, type: kResetUndoType, answer: 'r')];
      expect(replayLog(scheduler, undone), replayLog(scheduler, [log[0], log[1], log[3]]));
      // Progression: same states, no step for the reset or the undo.
      final r = LogReplay(scheduler: scheduler)..update(log);
      expect(r.states['it:ciao#rec'], s);
      expect(r.steps.map((x) => x.event.id), ['a', 'b', 'c']);
      expect(r.steps.last.before, isNull);
      final r2 = LogReplay(scheduler: scheduler)..update(log.take(3));
      expect(r2.states, isEmpty);
      // Incremental adds agree with full updates.
      final r3 = LogReplay(scheduler: scheduler);
      for (final e in undone) {
        r3.add(e);
      }
      expect(r3.states, replayLog(scheduler, undone));
      // Just before step c the reset had cleared the facet.
      expect(r.statesAfterSteps(2), isEmpty);
      expect(r.statesAfterSteps(1), isNotEmpty);
    });
  });

  group('sync', () {
    test('a reset and its undo reach the other device, in any order', () async {
      var now = _now;
      final server = FakeSyncServer(clock: () => now);
      SyncEngine engineFor(data.InMemoryProgressStore p) => SyncEngine(
            store: InMemorySyncStore(),
            progress: p,
            importer: p,
            log: p,
            backend: FakeSyncBackend(server, account: 'alice'),
            syncedSettings: const {},
            clock: () => now,
            offsets: EventOffsets(fallback: (_) => Duration.zero),
            batchSize: 100,
          );
      final a = data.InMemoryProgressStore(scheduler: scheduler), b = data.InMemoryProgressStore(scheduler: scheduler);
      final ea = engineFor(a), eb = engineFor(b);
      var clock = _now;
      final f = EngineSessionFactory(
        course: it,
        store: a,
        scheduler: scheduler,
        options: const SessionOptions(sourceLang: 'en', seed: 1),
        clock: () => clock,
      );
      final s = await f.testOut('saluti');
      for (var e = await s.next(); e != null; e = await s.next()) {
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
        clock = clock.add(const Duration(seconds: 10));
      }
      await ea.sync();
      await eb.sync();
      Future<Map<String, FacetState>> st(ProgressStore p) async => {for (final x in await p.allStates()) x.facetId: x};
      expect(await st(b), await st(a));

      final resets = await resetSkills(a, it, ['saluti'], now: clock.add(const Duration(minutes: 1)));
      now = now.add(const Duration(minutes: 1));
      await ea.sync();
      await eb.sync();
      expect(await st(b), await st(a));
      expect((await st(b)).keys.where((k) => k.contains('ciao')), isEmpty);

      await undoReset(a, resets, now: clock.add(const Duration(minutes: 2)));
      now = now.add(const Duration(minutes: 1));
      await ea.sync();
      await eb.sync();
      expect(await st(b), await st(a));
      expect((await st(b)).keys.where((k) => k.contains('ciao')), isNotEmpty);

      // A third device that receives the undo before the reset ends the same.
      final c = data.InMemoryProgressStore(scheduler: scheduler);
      final log = await a.log();
      await c.importEvents(log.reversed);
      expect(await st(c), await st(a));
    });
  });
}
