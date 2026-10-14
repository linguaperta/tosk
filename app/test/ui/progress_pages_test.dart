import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/progress/progress_screen.dart';
import 'package:tosk/ui/progress/verb_collection_screen.dart';
import 'package:tosk/ui/progression/progression_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<TestProgressStore> _seeded() async {
  final store = TestProgressStore();
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

void main() {
  testWidgets('map header shows level and streak; tapping it opens the progress page', (tester) async {
    await pumpApp(tester, store: await _seeded());
    expect(find.byKey(const ValueKey('map-header')), findsOneWidget);
    expect(find.byType(LevelBadge), findsOneWidget);
    expect(find.byType(StreakCounter), findsOneWidget);
    // Demo course, labelled.
    expect(find.byKey(const ValueKey('demo-badge')), findsOneWidget);
    await tapKey(tester, 'map-header');
    expect(find.byType(ProgressScreen), findsOneWidget);
  });

  testWidgets('progress page: profile, heatmap, challenges; verb collection from there and the nav', (tester) async {
    await pumpApp(tester, size: const Size(400, 1400), store: await _seeded());
    await goTab(tester, 'Progress');
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('progress-profile')), findsOneWidget);
    // Level and XP are the active course's; the streak section is account-wide.
    expect(find.byKey(const ValueKey('progress-course')), findsOneWidget);
    expect(find.textContaining('XP in Italian'), findsOneWidget);
    expect(find.text('Streak and daily goal · all courses'), findsOneWidget);
    expect(find.byKey(const ValueKey('progress-streak')), findsOneWidget);
    expect(find.byType(StreakHeatmap), findsOneWidget);
    expect(find.byType(ChallengesList), findsOneWidget);
    await tapKey(tester, 'open-verbs');
    expect(find.byType(VerbCollectionScreen), findsOneWidget);
    expect(find.byType(VerbCollectionView), findsOneWidget);
    expect(find.text('mangiare'), findsWidgets);
    // Back to the progress page via the nav.
    await goTab(tester, 'Progress');
    expect(find.byType(ProgressScreen), findsOneWidget);
  });

  testWidgets('tier badges on map nodes come from progression', (tester) async {
    await pumpApp(tester, store: await _seeded());
    expect(find.byType(TierBadge), findsWidgets);
  });

  testWidgets('non-stop start screen shows the best run after a run', (tester) async {
    await pumpApp(tester);
    await goTab(tester, 'Non-stop');
    expect(find.byKey(const ValueKey('nonstop-record-empty')), findsOneWidget);
    await tapKey(tester, 'nonstop-start');
    expect(find.byType(NonStopHud), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await answerCurrent(tester);
    }
    expect(tester.widget<NonStopHud>(find.byType(NonStopHud)).run.combo, 6);
    await tapKey(tester, 'nonstop-stop');
    await tapKey(tester, 'summary-done');
    expect(find.byKey(const ValueKey('nonstop-record')), findsOneWidget);
  });
}
