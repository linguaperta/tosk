import 'dart:io';

import 'package:tosk/app.dart';
import 'package:tosk/app_bootstrap.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/bootstrap.dart';
import 'package:tosk/data/packs/local_pack_source.dart';
import 'package:tosk/engine/engine.dart';
import 'package:tosk/progression/calendar.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/course_fixture.dart';
import '../ui/helpers.dart';
import 'app_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // drift_flutter asks path_provider for a temp folder (for SQLite's temp files).
  setUpAll(() {
    final tmp = Directory.systemTemp.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp,
    );
  });

  test('no packs: demo courses with their own seeded progress DB; settings survive a restart', () async {
    final dir = tempDir('tosk_boot_demo');
    final options = AppDataOptions(dataDirectory: dir.path, bundled: const NoBundledPacks());

    final boot = await bootApp(options: options, clock: () => testNow);
    expect(boot.demoMode, isTrue);
    expect(File('${dir.path}/progress$demoProgressDbSuffix.sqlite').existsSync(), isTrue);
    final seeded = await boot.app.progress.logCount();
    expect(seeded, greaterThan(0));

    var container = ProviderContainer.test(overrides: boot.overrides);
    expect((await container.read(availableCoursesProvider.future)).map((c) => c.id), ['it', 'nl']);
    expect(container.read(courseCatalogProvider).isDemo('it'), isTrue);
    await container.read(settingsProvider.future);
    await container
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(themeMode: ThemeMode.dark, reduceMotion: true, courseId: 'nl', sourceLang: 'nl'));
    container.dispose();
    await boot.close();

    // Restart on the same folder: same DB, settings read back, no second seeding.
    final again = await bootApp(options: options, clock: () => testNow.add(const Duration(days: 3)));
    addTearDown(again.close);
    expect(again.demoMode, isTrue);
    expect(await again.app.progress.logCount(), seeded);
    container = ProviderContainer.test(overrides: again.overrides);
    final s = await container.read(settingsProvider.future);
    expect(s.themeMode, ThemeMode.dark);
    expect(s.reduceMotion, isTrue);
    expect(s.courseId, 'nl');
    expect(s.sourceLang, 'nl');
    expect(await container.read(activeCourseIdProvider.future), 'nl');
    expect(container.read(activeCourseIsDemoProvider), isTrue);
  });

  test('a Dutch-only pack copied into courses/ is listed; an English setting falls back to Dutch', () async {
    // How the locally built Sarnami pack is loaded on desktop (docs/sarnami.md).
    final dir = tempDir('tosk_boot_dropped');
    Directory('${dir.path}/courses').createSync();
    writeFixtureCourseFile('${dir.path}/courses/hns.sqlite', overrideMeta: {
      'course_id': 'hns',
      'target': 'hns',
      'title': '{"nl":"Sarnami"}',
      'translations': '["nl"]',
      'unverified': '1',
    });
    final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path, bundled: fixtureBundledPacks()));
    addTearDown(boot.close);
    final container = ProviderContainer.test(overrides: boot.overrides);
    final courses = await container.read(availableCoursesProvider.future);
    expect(courses.map((c) => c.id), ['hns', 'it']);
    expect(courses.first.unverified, isTrue);

    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).change((s) => s.copyWith(courseId: 'hns', sourceLang: 'en'));
    final course = await container.read(courseDataProvider.future);
    expect(course.meta.id, 'hns');
    expect(container.read(sourceLangProvider), 'nl');
    expect(container.read(sessionOptionsProvider).sourceLang, 'nl');
    // The setting itself is kept, so Italian goes back to English.
    expect((await container.read(settingsProvider.future)).sourceLang, 'en');
    final factory = await container.read(sessionFactoryProvider.future);
    expect(await (await factory.lesson(course.skills.first.id)).next(), isNotNull);
  });

  test('web pack mirror: no bundled pack is read; the real progress DB from the first visit', () async {
    final dir = tempDir('tosk_boot_web_mirror');
    final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path, webPackMirror: true));
    addTearDown(boot.close);
    // Nothing installed yet (the learner downloads from the picker), still
    // the normal, unseeded progress database: picks and answers made before
    // the next reload are kept.
    expect(boot.demoMode, isFalse);
    expect(await boot.app.availableCourses(), isEmpty);
    expect(await boot.app.progress.logCount(), 0);
    expect(File('${dir.path}/progress.sqlite').existsSync(), isTrue);
    expect(File('${dir.path}/progress$demoProgressDbSuffix.sqlite').existsSync(), isFalse);
    // The demo course fills the map until a pack is downloaded.
    final container = ProviderContainer.test(overrides: boot.overrides);
    expect((await container.read(availableCoursesProvider.future)).map((c) => c.id), ['it', 'nl']);
    expect(container.read(courseCatalogProvider).isDemo('it'), isTrue);
  });

  test('the web pack mirror is used on web builds with downloads and no bundled packs passed in', () {
    bool uses({bool web = true, bool bundledGiven = false, bool downloads = true, String path = 'packs/index.json'}) =>
        usesWebPackMirror(web: web, bundledGiven: bundledGiven, downloads: downloads, webIndexPath: path);
    expect(uses(), isTrue);
    expect(uses(web: false), isFalse);
    expect(uses(bundledGiven: true), isFalse);
    expect(uses(downloads: false), isFalse, reason: 'no downloads: the bundled packs are all there is');
    expect(uses(path: ''), isFalse, reason: 'TOSK_WEB_PACK_INDEX empty: the releases index');
    // Off the web the option is false unless a test sets it.
    expect(const AppDataOptions(appVersion: '1.0.0').packsFromWebMirror, isFalse);
    expect(const AppDataOptions(webPackMirror: true).packsFromWebMirror, isTrue);
  });

  test('bundled packs: pack mode on the normal progress DB, used automatically', () async {
    final dir = tempDir('tosk_boot_packs');
    final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path, bundled: fixtureBundledPacks()));
    addTearDown(boot.close);
    expect(boot.demoMode, isFalse);
    expect(await boot.app.progress.logCount(), 0);
    expect(File('${dir.path}/progress.sqlite').existsSync(), isTrue);

    final container = ProviderContainer.test(overrides: boot.overrides);
    expect((await container.read(availableCoursesProvider.future)).map((c) => c.id), ['it']);
    expect(container.read(courseCatalogProvider).isDemo('it'), isFalse);
    final course = await container.read(courseDataProvider.future);
    expect(course.skill('present-are'), isNotNull);
    expect(container.read(activeCourseIsDemoProvider), isFalse);
    // The engine runs on it.
    final factory = await container.read(sessionFactoryProvider.future);
    expect(factory, isA<EngineSessionFactory>());
    final session = await factory.lesson('greetings');
    expect(await session.next(), isNotNull);
  });

  test('the real bundled packs (assets/courses) load and the engine runs on every course', () async {
    final dir = tempDir('tosk_boot_assets');
    final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path));
    addTearDown(boot.close);
    final packs = await boot.app.availableCourses();
    expect(packs.map((p) => p.id), containsAll(['es', 'it', 'nl']));
    expect(boot.demoMode, isFalse);
    final container = ProviderContainer.test(overrides: [...boot.overrides, clockProvider.overrideWithValue(() => testNow)]);
    for (final p in packs) {
      await container.read(settingsProvider.notifier).change((s) => s.copyWith(courseId: p.id));
      final course = await container.read(courseDataProvider.future);
      expect(course.meta.id, p.id);
      expect(course.skills, isNotEmpty);
      final factory = await container.read(sessionFactoryProvider.future);
      final session = await factory.lesson(course.skills.first.id);
      expect(await session.next(), isNotNull, reason: p.id);
      final stats = await container.read(skillStatsProvider.future);
      expect(stats.keys, containsAll(course.skills.map((s) => s.id)));
    }
  });

  testWidgets('the app boots on openAppData against a temp dir and shows the map', (tester) async {
    final dir = tempDir('tosk_boot_ui');
    final boot = (await tester.runAsync(
      () => bootApp(
        options: AppDataOptions(dataDirectory: dir.path, bundled: fixtureBundledPacks()),
      ),
    ))!;
    setSurface(tester, const Size(420, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...boot.overrides,
          clockProvider.overrideWithValue(() => testNow),
          calendarProvider.overrideWithValue(LocalCalendar.utc),
        ],
        child: const ToskApp(),
      ),
    );
    final node = find.byKey(const ValueKey('skill-node-greetings'));
    for (
      var i = 0;
      i < 100 && (node.evaluate().isEmpty || find.byKey(const ValueKey('map-header')).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(node, findsOneWidget);
    expect(find.byKey(const ValueKey('map-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-badge')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(boot.close);
  });

  test('AppSettings round-trip through ProgressRepo on disk', () async {
    final dir = tempDir('tosk_settings');
    final path = '${dir.path}/progress.sqlite';
    var repo = fileProgressRepo(path);
    const s = AppSettings(
      courseId: 'it',
      sourceLang: 'nl',
      defaultFocus: LessonFocus.grammar,
      accents: AccentStrictness.strict,
      themeMode: ThemeMode.light,
      reduceMotion: true,
    );
    await s.save(repo);
    await repo.close();
    repo = fileProgressRepo(path);
    addTearDown(repo.close);
    expect(await AppSettings.load(repo), s);
  });
}
