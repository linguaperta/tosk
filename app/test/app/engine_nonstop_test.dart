import 'package:tosk/app.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/progression.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/progression/nonstop_hud.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';
import '../ui/helpers.dart';
import 'app_fixture.dart';

/// The engine factory, keeping the non-stop session it hands out.
class _SpyFactory extends EngineSessionFactory {
  _SpyFactory({
    required super.course,
    required super.store,
    required super.scheduler,
    required super.options,
    super.clock,
  });

  NonStopSession? session;

  @override
  Future<NonStopSession> nonStop() async => session = await super.nonStop();
}

void main() {
  testWidgets('non-stop through the engine: HUD fed from results, bonus round enqueued, record = live score', (
    tester,
  ) async {
    final dir = tempDir('tosk_nonstop');
    final repo = fileProgressRepo('${dir.path}/progress.sqlite');
    addTearDown(() => tester.runAsync(repo.close));
    final app = fixtureAppData(repo);
    setSurface(tester, const Size(420, 900));
    // One earlier review in every skill, so every skill (and its verb tables) is unlocked.
    final course = fixtureCourse();
    await tester.runAsync(() async {
      for (final s in course.skills) {
        final f = course.skillFacets(s.id).first;
        await repo.record(
          ReviewEvent(
            id: 'seed-${s.id}',
            facetId: f.facetId,
            at: testNow.subtract(const Duration(days: 2)),
            rating: Rating.good,
            exerciseType: 'flashcard',
            inputMode: InputMode.self,
            responseMs: 1000,
            correct: true,
            mode: 'lesson',
          ),
        );
      }
    });
    // A clock that moves, so answers have distinct `at`s (as in real use).
    var t = testNow;
    DateTime clock() => t = t.add(const Duration(milliseconds: 1500));
    _SpyFactory? factory;

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...fixtureBoot(app).overrides,
          clockProvider.overrideWithValue(clock),
          calendarProvider.overrideWithValue(LocalCalendar.utc),
          routerProvider.overrideWith((ref) => buildRouter(initialLocation: Routes.nonstopPlay)),
          sessionFactoryProvider.overrideWith((ref) async {
            final course = await ref.watch(courseDataProvider.future);
            return factory = _SpyFactory(
              course: course,
              store: ref.watch(progressStoreProvider),
              scheduler: ref.watch(schedulerProvider),
              options: ref.watch(sessionOptionsProvider),
              clock: ref.watch(clockProvider),
            );
          }),
        ],
        child: const ToskApp(),
      ),
    );
    await tester.pumpAndSettle();

    NonStopRun run() => tester.widget<NonStopHud>(find.byType(NonStopHud)).run;
    expect(run().score, 0);

    var bonusSeen = false;
    for (var i = 0; i < 27; i++) {
      await answerCurrent(tester);
      if (i == 24) {
        // The 25th correct answer started the conjugation blitz: the engine now serves conj_pick.
        expect(run().bonusRound, isNotNull);
        expect(currentExercise(tester).type, ExerciseType.conjPick);
        bonusSeen = factory!.session!.bonusRemaining > 0;
      }
    }
    expect(run().answered, 27);
    expect(run().correct, 27);
    expect(run().bestCombo, 27);
    expect(run().bonusRoundsStarted, 1);
    expect(bonusSeen, isTrue, reason: 'the 25th correct answer starts a bonus round and enqueues it in the engine');
    final live = run().score;
    expect(live, greaterThan(27 * 10));

    await tapKey(tester, 'nonstop-stop');
    expect(find.text('Run finished'), findsOneWidget);

    // The best run replayed from the review log equals the live score.
    final container = ProviderScope.containerOf(tester.element(find.byType(ToskApp)));
    final best = (await tester.runAsync(() => container.read(bestNonStopRunProvider.future)));
    expect(best!.score, live);
    expect(best.answered, 27);
  });
}
