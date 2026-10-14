/// `GitHubPackSource`: course packs published as GitHub Release assets of
/// `timoverlaan/tosk-data` (see `pipeline/pipeline/publish.py` and
/// docs/release.md, "Publishing course packs"). Pure Dart.
///
/// * **Index.** `index.json` comes from a stable URL, GitHub's redirect to the
///   newest release's asset ([kDefaultPackIndexUrl]); every course entry names
///   its own asset URL, version, size, sha256, schema version and minimum app
///   version.
/// * **Installed packs.** Everything installed (bundled, downloaded, added from
///   a file) lives in [local]; this source delegates the [PackSource] calls to
///   it, so it lists exactly what can be opened offline. [offers] combines that
///   with an index for the course picker.
/// * **Downloads** ([download]) stream into a staging file next to the
///   installed pack, checking size and sha256 on the way, then
///   [LocalPackSource.installStaged] validates the pack (course id, version,
///   schema), swaps it in atomically and opens it with [verify]; if that fails
///   the previous version is restored. Progress is never touched: item ids are
///   permanent, and facets whose items disappear simply stop being scheduled.
/// * **Errors** are [PackDownloadException]s with a short, polite message; the
///   installed packs keep working whatever happens online.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../core/core.dart';
import '../course/course_schema.dart';
import 'local_pack_source.dart';

/// The stable index URL: GitHub redirects `releases/latest/download/<asset>`
/// to that asset of the newest (non-draft, non-prerelease) release.
const String kDefaultPackIndexUrl =
    'https://github.com/timoverlaan/tosk-data/releases/latest/download/index.json';

/// Browsers follow redirects themselves (and fail on `followRedirects: false`).
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

class GitHubPackSource implements PackSource, RemotePackSource {
  GitHubPackSource({
    required this.local,
    required this.client,
    required this.appVersion,
    Uri? indexUrl,
    this.verify,
    this.maxRedirects = 5,
    this.timeout = const Duration(seconds: 30),
  }) : indexUrl = indexUrl ?? Uri.parse(kDefaultPackIndexUrl);

  /// Installed packs (bundled, downloaded, from files).
  final LocalPackSource local;
  final http.Client client;

  /// This app's version (`kAppVersion`), compared with `min_app_version`.
  final String appVersion;
  final Uri indexUrl;

  /// Opens a freshly swapped-in pack (the app loads it fully); a failure rolls
  /// the swap back. Null: only the meta is checked.
  final Future<void> Function(PackData data)? verify;
  final int maxRedirects;

  /// Connection and idle timeout.
  final Duration timeout;

  // ------------------------------------------------------------ PackSource (installed packs)

  @override
  Future<List<PackInfo>> available() => local.available();

  @override
  Future<PackHandle> open(String courseId) => local.open(courseId);

  @override
  Future<PackInfo> install(PackData data) => local.install(data);

  @override
  Future<bool> remove(String courseId) => local.remove(courseId);

  // ------------------------------------------------------------ remote

  @override
  Future<RemoteIndex> fetchIndex({Uri? url}) async {
    final res = await _get(url ?? indexUrl);
    final String text;
    try {
      text = utf8.decode(await res.stream.timeout(timeout).expand((c) => c).toList());
    } on Object catch (e) {
      throw _network(e);
    }
    try {
      return RemoteIndex.parse(text);
    } on FormatException catch (e) {
      throw PackDownloadException(
        PackDownloadError.corrupt,
        "The course list couldn't be read. Try again later.",
        detail: e.message,
      );
    }
  }

  /// Installed courses combined with [index] (see [combineOffers]).
  Future<List<CourseOffer>> offers(RemoteIndex? index) async => combineOffers(
    installed: {for (final p in await local.available()) p.id: p.version},
    index: index,
    appVersion: appVersion,
    schemaMajor: kCourseDbSchemaVersion,
  );

  @override
  Future<PackInfo> download(RemotePack pack, {DownloadProgress? onProgress, DownloadCancel? cancel}) async {
    final bad = incompatibility(pack, appVersion: appVersion, schemaMajor: kCourseDbSchemaVersion);
    if (bad != null) {
      throw PackDownloadException(PackDownloadError.incompatible, 'This version of the course $bad.');
    }
    if (cancel?.isCancelled ?? false) throw _cancelled;
    final abort = Completer<void>();
    cancel?.onCancel(() {
      if (!abort.isCompleted) abort.complete();
    });
    await local.available(); // bundled packs and crash recovery first
    final staging = await local.store.stage(pack.id);
    try {
      final res = await _get(Uri.parse(pack.url), abort: abort.future);
      final hash = _HashSink();
      final digest = crypto.sha256.startChunkedConversion(hash);
      var received = 0;
      onProgress?.call(0, pack.size);
      try {
        await for (final chunk in res.stream.timeout(timeout)) {
          if (cancel?.isCancelled ?? false) throw _cancelled;
          received += chunk.length;
          if (received > pack.size) {
            throw const PackDownloadException(
              PackDownloadError.corrupt,
              'The download was larger than expected. Try again later.',
            );
          }
          digest.add(chunk);
          await staging.add(chunk);
          onProgress?.call(received, pack.size);
        }
      } on PackDownloadException {
        rethrow;
      } on Object catch (e) {
        throw (cancel?.isCancelled ?? false) ? _cancelled : _network(e);
      }
      if (cancel?.isCancelled ?? false) throw _cancelled;
      digest.close();
      if (received != pack.size) {
        throw PackDownloadException(
          PackDownloadError.corrupt,
          'The download was incomplete. Try again.',
          detail: 'got $received of ${pack.size} bytes',
        );
      }
      if (hash.value != pack.sha256) {
        throw PackDownloadException(
          PackDownloadError.corrupt,
          "The downloaded file didn't match its checksum. Try again later.",
          detail: 'sha256 ${hash.value}, expected ${pack.sha256}',
        );
      }
      final data = await staging.finish();
      try {
        return await local.installStaged(pack.id, staging, data, version: pack.version, verify: verify);
      } on CourseFormatException catch (e) {
        throw PackDownloadException(
          PackDownloadError.corrupt,
          "The downloaded course couldn't be opened. Your current version is kept.",
          detail: e.message,
        );
      } on PackDownloadException {
        rethrow;
      } on Object catch (e) {
        throw PackDownloadException(
          PackDownloadError.corrupt,
          "The downloaded course couldn't be opened. Your current version is kept.",
          detail: '$e',
        );
      }
    } on Object {
      await staging.discard();
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  static const _cancelled = PackDownloadException(PackDownloadError.cancelled, 'Download cancelled.');

  /// GET [url], following redirects by hand (natively), so GitHub's
  /// `releases/download` → object storage hop works with any client.
  Future<http.StreamedResponse> _get(Uri url, {Future<void>? abort}) async {
    var current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final req = http.AbortableRequest('GET', current, abortTrigger: abort)..followRedirects = _isWeb;
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(timeout);
      } on http.RequestAbortedException {
        throw _cancelled;
      } on Object catch (e) {
        throw _network(e);
      }
      final location = res.headers['location'];
      if (const {301, 302, 303, 307, 308}.contains(res.statusCode) && location != null) {
        unawaited(res.stream.drain<void>().catchError((_) {}));
        current = current.resolve(location);
        continue;
      }
      if (res.statusCode != 200) {
        unawaited(res.stream.drain<void>().catchError((_) {}));
        throw PackDownloadException(
          PackDownloadError.http,
          res.statusCode == 404
              ? "The course server doesn't have this file (yet). Try again later."
              : 'The course server had a problem (${res.statusCode}). Try again later.',
          detail: 'HTTP ${res.statusCode} for $current',
        );
      }
      return res;
    }
    throw PackDownloadException(PackDownloadError.http, 'The course server redirected too often.', detail: '$url');
  }

  static PackDownloadException _network(Object e) => PackDownloadException(
    PackDownloadError.network,
    "Couldn't reach the course server. Check your connection; everything installed keeps working offline.",
    detail: '$e',
  );
}

class _HashSink implements Sink<crypto.Digest> {
  String? value;
  @override
  void add(crypto.Digest data) => value = data.toString();
  @override
  void close() {}
}
