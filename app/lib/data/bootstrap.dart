/// Flutter bootstrap of the data layer: `openAppData()` opens the progress
/// database, the scheduler and the pack source for the current platform.
/// Wire it into Riverpod with e.g. a `FutureProvider<AppData>`.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/core.dart';
import 'app_data.dart';
import 'fsrs/fsrs_scheduler.dart';
import 'packs/asset_bundle_packs.dart';
import 'packs/github_pack_source.dart';
import 'packs/local_pack_source.dart';
import 'platform/platform.dart' as platform;
import 'progress/progress_connection.dart';
import 'progress/progress_repo.dart';

export 'app_data.dart';

class AppDataOptions {
  const AppDataOptions({
    this.dataDirectory,
    this.progressDbName = 'progress',
    this.bundled,
    this.sync = const NullSyncBackend(),
    this.appVersion,
    this.httpClient,
    this.packIndexUrl,
  });

  /// Base folder for `progress.sqlite` and `courses/` (native). Defaults to the
  /// app support directory (private on mobile; AppData/Application Support on desktop).
  final String? dataDirectory;
  final String progressDbName;

  /// Bundled packs; defaults to `assets/courses/*.sqlite` from the root bundle.
  final BundledPacks? bundled;
  final SyncBackend sync;

  /// This app's version; with it, packs are also offered online
  /// ([GitHubPackSource]). Null: local packs only.
  final String? appVersion;

  /// HTTP client for course downloads (default: a new `http.Client`).
  final http.Client? httpClient;

  /// Release index URL (default [kDefaultPackIndexUrl]).
  final Uri? packIndexUrl;
}

Future<AppData> openAppData({AppDataOptions options = const AppDataOptions()}) async {
  final String? base =
      kIsWeb ? null : (options.dataDirectory ?? (await getApplicationSupportDirectory()).path);
  final scheduler = FsrsScheduler();
  final progress = ProgressRepo(
    await openProgressDb(name: options.progressDbName, directory: base),
    scheduler: scheduler,
  );
  final local = LocalPackSource(
    bundled: options.bundled ?? AssetBundlePacks(),
    store: platform.defaultPackFileStore(base),
    readMeta: platform.readPackMeta,
    onWarning: (m) => debugPrint('[packs] $m'),
  );
  final appVersion = options.appVersion;
  final PackSource packs = appVersion == null
      ? local
      : GitHubPackSource(
          local: local,
          client: options.httpClient ?? http.Client(),
          appVersion: appVersion,
          indexUrl: options.packIndexUrl,
          // A downloaded pack must load fully before it replaces the old one.
          verify: (data) async => platform.loadCoursePack(data),
        );
  return AppData(
    progress: progress,
    packs: packs,
    loadPack: platform.loadCoursePack,
    scheduler: scheduler,
    sync: options.sync,
  );
}

/// Whether installing packs from a file path works on this platform.
const bool supportsPackFiles = platform.supportsPackFiles;
