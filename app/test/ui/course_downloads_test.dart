// Course downloads in the course picker: online courses ("Download (12 MB)"),
// "Update available" (badge, and the dot on the course switcher), progress
// with cancel, polite errors with retry, the daily automatic check and its
// toggle, and "Add course from file…" (new course, a newer file replacing an
// installed one with progress kept, a bad file). Plus black & white pixel
// scans and overflow checks at every e-ink harness size.
import 'dart:async';
import 'dart:typed_data';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_schema.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/course_catalog.dart';
import 'package:tosk/ui/courses/course_updates.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/pack_course_catalog.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes, bwStore;
import 'helpers.dart';

/// The demo courses, treated as installed packs, plus packs "installed" by the tests.
class TestCatalog implements CourseCatalog {
  final demo = DemoCourseCatalog();
  final Map<String, CourseMeta> installed = {};

  void add(PackInfo p) => installed[p.id] = PackCourseCatalog.listingMeta(p);

  @override
  Future<List<CourseMeta>> listCourses() async {
    final base = await demo.listCourses();
    return [
      for (final c in base) installed[c.id] ?? c,
      for (final c in installed.values)
        if (!base.any((b) => b.id == c.id)) c,
    ];
  }

  @override
  Future<CourseData> open(String courseId) => demo.open(courseId == 'nl' ? 'nl' : 'it');

  @override
  bool isDemo(String courseId) => false;
}

PackInfo _info(String id, String version, String title) =>
    PackInfo(id: id, version: version, title: {'en': title}, origin: PackOrigin.remote);

RemotePack _pack(String id, String version, String title, {int size = 12000000, String minApp = '0.3.0'}) =>
    RemotePack(
      id: id,
      version: version,
      title: {'en': title, 'nl': title},
      description: {'en': 'Learn $title from English and Dutch.'},
      sources: const ['en', 'nl'],
      url: 'https://example.invalid/$id.sqlite',
      sha256: 'x',
      size: size,
      schemaVersion: '$kCourseDbSchemaVersion',
      minAppVersion: minApp,
    );

class FakeRemote implements RemotePackSource {
  FakeRemote(this.catalog);
  final TestCatalog catalog;
  RemoteIndex index = RemoteIndex(
    courses: [
      _pack('it', '1.2.0', 'Italian'),
      _pack('es', '1.0.0', 'Spanish'),
      _pack('fr', '1.0.0', 'French', minApp: '99.0.0'),
    ],
  );
  int fetches = 0;
  Object? fetchError;

  /// Downloads of these ids wait here (progress shows half done).
  final Map<String, Completer<void>> gates = {};
  final Map<String, PackDownloadException> failures = {};
  final List<String> downloaded = [];

  @override
  Future<RemoteIndex> fetchIndex({Uri? url}) async {
    fetches++;
    if (fetchError case final e?) throw e;
    return index;
  }

  @override
  Future<PackInfo> download(RemotePack pack, {DownloadProgress? onProgress, DownloadCancel? cancel}) async {
    onProgress?.call(0, pack.size);
    onProgress?.call(pack.size ~/ 2, pack.size);
    if (gates[pack.id] case final gate?) {
      final cancelled = Completer<void>();
      cancel?.onCancel(cancelled.complete);
      await Future.any([gate.future, cancelled.future]);
    }
    if (cancel?.isCancelled ?? false) {
      throw const PackDownloadException(PackDownloadError.cancelled, 'Download cancelled.');
    }
    if (failures[pack.id] case final e?) throw e;
    onProgress?.call(pack.size, pack.size);
    downloaded.add(pack.id);
    final info = _info(pack.id, pack.version, pack.title['en']!);
    catalog.add(info);
    return info;
  }
}

const _offline = PackDownloadException(
  PackDownloadError.network,
  "Couldn't reach the course server. Check your connection; everything installed keeps working offline.",
);

void main() {
  late TestCatalog catalog;
  late FakeRemote remote;
  setUp(() {
    catalog = TestCatalog();
    remote = FakeRemote(catalog);
  });

  List<Override> online({List<Override> extra = const []}) => [
    courseCatalogProvider.overrideWithValue(catalog),
    remotePacksProvider.overrideWithValue(remote),
    ...extra,
  ];

  Future<void> openPicker(WidgetTester tester) async {
    await tapKey(tester, 'course-switcher');
    await tapKey(tester, 'manage-courses');
    expect(find.byKey(const ValueKey('course-picker')), findsOneWidget);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Scrolls the picker's list from the top until [f] is on screen.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    final list = find.descendant(of: key('course-picker'), matching: find.byType(Scrollable)).first;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pumpAndSettle();
    if (f.hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 150, scrollable: list);
    }
    await tester.pumpAndSettle();
  }

  group('downloads', () {
    testWidgets('start check, update badge and dot, download with progress, cancel, error, retry', (tester) async {
      final store = await pumpApp(tester, overrides: online());
      expect(remote.fetches, 1); // checked on start
      expect(store.settings[SettingKeys.packLastCheck], isNotNull);
      expect(store.settings[SettingKeys.packIndexCache], contains('"es"'));
      expect(key('course-update-dot'), findsOneWidget); // it (a course of mine) has 1.2.0

      await openPicker(tester);
      expect(key('update-badge'), findsOneWidget);
      expect(find.text('Update to v1.2.0 (12 MB)'), findsOneWidget);
      await reveal(tester, key('course-online-es'));
      expect(find.text('Download (12 MB)'), findsOneWidget);
      expect(find.text('Learn Spanish from English and Dutch.'), findsOneWidget);
      await reveal(tester, key('course-needs-app-fr'));
      expect(key('course-download-fr'), findsNothing);

      // Progress, then cancel: nothing changes.
      remote.gates['es'] = Completer();
      await reveal(tester, key('course-download-es'));
      await tapKey(tester, 'course-download-es');
      expect(key('course-progress-es'), findsOneWidget);
      expect(find.textContaining('Downloading… 50%'), findsOneWidget);
      await tapKey(tester, 'course-cancel-es');
      expect(key('course-progress-es'), findsNothing);
      expect(key('course-download-es'), findsOneWidget);
      expect(remote.downloaded, isEmpty);

      // A failure is polite and can be retried.
      remote.gates.clear();
      remote.failures['es'] = _offline;
      await tapKey(tester, 'course-download-es');
      expect(key('course-error-es'), findsOneWidget);
      expect(find.textContaining('keeps working offline'), findsOneWidget);
      remote.failures.clear();
      await tapKey(tester, 'course-retry-es');
      // A new course: added to my courses right away (where to start?).
      await tapKey(tester, 'placement-scratch');
      expect(remote.downloaded, ['es']);
      expect(store.settings[SettingKeys.coursesAdded], 'it,nl,es');
      await reveal(tester, key('course-card-es'));
      expect(key('course-online-es'), findsNothing);

      // Update Italian: the badge goes, and the dot with it.
      await reveal(tester, key('course-download-it'));
      await tapKey(tester, 'course-download-it');
      expect(remote.downloaded, ['es', 'it']);
      expect(key('update-badge'), findsNothing);
      expect(find.byKey(const ValueKey('placement-find')), findsNothing); // an update asks nothing
      await tapKey(tester, 'course-picker-done');
      expect(key('course-update-dot'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at most one automatic check a day; the cached index shows offline', (tester) async {
      final cached = remote.index.toJsonString();
      final store = TestProgressStore(
        settings: {
          SettingKeys.packIndexCache: cached,
          SettingKeys.packLastCheck: testNow.subtract(const Duration(hours: 3)).toIso8601String(),
        },
      );
      await pumpApp(tester, store: store, overrides: online());
      expect(remote.fetches, 0);
      expect(key('course-update-dot'), findsOneWidget); // from the cache
      await openPicker(tester);
      expect(find.textContaining('Last checked'), findsOneWidget);
      // Manual check while offline: a polite message, nothing else changes.
      remote.fetchError = _offline;
      await tapKey(tester, 'course-check-updates');
      expect(remote.fetches, 1);
      expect(find.textContaining("Couldn't reach the course server"), findsOneWidget);
      expect(key('update-badge'), findsOneWidget);
    });

    testWidgets('an old check runs again on start; offline at start is silent', (tester) async {
      remote.fetchError = _offline;
      final store = TestProgressStore(
        settings: {SettingKeys.packLastCheck: testNow.subtract(const Duration(days: 2)).toIso8601String()},
      );
      await pumpApp(tester, store: store, overrides: online());
      expect(remote.fetches, 1);
      await openPicker(tester);
      expect(find.textContaining("Couldn't reach"), findsNothing);
      expect(key('course-online-es'), findsNothing);
    });

    testWidgets('the setting turns the automatic check off (manual checks still work)', (tester) async {
      final store = TestProgressStore(settings: {SettingKeys.autoCheckCourseUpdates: 'false'});
      await pumpApp(tester, store: store, overrides: online());
      expect(remote.fetches, 0);
      expect(key('course-update-dot'), findsNothing);
      await openPicker(tester);
      await tapKey(tester, 'course-check-updates');
      expect(remote.fetches, 1);
      expect(key('update-badge'), findsOneWidget);
      await tapKey(tester, 'course-picker-done');
      await goTab(tester, 'Settings');
      await scrollToFind(tester, key('auto-check-course-updates'));
      await tapKey(tester, 'auto-check-course-updates');
      expect(store.settings[SettingKeys.autoCheckCourseUpdates], 'true');
    });

    testWidgets('without downloads (no data layer) the picker has no online parts', (tester) async {
      await pumpApp(tester);
      await openPicker(tester);
      expect(key('course-check-updates'), findsNothing);
      expect(key('course-add-file'), findsNothing);
      expect(find.textContaining('Download ('), findsNothing);
    });
  });

  group('add course from file', () {
    testWidgets('a new course is added; a newer file replaces it and keeps progress; a bad file', (tester) async {
      var version = '0.1.0';
      Object? failure;
      var picks = 0;
      final overrides = online(
        extra: [
          packFilePickerProvider.overrideWithValue(() async {
            picks++;
            return PackBytes(Uint8List(4), name: 'hns.sqlite');
          }),
          packInstallerProvider.overrideWithValue((data) async {
            if (failure case final f?) throw f;
            final info = PackInfo(
              id: 'hns',
              version: version,
              title: const {'en': 'Sarnami', 'nl': 'Sarnami'},
              origin: PackOrigin.local,
              unverified: true,
            );
            catalog.add(info);
            return info;
          }),
        ],
      );
      final store = await pumpApp(tester, overrides: overrides);
      await openPicker(tester);
      await reveal(tester, key('course-add-file'));
      await tapKey(tester, 'course-add-file');
      await tapKey(tester, 'placement-scratch'); // added to my courses right away
      expect(picks, 1);
      expect(store.settings[SettingKeys.coursesAdded], 'it,nl,hns');
      await reveal(tester, key('course-notice'));
      expect(find.text('Added Sarnami v0.1.0.'), findsOneWidget);

      await store.record(
        ReviewEvent(
          id: 'h1',
          facetId: 'hns:ham#rec',
          at: testNow,
          rating: Rating.good,
          exerciseType: 'flashcard',
          inputMode: InputMode.self,
          responseMs: 800,
          correct: true,
        ),
      );
      version = '0.2.0';
      await reveal(tester, key('course-add-file'));
      await tapKey(tester, 'course-add-file');
      expect(find.byKey(const ValueKey('placement-find')), findsNothing);
      await reveal(tester, key('course-notice'));
      expect(find.text('Updated Sarnami from v0.1.0 to v0.2.0. Your progress is kept.'), findsOneWidget);
      expect((await store.log(courseId: 'hns')).single.id, 'h1');
      await reveal(tester, key('course-langs-hns'));
      expect(find.textContaining('v0.2.0'), findsOneWidget);

      failure = CourseFormatException('meta.course_id is missing');
      await reveal(tester, key('course-add-file'));
      await tapKey(tester, 'course-add-file');
      await reveal(tester, key('course-notice'));
      expect(
        find.text("This file couldn't be added as a course: meta.course_id is missing"),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('black & white and layout', () {
    Future<void> walk(WidgetTester tester, Future<void> Function(String what) check) async {
      await check('map with the update dot');
      await openPicker(tester);
      remote.failures['it'] = _offline;
      await tapKey(tester, 'course-download-it'); // error row
      remote.gates['es'] = Completer();
      await reveal(tester, key('course-download-es'));
      await tapKey(tester, 'course-download-es'); // progress row
      await reveal(tester, key('course-add-file'));
      await tapKey(tester, 'course-add-file'); // notice (an error here)
      await reveal(tester, key('course-notice'));
      await check('picker: notice, update badge, error');
      await reveal(tester, key('course-progress-es'));
      await check('picker: progress, online course, needs a newer app');
      await reveal(tester, key('course-add-file'));
      await check('picker: add from file');
    }

    List<Override> withFile() => online(
      extra: [
        packFilePickerProvider.overrideWithValue(() async => PackBytes(Uint8List(4))),
        packInstallerProvider.overrideWithValue((_) async => throw CourseFormatException('not a course pack')),
      ],
    );

    for (final entry in bwSizes.entries) {
      testWidgets('black & white ${entry.key}', (tester) async {
        await pumpApp(tester, size: entry.value, store: await bwStore(), overrides: withFile());
        await walk(tester, (what) async {
          await expectGrayscale(tester, what);
          expect(tester.takeException(), isNull, reason: what);
        });
      });
    }

    for (final size in const [Size(320, 568), Size(1280, 800)]) {
      testWidgets('color, dark, text 1.3 at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = TestProgressStore(settings: {SettingKeys.themeMode: 'dark'});
        await pumpApp(tester, size: size, store: store, overrides: withFile());
        await walk(tester, (what) async => expect(tester.takeException(), isNull, reason: what));
      });
    }
  });
}
