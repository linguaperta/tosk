import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_exercises.dart';
import 'package:tosk/ui/demo/demo_grader.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/demo/demo_session.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A correct answer for any demo exercise.
Answer correctAnswer(Exercise ex) => switch (ex) {
  FlashcardExercise() => const SelfGradeAnswer(Rating.good),
  MultipleChoiceExercise e => ChoiceAnswer(e.correctIndex),
  MatchPairsExercise e => MatchAnswer(Map.of(e.solution)),
  ConjPickExercise e => ChoiceAnswer(e.correctIndex),
  ConjGridExercise e => GridAnswer([for (final c in e.cells) c.prefilled ? '' : c.expected]),
  SentenceBuilderExercise e => TilesAnswer(e.answers.first),
  ClozeExercise e => e.options != null ? ChoiceAnswer(e.correctIndex!) : TextAnswer(e.expected),
  SpotErrorExercise e => TokenAnswer(e.errorIndex),
  TransformExercise e => TilesAnswer(e.answers.first),
};

void main() {
  const grader = DemoGrader();

  test('demo pools cover all 9 exercise types in both courses', () {
    for (final course in ['it', 'nl']) {
      final types = demoExercises(course, 'en').map((e) => e.type).toSet();
      expect(types, ExerciseType.values.toSet(), reason: course);
    }
  });

  test('demo exercises reference facets of their skill in the demo course', () {
    for (final course in [buildDemoItalian(), buildDemoDutch()]) {
      for (final ex in demoExercises(course.meta.id, 'en')) {
        expect(course.skill(ex.skillId!), isNotNull, reason: ex.id);
        final facets = course.skillFacets(ex.skillId!).map((f) => f.facetId).toSet();
        final all = {for (final s in course.skills) ...course.skillFacets(s.id).map((f) => f.facetId)};
        for (final f in ex.facetIds) {
          expect(all.contains(f) || facets.contains(f), isTrue, reason: '${ex.id}: $f');
        }
      }
    }
  });

  test('every demo exercise grades its correct answer as correct', () {
    for (final lang in ['en', 'nl']) {
      for (final ex in [...demoExercises('it', lang), ...demoExercises('nl', lang)]) {
        final r = grader.grade(ex, correctAnswer(ex));
        expect(r.correct, isTrue, reason: ex.id);
        expect(r.outcomes.length, ex.facetIds.length, reason: ex.id);
      }
    }
  });

  group('DemoGrader', () {
    test('wrong choices and tiles are wrong', () {
      final pool = demoExercises('it', 'en');
      final mc = pool.whereType<MultipleChoiceExercise>().first;
      expect(grader.grade(mc, ChoiceAnswer((mc.correctIndex + 1) % mc.options.length)).correct, isFalse);
      final sb = pool.whereType<SentenceBuilderExercise>().first;
      expect(grader.grade(sb, const TilesAnswer(['ciao'])).correct, isFalse);
    });

    test('grid marks per cell', () {
      final grid = demoExercises('it', 'en').whereType<ConjGridExercise>().first;
      final cells = [for (final c in grid.cells) c.prefilled ? '' : c.expected];
      cells[1] = 'nope';
      final r = grader.grade(grid, GridAnswer(cells));
      expect(r.correct, isFalse);
      expect(r.cellCorrect![1], isFalse);
      expect(r.cellCorrect!.where((m) => !m).length, 1);
    });

    test('match pairs: a missed pair is wrong for that facet only', () {
      final mp = demoExercises('it', 'en').whereType<MatchPairsExercise>().first;
      final r = grader.grade(mp, MatchAnswer(Map.of(mp.solution), missed: {1}));
      expect(r.correct, isFalse);
      expect(r.outcomes.where((o) => !o.correct).map((o) => o.facetId), [mp.pairFacetIds[1]]);
    });

    test('cloze text: lenient accents and case, strict accents', () {
      const cloze = ClozeExercise(
        id: 'x',
        facetId: 'it:essere#form:presente',
        before: 'Lui ',
        after: ' qui.',
        expected: 'è',
        accepted: ['è'],
      );
      expect(grader.grade(cloze, const TextAnswer('E')).correct, isTrue);
      expect(const DemoGrader(accents: AccentStrictness.strict).grade(cloze, const TextAnswer('e')).correct, isFalse);
      expect(const DemoGrader(accents: AccentStrictness.strict).grade(cloze, const TextAnswer(' È ')).correct, isTrue);
      expect(grader.grade(cloze, const TextAnswer('x', candidates: ['è'])).correct, isTrue);
    });

    test('fast correct answers rate Easy, wrong ones Again', () {
      final mc = demoExercises('it', 'en').whereType<MultipleChoiceExercise>().first;
      expect(
        grader.grade(mc, ChoiceAnswer(mc.correctIndex), elapsed: const Duration(seconds: 1)).outcomes.single.rating,
        Rating.easy,
      );
      expect(
        grader.grade(mc, ChoiceAnswer(mc.correctIndex), elapsed: const Duration(seconds: 9)).outcomes.single.rating,
        Rating.good,
      );
      expect(grader.grade(mc, const ChoiceAnswer(99)).outcomes.single.rating, Rating.again);
    });
  });

  group('DemoPracticeSession', () {
    late InMemoryProgressStore store;
    late DemoSessionFactory factory;
    setUp(() {
      store = InMemoryProgressStore();
      factory = DemoSessionFactory(
        course: buildDemoItalian(),
        store: store,
        options: const SessionOptions(sourceLang: 'en'),
        clock: () => DateTime.utc(2026, 10, 13),
      );
    });

    test('lesson: planned length, records events, re-queues a mistake once', () async {
      final s = await factory.lesson('present-are', length: 4);
      expect(s.plannedLength, 4);
      final first = (await s.next())!;
      await s.submit(first, const ChoiceAnswer(99), elapsed: const Duration(seconds: 5));
      var served = 1;
      Exercise? ex;
      while ((ex = await s.next()) != null) {
        served++;
        await s.submit(ex!, correctAnswer(ex), elapsed: const Duration(seconds: 5));
      }
      expect(served, 5); // 4 + the re-queued mistake
      final sum = s.summary();
      expect(sum.answered, 5);
      expect(sum.correct, 4);
      expect(sum.mistakes, isNotEmpty);
      expect(await store.log(), hasLength(greaterThanOrEqualTo(5)));
      expect(await store.mistakes(), isNotEmpty);
    });

    test('focus filters exercise types', () async {
      final s = await factory.lesson('present-are', focus: LessonFocus.grammar, length: 8);
      Exercise? ex;
      while ((ex = await s.next()) != null) {
        expect({
          ExerciseType.conjPick,
          ExerciseType.conjGrid,
          ExerciseType.cloze,
          ExerciseType.transform,
          ExerciseType.spotError,
        }, contains(ex!.type));
        await s.submit(ex, correctAnswer(ex), elapsed: Duration.zero);
      }
    });

    test('lab honours skills, types and length', () async {
      final s = await factory.lab(skillIds: ['greetings', 'food'], types: [ExerciseType.multipleChoice], length: 3);
      for (var i = 0; i < 3; i++) {
        final ex = (await s.next())!;
        expect(ex.type, ExerciseType.multipleChoice);
        expect(['greetings', 'food'], contains(ex.skillId));
        await s.submit(ex, correctAnswer(ex), elapsed: Duration.zero);
      }
      expect(await s.next(), isNull);
    });

    test('lab with no matching exercises is empty', () async {
      final s = await factory.lab(skillIds: ['greetings'], types: [ExerciseType.conjGrid], length: 5);
      expect(s.plannedLength, 0);
      expect(await s.next(), isNull);
    });

    test('non-stop is endless until stopped', () async {
      final s = await factory.nonStop();
      expect(s.plannedLength, isNull);
      for (var i = 0; i < 40; i++) {
        final ex = (await s.next())!;
        await s.submit(ex, correctAnswer(ex), elapsed: Duration.zero);
      }
      expect(s.answered, 40);
      s.stop();
      expect(await s.next(), isNull);
      expect(s.summary().correct, 40);
    });
  });

  test('skillStatsProvider on the seeded demo course: FSRS strength, progression tiers, locking, fading', () async {
    final course = buildDemoItalian();
    final store = InMemoryProgressStore();
    final now = DateTime.utc(2026, 10, 13);
    final container = ProviderContainer.test(
      overrides: [
        progressStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => now),
        calendarProvider.overrideWithValue(LocalCalendar.utc),
      ],
    );
    var stats = await container.read(skillStatsProvider.future);
    expect(stats['greetings']!.tier, MapTier.available);
    expect(stats['food']!.tier, MapTier.locked);
    await seedDemoProgress(store, course, now);
    container.read(progressRevisionProvider.notifier).bump();
    stats = await container.read(skillStatsProvider.future);
    expect(stats['greetings']!.tier.index, greaterThanOrEqualTo(MapTier.bronze.index));
    expect(stats['greetings']!.strength, greaterThan(stats['articles']!.strength));
    expect(stats['articles']!.tier, MapTier.started); // one review: still in FSRS learning
    expect(stats['articles']!.fading, greaterThan(0));
    expect(stats['articles']!.decay, stats['articles']!.fading);
    expect(stats['family']!.tier, MapTier.available); // prerequisite practiced
    expect(stats['passato']!.tier, MapTier.locked);
    expect(stats['greetings']!.daysSince(now), 4);
    expect(stats['greetings']!.totalFacets, course.skillFacets('greetings').length);
    expect(stats['greetings']!.practicedFacets, stats['greetings']!.totalFacets);
  });

  test('mapTier and skillTierOf are inverse', () {
    for (final t in MapTier.values) {
      expect(mapTier(skillTierOf(t)), t);
    }
  });
}
