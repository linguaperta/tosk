// Exploratory QA walkthrough on the real bundled packs, with real fonts, that
// saves a PNG of every step. Not part of the default suite (no `_test` suffix):
//
//   QA_OUT=/path/to/dir flutter test test/qa/qa_walkthrough.dart
//
// Then look at the screenshots. Layout errors (overflows) still fail the run.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:tosk/app.dart';
import 'package:tosk/app_bootstrap.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/app_data.dart';
import 'package:tosk/data/course/course_bytes.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/data/packs/pack_file_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
import 'package:tosk/engine/engine.dart' show FocusPresets;
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/lesson/exercises/exercise_view.dart';
import 'package:tosk/ui/map/skill_sheet.dart';
import 'package:tosk/ui/pack_course_catalog.dart';
import 'package:tosk/ui/router.dart';
import 'package:tosk/ui/routes.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tosk/ui/course_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../app/app_fixture.dart' show MapBundledPacks;
import '../fixtures/big_map_course.dart';
import '../ui/helpers.dart' show answerCurrent, currentExercise, goTab, setSurface, tapKey, testNow;

final _out = Directory(Platform.environment['QA_OUT'] ?? 'build/qa');
const _root = ValueKey('qa-root');

Future<void> loadQaFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/timo/dev/flutter';
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async => ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final n in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
    'roboto-light.ttf',
    'roboto-mediumitalic.ttf',
  ]) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'))).load();
}

AppData _realPacks(ProgressRepo progress) {
  Uint8List bytes(String id) => File('assets/courses/$id.sqlite').readAsBytesSync();
  return AppData(
    progress: progress,
    packs: LocalPackSource(
      bundled: MapBundledPacks({'assets/courses/it.sqlite': bytes('it'), 'assets/courses/nl.sqlite': bytes('nl')}),
      store: MemoryPackFileStore(),
      readMeta: (d) async => readCourseMetaFromBytes(sqlite3, (d as PackBytes).bytes),
    ),
    loadPack: (d) async => loadCourseRepoFromBytes(sqlite3, (d as PackBytes).bytes),
  );
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _out.createSync(recursive: true);
    File('${_out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<ProgressRepo> pumpReal(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Map<String, String> settings = const {},
  String? location,
  double textScale = 1,
  CourseCatalog? catalog,
}) async {
  setSurface(tester, size);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final repo = ProgressRepo(ProgressDb(NativeDatabase.memory()));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(repo.close);
  });
  // Both courses added (the course picker opens on a fresh profile otherwise).
  for (final e in {'courses.added': 'it,nl', ...settings}.entries) {
    await repo.setSetting(e.key, e.value);
  }
  final app = _realPacks(repo);
  final boot = AppBoot(
    app: app,
    catalog: PackCourseCatalog(app, fallback: DemoCourseCatalog()),
    demoMode: false,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _root,
      child: ProviderScope(
        retry: (_, _) => null,
        overrides: [
          appDataProvider.overrideWithValue(app),
          progressStoreProvider.overrideWithValue(app.progress),
          courseCatalogProvider.overrideWithValue(catalog ?? boot.catalog),
          clockProvider.overrideWithValue(() => testNow),
          calendarProvider.overrideWithValue(LocalCalendar.utc),
          // The asset bundle caches its first load in another test's zone; the
          // embedded defaults equal the JSON asset.
          focusPresetsProvider.overrideWith((ref) async => FocusPresets.defaults),
          if (location != null) routerProvider.overrideWith((ref) => buildRouter(initialLocation: location)),
        ],
        child: const ToskApp(),
      ),
    ),
  );
  await settleReal(tester, until: find.byKey(const ValueKey('map-scroll')));
  return repo;
}

/// Pumps with real async gaps (asset and database futures) until [until] shows.
Future<void> settleReal(WidgetTester tester, {required Finder until}) async {
  for (var i = 0; i < 200 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (until.evaluate().isEmpty) {
    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ');
    fail('Not shown: $until. On screen: $texts');
  }
  await tester.pumpAndSettle();
}

bool get _done => find.byKey(const ValueKey('session-summary')).evaluate().isNotEmpty;

/// Plays the current session to the summary, screenshotting each exercise
/// (answered wrong first when [wrongEvery] divides its index) and its feedback.
Future<void> playAndShoot(WidgetTester tester, String prefix, {int wrongEvery = 3, int cap = 40}) async {
  for (var i = 0; i < cap && !_done; i++) {
    final ex = currentExercise(tester);
    final tag = '$prefix-${i.toString().padLeft(2, '0')}-${ex.type.id}';
    await shot(tester, tag);
    final wrong = wrongEvery > 0 && i % wrongEvery == 1 && ex.type != ExerciseType.flashcard;
    await answerWithFeedbackShot(tester, tag, wrong: wrong);
  }
  await shot(tester, '$prefix-summary');
}

/// Like `answerCurrent`, with a screenshot of the feedback banner before Continue.
Future<void> answerWithFeedbackShot(WidgetTester tester, String tag, {bool wrong = false}) async {
  final ex = currentExercise(tester);
  if (ex is FlashcardExercise || ex is MatchPairsExercise) {
    await answerCurrent(tester, wrong: wrong);
    return;
  }
  // answerCurrent taps Continue at the end; intercept by answering via a copy
  // of its logic up to Check: simplest is to answer, but take the shot first
  // by checking without continuing.
  await answerCurrentNoContinue(tester, wrong: wrong);
  await shot(tester, '$tag-feedback');
  await tapKey(tester, 'continue-button');
}

Future<void> answerCurrentNoContinue(WidgetTester tester, {bool wrong = false}) async {
  // Re-use answerCurrent by temporarily hiding Continue is not possible; replicate
  // the selection part for the types that use the Check button.
  final ex = currentExercise(tester);
  Future<void> check() => tapKey(tester, 'check-button');
  int free(List<String> tiles, String w, Set<int> used) {
    for (var t = 0; t < tiles.length; t++) {
      if (!used.contains(t) && tiles[t] == w) return t;
    }
    throw StateError('No tile "$w" in $tiles');
  }

  switch (ex) {
    case MultipleChoiceExercise e:
      await tapKey(tester, 'option-${wrong ? (e.correctIndex + 1) % e.options.length : e.correctIndex}');
    case ConjPickExercise e:
      await tapKey(tester, 'ending-${wrong ? (e.correctIndex + 1) % e.endings.length : e.correctIndex}');
    case ConjGridExercise e:
      final used = <int>{};
      final asked = [
        for (var i = 0; i < e.cells.length; i++)
          if (!e.cells[i].prefilled) i,
      ];
      final words = [for (final i in asked) e.cells[i].expected];
      if (wrong && words.length > 1) words.setAll(0, [words[1], words[0]]);
      for (var k = 0; k < asked.length; k++) {
        final t = free(e.tiles, words[k], used);
        used.add(t);
        await tapKey(tester, 'grid-cell-${asked[k]}');
        await tapKey(tester, 'grid-tile-$t');
      }
    case SentenceBuilderExercise(:final tiles, :final answers) || TransformExercise(:final tiles, :final answers):
      final used = <int>{};
      final words = List.of(answers.first);
      if (wrong) words.removeLast();
      for (final w in words) {
        final t = free(tiles, w, used);
        used.add(t);
        await tapKey(tester, 'tile-$t');
      }
    case ClozeExercise e:
      if (e.options != null) {
        await tapKey(tester, 'cloze-option-${wrong ? (e.correctIndex! + 1) % e.options!.length : e.correctIndex}');
      } else {
        await tester.enterText(find.byKey(const ValueKey('answer-input')), wrong ? 'xyz' : e.expected);
      }
    case SpotErrorExercise e:
      await tapKey(tester, 'token-${wrong ? (e.errorIndex == 0 ? 1 : 0) : e.errorIndex}');
    default:
      throw StateError('self-submitting');
  }
  await check();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(loadQaFonts);
  // Note: flutter_test draws elevation shadows as solid black outlines
  // (debugDisableShadows); a thick black border around a FAB is that.

  for (final variant in ['it', 'nl', 'bw']) {
    final course = variant == 'bw' ? 'it' : variant;
    final settings = {SettingKeys.course: course, if (variant == 'bw') SettingKeys.display: 'bw'};
    testWidgets('$variant: map, sheet, lesson, lab per type, progress, mistakes, settings', (tester) async {
      await pumpReal(tester, settings: settings);
      await shot(tester, '$variant-01-map');
      final mapScroll = find.byKey(const ValueKey('map-scroll'));
      await tester.drag(mapScroll, const Offset(0, -600));
      await shot(tester, '$variant-02-map-scrolled');
      await tester.drag(mapScroll, const Offset(0, 3000));
      await tester.pumpAndSettle();

      final course0 = (await tester.runAsync(
        () async => ProviderScope.containerOf(tester.element(mapScroll)).read(courseDataProvider.future),
      ))!;
      final first = course0.skills.first;
      final grammar = course0.skills.firstWhere((s) => s.kind != SkillKind.vocab, orElse: () => first);
      await tester.longPress(find.byKey(ValueKey('skill-node-${grammar.id}')));
      await shot(tester, '$variant-03-sheet');
      final sheet = find.descendant(of: find.byType(SkillSheet), matching: find.byType(Scrollable)).first;
      await tester.drag(sheet, const Offset(0, -500));
      await shot(tester, '$variant-04-sheet-scrolled');
      await tester.drag(sheet, const Offset(0, -1500));
      await shot(tester, '$variant-05-sheet-items');
      await tester.tapAt(const Offset(200, 10));
      await tester.pumpAndSettle();

      // A lesson on the first skill.
      await tapKey(tester, 'skill-node-${first.id}');
      await playAndShoot(tester, '$variant-10-lesson');
      await tapKey(tester, 'summary-done');
      await shot(tester, '$variant-11-map-after');
      expect(tester.takeException(), isNull);
    });

    for (final type in ExerciseType.values) {
      testWidgets('$variant: lab ${type.id}', (tester) async {
        final container = await pumpReal(tester, settings: settings);
        final c = (await tester.runAsync(
          () => ProviderScope.containerOf(tester.element(find.byType(ToskApp))).read(courseDataProvider.future),
        ))!;
        container.toString();
        final router = ProviderScope.containerOf(tester.element(find.byType(ToskApp))).read(routerProvider);
        router.go(Routes.labPlay(skills: [for (final s in c.skills) s.id], types: [type], length: 3));
        await settleReal(
          tester,
          until: find.byWidgetPredicate((w) => w is ExerciseView || w.key == const ValueKey('player-empty')),
        );
        if (find.byType(ExerciseView).evaluate().isEmpty) {
          await shot(tester, '$variant-20-lab-${type.id}-empty');
          return;
        }
        await playAndShoot(tester, '$variant-20-lab-${type.id}', wrongEvery: 2);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (p, size, settings) in const [
    ('it', Size(400, 800), {SettingKeys.course: 'it'}),
    ('bw', Size(400, 800), {SettingKeys.course: 'it', SettingKeys.display: 'bw'}),
    ('boox', Size(1003, 1337), {SettingKeys.course: 'nl', SettingKeys.display: 'bw'}),
    ('poke', Size(572, 772), {SettingKeys.course: 'it', SettingKeys.display: 'bw', SettingKeys.sourceLang: 'nl'}),
  ]) {
    testWidgets('$p: lesson, summary, map, sheet, progress, verbs, mistakes, settings, lab, non-stop', (tester) async {
      await pumpReal(tester, size: size, settings: settings);
      final first = find.byKey(const ValueKey('map-scroll'));
      expect(first, findsOneWidget);
      await shot(tester, '$p-29-map-fresh');
      final c = (await tester.runAsync(
        () => ProviderScope.containerOf(tester.element(first)).read(courseDataProvider.future),
      ))!;
      await tapKey(tester, 'skill-node-${c.skills.first.id}');
      if (p == 'it') {
        for (var i = 0; i < 40 && !_done; i++) {
          await answerCurrent(tester, wrong: i % 3 == 1);
        }
      } else {
        await playAndShoot(tester, '$p-10-lesson');
      }
      await shot(tester, '$p-30-summary');
      await tapKey(tester, 'summary-done');
      await shot(tester, '$p-31-map-with-mistakes');
      await tester.tap(find.text('Progress').first);
      await tester.pumpAndSettle();
      await shot(tester, '$p-32-progress');
      await tester.drag(find.byKey(const ValueKey('progress-list')), const Offset(0, -700));
      await shot(tester, '$p-33-progress-scrolled');
      await tester.drag(find.byKey(const ValueKey('progress-list')), const Offset(0, 2000));
      await tester.pumpAndSettle();
      final progressScroll = find
          .descendant(of: find.byKey(const ValueKey('progress-list')), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('open-mistakes')), 200, scrollable: progressScroll);
      await tapKey(tester, 'open-mistakes');
      await shot(tester, '$p-34-mistakes');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('open-verbs')), -200, scrollable: progressScroll);
      await tapKey(tester, 'open-verbs');
      await shot(tester, '$p-35-verbs');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await goTab(tester, 'Settings');
      await shot(tester, '$p-36-settings');
      await goTab(tester, 'Lab');
      await shot(tester, '$p-37-lab');
      await goTab(tester, 'Non-stop');
      await shot(tester, '$p-38-nonstop-start');
      await goTab(tester, 'Lookup');
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), c.meta.id == 'it' ? 'mangiamo' : 'gegeten');
      await tester.pumpAndSettle();
      await shot(tester, '$p-40-lookup');
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await shot(tester, '$p-41-word');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await goTab(tester, 'Grammar');
      await shot(tester, '$p-42-grammar');
      await goTab(tester, 'Map');
      await tapKey(tester, 'course-switcher');
      await tapKey(tester, 'manage-courses');
      await tapKey(tester, 'course-preview-${c.meta.id}');
      await shot(tester, '$p-43-course-picker');
      await tapKey(tester, 'course-picker-done');
      final grammar = c.skills.where((s) => s.kind == SkillKind.grammar).first;
      await tester.longPress(find.byKey(ValueKey('skill-node-${grammar.id}')));
      await tester.pumpAndSettle();
      await shot(tester, '$p-39-sheet');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dark, 320 px, text 1.3: map and a lesson (nl, source nl)', (tester) async {
    await pumpReal(
      tester,
      size: const Size(320, 640),
      textScale: 1.3,
      settings: {SettingKeys.course: 'nl', SettingKeys.themeMode: 'dark', SettingKeys.sourceLang: 'nl'},
    );
    await shot(tester, 'dark-01-map');
    final mapScroll = find.byKey(const ValueKey('map-scroll'));
    final c = (await tester.runAsync(
      () => ProviderScope.containerOf(tester.element(mapScroll)).read(courseDataProvider.future),
    ))!;
    await tester.drag(mapScroll, const Offset(0, -500));
    await shot(tester, 'dark-02-map-scrolled');
    await tester.drag(mapScroll, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tapKey(tester, 'skill-node-${c.skills.first.id}');
    await playAndShoot(tester, 'dark-10-lesson');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop 1280x800: map and a lesson (it, source nl)', (tester) async {
    await pumpReal(
      tester,
      size: const Size(1280, 800),
      settings: {SettingKeys.course: 'it', SettingKeys.sourceLang: 'nl'},
    );
    await shot(tester, 'desk-01-map');
    final mapScroll = find.byKey(const ValueKey('map-scroll'));
    final c = (await tester.runAsync(
      () => ProviderScope.containerOf(tester.element(mapScroll)).read(courseDataProvider.future),
    ))!;
    final grammar = c.skills.where((s) => s.kind != SkillKind.vocab).toList();
    await tapKey(tester, 'skill-node-${grammar.length > 1 ? grammar[1].id : c.skills.first.id}');
    if (find.byKey(const ValueKey('start-lesson')).evaluate().isNotEmpty) {
      await shot(tester, 'desk-02-locked-sheet');
      await tapKey(tester, 'start-lesson');
    }
    await playAndShoot(tester, 'desk-10-lesson');
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, scale) in const [
    ('320', Size(320, 640), 1.0),
    ('400', Size(400, 800), 1.3),
    ('1280', Size(1280, 800), 1.0),
  ]) {
    testWidgets('big map (30 skills) at $name', (tester) async {
      await pumpReal(tester, size: size, textScale: scale, catalog: BigCourseCatalog());
      final mapScroll = find.byKey(const ValueKey('map-scroll'));
      for (var i = 0; i < 8; i++) {
        await shot(tester, 'big-$name-$i');
        await tester.drag(mapScroll, Offset(0, -size.height * 0.8));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
