import 'package:drift/native.dart';
import 'package:tosk/app.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/debug/debug_screen.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/helpers.dart';
import 'app_fixture.dart';

void main() {
  testWidgets('/debug opens the data layer DebugScreen over the app data', (tester) async {
    final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
    addTearDown(() => tester.runAsync(repo.close));
    final app = fixtureAppData(repo);
    await tester.runAsync(() => repo.setSetting(SettingKeys.welcomeDone, 'true'));
    setSurface(tester, const Size(420, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...fixtureBoot(app).overrides,
          clockProvider.overrideWithValue(() => testNow),
          routerProvider.overrideWith((ref) => buildRouter(initialLocation: Routes.settings)),
        ],
        child: const ToskApp(),
      ),
    );
    await tester.pumpAndSettle();
    // A fresh profile: the course picker opens first; Done adds the course shown.
    expect(find.byKey(const ValueKey('course-picker')), findsOneWidget);
    await tapKey(tester, 'course-picker-done');
    expect(find.byKey(const ValueKey('course-picker')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-debug')),
      300,
      scrollable: find.descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable)),
    );
    await tapKey(tester, 'open-debug');
    expect(find.byType(DebugScreen), findsOneWidget);
    expect(find.text('Data debug'), findsOneWidget);
    expect(find.textContaining('(it) v'), findsWidgets);

    // Leaving it refreshes what the app derived from packs and progress.
    final container = ProviderScope.containerOf(tester.element(find.byType(ToskApp)));
    final rev = container.read(progressRevisionProvider);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DebugScreen), findsNothing);
    expect(container.read(progressRevisionProvider), rev + 1);
  });
}
