// "I was right": answer overrides (kOverrideType). The override is its own
// log event; every replay (store record, importEvents, rebuildStates,
// progression) treats the overridden answer as rated Good.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/event_importer.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/progress/replay.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';
import 'helpers.dart';

final _t0 = DateTime.utc(2026, 10, 13, 12);
const _elapsed = Duration(seconds: 9);

ReviewEvent _ev(String id, String facet, int minute, Rating rating, {String type = 'cloze', String? answer}) =>
    ReviewEvent(
      id: id,
      facetId: facet,
      at: _t0.add(Duration(minutes: minute)),
      rating: rating,
      exerciseType: type,
      inputMode: type == kOverrideType ? InputMode.self : InputMode.tap,
      responseMs: type == kOverrideType ? 0 : 4000,
      correct: rating != Rating.again,
      answer: answer,
      sessionId: 's1',
      mode: 'lesson',
    );

ReviewEvent _override(String id, String target, String facet, int minute) =>
    _ev(id, facet, minute, Rating.good, type: kOverrideType, answer: target);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final scheduler = FsrsScheduler();
  const f = 'it:mangiare#form:presente';

  group('applyOverrides', () {
    test('no override: the same list', () {
      final log = [_ev('a', f, 0, Rating.good), _ev('b', f, 5, Rating.again)];
      expect(identical(applyOverrides(log), log), isTrue);
    });

    test('the target takes the override rating in place; the override is dropped', () {
      final log = [_ev('a', f, 0, Rating.good), _ev('b', f, 5, Rating.again), _override('c', 'b', f, 6)];
      final out = applyOverrides(log);
      expect(out.map((e) => e.id), ['a', 'b']);
      expect(out[1].rating, Rating.good);
      expect(out[1].correct, isTrue);
      expect(out[1].at, log[1].at);
    });

    test('an override whose target is missing does nothing; the last of several wins', () {
      expect(applyOverrides([_override('c', 'zzz', f, 1)]), isEmpty);
      final log = [
        _ev('b', f, 5, Rating.again),
        _override('c', 'b', f, 6),
        _ev('d', f, 7, Rating.hard, type: kOverrideType, answer: 'b'),
      ];
      expect(applyOverrides(log).single.rating, Rating.hard);
    });
  });

  final stores = <String, Future<(ProgressStore, EventImporter)> Function()>{
    'ProgressRepo (drift)': () async {
      final r = ProgressRepo(ProgressDb(NativeDatabase.memory()), scheduler: scheduler);
      addTearDown(r.close);
      return (r as ProgressStore, r as EventImporter);
    },
    'InMemoryProgressStore': () async {
      final s = InMemoryProgressStore(scheduler: scheduler);
      return (s as ProgressStore, s as EventImporter);
    },
  };

  for (final MapEntry(key: name, value: make) in stores.entries) {
    group(name, () {
      test('record(override) re-rates the overridden answer; rebuildStates agrees', () async {
        final (store, _) = await make();
        await store.record(_ev('a', f, 0, Rating.good));
        await store.record(_ev('b', f, 600, Rating.again));
        final after = (await store.record(_override('c', 'b', f, 601)))!;
        final expected = foldFacet(scheduler, f, [_ev('a', f, 0, Rating.good), _ev('b', f, 600, Rating.good)]);
        expect(after, expected);
        expect(after.lapses, 0);
        await store.rebuildStates();
        expect(await store.state(f), expected);
        // The log keeps both events: append-only.
        expect((await store.log()).map((e) => e.id), ['a', 'b', 'c']);
        // A later answer builds on the corrected state.
        final next = await store.record(_ev('d', f, 2000, Rating.good));
        await store.rebuildStates();
        expect(await store.state(f), next);
      });

      test('an import with the override before its target (sync order) ends the same', () async {
        final (store, importer) = await make();
        await importer.importEvents([_override('c', 'b', f, 601)]);
        expect(await store.state(f), isNull);
        await importer.importEvents([_ev('a', f, 0, Rating.good), _ev('b', f, 600, Rating.again)]);
        final expected = foldFacet(scheduler, f, [_ev('a', f, 0, Rating.good), _ev('b', f, 600, Rating.good)]);
        expect(await store.state(f), expected);
        expect(await importer.importEvents([_override('c', 'b', f, 601)]), 0, reason: 'idempotent');
      });
    });
  }

  group('progression', () {
    test('an overridden answer earns the XP of a right one; the override is no review', () async {
      final course = italianCourse();
      final plain = InMemoryProgressStore(scheduler: scheduler);
      final overridden = InMemoryProgressStore(scheduler: scheduler);
      await plain.record(_ev('a', f, 0, Rating.good));
      await plain.record(_ev('b', f, 600, Rating.good));
      for (final e in [_ev('a', f, 0, Rating.good), _ev('b', f, 600, Rating.again), _override('c', 'b', f, 601)]) {
        await overridden.record(e);
      }
      ProgressionService svc(ProgressStore s) =>
          ProgressionService(store: s, scheduler: scheduler, course: course, clock: () => _t0.add(const Duration(days: 1)), calendar: LocalCalendar.utc);
      final p1 = await svc(plain).profile();
      final p2 = await svc(overridden).profile();
      expect(p2.totalXp, p1.totalXp);
      expect(p2.totalReviews, 2);
      expect(p2.todayReviews, p1.todayReviews);

      // Incremental: the replay sees the override arrive after the fact.
      final replay = LogReplay(scheduler: scheduler)..update(await overridden.log());
      final before = LogReplay(scheduler: scheduler)
        ..update([_ev('a', f, 0, Rating.good), _ev('b', f, 600, Rating.again)]);
      expect(before.update(await overridden.log()), ReplayUpdate.rebuilt);
      expect(before.totalXp, replay.totalXp);
      expect(before.add(_override('c', 'b', f, 601)), ReplayUpdate.unchanged);
    });
  });

  group('engine session', () {
    late InMemoryProgressStore store;
    late DateTime clock;
    final it = italianCourse();

    EngineSessionFactory factory() => EngineSessionFactory(
      course: it,
      store: store,
      scheduler: scheduler,
      options: const SessionOptions(sourceLang: 'en', seed: 3),
      clock: () => clock,
    );

    setUp(() {
      store = InMemoryProgressStore(scheduler: scheduler);
      clock = _t0;
    });

    test('overrideAnswer: Good instead of Again, no re-ask, mistake resolved, counted correct', () async {
      final s = await factory().lab(skillIds: ['presente-are'], types: [ExerciseType.conjPick], length: 3);
      final first = (await s.next())!;
      final r = await s.submit(first, wrongAnswer(first), elapsed: _elapsed);
      expect(r.correct, isFalse);
      expect(s.plannedLength, 4, reason: 'a re-ask was queued');
      expect((await openMistakes(store: store, course: it, scheduler: scheduler, now: clock)).length, 1);
      final overridable = s as OverridableSession;
      expect(overridable.canOverride(first.id), isTrue);

      clock = clock.add(const Duration(seconds: 5));
      final written = await overridable.overrideAnswer(first.id);
      expect(written, hasLength(1));
      final o = written.single;
      expect(o.isOverride, isTrue);
      expect(o.rating, Rating.good);
      final original = (await store.log()).firstWhere((e) => e.facetId == first.facetId && !e.isOverride);
      expect(o.overriddenId, original.id);
      expect(overridable.canOverride(first.id), isFalse);
      expect(await overridable.overrideAnswer(first.id), isEmpty, reason: 'only once');

      expect(s.correctCount, 1);
      expect(s.plannedLength, 3, reason: 're-ask dropped');
      expect(s.summary().mistakes, isEmpty);
      expect(s.mistakeContext(first.id), isNull);
      expect(await openMistakes(store: store, course: it, scheduler: scheduler, now: clock), isEmpty);

      final expected = scheduler.review(first.facetId, null, Rating.good, toStoredTime(original.at));
      expect(await store.state(first.facetId), expected);
      await store.rebuildStates();
      expect(await store.state(first.facetId), expected);

      // The rest of the session runs without the re-ask.
      var served = 1;
      for (var e = await s.next(); e != null; e = await s.next()) {
        served++;
        await s.submit(e, correctAnswer(e), elapsed: _elapsed);
      }
      expect(served, 3);
    });

    test('a right answer cannot be overridden', () async {
      final s = await factory().lab(skillIds: ['presente-are'], types: [ExerciseType.conjPick], length: 1);
      final e = (await s.next())!;
      await s.submit(e, correctAnswer(e), elapsed: _elapsed);
      expect((s as OverridableSession).canOverride(e.id), isFalse);
      expect(await s.overrideAnswer(e.id), isEmpty);
    });
  });
}
