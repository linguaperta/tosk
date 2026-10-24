// The update notice in the app: the card above the navigation (phone) or
// under the page (rail), its buttons, Settings → About → Check for updates,
// the web's "tosk was updated — reload" and one-time "What's new"; black &
// white pixel checks and no overflow at small sizes with large text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tosk/device/device_info.dart';
import 'package:tosk/device/device_providers.dart';
import 'package:tosk/ui/common/external_link.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:tosk/updates/app_release.dart';
import 'package:tosk/updates/update_check.dart';
import 'package:tosk/updates/web_update.dart';

import '../updates/app_release_test.dart' show releaseJson;
import '../updates/update_check_test.dart' show FakeReleaseSource;
import '../updates/web_update_test.dart' show FakeWebUpdateSource, whatsNew;
import 'bw_helpers.dart';
import 'helpers.dart';

const kNotes =
    'Preview (arm64). Restructured courses with topic trees: slim main trees, themed topics on tappable '
    'branches with the name carved into the bark, and a tree menu.';

AppRelease update077() => AppRelease.fromJson(
  releaseJson('preview-0.7.7', name: 'Preview 7.7 (0.7.7)', body: kNotes, assets: ['tosk-preview-7.7-arm64.apk']),
  repo: kAppReleaseRepo,
)!;

/// Overrides for a sideloaded Android build that finds [releases] on GitHub.
List<Override> githubOverrides(FakeReleaseSource source, {List<Uri>? opened}) => [
  updateModeProvider.overrideWithValue(UpdateMode.github),
  releaseSourceProvider.overrideWithValue(source),
  currentAppVersionProvider.overrideWithValue(AppVersion.parse('0.7.6')!),
  updatePlatformProvider.overrideWithValue(UpdatePlatform.android),
  deviceInfoProvider.overrideWith((ref) async => const DeviceInfo(abis: ['arm64-v8a'])),
  externalLinkOpenerProvider.overrideWithValue((u) async {
    opened?.add(u);
    return true;
  }),
];

List<Override> webOverrides(FakeWebUpdateSource source, {String version = '0.7.6'}) => [
  updateModeProvider.overrideWithValue(UpdateMode.web),
  webUpdateSourceProvider.overrideWithValue(source),
  currentAppVersionProvider.overrideWithValue(AppVersion.parse(version)!),
  buildIdProvider.overrideWithValue('aaa111'),
];

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  group('sideloaded (GitHub Releases)', () {
    testWidgets('the notice: version, title, notes; Later snoozes it', (tester) async {
      final source = FakeReleaseSource([update077()]);
      final store = await pumpApp(tester, size: const Size(390, 844), overrides: githubOverrides(source));
      expect(key('app-update-notice'), findsOneWidget);
      expect(find.text('Version 0.7.7 is available'), findsOneWidget);
      expect(find.text('Preview 7.7 (0.7.7)'), findsOneWidget);
      expect(find.textContaining('Restructured courses'), findsOneWidget);
      // Above the navigation bar, never over the page.
      final card = tester.getRect(key('app-update-notice'));
      expect(card.bottom, lessThanOrEqualTo(tester.getRect(key('bottom-nav')).top));
      // The title is a heading, the card a live region (announced when it appears).
      expect(tester.getSemantics(find.text('Version 0.7.7 is available')), isSemantics(isHeader: true));
      for (final k in ['app-update-download', 'app-update-later', 'app-update-skip']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(40), reason: k);
      }
      await tapKey(tester, 'app-update-later');
      expect(key('app-update-notice'), findsNothing);
      expect(store.settings[UpdateSettingKeys.snooze], startsWith('0.7.7|'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Download opens the APK for the device; "Don\'t show again" remembers the version', (tester) async {
      final opened = <Uri>[];
      final source = FakeReleaseSource([update077()]);
      var store = await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: githubOverrides(source, opened: opened),
      );
      await tapKey(tester, 'app-update-download');
      expect(opened.single.toString(), endsWith('/preview-0.7.7/tosk-preview-7.7-arm64.apk'));
      expect(key('app-update-notice'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      store = await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: githubOverrides(FakeReleaseSource([update077()])),
      );
      await tapKey(tester, 'app-update-skip');
      expect(store.settings[UpdateSettingKeys.skip], '0.7.7');
      expect(key('app-update-notice'), findsNothing);
    });

    testWidgets('Settings → About → Check for updates', (tester) async {
      final source = FakeReleaseSource([]);
      await pumpApp(tester, size: const Size(390, 844), overrides: githubOverrides(source));
      expect(key('app-update-notice'), findsNothing);
      await goTab(tester, 'Settings');
      await tapKey(tester, 'check-updates');
      expect(find.text('You have the latest version'), findsOneWidget);
      source.offline = true;
      await tapKey(tester, 'check-updates');
      expect(find.text("Couldn't check. Are you online?"), findsOneWidget);
      source
        ..offline = false
        ..releases = [update077()];
      await tapKey(tester, 'check-updates');
      expect(find.text('Version 0.7.7 is available'), findsNWidgets(2), reason: 'the tile and the notice');
      expect(key('app-update-notice'), findsOneWidget);
      expect(source.fetches, 4, reason: 'the start, then three taps');
    });

    testWidgets('a skipped version still shows after a manual check', (tester) async {
      final source = FakeReleaseSource([update077()]);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: TestProgressStore(settings: {UpdateSettingKeys.skip: '0.7.7'}),
        overrides: githubOverrides(source),
      );
      expect(key('app-update-notice'), findsNothing);
      await goTab(tester, 'Settings');
      await tapKey(tester, 'check-updates');
      expect(key('app-update-notice'), findsOneWidget);
    });

    testWidgets('wide windows: under the page, next to the rail', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800), overrides: githubOverrides(FakeReleaseSource([update077()])));
      final card = tester.getRect(key('app-update-notice'));
      expect(card.left, greaterThanOrEqualTo(tester.getRect(key('nav-rail')).right));
      expect(card.bottom, 800);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline at start: no notice, no error', (tester) async {
      final source = FakeReleaseSource([update077()])..offline = true;
      await pumpApp(tester, size: const Size(390, 844), overrides: githubOverrides(source));
      expect(key('app-update-notice'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('web', () {
    testWidgets('a new deploy: "tosk was updated" with Reload; Later hides it', (tester) async {
      final source = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'bbb222'));
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'}),
        overrides: webOverrides(source),
      );
      expect(key('web-update-notice'), findsNothing);
      source.workerTakesOver();
      await tester.pumpAndSettle();
      expect(key('web-update-notice'), findsOneWidget);
      expect(find.text('tosk was updated'), findsOneWidget);
      expect(find.textContaining('version 0.7.7'), findsOneWidget);
      await tapKey(tester, 'web-update-reload');
      expect(source.reloads, 1);
      await tapKey(tester, 'web-update-later');
      expect(key('web-update-notice'), findsNothing);
      // No GitHub check and no Check for updates on the web.
      await goTab(tester, 'Settings');
      await scrollToFind(tester, key('show-welcome'));
      expect(key('check-updates'), findsNothing);
    });

    testWidgets("after the reload: What's new in 0.7.7, once", (tester) async {
      final source = FakeWebUpdateSource(
        deployed: whatsNew('0.7.7', build: 'aaa111', notes: '- **Topic trees**\n- Fixes'),
      );
      final store = TestProgressStore(settings: {kWhatsNewSeenKey: '0.7.6'});
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: store,
        overrides: webOverrides(source, version: '0.7.7'),
      );
      expect(key('whats-new-sheet'), findsOneWidget);
      expect(find.text("What's new in 0.7.7"), findsOneWidget);
      expect(find.text('Preview 0.7.7'), findsOneWidget);
      await tapKey(tester, 'whats-new-close');
      expect(key('whats-new-sheet'), findsNothing);
      expect(store.settings[kWhatsNewSeenKey], '0.7.7');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        size: const Size(390, 844),
        store: store,
        overrides: webOverrides(source, version: '0.7.7'),
      );
      expect(key('whats-new-sheet'), findsNothing);
    });
  });

  group('black & white, dark, small screens, large text', () {
    for (final (name, size, settings, scale) in [
      ('bw phone', const Size(390, 844), {SettingKeys.display: 'bw'}, 1.0),
      ('bw 6" e-reader', const Size(572, 772), {SettingKeys.display: 'bw'}, 1.0),
      ('bw 320 text 1.3', const Size(320, 568), {SettingKeys.display: 'bw'}, 1.3),
      ('dark 320 text 1.3', const Size(320, 568), {SettingKeys.themeMode: 'dark'}, 1.3),
      ('colour 360 text 1.6', const Size(360, 640), <String, String>{}, 1.6),
    ]) {
      testWidgets(name, (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final web = FakeWebUpdateSource(deployed: whatsNew('0.7.7', build: 'bbb222'));
        await pumpApp(
          tester,
          size: size,
          store: TestProgressStore(settings: settings),
          overrides: githubOverrides(FakeReleaseSource([update077()])),
        );
        expect(key('app-update-notice'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        if (settings[SettingKeys.display] == 'bw') await expectGrayscale(tester, '$name: update notice');
        await tester.pumpWidget(const SizedBox());

        await pumpApp(
          tester,
          size: size,
          store: TestProgressStore(settings: {...settings, kWhatsNewSeenKey: '0.7.6'}),
          overrides: webOverrides(web),
        );
        web.workerTakesOver();
        await tester.pumpAndSettle();
        expect(key('web-update-notice'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        if (settings[SettingKeys.display] == 'bw') await expectGrayscale(tester, '$name: reload notice');
      });
    }
  });

  testWidgets('semantics: the buttons are labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, size: const Size(390, 844), overrides: githubOverrides(FakeReleaseSource([update077()])));
    for (final label in ['Download', 'Later', "Don't show again for this version"]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isButton: true, hasTapAction: true),
        reason: label,
      );
    }
    handle.dispose();
  });
}
