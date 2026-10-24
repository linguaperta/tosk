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

/// Web builds read the course index from the same-origin pack mirror next to
/// the app (GitHub Pages: `<site>/packs/index.json`, gzipped packs; see
/// docs/release.md, "Web app and pack mirror"), which avoids the CORS problem
/// of GitHub's release redirects. Empty: the GitHub Releases index.
const String kWebPackIndexPath = String.fromEnvironment('TOSK_WEB_PACK_INDEX', defaultValue: 'packs/index.json');

Uri? _defaultIndexUrl() =>
    kIsWeb && kWebPackIndexPath.isNotEmpty ? platform.pageBaseUri()?.resolve(kWebPackIndexPath) : null;

class AppDataOptions {
  const AppDataOptions({
    this.dataDirectory,
    this.progressDbName = 'progress',
    this.bundled,
    this.appVersion,
    this.httpClient,
    this.packIndexUrl,
    this.webPackMirror,
  });

  /// Base folder for `progress.sqlite` and `courses/` (native). Defaults to the
  /// app support directory (private on mobile; AppData/Application Support on desktop).
  final String? dataDirectory;
  final String progressDbName;

  /// Bundled packs; defaults to `assets/courses/*.sqlite` from the root bundle.
  final BundledPacks? bundled;

  /// This app's version; with it, packs are also offered online
  /// ([GitHubPackSource]). Null: local packs only.
  final String? appVersion;

  /// HTTP client for course downloads (default: a new `http.Client`).
  final http.Client? httpClient;

  /// Release index URL (default [kDefaultPackIndexUrl]).
  final Uri? packIndexUrl;

  /// Courses come only from the web pack mirror, not from the app bundle
  /// (null: [usesWebPackMirror] decides; tests set it).
  final bool? webPackMirror;

  /// Whether this start gets its courses from the web pack mirror; see
  /// [usesWebPackMirror].
  bool get packsFromWebMirror =>
      webPackMirror ??
      usesWebPackMirror(
        web: kIsWeb,
        bundledGiven: bundled != null,
        downloads: appVersion != null,
        webIndexPath: kWebPackIndexPath,
      );
}

/// Whether a start reads its courses only from the same-origin web pack
/// mirror: a web build with downloads, the mirror configured
/// ([kWebPackIndexPath]) and no bundled packs passed in. Then the packs in
/// the app bundle (`assets/courses/*.sqlite`, ~57 MB for three courses) are
/// never fetched: the learner downloads the gzipped copy (~5 MB) of each
/// course they pick. Without that, every first visit downloaded every
/// bundled pack (and every start read them all again) just to list them.
bool usesWebPackMirror({
  required bool web,
  required bool bundledGiven,
  required bool downloads,
  required String webIndexPath,
}) => web && !bundledGiven && downloads && webIndexPath.isNotEmpty;

Future<AppData> openAppData({AppDataOptions options = const AppDataOptions()}) async {
  final String? base = kIsWeb ? null : (options.dataDirectory ?? (await getApplicationSupportDirectory()).path);
  final scheduler = FsrsScheduler();
  final progress = ProgressRepo(
    await openProgressDb(name: options.progressDbName, directory: base),
    scheduler: scheduler,
  );
  final local = LocalPackSource(
    bundled: options.bundled ?? (options.packsFromWebMirror ? const NoBundledPacks() : AssetBundlePacks()),
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
          indexUrl: options.packIndexUrl ?? _defaultIndexUrl(),
          sameOrigin: kIsWeb ? platform.pageBaseUri() : null,
          // A downloaded pack must load fully before it replaces the old one.
          verify: (data) async => platform.loadCoursePack(data),
        );
  return AppData(
    progress: progress,
    packs: packs,
    loadPack: platform.loadCoursePack,
    scheduler: scheduler,
  );
}

/// Whether installing packs from a file path works on this platform.
const bool supportsPackFiles = platform.supportsPackFiles;
