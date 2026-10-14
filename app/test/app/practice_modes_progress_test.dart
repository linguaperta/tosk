// Every practice mode advances the skills on the map: the real engine and
// progression over an on-disk ProgressRepo and the fixture course. Non-stop
// alone works through the map (new facets in skill order, unlocks); lab,
// fading, mistake review, tough words, test out and placement all record
// events that move strength, tiers and the course's XP. And the UI refreshes
// the map after leaving a session, also mid-way.
import 'package:tosk/app.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart';
import '../fixtures/course_fixture.dart';
import '../ui/helpers.dart';
import 'app_fixture.dart';

/// The app's engine and progression over one on-disk progress database, with
/// a clock the test moves.
class _World {
  _World(this.repo) : course = fixtureCourse();

  final ProgressRepo repo;
  final InMemoryCourseData course;
  DateTime now = DateTime.utc(2026, 10, 1, 9);

  DateTime clock() => now;

  EngineSessionFactory get factory => EngineSessionFactory(
    course: course,
    store: repo,
    scheduler: repo.scheduler,
    options: const SessionOptions(sourceLang: 'en', accents: AccentStrictness.lenient, seed: 7),
    clock: clock,
  );

  ProgressionService get progression =>
      ProgressionService(store: repo, scheduler: repo.scheduler, course: course, clock: clock, calendar: LocalCalendar.utc);

  Future<Map<String, SkillProgress>> tiers() => progression.skillTiers(now);

  Future<int> xp() async => (await progression.profile(now)).totalXp;

  /// Answers every exercise (right, or wrong where [wrong] says so), [step]
  /// apart, until the session ends or [cap] answers; returns the count.
  Future<int> play(
    PracticeSession s, {
    int cap = 200,
    Duration step = const Duration(seconds: 20),
    bool Function(int i, Exercise e)? wrong,
  }) async {
    var n = 0;
    for (var e = await s.next(); e != null && n < cap; e = await s.next()) {
      final bad = wrong?.call(n, e) ?? false;
      await s.submit(e, bad ? wrongAnswer(e) : correctAnswer(e), elapsed: const Duration(seconds: 6));
      now = now.add(step);
      n++;
    }
    s.stop();
    return n;
  }
}

Future<_World> _world(String name) async {
  final dir = tempDir(name);
  final repo = fileProgressRepo('${dir.path}/progress.sqlite');
  addTearDown(repo.close);
  return _World(repo);
}

void main() {
  group('non-stop alone works through the map', () {
    test('new facets come in skill order from unlocked skills; skills start, learn and unlock', () async {
      final w = await _world('tosk_ns');
      expect((await w.tiers())['greetings']!.tier, SkillTier.available);
      expect((await w.tiers())['present-are']!.tier, SkillTier.locked);
      final ns = await w.factory.nonStop();
      final answered = await w.play(ns, cap: 260);
      expect(answered, 260);

      final log = await w.repo.log();
      expect(log.every((e) => e.mode == 'nonstop'), isTrue);
      // Every facet's first review happened while its skill was unlocked:
      // each prerequisite had a reviewed facet before.
      final firstSeen = <String, DateTime>{};
      for (final e in log) {
        firstSeen.putIfAbsent(e.facetId, () => e.at);
      }
      for (final entry in firstSeen.entries) {
        for (final skillId in w.course.skillsForFacet(entry.key)) {
          final skill = w.course.skill(skillId)!;
          for (final req in skill.requires) {
            final started = w.course.skillFacets(req).any((f) => firstSeen[f.facetId]?.isBefore(entry.value) ?? false);
            if (w.course.skillsForFacet(entry.key).length == 1) {
              expect(started, isTrue, reason: '${entry.key} before $req was started');
            }
          }
        }
      }
      // New facets kept coming until every facet of the course was introduced.
      final all = {for (final s in w.course.skills) for (final f in w.course.skillFacets(s.id)) f.facetId};
      expect(firstSeen.keys.toSet(), all, reason: '${firstSeen.length} of ${all.length} facets in $answered answers');
      // ...at a steady pace: the first half of the run already brought in most.
      final half = log[log.length ~/ 2].at;
      expect(firstSeen.values.where((t) => t.isBefore(half)).length, greaterThan(all.length * 0.6));

      // The map moved: the first skills are learned, the next ones unlocked and started.
      final tiers = await w.tiers();
      expect(tiers['greetings']!.tier.index, greaterThanOrEqualTo(SkillTier.bronze.index), reason: '${tiers['greetings']}');
      expect(tiers['essere-avere']!.tier.index, greaterThanOrEqualTo(SkillTier.started.index));
      expect(tiers['food']!.tier.index, greaterThanOrEqualTo(SkillTier.started.index));
      expect(tiers.values.where((p) => p.tier == SkillTier.locked), isEmpty, reason: '$tiers');
      // XP and level for the course.
      final profile = await w.progression.profile(w.now);
      expect(profile.totalXp, greaterThan(500));
      expect(profile.totalReviews, log.length);
    });

    test('a new facet that cannot be built is skipped, not retried forever', () async {
      final w = await _world('tosk_ns_skip');
      // Only flashcards for vocab: any grammar facet (conj types) fails to build
      // with these templates, so non-stop must move past them.
      final factory = EngineSessionFactory(
        course: w.course,
        store: w.repo,
        scheduler: w.repo.scheduler,
        options: const SessionOptions(sourceLang: 'en', seed: 3),
        templates: const [FlashcardTemplate()],
        clock: w.clock,
      );
      final ns = await factory.nonStop();
      final n = await w.play(ns, cap: 120);
      expect(n, 120);
      final reviewed = {for (final e in await w.repo.log()) e.facetId};
      // Vocab facets of several skills got introduced although grammar ones in between could not.
      expect(reviewed.where((f) => f.contains('#rec') || f.contains('#prod')).length, greaterThan(8));
    });
  });

  group('every mode advances the skills and the course XP', () {
    test('lab', () async {
      final w = await _world('tosk_lab');
      final s = await w.factory.lab(skillIds: ['greetings'], types: [ExerciseType.multipleChoice, ExerciseType.flashcard], length: 10);
      await w.play(s);
      final log = await w.repo.log();
      expect(log, isNotEmpty);
      expect(log.every((e) => e.mode == 'lab'), isTrue);
      final t = (await w.tiers())['greetings']!;
      expect(t.tier.index, greaterThanOrEqualTo(SkillTier.started.index));
      expect(t.strength, greaterThan(0));
      expect(await w.xp(), greaterThan(0));
      expect((await w.tiers())['food']!.tier, SkillTier.available); // unlocked by the lab practice
    });

    test('fading, mistake review and tough words', () async {
      final w = await _world('tosk_review');
      // A lesson with one mistake, then a week later.
      final lesson = await w.factory.lesson('greetings');
      await w.play(lesson, wrong: (i, _) => i == 0);
      final mistakes = await openMistakes(store: w.repo, course: w.course, scheduler: w.repo.scheduler, now: w.now);
      expect(mistakes, isNotEmpty);
      w.now = w.now.add(const Duration(days: 7));

      Future<void> expectAdvanced(String mode, Future<void> Function() run) async {
        final xp0 = await w.xp();
        final before = await w.repo.log();
        final strength0 = (await w.tiers())['greetings']!.strength;
        await run();
        final after = await w.repo.log();
        final added = after.where((e) => !before.any((b) => b.id == e.id)).toList();
        expect(added, isNotEmpty, reason: mode);
        expect(added.every((e) => e.mode == 'review'), isTrue, reason: mode);
        expect(await w.xp(), greaterThan(xp0), reason: mode);
        expect((await w.tiers())['greetings']!.strength, greaterThan(strength0), reason: mode);
      }

      await expectAdvanced('fading', () async => w.play(await w.factory.fading()));
      w.now = w.now.add(const Duration(days: 7));
      // A new mistake to review.
      await w.play(await w.factory.lesson('greetings'), wrong: (i, _) => i == 0);
      w.now = w.now.add(const Duration(days: 5));
      await expectAdvanced('mistake review', () async => w.play(await w.factory.review()));

      // Tough words: a facet forgotten four times after learning it.
      const leech = 'it:grazie#rec';
      var at = w.now.add(const Duration(days: 1));
      Future<void> rec(Rating r) async {
        await w.repo.record(
          ReviewEvent(
            id: 'leech-${at.millisecondsSinceEpoch}',
            facetId: leech,
            at: at,
            rating: r,
            exerciseType: 'flashcard',
            inputMode: InputMode.self,
            responseMs: 1000,
            correct: r != Rating.again,
            mode: 'lesson',
          ),
        );
        at = at.add(const Duration(days: 3));
      }

      for (var i = 0; i < 5; i++) {
        await rec(Rating.good);
        await rec(Rating.again);
      }
      w.now = at;
      await expectAdvanced('tough words', () async {
        final s = await w.factory.toughWords(minLapses: 4);
        expect(s.plannedLength, greaterThan(0));
        await w.play(s);
      });
    });

    test('test out credits the skill (bronze) and unlocks the next; its answers earn XP', () async {
      final w = await _world('tosk_testout');
      final s = await w.factory.testOut('greetings');
      await w.play(s);
      expect(s.outcome!.passed, isTrue);
      final tiers = await w.tiers();
      expect(tiers['greetings']!.tier.index, greaterThanOrEqualTo(SkillTier.bronze.index));
      expect(tiers['essere-avere']!.tier, SkillTier.available);
      expect(tiers['food']!.tier, SkillTier.available);
      expect(await w.xp(), greaterThan(0));
      final log = await w.repo.log();
      expect(log.every((e) => e.mode == 'testOut'), isTrue);
    });

    test('placement credits the units it passes', () async {
      final w = await _world('tosk_placement');
      final s = await w.factory.placement();
      await w.play(s);
      expect(s.outcome!.passedUnits, isNotEmpty);
      final tiers = await w.tiers();
      for (final skill in w.course.skills.where((k) => k.unitId == 'u1')) {
        expect(tiers[skill.id]!.tier.index, greaterThanOrEqualTo(SkillTier.bronze.index), reason: skill.id);
      }
      expect(await w.xp(), greaterThan(0));
    });
  });

  group('the map refreshes after leaving a session', () {
    Future<(ProgressRepo, ProviderContainer)> boot(WidgetTester tester, String initial) async {
      final dir = tempDir('tosk_refresh');
      final repo = fileProgressRepo('${dir.path}/progress.sqlite');
      addTearDown(() => tester.runAsync(repo.close));
      // An install that already chose its course (no first-run picker).
      await tester.runAsync(() => repo.setSetting(SettingKeys.coursesAdded, 'it'));
      final app = fixtureAppData(repo);
      setSurface(tester, const Size(420, 900));
      var t = testNow;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...fixtureBoot(app).overrides,
            clockProvider.overrideWithValue(() => t = t.add(const Duration(seconds: 2))),
            calendarProvider.overrideWithValue(LocalCalendar.utc),
            // The asset bundle's cached future hangs in a second widget test
            // of a file (test-only; see docs/qa-2026-10.md #22).
            focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults),
            routerProvider.overrideWith((ref) => buildRouter(initialLocation: initial)),
          ],
          child: const ToskApp(),
        ),
      );
      await tester.pumpAndSettle();
      return (repo, ProviderScope.containerOf(tester.element(find.byType(ToskApp))));
    }

    SkillNode node(WidgetTester tester, String id) => tester.widget<SkillNode>(
      find.ancestor(of: find.byKey(ValueKey('skill-node-$id')), matching: find.byType(SkillNode)),
    );

    testWidgets('stopping non-stop mid-way: the map and the header show the answers', (tester) async {
      final (repo, container) = await boot(tester, Routes.nonstopPlay);
      for (var i = 0; i < 4; i++) {
        await answerCurrent(tester);
      }
      await tapKey(tester, 'nonstop-stop');
      expect(find.text('Run finished'), findsOneWidget);
      await tapKey(tester, 'summary-done');
      expect(find.byType(MapScreen), findsOneWidget);
      expect(node(tester, 'greetings').stats.practiced, isTrue);
      final profile = (await tester.runAsync(() => container.read(progressProfileProvider.future)))!;
      expect(profile.totalXp, greaterThan(0));
      expect(profile.totalReviews, (await tester.runAsync(repo.log))!.length);
    });

    testWidgets('a player route removed without Quit still refreshes the map', (tester) async {
      final (repo, container) = await boot(tester, Routes.map);
      expect(node(tester, 'greetings').stats.practiced, isFalse);
      await startLessonFromMap(tester, 'greetings');
      await answerCurrent(tester);
      await answerCurrent(tester);
      expect((await tester.runAsync(repo.log))!, isNotEmpty);
      // Leave by navigation (no Quit dialog, no summary).
      container.read(routerProvider).go(Routes.map);
      await tester.pumpAndSettle();
      expect(find.byType(MapScreen), findsOneWidget);
      expect(node(tester, 'greetings').stats.practiced, isTrue);
    });
  });
}

