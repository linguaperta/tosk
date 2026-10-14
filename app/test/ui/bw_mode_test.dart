// Black & white (e-ink) mode: palette, forced reduced motion, and every screen
// and exercise type (with its feedback states) rendered without a single
// colored pixel. See bw_helpers.dart for the method.
import 'package:tosk/core/core.dart';
import 'package:tosk/progression/progression.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/demo/demo_seed.dart';
import 'package:tosk/ui/lesson/feedback_banner.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/progression/nonstop_hud.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/app_settings.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/theme/bw_skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'helpers.dart';

const bwSettings = {SettingKeys.display: 'bw'};

Future<TestProgressStore> bwStore({Map<String, String> extra = const {}}) async {
  final store = TestProgressStore(settings: {...bwSettings, ...extra});
  await seedDemoProgress(store, buildDemoItalian(), testNow);
  return store;
}

bool _isPalette(Color c) => c.a == 0 || kBwPalette.any((p) => p.toARGB32() == c.toARGB32());

void main() {
  overflowGroup();

  group('palette', () {
    test('every ColorScheme color is black, white or the one gray', () {
      final s = bwTheme().colorScheme;
      final colors = {
        'primary': s.primary,
        'onPrimary': s.onPrimary,
        'primaryContainer': s.primaryContainer,
        'onPrimaryContainer': s.onPrimaryContainer,
        'primaryFixed': s.primaryFixed,
        'primaryFixedDim': s.primaryFixedDim,
        'onPrimaryFixed': s.onPrimaryFixed,
        'onPrimaryFixedVariant': s.onPrimaryFixedVariant,
        'secondary': s.secondary,
        'onSecondary': s.onSecondary,
        'secondaryContainer': s.secondaryContainer,
        'onSecondaryContainer': s.onSecondaryContainer,
        'secondaryFixed': s.secondaryFixed,
        'secondaryFixedDim': s.secondaryFixedDim,
        'onSecondaryFixed': s.onSecondaryFixed,
        'onSecondaryFixedVariant': s.onSecondaryFixedVariant,
        'tertiary': s.tertiary,
        'onTertiary': s.onTertiary,
        'tertiaryContainer': s.tertiaryContainer,
        'onTertiaryContainer': s.onTertiaryContainer,
        'tertiaryFixed': s.tertiaryFixed,
        'tertiaryFixedDim': s.tertiaryFixedDim,
        'onTertiaryFixed': s.onTertiaryFixed,
        'onTertiaryFixedVariant': s.onTertiaryFixedVariant,
        'error': s.error,
        'onError': s.onError,
        'errorContainer': s.errorContainer,
        'onErrorContainer': s.onErrorContainer,
        'surface': s.surface,
        'onSurface': s.onSurface,
        'surfaceDim': s.surfaceDim,
        'surfaceBright': s.surfaceBright,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
        'onSurfaceVariant': s.onSurfaceVariant,
        'outline': s.outline,
        'outlineVariant': s.outlineVariant,
        'shadow': s.shadow,
        'scrim': s.scrim,
        'inverseSurface': s.inverseSurface,
        'onInverseSurface': s.onInverseSurface,
        'inversePrimary': s.inversePrimary,
        'surfaceTint': s.surfaceTint,
      };
      for (final e in colors.entries) {
        expect(_isPalette(e.value), isTrue, reason: '${e.key} = ${e.value}');
      }
      expect(isMonochrome(s), isTrue);
    });

    test('ThemeData colors, no splashes, no shadows, 2 px borders', () {
      final t = bwTheme();
      final colors = {
        'scaffold': t.scaffoldBackgroundColor,
        'canvas': t.canvasColor,
        'card': t.cardColor,
        'divider': t.dividerColor,
        'disabled': t.disabledColor,
        'hint': t.hintColor,
        'highlight': t.highlightColor,
        'splash': t.splashColor,
        'hover': t.hoverColor,
        'focus': t.focusColor,
        'shadow': t.shadowColor,
        'primaryColor': t.primaryColor,
        'unselected': t.unselectedWidgetColor,
        'secondaryHeader': t.secondaryHeaderColor,
        'appBar': t.appBarTheme.backgroundColor!,
        'cardTheme': t.cardTheme.color!,
        'sheet': t.bottomSheetTheme.backgroundColor!,
        'sheetBarrier': t.bottomSheetTheme.modalBarrierColor!,
        'dialog': t.dialogTheme.backgroundColor!,
        'dialogBarrier': t.dialogTheme.barrierColor!,
        'navBar': t.navigationBarTheme.backgroundColor!,
        'navIndicator': t.navigationBarTheme.indicatorColor!,
        'progress': t.progressIndicatorTheme.color!,
        'progressTrack': t.progressIndicatorTheme.linearTrackColor!,
        'fab': t.floatingActionButtonTheme.backgroundColor!,
        'chip': t.chipTheme.backgroundColor!,
        'chipSelected': t.chipTheme.selectedColor!,
      };
      for (final e in colors.entries) {
        expect(_isPalette(e.value), isTrue, reason: '${e.key} = ${e.value}');
      }
      for (final c in [t.highlightColor, t.splashColor, t.hoverColor, t.shadowColor]) {
        expect(c.a, 0);
      }
      expect(t.splashFactory, NoSplash.splashFactory);
      expect(t.cardTheme.elevation, 0);
      expect((t.cardTheme.shape! as RoundedRectangleBorder).side.width, greaterThanOrEqualTo(2));
      expect(t.chipTheme.side!.width, greaterThanOrEqualTo(2));
      expect(t.floatingActionButtonTheme.elevation, 0);
      expect(t.textTheme.bodyMedium!.color, kBwBlack);
      // Gray is AA on white (4.5:1).
      double lum(Color c) => c.computeLuminance();
      expect((lum(kBwWhite) + 0.05) / (lum(kBwGray) + 0.05), greaterThanOrEqualTo(4.5));
    });
  });

  testWidgets('black & white forces reduced motion but keeps haptics and sounds', (tester) async {
    await pumpApp(tester, store: TestProgressStore(settings: bwSettings));
    final c = ProviderScope.containerOf(tester.element(find.byKey(appRootKey)));
    expect(c.read(bwProvider), isTrue);
    expect(c.read(reduceMotionProvider), isTrue);
    expect(c.read(motionProvider).reduced, isTrue);
    expect(c.read(fxProvider).enabled, isTrue);
    expect(c.read(themeModeProvider), ThemeMode.light);
    expect(isMonochrome(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme), isTrue);
  });

  testWidgets('settings: Display switches to black & white and persists', (tester) async {
    final store = await pumpApp(tester, initialLocation: Routes.settings);
    await tapKey(tester, 'setting-display-Black & white');
    expect(store.settings[SettingKeys.display], 'bw');
    expect(find.byKey(const ValueKey('setting-theme')), findsNothing); // always light
    await expectGrayscale(tester, 'settings');
    final c = ProviderScope.containerOf(tester.element(find.byKey(appRootKey)));
    expect((await c.read(settingsProvider.future)).display, DisplayMode.bw);
  });

  testWidgets('map, skill sheet, progress, verbs, mistakes, lab, non-stop, settings, debug', (tester) async {
    final store = await bwStore();
    await pumpApp(tester, store: store, size: const Size(400, 900));
    await expectGrayscale(tester, 'map');
    final node = find.byKey(const ValueKey('skill-node-present-are'));
    await tester.ensureVisible(node);
    await tester.pumpAndSettle();
    await tester.longPress(node);
    await tester.pumpAndSettle();
    await expectGrayscale(tester, 'skill sheet');
    // No dimming overlay behind the sheet: the map's margin stays pure white.
    expect((await pixelAt(tester, const Offset(1, 150))).toARGB32(), 0xFFFFFFFF);
    final sheet = find.descendant(of: find.byType(SkillSheet), matching: find.byType(Scrollable)).first;
    await tester.drag(sheet, const Offset(0, -600));
    await expectGrayscale(tester, 'skill sheet (note)');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    for (final tab in ['Lab', 'Non-stop', 'Progress', 'Settings']) {
      await goTab(tester, tab);
      await expectGrayscale(tester, tab);
    }
    await goTab(tester, 'Progress');
    await tester.drag(find.byKey(const ValueKey('progress-list')), const Offset(0, -700));
    await expectGrayscale(tester, 'progress (scrolled)');
    await tester.drag(find.byKey(const ValueKey('progress-list')), const Offset(0, -1400));
    await expectGrayscale(tester, 'progress (badges)');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-verbs')),
      -300,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('progress-list')), matching: find.byType(Scrollable))
          .first,
    );
    await tapKey(tester, 'open-verbs');
    await expectGrayscale(tester, 'verb collection');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await goTab(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-debug')),
      300,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('settings-list')), matching: find.byType(Scrollable))
          .first,
    );
    await expectGrayscale(tester, 'settings (bottom)');
    await tapKey(tester, 'open-debug');
    await expectGrayscale(tester, 'debug');
  });

  for (final type in ExerciseType.values) {
    testWidgets('exercise ${type.id}: draft, wrong feedback, retry right, summary', (tester) async {
      await pumpApp(
        tester,
        store: TestProgressStore(settings: bwSettings),
        initialLocation: Routes.labPlay(
          skills: buildDemoItalian().skills.map((s) => s.id).toList(),
          types: [type],
          length: 1,
        ),
      );
      await expectGrayscale(tester, '${type.id} (new)');
      await answerWithoutContinue(tester, wrong: true);
      await expectGrayscale(tester, '${type.id} (wrong)');
      if (find.byKey(const ValueKey('continue-button')).evaluate().isNotEmpty) await tapKey(tester, 'continue-button');
      while (find.byKey(const ValueKey('session-summary')).evaluate().isEmpty) {
        await answerWithoutContinue(tester);
        await expectGrayscale(tester, '${type.id} (right)');
        if (find.byKey(const ValueKey('continue-button')).evaluate().isNotEmpty) {
          await tapKey(tester, 'continue-button');
        }
      }
      await expectGrayscale(tester, '${type.id} summary');
    });
  }

  testWidgets('feedback panel: accent slip and actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bwTheme(),
        home: const RepaintBoundary(
          key: appRootKey,
          child: Scaffold(
            bottomNavigationBar: FeedbackBanner(
              result: Result(correct: true, expected: 'perché', given: 'perche', outcomes: [], accentSlip: true),
              onContinue: _noop,
              onWhy: _noop,
              reduceMotion: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('feedback-accent')), findsOneWidget);
    await expectGrayscale(tester, 'accent slip');
  });

  testWidgets('non-stop HUD with combo and bonus round', (tester) async {
    var run = const NonStopRun();
    final ex = const MultipleChoiceExercise(
      id: 'x',
      facetId: 'it:ciao#rec',
      instruction: '',
      prompt: 'ciao',
      options: ['hi', 'no'],
      correctIndex: 0,
      direction: Direction.recognize,
    );
    const ok = Result(correct: true, expected: 'hi', given: 'hi', outcomes: []);
    for (var i = 0; i < 26; i++) {
      run = run.applyResult(ex, ok, at: testNow.add(Duration(seconds: i * 5)));
    }
    expect(run.bonusRound, isNotNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: bwTheme(),
        home: RepaintBoundary(
          key: appRootKey,
          child: Scaffold(body: NonStopHud(run: run, reduceMotion: true)),
        ),
      ),
    );
    await expectGrayscale(tester, 'non-stop HUD');
  });

  testWidgets('mistakes list', (tester) async {
    final store = await bwStore();
    await store.saveMistake(
      MistakeRecord(
        id: 'm1',
        facetId: 'it:mangiare#form:presente',
        at: testNow.subtract(const Duration(hours: 3)),
        exerciseType: 'conj_pick',
        prompt: 'Pick the right ending: mang___',
        expected: 'mangiamo',
        given: 'mangiate',
        skillId: 'present-are',
      ),
    );
    await pumpApp(tester, store: store, initialLocation: Routes.mistakes);
    expect(find.byKey(const ValueKey('mistakes-list')), findsOneWidget);
    await expectGrayscale(tester, 'mistakes');
  });
}

/// Phone, small phone, 6" and 7" e-readers (Boox Poke / Page at 300 dpi), the
/// 10.3" Boox Note Air (1404 x 1872 at 226 dpi), tablet and desktop, in logical pixels.
const bwSizes = {
  'phone 360x640': Size(360, 640),
  'small phone 320x568': Size(320, 568),
  'e-reader 6in 572x772': Size(572, 772),
  'e-reader 7in 674x896': Size(674, 896),
  'Boox 10.3in 1003x1337': Size(1003, 1337),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1280x800': Size(1280, 800),
};

/// Layout (no overflow) and grayscale at every size, every exercise type.
void overflowGroup() {
  final allSkills = buildDemoItalian().skills.map((s) => s.id).toList();
  for (final entry in bwSizes.entries) {
    group('black & white ${entry.key}', () {
      testWidgets('screens', (tester) async {
        await pumpApp(tester, size: entry.value, store: await bwStore());
        await expectGrayscale(tester, 'map');
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byKey(const ValueKey('map-scroll')), const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        for (final tab in ['Lab', 'Non-stop', 'Settings', 'Progress']) {
          await tester.tap(find.text(tab).first);
          await tester.pumpAndSettle();
        }
        await expectGrayscale(tester, 'progress');
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byKey(const ValueKey('progress-list')), const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });

      for (final type in ExerciseType.values) {
        testWidgets('player: ${type.id}', (tester) async {
          await pumpApp(
            tester,
            size: entry.value,
            store: TestProgressStore(settings: bwSettings),
            initialLocation: Routes.labPlay(skills: allSkills, types: [type], length: 1),
          );
          await answerCurrent(tester, wrong: true);
          await playToSummary(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}

void _noop() {}

/// Answers the current exercise and checks it, without continuing past the feedback.
Future<void> answerWithoutContinue(WidgetTester tester, {bool wrong = false}) async {
  final ex = currentExercise(tester);
  if (ex is FlashcardExercise || ex is MatchPairsExercise) {
    // Self-submitting: answerCurrent leaves no banner to look at.
    await answerCurrent(tester, wrong: wrong);
    return;
  }
  await answerCurrentNoContinue(tester, wrong: wrong);
}
