// The update check of sideloaded builds: once a day, cached, silent offline,
// "Later" for a week, "Don't show again" per version, a manual check that
// shows anyway, and Download opening the fitting APK or the release page.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tosk/device/device_info.dart';
import 'package:tosk/device/device_providers.dart';
import 'package:tosk/providers.dart';
import 'package:tosk/ui/common/external_link.dart';
import 'package:tosk/updates/app_release.dart';
import 'package:tosk/updates/update_check.dart';

import '../ui/helpers.dart' show TestProgressStore;
import 'app_release_test.dart' show releaseJson;

/// Releases on demand; [offline] throws like a missing network.
class FakeReleaseSource implements ReleaseSource {
  FakeReleaseSource(this.releases);
  List<AppRelease> releases;
  bool offline = false;
  int fetches = 0;

  @override
  Future<List<AppRelease>> fetch() async {
    fetches++;
    if (offline) throw const SocketException('offline');
    return releases;
  }
}

AppRelease rel(String tag, {List<String> assets = const ['tosk-preview-arm64.apk']}) => AppRelease.fromJson(
  releaseJson(tag, assets: assets, body: 'Notes of $tag'),
  repo: kAppReleaseRepo,
)!;

class Harness {
  Harness({
    List<AppRelease>? releases,
    TestProgressStore? store,
    String current = '0.7.6',
    this.abis = const ['arm64-v8a'],
  }) : source = FakeReleaseSource(releases ?? [rel('preview-0.7.6'), rel('preview-0.7.7')]),
       store = store ?? TestProgressStore() {
    container = ProviderContainer(
      overrides: [
        progressStoreProvider.overrideWithValue(this.store),
        clockProvider.overrideWithValue(() => now),
        releaseSourceProvider.overrideWithValue(source),
        currentAppVersionProvider.overrideWithValue(AppVersion.parse(current)!),
        updatePlatformProvider.overrideWithValue(UpdatePlatform.android),
        deviceInfoProvider.overrideWith((ref) async => DeviceInfo(abis: abis)),
        externalLinkOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
    );
  }

  final FakeReleaseSource source;
  final TestProgressStore store;
  final List<String> abis;
  final opened = <Uri>[];
  late final ProviderContainer container;
  DateTime now = DateTime.utc(2026, 10, 25, 9);

  AppUpdate get ctl => container.read(appUpdateProvider.notifier);
  AppUpdateState get state => container.read(appUpdateProvider);

  /// A new app start on the same device (same settings).
  Harness restart({String current = '0.7.6'}) {
    container.dispose();
    final next = Harness(releases: source.releases, store: store, current: current, abis: abis)..now = now;
    next.source.offline = source.offline;
    return next;
  }
}

void main() {
  test('start: checks, shows the newest newer release and caches it', () async {
    final h = Harness();
    await h.ctl.startup();
    expect(h.source.fetches, 1);
    expect(h.state.visible, isTrue);
    expect(h.state.release?.version, AppVersion.parse('0.7.7'));
    expect(h.store.settings[UpdateSettingKeys.lastCheck], '2026-10-25T09:00:00.000Z');
    expect(h.store.settings[UpdateSettingKeys.cache], contains('preview-0.7.7'));
    await h.ctl.startup();
    expect(h.source.fetches, 1, reason: 'once per start');
  });

  test('at most once a day; the cache shows the notice in between, even offline', () async {
    var h = Harness();
    await h.ctl.startup();
    h.now = h.now.add(const Duration(hours: 5));
    h = h.restart();
    h.source.offline = true;
    await h.ctl.startup();
    expect(h.source.fetches, 0, reason: 'checked 5 hours ago');
    expect(h.state.visible, isTrue, reason: 'from the cache');
    h.now = h.now.add(const Duration(hours: 20));
    h = h.restart();
    h.source.offline = true;
    await h.ctl.startup();
    expect(h.source.fetches, 1);
    expect(h.state.lastResult, UpdateCheckResult.failed);
    expect(h.state.visible, isTrue, reason: 'offline: the cached offer stays');
  });

  test('offline on the first start: silent, nothing shown, nothing stored', () async {
    final h = Harness()..source.offline = true;
    await h.ctl.startup();
    expect(h.state.visible, isFalse);
    expect(h.state.release, isNull);
    expect(h.state.lastResult, UpdateCheckResult.failed);
    expect(h.store.settings.containsKey(UpdateSettingKeys.lastCheck), isFalse, reason: 'retried next start');
  });

  test('up to date: nothing shown; an old cache is no offer after updating', () async {
    var h = Harness(releases: [rel('preview-0.7.6')]);
    await h.ctl.startup();
    expect(h.state.visible, isFalse);
    expect(h.state.lastResult, UpdateCheckResult.upToDate);

    h = Harness(releases: [rel('preview-0.7.7')]);
    await h.ctl.startup();
    expect(h.state.visible, isTrue);
    // The learner installs 0.7.7; the next start is within the day.
    h = h.restart(current: '0.7.7');
    h.source.offline = true;
    await h.ctl.startup();
    expect(h.state.visible, isFalse);
    expect(h.state.release, isNull);
  });

  test('Later hides that version for a week; a newer version shows at once', () async {
    var h = Harness();
    await h.ctl.startup();
    await h.ctl.later();
    expect(h.state.visible, isFalse);
    expect(h.store.settings[UpdateSettingKeys.snooze], '0.7.7|2026-11-01T09:00:00.000Z');

    h.now = h.now.add(const Duration(days: 3));
    h = h.restart();
    await h.ctl.startup();
    expect(h.source.fetches, 1);
    expect(h.state.visible, isFalse, reason: 'snoozed for a week');

    h.now = h.now.add(const Duration(days: 4, minutes: 1));
    h = h.restart();
    await h.ctl.startup();
    expect(h.state.visible, isTrue, reason: 'the week is over');

    await h.ctl.later();
    h.source.releases = [...h.source.releases, rel('preview-0.7.8')];
    h.now = h.now.add(const Duration(days: 1, minutes: 1));
    h = h.restart();
    await h.ctl.startup();
    expect(h.state.release?.version, AppVersion.parse('0.7.8'));
    expect(h.state.visible, isTrue, reason: 'the snooze was for 0.7.7');
  });

  test("Don't show again: never automatically for that version; a manual check shows it", () async {
    var h = Harness();
    await h.ctl.startup();
    await h.ctl.skipVersion();
    expect(h.store.settings[UpdateSettingKeys.skip], '0.7.7');
    h.now = h.now.add(const Duration(days: 30));
    h = h.restart();
    await h.ctl.startup();
    expect(h.state.visible, isFalse);
    expect(await h.ctl.check(manual: true), UpdateCheckResult.available);
    expect(h.state.visible, isTrue, reason: 'asked for in Settings');
    h.source.releases = [...h.source.releases, rel('v0.8.0')];
    h.now = h.now.add(const Duration(days: 2));
    h = h.restart();
    await h.ctl.startup();
    expect(h.state.visible, isTrue, reason: '0.8.0 was not skipped');
  });

  test('Download opens the APK for this device, else the release page', () async {
    var h = Harness();
    await h.ctl.startup();
    expect(await h.ctl.download(), isTrue);
    expect(h.opened.single.path, endsWith('/preview-0.7.7/tosk-preview-arm64.apk'));
    expect(h.state.visible, isFalse, reason: 'hidden for now, not snoozed');
    expect(h.store.settings.containsKey(UpdateSettingKeys.snooze), isFalse);

    h = Harness(abis: const ['armeabi-v7a']);
    await h.ctl.startup();
    await h.ctl.download();
    expect(h.opened.single, Uri.parse('https://github.com/linguaperta/tosk/releases/tag/preview-0.7.7'));
  });

  test('manual check while offline reports the failure and never throws', () async {
    final h = Harness()..source.offline = true;
    expect(await h.ctl.check(manual: true), UpdateCheckResult.failed);
    expect(h.state.checking, isFalse);
  });

  test('no source (web, iOS, tests): nothing happens', () async {
    final c = ProviderContainer(
      overrides: [
        progressStoreProvider.overrideWithValue(TestProgressStore()),
        releaseSourceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appUpdateProvider.notifier).startup();
    expect(await c.read(appUpdateProvider.notifier).check(manual: true), UpdateCheckResult.failed);
    expect(c.read(appUpdateProvider).visible, isFalse);
  });

  test('suppression rules', () {
    final r = rel('preview-0.7.7');
    final now = DateTime.utc(2026, 10, 25);
    expect(updateNoticeSuppressed(r, now: now), isFalse);
    expect(updateNoticeSuppressed(r, now: now, skip: '0.7.7'), isTrue);
    expect(updateNoticeSuppressed(r, now: now, skip: '0.7.6'), isFalse);
    expect(updateNoticeSuppressed(r, now: now, snooze: '0.7.7|2026-10-26T00:00:00Z'), isTrue);
    expect(updateNoticeSuppressed(r, now: now, snooze: '0.7.7|2026-10-24T00:00:00Z'), isFalse);
    expect(updateNoticeSuppressed(r, now: now, snooze: '0.7.6|2026-10-26T00:00:00Z'), isFalse);
    expect(updateNoticeSuppressed(r, now: now, snooze: 'garbage'), isFalse);
  });

  group('GitHubReleaseSource', () {
    test('asks the releases API over https, unauthenticated, and parses it', () async {
      late http.Request seen;
      final source = GitHubReleaseSource(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode([releaseJson('preview-0.7.7'), releaseJson('packs-20261024')]), 200);
        }),
      );
      final list = await source.fetch();
      expect(list.map((r) => r.tag), ['preview-0.7.7']);
      expect(seen.url.toString(), 'https://api.github.com/repos/linguaperta/tosk/releases?per_page=15');
      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(seen.headers['Accept'], 'application/vnd.github+json');
    });

    test('errors: status codes, bad JSON, timeouts', () async {
      Future<List<AppRelease>> fetchWith(Future<http.Response> Function() answer, {Duration? timeout}) =>
          GitHubReleaseSource(
            client: MockClient((_) => answer()),
            timeout: timeout ?? const Duration(seconds: 10),
          ).fetch();
      await expectLater(
        fetchWith(() async => http.Response('rate limited', 403)),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(fetchWith(() async => http.Response('<html>', 200)), throwsFormatException);
      await expectLater(
        fetchWith(() => Completer<http.Response>().future, timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
