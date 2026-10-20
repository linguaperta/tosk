/// Course downloads and updates for the UI: the online index (checked at most
/// once a day on start when enabled, or on request), the combined list of
/// installed and online courses, running downloads with progress and cancel,
/// and adding a course pack from a file.
///
/// Nothing is ever downloaded without a tap. Errors are kept per action and
/// shown politely; whatever is installed keeps working offline.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_version.dart';
import '../../core/core.dart';
import '../../data/bootstrap.dart' show supportsPackFiles;
import '../../data/course/course_schema.dart';
import '../../providers.dart';
import '../settings/setting_keys.dart';

/// Online course packs, or null when the app runs without downloads (tests,
/// no data layer).
final remotePacksProvider = Provider<RemotePackSource?>((ref) => ref.watch(appDataProvider)?.remote);

/// This app's version, compared with each pack's `min_app_version`.
final appVersionProvider = Provider<String>((ref) => kAppVersion);

/// Picks a course pack file; null when the user cancels.
typedef PackFilePicker = Future<PackData?> Function();

final packFilePickerProvider = Provider<PackFilePicker>((ref) => pickPackFile);

/// Installs a pack from a file (replacing an installed pack of the same
/// course; progress is kept). Null without a data layer.
final packInstallerProvider = Provider<Future<PackInfo> Function(PackData data)?>(
  (ref) => ref.watch(appDataProvider)?.installPack,
);

/// The system file picker (the debug screen's flow).
Future<PackData?> pickPackFile() async {
  final f = await FilePicker.pickFile(dialogTitle: 'Choose a course pack (.sqlite)');
  if (f == null) return null;
  final path = f.path;
  return (supportsPackFiles && path != null) ? PackFile(path) : PackBytes(await f.readAsBytes(), name: f.name);
}

/// How often the automatic check runs at most.
const Duration kUpdateCheckInterval = Duration(hours: 24);

@immutable
class CourseDownload {
  const CourseDownload({required this.received, required this.total, this.error, this.cancel});

  final int received;
  final int total;

  /// The last failure (the download is no longer running).
  final String? error;
  final DownloadCancel? cancel;

  bool get running => error == null;
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

@immutable
class CourseUpdatesState {
  const CourseUpdatesState({this.index, this.checkedAt, this.checking = false, this.error, this.downloads = const {}});

  /// The latest index (fetched, or cached from an earlier check).
  final RemoteIndex? index;
  final DateTime? checkedAt;
  final bool checking;

  /// The last manual check's failure (automatic checks fail silently).
  final String? error;
  final Map<String, CourseDownload> downloads;

  CourseUpdatesState copyWith({
    RemoteIndex? index,
    DateTime? checkedAt,
    bool? checking,
    String? Function()? error,
    Map<String, CourseDownload>? downloads,
  }) => CourseUpdatesState(
    index: index ?? this.index,
    checkedAt: checkedAt ?? this.checkedAt,
    checking: checking ?? this.checking,
    error: error == null ? this.error : error(),
    downloads: downloads ?? this.downloads,
  );
}

final courseUpdatesProvider = NotifierProvider<CourseUpdates, CourseUpdatesState>(CourseUpdates.new);

class CourseUpdates extends Notifier<CourseUpdatesState> {
  bool _started = false;

  @override
  CourseUpdatesState build() => const CourseUpdatesState();

  RemotePackSource? get _remote => ref.read(remotePacksProvider);
  ProgressStore get _store => ref.read(progressStoreProvider);

  /// On app start: loads the cached index and, if automatic checks are on and
  /// the last check is older than [kUpdateCheckInterval], checks (silently).
  Future<void> startup() async {
    if (_started || _remote == null) return;
    _started = true;
    try {
      final cached = await _store.getSetting(SettingKeys.packIndexCache);
      final last = DateTime.tryParse(await _store.getSetting(SettingKeys.packLastCheck) ?? '');
      if (cached != null && cached.isNotEmpty && state.index == null) {
        state = state.copyWith(index: RemoteIndex.parse(cached), checkedAt: last);
      }
      final settings = await ref.read(settingsProvider.future);
      if (!settings.autoCheckCourseUpdates) return;
      final now = ref.read(clockProvider)();
      if (last != null && now.difference(last) < kUpdateCheckInterval) return;
    } on Object catch (e) {
      debugPrint('[packs] update check skipped: $e');
    }
    await check(quiet: true);
  }

  /// Fetches the index. [quiet]: failures are not shown (offline at start).
  Future<void> check({bool quiet = false}) async {
    final remote = _remote;
    if (remote == null || state.checking) return;
    state = state.copyWith(checking: true, error: () => null);
    try {
      final custom = (await _store.getSetting(SettingKeys.packIndexUrl))?.trim();
      final index = await remote.fetchIndex(url: custom == null || custom.isEmpty ? null : Uri.tryParse(custom));
      final now = ref.read(clockProvider)();
      state = state.copyWith(index: index, checkedAt: now, checking: false);
      await _store.setSetting(SettingKeys.packIndexCache, index.toJsonString());
      await _store.setSetting(SettingKeys.packLastCheck, now.toUtc().toIso8601String());
    } on Object catch (e) {
      debugPrint('[packs] update check failed: $e');
      final message = e is PackDownloadException
          ? e.message
          : "Couldn't check for course updates. Everything installed keeps working offline.";
      state = state.copyWith(checking: false, error: () => quiet ? null : message);
    }
  }

  /// Downloads course [id] from the index (a tap on Download or Update).
  /// Returns the installed pack, or null on failure or cancel (the error is
  /// in [CourseUpdatesState.downloads]).
  Future<PackInfo?> download(String id) async {
    final remote = _remote;
    final pack = state.index?[id];
    if (remote == null || pack == null || (state.downloads[id]?.running ?? false)) return null;
    final cancel = DownloadCancel();
    _setDownload(id, CourseDownload(received: 0, total: pack.downloadSize(web: kIsWeb), cancel: cancel));
    var lastPercent = -1;
    try {
      void progress(int got, int total) {
        final percent = total > 0 ? got * 100 ~/ total : 0;
        if (percent == lastPercent) return;
        lastPercent = percent;
        _setDownload(id, CourseDownload(received: got, total: total, cancel: cancel));
      }

      final app = ref.read(appDataProvider);
      final info = app != null && identical(app.remote, remote)
          ? await app.downloadPack(pack, onProgress: progress, cancel: cancel)
          : await remote.download(pack, onProgress: progress, cancel: cancel);
      _setDownload(id, null);
      refreshCourses(id);
      return info;
    } on Object catch (e) {
      debugPrint('[packs] download of $id failed: $e');
      if (e is PackDownloadException && e.kind == PackDownloadError.cancelled) {
        _setDownload(id, null);
      } else {
        _setDownload(
          id,
          CourseDownload(
            received: 0,
            total: pack.downloadSize(web: kIsWeb),
            error: e is PackDownloadException ? e.message : "The download didn't work. Try again later.",
          ),
        );
      }
      return null;
    }
  }

  void cancel(String id) => state.downloads[id]?.cancel?.cancel();

  /// Clears a failed download's message.
  void dismissError(String id) {
    if (state.downloads[id]?.error != null) _setDownload(id, null);
  }

  /// After a pack was installed or replaced: list and open the new version.
  void refreshCourses(String id) {
    ref.invalidate(availableCoursesProvider);
    ref.invalidate(coursePreviewProvider(id));
  }

  void _setDownload(String id, CourseDownload? d) {
    final next = {...state.downloads};
    if (d == null) {
      next.remove(id);
    } else {
      next[id] = d;
    }
    state = state.copyWith(downloads: next);
  }
}

/// Installed courses (demo courses don't count) combined with the index, by id.
final courseOffersProvider = Provider<Map<String, CourseOffer>>((ref) {
  final catalog = ref.watch(courseCatalogProvider);
  final installed = ref.watch(availableCoursesProvider).value ?? const <CourseMeta>[];
  final index = ref.watch(courseUpdatesProvider.select((s) => s.index));
  final offers = combineOffers(
    installed: {
      for (final c in installed)
        if (!catalog.isDemo(c.id)) c.id: c.version,
    },
    index: index,
    appVersion: ref.watch(appVersionProvider),
    schemaMajor: kCourseDbSchemaVersion,
  );
  return {for (final o in offers) o.id: o};
});

/// Whether one of my courses has an update (the dot on the course switcher).
final courseUpdateAvailableProvider = Provider<bool>((ref) {
  final offers = ref.watch(courseOffersProvider);
  final mine = ref.watch(settingsProvider.select((s) => s.value?.myCourseIds ?? const <String>[]));
  return mine.any((id) => offers[id]?.status == OfferStatus.updateAvailable);
});

/// "12 MB", "7.4 MB", "0.3 MB".
String formatMegabytes(int bytes) {
  final mb = bytes / 1e6;
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}
