/// Progression on the real FSRS scheduler and real stores: everything derived
/// from the review log is the same however the log was assembled (in order,
/// shuffled imports, out-of-order records + rebuild, drift or in memory).
library;

import 'dart:math';

import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/fsrs/fsrs_scheduler.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/data/stats/skill_stats.dart';
import 'package:tosk/progression/progression.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

/// ~90 days of sessions over the fixture course's facets: lessons and non-stop
/// runs, mostly right answers, some timestamp ties, match-pairs style
/// multi-facet answers at one instant.
List<ReviewEvent> _log(CourseData course, {int seed = 7}) {
  final rnd = Random(seed);
  final facets = <String>{for (final s in course.skills) ...course.skillFacets(s.id).map((f) => f.facetId)}.toList();
  final events = <ReviewEvent>[];
  var n = 0;
  var t = _now.subtract(const Duration(days: 90));
  for (var session = 0; session < 70; session++) {
    t = t.add(Duration(hours: 4 + rnd.nextInt(40)));
    if (t.isAfter(_now)) break;
    final mode = session % 4 == 3 ? 'nonstop' : 'lesson';
    final answers = 5 + rnd.nextInt(15);
    for (var a = 0; a < answers; a++) {
      t = t.add(Duration(seconds: 5 + rnd.nextInt(20)));
      final multi = rnd.nextInt(8) == 0;
      final type = multi ? 'match_pairs' : ExerciseType.values[rnd.nextInt(ExerciseType.values.length)].id;
      final picked = multi ? List.generate(3, (_) => facets[rnd.nextInt(facets.length)]).toSet() : {facets[rnd.nextInt(facets.length)]};
      for (final f in picked) {
        final r = Rating.values[[0, 1, 2, 2, 2, 2, 3, 3][rnd.nextInt(8)]];
        events.add(
          ReviewEvent(
            id: 'e${(n++).toString().padLeft(5, '0')}-${rnd.nextInt(1 << 30)}',
            facetId: f,
            at: t,
            rating: r,
            exerciseType: type,
            inputMode: InputMode.tap,
            responseMs: 1000 + rnd.nextInt(9000),
            correct: r != Rating.again,
            sessionId: 's$session',
            mode: mode,
          ),
        );
      }
    }
  }
  return events;
}

/// Everything progression shows, as one comparable string.
Future<String> _fingerprint(ProgressionService svc) async {
  final b = StringBuffer();
  final p = await svc.profile(_now);
  b.writeln('xp ${p.totalXp} lvl ${p.level.level} ${p.level.xpIntoLevel}/${p.level.xpForNext} '
      'streak ${p.currentStreak}/${p.longestStreak} freezes ${p.freezes} today ${p.todayReviews}/${p.todayXp} '
      'reviews ${p.totalReviews}');
  final tiers = await svc.skillTiers(_now);
  for (final e in tiers.entries) {
    final t = e.value;
    b.writeln('${e.key} ${t.tier.name} s=${t.strength.toStringAsFixed(12)} f=${t.fading.toStringAsFixed(12)} '
        'r=${t.reviewedCount} l=${t.learnedCount} due=${t.dueCount}');
  }
  final verbs = await svc.verbCollection(_now);
  for (final v in verbs.verbs) {
    b.writeln('${v.itemId} ${[for (final c in v.cells) '${c.tense}:${c.mastery.name}'].join(',')}');
  }
  final heat = await svc.heatmap(now: _now);
  b.writeln('heat ${[for (var d = heat.from; !d.isAfter(heat.to); d = d.addDays(1)) heat.countOn(d)].join(',')}');
  final board = await svc.challenges(_now);
  b.writeln('week ${[for (final c in board.weekly) c.progress].join(',')} month ${[for (final c in board.monthly) c.progress].join(',')}');
  b.writeln('badges ${board.badges.map((x) => x.id).join(',')}');
  for (final r in await svc.nonStopHistory()) {
    b.writeln('run ${r.sessionId} ${r.score} ${r.answered}/${r.correct} combo ${r.bestCombo}');
  }
  for (final sid in ['s0', 's3', 's40', 's69']) {
    final s = await svc.sessionSummary(sid);
    if (s == null) continue;
    b.writeln('sum $sid xp ${s.xpEarned} ${s.levelBefore.level}->${s.levelAfter.level} '
        'improved ${s.improvedItemIds.join(',')} tiers ${[for (final c in s.tierChanges) '${c.skillId}:${c.from.name}>${c.to.name}'].join(',')}');
  }
  return b.toString();
}

ProgressionService _service(ProgressStore store, CourseData course) => ProgressionService(
  store: store,
  scheduler: FsrsScheduler(),
  course: course,
  clock: () => _now,
  calendar: LocalCalendar.utc,
);

void main() {
  final course = fixtureCourse();
  final log = _log(course);

  test('the log is substantial and has ties and multi-facet answers', () {
    expect(log.length, greaterThan(400));
    final ats = log.map((e) => e.at).toList();
    expect(ats.toSet().length, lessThan(ats.length));
    expect(log.where((e) => e.mode == 'nonstop'), isNotEmpty);
  });

  test('progression recomputed from the log is identical across stores and insertion orders (FSRS)', () async {
    // A: in memory, in order.
    final a = InMemoryProgressStore(scheduler: FsrsScheduler());
    for (final e in log) {
      await a.record(e);
    }
    // B: drift, shuffled import (sync merge path).
    final b = ProgressRepo(ProgressDb(NativeDatabase.memory()), scheduler: FsrsScheduler());
    addTearDown(b.close);
    await b.importEvents(List.of(log)..shuffle(Random(1)));
    // C: drift, recorded newest first (every record out of order), then a full rebuild.
    final c = ProgressRepo(ProgressDb(NativeDatabase.memory()), scheduler: FsrsScheduler());
    addTearDown(c.close);
    for (final e in log.reversed) {
      await c.record(e);
    }
    await c.rebuildStates();

    final fa = await _fingerprint(_service(a, course));
    expect(fa, contains('xp '));
    expect(await _fingerprint(_service(b, course)), fa);
    expect(await _fingerprint(_service(c, course)), fa);
    // And a second computation on the same service (cached replay) agrees.
    final svc = _service(a, course);
    await _fingerprint(svc);
    expect(await _fingerprint(svc), fa);
  });

  test('incremental replay as the log grows equals a fresh replay; replay states equal stored FSRS states', () async {
    final store = InMemoryProgressStore(scheduler: FsrsScheduler());
    final growing = _service(store, course);
    for (var i = 0; i < log.length; i++) {
      await store.record(log[i]);
      if (i % 97 == 0) await growing.refresh();
    }
    expect(await _fingerprint(growing), await _fingerprint(_service(store, course)));

    // The replay's FSRS states are exactly the store's incrementally updated states.
    final stored = {for (final s in await store.allStates()) s.facetId: s};
    expect(growing.replay.states, stored);

    // And the data layer's skill strength agrees with progression's.
    final stats = await SkillStatsService(store, FsrsScheduler()).forCourse(course, now: _now);
    final tiers = await growing.skillTiers(_now);
    for (final id in tiers.keys) {
      expect(stats[id]!.strength, closeTo(tiers[id]!.strength, 1e-12), reason: id);
      expect(stats[id]!.lastPracticed, tiers[id]!.lastPracticed, reason: id);
    }
  });

  test('a sync merge of an older event changes results exactly as a full recompute does', () async {
    final half = log.length ~/ 2;
    final store = InMemoryProgressStore(scheduler: FsrsScheduler());
    final missing = log[half ~/ 2];
    for (final e in log) {
      if (!identical(e, missing)) await store.record(e);
    }
    final svc = _service(store, course);
    final before = await _fingerprint(svc);
    await store.importEvents([missing]); // arrives late, from another device
    final after = await _fingerprint(svc);
    expect(after, isNot(before));

    final full = InMemoryProgressStore(scheduler: FsrsScheduler());
    for (final e in log) {
      await full.record(e);
    }
    expect(after, await _fingerprint(_service(full, course)));
  });
}
