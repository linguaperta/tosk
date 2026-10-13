// Layout smoke tests: every screen and every exercise type at phone, small-phone,
// tablet and desktop sizes. Any RenderFlex overflow or other layout error fails
// the test (golden-free).
import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const sizes = {
  'phone 360x640': Size(360, 640),
  'small phone 320x568': Size(320, 568),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1280x800': Size(1280, 800),
};

Future<TestProgressStore> seeded({Map<String, String> settings = const {}}) async {
  final store = TestProgressStore(settings: settings);
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

Future<void> scrollThrough(WidgetTester tester, Finder scrollable) async {
  for (var i = 0; i < 8; i++) {
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
}

void main() {
  final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();

  for (final entry in sizes.entries) {
    final size = entry.value;
    group(entry.key, () {
      testWidgets('map, skill sheet, lab, non-stop, settings', (tester) async {
        await pumpApp(tester, size: size, store: await seeded());
        await scrollThrough(tester, find.byKey(const ValueKey('map-scroll')));

        // Skill sheet with note + table + verb forms.
        await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, 3000));
        await tester.pumpAndSettle();
        final node = find.byKey(const ValueKey('skill-node-present-are'));
        await tester.ensureVisible(node);
        await tester.pumpAndSettle();
        await tester.longPress(node);
        await tester.pumpAndSettle();
        final sheet = find.descendant(of: find.byType(SkillSheet), matching: find.byType(Scrollable)).first;
        await scrollThrough(tester, sheet);
        await tester.tapAt(const Offset(10, 10)); // dismiss
        await tester.pumpAndSettle();

        for (final tab in ['Lab', 'Non-stop', 'Settings']) {
          await tester.tap(find.text(tab).first);
          await tester.pumpAndSettle();
        }
        await scrollThrough(tester, find.byKey(const ValueKey('settings-list')));
        await tester.tap(find.text('Lab').first);
        await tester.pumpAndSettle();
        await tapKey(tester, 'lab-unit-u1');
        await tapKey(tester, 'lab-unit-u2');
        await scrollThrough(tester, find.byKey(const ValueKey('lab-list')));
        expect(tester.takeException(), isNull);
      });

      testWidgets('dark theme, Dutch (unverified) course map', (tester) async {
        await pumpApp(
          tester,
          size: size,
          store: TestProgressStore(settings: {SettingKeys.themeMode: 'dark', SettingKeys.course: 'nl'}),
        );
        expect(find.byKey(const ValueKey('unverified-badge')), findsOneWidget);
        await scrollThrough(tester, find.byKey(const ValueKey('map-scroll')));
        expect(tester.takeException(), isNull);
      });

      for (final type in ExerciseType.values) {
        testWidgets('player: ${type.id} (wrong, retry, summary)', (tester) async {
          await pumpApp(
            tester,
            size: size,
            initialLocation: Routes.labPlay(skills: allSkills, types: [type], length: 1),
          );
          expect(currentExercise(tester).type, type);
          await answerCurrent(tester, wrong: true);
          await playToSummary(tester);
          expect(find.text('To review'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('non-stop player and text scale 1.3', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(tester, size: size, initialLocation: Routes.nonstopPlay);
        for (var i = 0; i < 12; i++) {
          await answerCurrent(tester, wrong: i.isEven);
        }
        await tapKey(tester, 'nonstop-stop');
        expect(find.text('Run finished'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
