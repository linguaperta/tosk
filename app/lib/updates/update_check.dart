/// The update notice of sideloaded builds (Android, Windows, macOS, Linux):
/// GitHub Releases of `linguaperta/tosk`, checked at most once a day on start
/// and from Settings → About → Check for updates.
///
/// Nothing is downloaded or installed by the app: Download opens the fitting
/// file (or the release page) in the browser. Offline, or when GitHub can't be
/// reached, the automatic check fails silently and the cached result stays.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../audio/test_env.dart';
import '../core/core.dart';
import '../device/device_info.dart' show DeviceInfo;
import '../device/device_providers.dart';
import '../providers.dart';
import '../ui/common/external_link.dart';
import 'app_release.dart';

/// The repository whose releases are the app's.
const String kAppReleaseRepo = 'linguaperta/tosk';

/// How often the automatic check runs at most.
const Duration kAppUpdateCheckInterval = Duration(hours: 24);

/// How long "Later" hides a version.
const Duration kAppUpdateSnooze = Duration(days: 7);

/// Device-only settings (not synced, not in backups).
abstract final class UpdateSettingKeys {
  /// When GitHub was last asked (UTC ISO 8601).
  static const lastCheck = 'update.last_check';

  /// The newest newer release found then (the API's JSON), or empty for none.
  static const cache = 'update.cache';

  /// `version|until` (UTC ISO 8601): "Later" for that version.
  static const snooze = 'update.snooze';

  /// A version for which "Don't show again" was chosen.
  static const skip = 'update.skip';
}

/// Fetches the app's releases.
abstract interface class ReleaseSource {
  /// Every app release, newest first as GitHub lists them. Throws when offline
  /// or on a bad answer.
  Future<List<AppRelease>> fetch();
}

/// `GET https://api.github.com/repos/{repo}/releases`, unauthenticated (60
/// requests an hour per address; the app asks once a day).
class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource({required this.client, this.repo = kAppReleaseRepo, this.timeout = const Duration(seconds: 10)});

  final http.Client client;
  final String repo;
  final Duration timeout;

  @override
  Future<List<AppRelease>> fetch() async {
    final res = await client
        .get(
          Uri.https('api.github.com', '/repos/$repo/releases', {'per_page': '15'}),
          headers: const {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
        )
        .timeout(timeout);
    if (res.statusCode != 200) throw http.ClientException('GitHub answered ${res.statusCode}');
    return AppRelease.listFromJson(utf8.decode(res.bodyBytes), repo: repo);
  }
}

/// How this build hears about new versions.
enum UpdateMode {
  /// Sideloaded (Android, desktop): GitHub Releases.
  github,

  /// The web app: a new service worker means a new deploy ("reload").
  web,

  /// Nothing (iOS, `flutter test` unless a test overrides it).
  none,
}

UpdateMode defaultUpdateMode() {
  if (runningInFlutterTest) return UpdateMode.none;
  if (kIsWeb) return UpdateMode.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => UpdateMode.github,
    _ => UpdateMode.none,
  };
}

final updateModeProvider = Provider<UpdateMode>((ref) => defaultUpdateMode());

/// The platform, for picking the release file.
final updatePlatformProvider = Provider<UpdatePlatform>((ref) {
  if (kIsWeb) return UpdatePlatform.other;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => UpdatePlatform.android,
    TargetPlatform.windows => UpdatePlatform.windows,
    TargetPlatform.macOS => UpdatePlatform.macos,
    TargetPlatform.linux => UpdatePlatform.linux,
    _ => UpdatePlatform.other,
  };
});

/// GitHub Releases, or null when this build doesn't check (web, iOS, tests).
final releaseSourceProvider = Provider<ReleaseSource?>(
  (ref) => ref.watch(updateModeProvider) == UpdateMode.github
      ? GitHubReleaseSource(client: ref.watch(httpClientProvider))
      : null,
);

/// This build's version (tests override it).
final currentAppVersionProvider = Provider<AppVersion>(
  (ref) => AppVersion.parse(kAppVersion) ?? const AppVersion(0, 0, 0),
);

/// Why a manual check found nothing to offer.
enum UpdateCheckResult { upToDate, available, failed }

@immutable
class AppUpdateState {
  const AppUpdateState({this.release, this.visible = false, this.checking = false, this.checkedAt, this.lastResult});

  /// The newest release newer than this app (null: none known).
  final AppRelease? release;

  /// Whether the notice is showing (not snoozed, skipped or dismissed).
  final bool visible;
  final bool checking;
  final DateTime? checkedAt;

  /// The last check's outcome (Settings shows it); null before any check.
  final UpdateCheckResult? lastResult;

  AppUpdateState copyWith({
    AppRelease? Function()? release,
    bool? visible,
    bool? checking,
    DateTime? checkedAt,
    UpdateCheckResult? lastResult,
  }) => AppUpdateState(
    release: release == null ? this.release : release(),
    visible: visible ?? this.visible,
    checking: checking ?? this.checking,
    checkedAt: checkedAt ?? this.checkedAt,
    lastResult: lastResult ?? this.lastResult,
  );
}

/// Whether the automatic notice stays hidden for [release]: "Don't show
/// again" for its version, or "Later" for its version until [snooze] ends.
bool updateNoticeSuppressed(AppRelease release, {required DateTime now, String? snooze, String? skip}) {
  final v = '${release.version}';
  if (skip == v) return true;
  if (snooze != null) {
    final parts = snooze.split('|');
    final until = parts.length == 2 ? DateTime.tryParse(parts[1]) : null;
    if (parts.first == v && until != null && now.isBefore(until)) return true;
  }
  return false;
}

final appUpdateProvider = NotifierProvider<AppUpdate, AppUpdateState>(AppUpdate.new);

class AppUpdate extends Notifier<AppUpdateState> {
  bool _started = false;

  @override
  AppUpdateState build() => const AppUpdateState();

  ProgressStore get _store => ref.read(progressStoreProvider);
  DateTime _now() => ref.read(clockProvider)();

  /// On app start: the cached result, then a quiet check when the last one is
  /// older than [kAppUpdateCheckInterval].
  Future<void> startup() async {
    final source = ref.read(releaseSourceProvider);
    if (_started || source == null) return;
    _started = true;
    DateTime? last;
    try {
      last = DateTime.tryParse(await _store.getSetting(UpdateSettingKeys.lastCheck) ?? '');
      final cached = await _store.getSetting(UpdateSettingKeys.cache);
      if (cached != null && cached.isNotEmpty) {
        final release = AppRelease.fromJson(jsonDecode(cached), repo: kAppReleaseRepo);
        await _offer(release, manual: false, checkedAt: last);
      }
    } on Object catch (e) {
      debugPrint('[update] cache unreadable: $e');
    }
    if (last != null && _now().difference(last).abs() < kAppUpdateCheckInterval) return;
    await check();
  }

  /// Asks GitHub. [manual] (Settings): shows the notice even when snoozed or
  /// skipped. Failures never throw; the cached result stays.
  Future<UpdateCheckResult> check({bool manual = false}) async {
    final source = ref.read(releaseSourceProvider);
    if (source == null) return UpdateCheckResult.failed;
    if (state.checking) return state.lastResult ?? UpdateCheckResult.failed;
    state = state.copyWith(checking: true);
    try {
      final releases = await source.fetch();
      final update = pickUpdate(releases, ref.read(currentAppVersionProvider));
      final now = _now();
      await _store.setSetting(UpdateSettingKeys.lastCheck, now.toUtc().toIso8601String());
      await _store.setSetting(UpdateSettingKeys.cache, update == null ? '' : jsonEncode(update.toJson()));
      await _offer(update, manual: manual, checkedAt: now);
      final result = update == null ? UpdateCheckResult.upToDate : UpdateCheckResult.available;
      state = state.copyWith(checking: false, lastResult: result);
      return result;
    } on Object catch (e) {
      debugPrint('[update] check failed: $e');
      state = state.copyWith(checking: false, lastResult: UpdateCheckResult.failed);
      return UpdateCheckResult.failed;
    }
  }

  Future<void> _offer(AppRelease? release, {required bool manual, DateTime? checkedAt}) async {
    // A cached offer the app has since caught up with is no offer.
    if (release != null && !(release.version > ref.read(currentAppVersionProvider))) release = null;
    var visible = release != null;
    if (release != null && !manual) {
      visible = !updateNoticeSuppressed(
        release,
        now: _now(),
        snooze: await _store.getSetting(UpdateSettingKeys.snooze),
        skip: await _store.getSetting(UpdateSettingKeys.skip),
      );
    }
    state = state.copyWith(release: () => release, visible: visible, checkedAt: checkedAt);
  }

  /// Opens the fitting download (or the release page) and hides the notice
  /// for now. False when nothing could open it.
  Future<bool> download() async {
    final release = state.release;
    if (release == null) return false;
    final abis =
        (await ref
                .read(deviceInfoProvider.future)
                .timeout(const Duration(seconds: 2), onTimeout: () => DeviceInfo.unknown))
            .abis;
    final url = downloadUrl(release, ref.read(updatePlatformProvider), abis: abis);
    final opened = await ref.read(externalLinkOpenerProvider)(url);
    if (opened) state = state.copyWith(visible: false);
    return opened;
  }

  /// "Later": hides this version for [kAppUpdateSnooze].
  Future<void> later() async {
    final release = state.release;
    state = state.copyWith(visible: false);
    if (release == null) return;
    final until = _now().add(kAppUpdateSnooze).toUtc().toIso8601String();
    await _store.setSetting(UpdateSettingKeys.snooze, '${release.version}|$until');
  }

  /// "Don't show again for this version".
  Future<void> skipVersion() async {
    final release = state.release;
    state = state.copyWith(visible: false);
    if (release == null) return;
    await _store.setSetting(UpdateSettingKeys.skip, '${release.version}');
  }

  /// Shows the notice again (Settings, when an update is known).
  void show() {
    if (state.release != null) state = state.copyWith(visible: true);
  }
}
