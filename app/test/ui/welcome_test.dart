// The first-run welcome (ui/welcome/): shown once on a fresh install before
// the course picker, its skip paths, the sign-in step only with sync, the
// Claude key (light validation, saved through AiConfig), never again after,
// "Show welcome again" in Settings, existing installs skip it, keyboard;
// black & white pixel scans and overflow at phone, e-reader and desktop
// sizes with large text. Plus the course picker leaving out the demo
// stand-ins when real courses can be chosen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/secret_store.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/sync/fake_sync_backend.dart';
import 'package:tosk/sync/firebase_auth.dart';
import 'package:tosk/sync/sync_engine.dart';
import 'package:tosk/sync/sync_providers.dart';
import 'package:tosk/sync/sync_service.dart';
import 'package:tosk/sync/sync_store.dart';
import 'package:tosk/ui/common/external_link.dart';
import 'package:tosk/ui/courses/course_picker.dart' show pickerCourses;
import 'package:tosk/ui/courses/course_updates.dart';
import 'package:tosk/ui/demo/demo_courses.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/ui/welcome/welcome_screen.dart';

import '../sync/sync_service_test.dart' show FakeIdentity, fakeAuthServer;
import 'bw_helpers.dart';
import 'bw_mode_test.dart' show bwSizes;
import 'course_downloads_test.dart' show FakeRemote, TestCatalog;
import 'helpers.dart';

Finder key(String k) => find.byKey(ValueKey(k));

/// A first start: no course added, the welcome not seen.
TestProgressStore freshStore([Map<String, String> settings = const {}]) =>
    TestProgressStore(fresh: true, welcome: true, settings: settings);

/// A sync service over fake Google and Firebase servers (as in sync_section_test).
Future<SyncService> fakeSync(WidgetTester tester) async {
  final server = FakeSyncServer(clock: () => DateTime.utc(2026, 10, 3));
  final progress = InMemoryProgressStore();
  late SyncService service;
  await tester.runAsync(() async {
    service = SyncService(
      engine: SyncEngine(
        store: InMemorySyncStore(),
        progress: progress,
        importer: progress,
        log: progress,
        backend: const NullSyncBackend(),
        syncedSettings: const {},
        clock: server.clock,
      ),
      auth: FirebaseAuthClient(apiKey: 'k', client: fakeAuthServer()),
      secrets: MemorySecretStore(),
      identity: FakeIdentity('google-token'),
      backendFor: (t) => FakeSyncBackend(server, account: t.uid),
    );
    await service.start(lifecycle: false);
  });
  addTearDown(service.dispose);
  return service;
}

/// Steps through every page of the welcome, calling [check] on each.
Future<void> walkWelcome(WidgetTester tester, Future<void> Function(String what) check) async {
  await check('welcome: Tosk');
  await tapKey(tester, 'welcome-next');
  await check('welcome: how it works');
  await tapKey(tester, 'welcome-next');
  if (key('welcome-page-sign-in').evaluate().isNotEmpty) {
    await check('welcome: sign in');
    await tapKey(tester, 'welcome-sync-skip');
  }
  await check('welcome: Claude key');
  await tester.enterText(key('welcome-key-field'), 'not-a-key');
  await tapKey(tester, 'welcome-key-save');
  await check('welcome: Claude key, invalid');
}

void main() {
  testWidgets('a first start shows the welcome, then the course picker; never again', (tester) async {
    final store = await pumpApp(tester, store: freshStore());
    expect(key('welcome'), findsOneWidget);
    expect(find.text("Hi, I'm Tosk!"), findsOneWidget);
    expect(find.textContaining('Ratatosk'), findsOneWidget);
    expect(key('wordmark'), findsOneWidget);
    expect(key('course-picker'), findsNothing);
    // No sync in tests: Tosk, how it works, the key.
    expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);

    await tapKey(tester, 'welcome-next');
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('Your course is a tree'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
    await tapKey(tester, 'welcome-next');
    expect(key('welcome-page-sign-in'), findsNothing);
    expect(key('welcome-page-key'), findsOneWidget);
    expect(find.text('Skip — choose a course'), findsOneWidget);
    await tapKey(tester, 'welcome-key-skip');

    expect(key('welcome'), findsNothing);
    expect(find.text('Choose your course'), findsOneWidget);
    expect(store.settings[SettingKeys.welcomeDone], 'true');

    // The next start: straight to the picker (still no course), no welcome.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, store: TestProgressStore(fresh: true, welcome: true, settings: store.settings));
    expect(key('welcome'), findsNothing);
    expect(find.text('Choose your course'), findsOneWidget);
  });

  testWidgets('existing installs (a course added) never see it', (tester) async {
    final store = await pumpApp(tester, store: TestProgressStore());
    expect(store.settings[SettingKeys.welcomeDone], isNull);
    expect(key('welcome'), findsNothing);
    expect(key('course-picker'), findsNothing);
  });

  testWidgets('Skip on the intro goes to the setup; back walks back', (tester) async {
    await pumpApp(tester, store: freshStore());
    await tapKey(tester, 'welcome-skip-intro');
    expect(key('welcome-page-key'), findsOneWidget);
    expect(key('welcome-skip-intro'), findsNothing);
    await tapKey(tester, 'welcome-back');
    expect(find.text('How it works'), findsOneWidget);
    await tapKey(tester, 'welcome-back');
    expect(find.text("Hi, I'm Tosk!"), findsOneWidget);
    expect(key('welcome-back'), findsNothing);
  });

  testWidgets('keyboard: Enter is the main button, Esc skips', (tester) async {
    final store = await pumpApp(tester, store: freshStore(), size: const Size(1280, 800));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('How it works'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('welcome-page-key'), findsOneWidget);
    // Enter with an empty field: asks for the key.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Paste your key first, or skip this step.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('welcome'), findsNothing);
    expect(store.settings[SettingKeys.welcomeDone], 'true');
  });

  testWidgets('the Claude key: light validation, Get a key, paste, save', (tester) async {
    final opened = <Uri>[];
    final secrets = MemorySecretStore();
    const fakeKey = 'sk-ant-test-0000000000000000';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': '  $fakeKey \n'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final store = await pumpApp(
      tester,
      store: freshStore(),
      overrides: [
        secretStoreProvider.overrideWithValue(secrets),
        externalLinkOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
    );
    await tapKey(tester, 'welcome-skip-intro');
    expect(find.textContaining('billed to your own Anthropic account'), findsOneWidget);
    expect(find.textContaining('the key stays only on this device'), findsOneWidget);

    await tapKey(tester, 'welcome-get-key');
    expect(opened, [Uri.parse('https://console.anthropic.com/settings/keys')]);

    final field = tester.widget<TextField>(key('welcome-key-field'));
    expect(field.obscureText, isTrue);

    await tester.enterText(key('welcome-key-field'), 'sk-proj-abcdefghijklmnopqrstuvwxyz');
    await tapKey(tester, 'welcome-key-save');
    expect(find.textContaining("doesn't look like a Claude API key"), findsOneWidget);
    expect(await secrets.read(AiSettingKeys.apiKeySecret), isNull);

    await tapKey(tester, 'welcome-key-paste');
    expect(find.textContaining("doesn't look like"), findsNothing);
    await tapKey(tester, 'welcome-key-save');
    expect(key('welcome-key-saved'), findsOneWidget);
    expect(await secrets.read(AiSettingKeys.apiKeySecret), fakeKey);
    expect(await store.getSetting(AiSettingKeys.provider), 'anthropic');
    expect(await store.getSetting(AiSettingKeys.model), isNull); // the default model

    await tapKey(tester, 'welcome-finish');
    expect(find.text('Choose your course'), findsOneWidget);
    expect(store.settings[SettingKeys.welcomeDone], 'true');
  });

  test('looksLikeClaudeKey', () {
    expect(looksLikeClaudeKey('sk-ant-api03-abcdefghijklmnop'), isTrue);
    expect(looksLikeClaudeKey('  sk-ant-api03-abcdefghijklmnop  '), isTrue);
    expect(looksLikeClaudeKey('sk-ant-'), isFalse);
    expect(looksLikeClaudeKey('sk-proj-abcdefghijklmnopqrstu'), isFalse);
    expect(looksLikeClaudeKey('sk-ant-api03 abcdefghijklmnop'), isFalse);
    expect(looksLikeClaudeKey(''), isFalse);
  });

  group('with sync', () {
    testWidgets('the sign-in step: sign in, then continue', (tester) async {
      final service = await fakeSync(tester);
      await pumpApp(tester, store: freshStore(), overrides: [syncServiceProvider.overrideWithValue(service)]);
      expect(find.bySemanticsLabel('Step 1 of 4'), findsOneWidget);
      await tapKey(tester, 'welcome-skip-intro');
      expect(key('welcome-page-sign-in'), findsOneWidget);
      expect(find.text('Keep your progress on all your devices'), findsOneWidget);
      expect(find.text('Skip — keep everything on this device'), findsOneWidget);
      expect(find.textContaining('Settings, under Account & sync'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(key('sync-sign-in'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Signed in as me@example.com.'), findsOneWidget);
      await tapKey(tester, 'welcome-next');
      expect(key('welcome-page-key'), findsOneWidget);
    });

    testWidgets('skip keeps everything on this device', (tester) async {
      final service = await fakeSync(tester);
      await pumpApp(tester, store: freshStore(), overrides: [syncServiceProvider.overrideWithValue(service)]);
      await tapKey(tester, 'welcome-skip-intro');
      await tapKey(tester, 'welcome-sync-skip');
      expect(key('welcome-page-key'), findsOneWidget);
      expect(service.status.signedIn, isFalse);
    });

    testWidgets('a failed sign-in says so in words', (tester) async {
      final service = await fakeSync(tester);
      final identity = service.identity as FakeIdentity;
      final sheet = identity.sheet = Completer<void>();
      await pumpApp(tester, store: freshStore(), overrides: [syncServiceProvider.overrideWithValue(service)]);
      await tapKey(tester, 'welcome-skip-intro');
      await tester.runAsync(() async {
        await tester.tap(key('sync-sign-in'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(find.text('Signing in…'), findsOneWidget);
      await tester.runAsync(() async {
        sheet.completeError(Exception('Google said no'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(key('welcome-signed-in'), findsNothing);
      expect(key('welcome-sync-error'), findsOneWidget);
      expect(find.textContaining('Google said no'), findsNothing); // a sentence, not the exception
      expect(key('welcome-sync-skip'), findsOneWidget);
    });
  });

  testWidgets('Settings → About → Show welcome again', (tester) async {
    final store = await pumpApp(tester);
    await goTab(tester, 'Settings');
    await scrollToFind(tester, key('show-welcome'));
    await tapKey(tester, 'show-welcome');
    expect(key('welcome'), findsOneWidget);
    await tapKey(tester, 'welcome-skip-intro');
    expect(find.text('Skip'), findsWidgets);
    await tapKey(tester, 'welcome-key-skip');
    expect(key('welcome'), findsNothing);
    expect(key('show-welcome'), findsOneWidget); // back in Settings, no picker
    expect(key('course-picker'), findsNothing);
    expect(store.settings[SettingKeys.welcomeDone], 'true');
  });

  group('black & white', () {
    for (final entry in bwSizes.entries) {
      testWidgets('pixels and layout at ${entry.key}', (tester) async {
        await pumpApp(tester, size: entry.value, store: freshStore({SettingKeys.display: 'bw'}));
        await walkWelcome(tester, (what) async {
          await expectGrayscale(tester, what);
          expect(tester.takeException(), isNull, reason: what);
        });
      });
    }

    testWidgets('no swiping and no sliding (reduced motion)', (tester) async {
      await pumpApp(tester, store: freshStore({SettingKeys.display: 'bw'}));
      final pages = tester.widget<PageView>(key('welcome-pages'));
      expect(pages.physics, isA<NeverScrollableScrollPhysics>());
      await tester.tap(key('welcome-next'));
      await tester.pump();
      expect(find.text('How it works'), findsOneWidget); // there at once, no animation
    });
  });

  for (final scale in const [1.3, 1.5]) {
    for (final size in const [Size(320, 568), Size(412, 915), Size(1280, 800)]) {
      testWidgets('text $scale at ${size.width.toInt()}x${size.height.toInt()}, colour and dark', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final theme in const ['light', 'dark']) {
          final service = await fakeSync(tester);
          await pumpApp(
            tester,
            size: size,
            store: freshStore({SettingKeys.themeMode: theme}),
            overrides: [syncServiceProvider.overrideWithValue(service)],
          );
          await walkWelcome(tester, (what) async => expect(tester.takeException(), isNull, reason: '$what ($theme)'));
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  testWidgets('every button is at least 48 dp tall', (tester) async {
    await pumpApp(tester, size: const Size(320, 568), store: freshStore());
    for (final f in [key('welcome-next'), key('welcome-skip-intro')]) {
      expect(tester.getSize(f).height, greaterThanOrEqualTo(48));
    }
    await tapKey(tester, 'welcome-skip-intro');
    for (final f in [key('welcome-key-save'), key('welcome-key-skip'), key('welcome-get-key'), key('welcome-back')]) {
      expect(tester.getSize(f).height, greaterThanOrEqualTo(48), reason: '$f');
    }
  });

  group('course picker: no demo stand-ins next to real courses', () {
    final demo = [
      const CourseMeta(id: 'it', version: '0.0.0-demo', title: {'en': 'Italian'}, target: 'it', translations: [], persons: [], tenses: []),
      const CourseMeta(id: 'nl', version: '0.0.0-demo', title: {'en': 'Dutch'}, target: 'nl', translations: [], persons: [], tenses: []),
    ];
    final offer = CourseOffer(
      id: 'it',
      status: OfferStatus.downloadable,
      remote: FakeRemote(TestCatalog()).index['it'],
    );

    test('demo only while there is nothing else', () {
      expect(pickerCourses(demo, isDemo: (_) => true, offers: const {}), demo);
      expect(pickerCourses(demo, isDemo: (_) => true, offers: {'it': offer}), isEmpty);
      expect(pickerCourses(demo, isDemo: (_) => true, offers: const {}, lookingOnline: true), isEmpty);
      final real = [demo.first];
      expect(pickerCourses(real, isDemo: (_) => false, offers: const {}), real);
    });

    List<Override> webLike() => [
      // A fresh web app: no packs, so the demo catalog stands in; the
      // course server has the real ones.
      courseCatalogProvider.overrideWithValue(DemoCourseCatalog()),
      remotePacksProvider.overrideWithValue(FakeRemote(TestCatalog())),
    ];

    testWidgets('a fresh web-like start lists only the downloads', (tester) async {
      await pumpApp(tester, store: TestProgressStore(fresh: true), overrides: webLike());
      final picker = key('course-picker');
      expect(picker, findsOneWidget);
      expect(find.descendant(of: picker, matching: key('demo-badge')), findsNothing);
      expect(find.descendant(of: picker, matching: find.textContaining('0.0.0-demo')), findsNothing);
      expect(key('course-card-it'), findsNothing);
      expect(key('course-card-nl'), findsNothing);
      expect(key('course-online-it'), findsOneWidget);
      expect(key('course-online-es'), findsOneWidget);
    });

    testWidgets('offline with nothing installed: the demo remains', (tester) async {
      final remote = FakeRemote(TestCatalog())..fetchError = Exception('offline');
      await pumpApp(
        tester,
        store: TestProgressStore(fresh: true),
        overrides: [
          courseCatalogProvider.overrideWithValue(DemoCourseCatalog()),
          remotePacksProvider.overrideWithValue(remote),
        ],
      );
      expect(key('course-card-it'), findsOneWidget);
    });
  });
}
