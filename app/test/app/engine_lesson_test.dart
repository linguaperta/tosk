import 'package:tosk/app.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/map_screen.dart';
import 'package:tosk/ui/map/skill_node.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/helpers.dart';
import 'app_fixture.dart';

void main() {
  testWidgets('a lesson end to end: real engine, ProgressRepo on disk, fixture course', (tester) async {
    final dir = tempDir('tosk_lesson');
    final repo = fileProgressRepo('${dir.path}/progress.sqlite');
    addTearDown(() => tester.runAsync(repo.close));
    final app = fixtureAppData(repo);
    setSurface(tester, const Size(420, 900));

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...fixtureBoot(app).overrides,
          clockProvider.overrideWithValue(() => testNow),
          calendarProvider.overrideWithValue(LocalCalendar.utc),
          routerProvider.overrideWith((ref) => buildRouter(initialLocation: Routes.lesson('greetings'))),
        ],
        child: const ToskApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The real engine over the pack's course.
    final container = ProviderScope.containerOf(tester.element(find.byType(ToskApp)));
    expect(await container.read(sessionFactoryProvider.future), isA<EngineSessionFactory>());
    expect(container.read(activeCourseIsDemoProvider), isFalse);

    // First answer wrong, the rest right.
    final first = currentExercise(tester);
    await answerCurrent(tester, wrong: true);
    final answered = 1 + await playToSummary(tester);
    expect(find.text('Session complete'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('stat-answered')), matching: find.text('$answered')),
      findsOneWidget,
    );
    expect(find.text('To review'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-progress-card')), findsOneWidget);

    // review_log: one Again for the first facet, everything else correct, one session.
    final log = (await tester.runAsync(repo.log))!;
    expect(log, isNotEmpty);
    expect(log.map((e) => e.sessionId).toSet(), hasLength(1));
    expect(log.every((e) => e.mode == 'lesson'), isTrue);
    final again = log.where((e) => e.rating == Rating.again).toList();
    expect(again, hasLength(1));
    expect(again.single.facetId, first.facetId);
    expect(log.where((e) => !e.correct), hasLength(1));
    // The mistake is re-asked and recovered with Good (never Easy).
    final recovered = log.where((e) => e.facetId == first.facetId && e.correct).toList();
    expect(recovered, isNotEmpty);
    expect(recovered.first.rating, Rating.good);
    final mistakes = (await tester.runAsync(repo.mistakes))!;
    expect(mistakes.single.id, again.single.id);
    expect(mistakes.single.skillId, 'greetings');
    // Facet states follow the log.
    final states = (await tester.runAsync(() => repo.states(log.map((e) => e.facetId))))!;
    expect(states.keys.toSet(), log.map((e) => e.facetId).toSet());

    // Back on the map the skill shows progress.
    await tapKey(tester, 'summary-done');
    expect(find.byType(MapScreen), findsOneWidget);
    final node = tester.widget<SkillNode>(
      find.ancestor(of: find.byKey(const ValueKey('skill-node-greetings')), matching: find.byType(SkillNode)),
    );
    expect(node.stats.practiced, isTrue);
    expect(node.stats.tier.index, greaterThanOrEqualTo(MapTier.started.index));
    expect(find.byKey(const ValueKey('map-header')), findsOneWidget);
  });
}
