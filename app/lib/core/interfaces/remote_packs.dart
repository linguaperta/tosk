/// Course packs published online: the release index (`index.json`), what the
/// app can do with each course (download, update), and the interface the UI
/// downloads through. Implemented by `GitHubPackSource`
/// (`data/packs/github_pack_source.dart`). Pure Dart.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../models/course.dart';
import 'packs.dart';

/// Highest `index_version` this app understands.
const int kSupportedIndexVersion = 1;

/// One course in the release index.
@immutable
class RemotePack {
  const RemotePack({
    required this.id,
    required this.version,
    required this.title,
    required this.url,
    required this.sha256,
    required this.size,
    required this.schemaVersion,
    this.description = const {},
    this.target = '',
    this.sources = const [],
    this.unverified = false,
    this.minAppVersion = '0.0.0',
    this.webUrl,
    this.gzSha256,
    this.gzSize,
  });

  factory RemotePack.fromJson(Map<String, dynamic> j) {
    I18n i18n(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : const {};
    final id = j['id'];
    final url = j['url'];
    final sha = j['sha256'];
    final size = j['size'];
    if (id is! String || id.isEmpty || url is! String || sha is! String || size is! int) {
      throw FormatException('Course entry is missing id, url, sha256 or size: $j');
    }
    return RemotePack(
      id: id,
      version: '${j['version'] ?? '0.0.0'}',
      title: i18n(j['title']),
      description: i18n(j['description']),
      target: '${j['target'] ?? id}',
      sources: [for (final s in (j['sources'] as List?) ?? const []) '$s'],
      unverified: j['unverified'] == true,
      schemaVersion: '${j['schema_version'] ?? '1'}',
      minAppVersion: '${j['min_app_version'] ?? '0.0.0'}',
      sha256: sha.toLowerCase(),
      size: size,
      url: url,
      webUrl: j['web_url'] is String ? j['web_url'] as String : null,
      gzSha256: j['gz_sha256'] is String ? (j['gz_sha256'] as String).toLowerCase() : null,
      gzSize: j['gz_size'] is int ? j['gz_size'] as int : null,
    );
  }

  final String id;
  final String version;
  final I18n title;
  final I18n description;
  final String target;

  /// Languages with translations (`meta.translations`).
  final List<String> sources;
  final bool unverified;

  /// The pack's `meta.schema_version` (`'1'`, `'1.1'`); the major must match the app's.
  final String schemaVersion;

  /// Oldest app version that can use this pack.
  final String minAppVersion;
  final String sha256;
  final int size;

  /// The pack itself (GitHub Releases); absolute, or relative to the index URL.
  final String url;

  /// v0.7, optional: a gzipped copy for the web app (the GitHub Pages pack
  /// mirror), with the checksum and size of the `.gz` file; [sha256] and
  /// [size] stay those of the uncompressed pack. Absolute or relative to the
  /// index URL. Older apps ignore these fields.
  final String? webUrl;
  final String? gzSha256;
  final int? gzSize;

  /// The gzipped copy can be used (all three fields present).
  bool get hasWebPack => webUrl != null && gzSha256 != null && gzSize != null;

  /// Bytes a download transfers: the `.gz` where the web copy is used.
  int downloadSize({required bool web}) => web && hasWebPack ? gzSize! : size;

  /// This entry with [url] and [webUrl] resolved against [base] (the URL the index came from).
  RemotePack resolvedAgainst(Uri base) => RemotePack(
    id: id,
    version: version,
    title: title,
    description: description,
    target: target,
    sources: sources,
    unverified: unverified,
    schemaVersion: schemaVersion,
    minAppVersion: minAppVersion,
    sha256: sha256,
    size: size,
    url: base.resolve(url).toString(),
    webUrl: webUrl == null ? null : base.resolve(webUrl!).toString(),
    gzSha256: gzSha256,
    gzSize: gzSize,
  );

  int get schemaMajor => int.tryParse(schemaVersion.split('.').first) ?? -1;

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'title': title,
    'description': description,
    'target': target,
    'sources': sources,
    'unverified': unverified,
    'schema_version': schemaVersion,
    'min_app_version': minAppVersion,
    'sha256': sha256,
    'size': size,
    'url': url,
    'web_url': ?webUrl,
    'gz_sha256': ?gzSha256,
    'gz_size': ?gzSize,
  };
}

/// The release index (`index.json`), see `pipeline/pipeline/publish.py`.
@immutable
class RemoteIndex {
  const RemoteIndex({required this.courses, this.indexVersion = 1, this.generatedAt, this.tag});

  /// Parses `index.json`. Throws [FormatException] for a malformed index or one
  /// from a newer `index_version` than [kSupportedIndexVersion].
  factory RemoteIndex.parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The course list is not valid JSON');
    }
    if (j is! Map<String, dynamic> || j['courses'] is! List) {
      throw const FormatException('The course list has no "courses"');
    }
    final version = j['index_version'];
    if (version is! int) throw const FormatException('The course list has no index_version');
    if (version > kSupportedIndexVersion) {
      throw FormatException('The course list needs a newer app (index_version $version)');
    }
    final courses = <RemotePack>[];
    for (final c in j['courses'] as List) {
      if (c is Map<String, dynamic>) courses.add(RemotePack.fromJson(c));
    }
    return RemoteIndex(
      courses: courses,
      indexVersion: version,
      generatedAt: DateTime.tryParse('${j['generated_at']}'),
      tag: j['tag'] as String?,
    );
  }

  final List<RemotePack> courses;
  final int indexVersion;
  final DateTime? generatedAt;
  final String? tag;

  RemotePack? operator [](String id) => courses.where((c) => c.id == id).firstOrNull;

  /// Every course's URLs resolved against [base] (where the index was fetched).
  RemoteIndex resolvedAgainst(Uri base) => RemoteIndex(
    courses: [for (final c in courses) c.resolvedAgainst(base)],
    indexVersion: indexVersion,
    generatedAt: generatedAt,
    tag: tag,
  );

  String toJsonString() => jsonEncode({
    'index_version': indexVersion,
    'generated_at': generatedAt?.toUtc().toIso8601String(),
    'tag': tag,
    'courses': [for (final c in courses) c.toJson()],
  });
}

/// What the app can do with a course, given what is installed and the index.
enum OfferStatus {
  /// Installed, and the index has nothing newer (or the course isn't online).
  installed,

  /// Installed, and the index has a newer version the app can use.
  updateAvailable,

  /// Not installed; can be downloaded.
  downloadable,

  /// The online version needs a newer app (schema or `min_app_version`).
  needsAppUpdate,
}

/// One course in the course picker: installed, online, or both.
@immutable
class CourseOffer {
  const CourseOffer({required this.id, required this.status, this.installedVersion, this.remote});

  final String id;
  final OfferStatus status;

  /// Version on this device (bundled, downloaded or added from a file).
  final String? installedVersion;
  final RemotePack? remote;

  bool get canDownload => status == OfferStatus.updateAvailable || status == OfferStatus.downloadable;
}

/// Why a remote pack can't be used by this app, or null when it can.
String? incompatibility(RemotePack p, {required String appVersion, required int schemaMajor}) {
  if (p.schemaMajor != schemaMajor) {
    return 'needs a newer app (course format ${p.schemaVersion})';
  }
  if (compareVersions(appVersion, p.minAppVersion) < 0) return 'needs app ${p.minAppVersion} or newer';
  return null;
}

/// Combines installed courses ([installed]: course id -> version) with the
/// [index]: every installed course, then the online-only ones, in index order.
List<CourseOffer> combineOffers({
  required Map<String, String> installed,
  required RemoteIndex? index,
  required String appVersion,
  required int schemaMajor,
}) {
  final out = <CourseOffer>[];
  for (final MapEntry(key: id, value: version) in installed.entries) {
    final r = index?[id];
    final newer = r != null && compareVersions(r.version, version) > 0;
    final usable = r != null && incompatibility(r, appVersion: appVersion, schemaMajor: schemaMajor) == null;
    out.add(
      CourseOffer(
        id: id,
        installedVersion: version,
        remote: r,
        status: newer && usable ? OfferStatus.updateAvailable : OfferStatus.installed,
      ),
    );
  }
  for (final r in index?.courses ?? const <RemotePack>[]) {
    if (installed.containsKey(r.id)) continue;
    final bad = incompatibility(r, appVersion: appVersion, schemaMajor: schemaMajor);
    out.add(
      CourseOffer(id: r.id, remote: r, status: bad == null ? OfferStatus.downloadable : OfferStatus.needsAppUpdate),
    );
  }
  return out;
}

/// Download progress: [received] of [total] bytes.
typedef DownloadProgress = void Function(int received, int total);

/// Cancels a running download: call [cancel]; the download then throws
/// [PackDownloadException] with [PackDownloadError.cancelled].
class DownloadCancel {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

enum PackDownloadError {
  /// No connection, DNS failure, connection dropped mid-download.
  network,

  /// The server answered with an error status (404, 500...).
  http,

  /// Wrong size or checksum, or the file isn't a valid pack for this course.
  corrupt,

  /// The pack needs a newer app.
  incompatible,

  /// The user cancelled.
  cancelled,
}

/// A failed index fetch or download. [message] is short and polite, for the UI.
class PackDownloadException implements Exception {
  const PackDownloadException(this.kind, this.message, {this.detail});
  final PackDownloadError kind;
  final String message;

  /// Technical detail (status code, exception text), for logs.
  final String? detail;

  @override
  String toString() => 'PackDownloadException($kind): $message${detail == null ? '' : ' ($detail)'}';
}

/// Online course packs, as the UI sees them.
abstract interface class RemotePackSource {
  /// Fetches the release index (from [url], else the default index URL).
  Future<RemoteIndex> fetchIndex({Uri? url});

  /// Downloads, verifies and installs [pack], replacing the installed version
  /// of that course atomically. Progress (item ids, the review log) is never touched.
  Future<PackInfo> download(RemotePack pack, {DownloadProgress? onProgress, DownloadCancel? cancel});
}

/// Compares semantic versions (`1.2.3`, `1.2.3-beta.1`); a pre-release sorts
/// before its release, build metadata (`+…`) is ignored. Non-numeric parts
/// compare as strings.
int compareVersions(String a, String b) {
  (List<String>, List<String>?) split(String v) {
    final core = v.split('+').first;
    final dash = core.indexOf('-');
    final main = (dash < 0 ? core : core.substring(0, dash)).split('.');
    final pre = dash < 0 ? null : core.substring(dash + 1).split('.');
    return (main, pre);
  }

  int cmpParts(List<String> x, List<String> y, {bool padZero = true}) {
    final n = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      if (!padZero && (i >= x.length || i >= y.length)) return x.length.compareTo(y.length);
      final xs = i < x.length ? x[i] : '0';
      final ys = i < y.length ? y[i] : '0';
      final xi = int.tryParse(xs);
      final yi = int.tryParse(ys);
      final c = (xi != null && yi != null)
          ? xi.compareTo(yi)
          : (xi != null ? -1 : (yi != null ? 1 : xs.compareTo(ys)));
      if (c != 0) return c;
    }
    return 0;
  }

  final (am, ap) = split(a.trim());
  final (bm, bp) = split(b.trim());
  final c = cmpParts(am, bm);
  if (c != 0) return c;
  if (ap == null && bp == null) return 0;
  if (ap == null) return 1;
  if (bp == null) return -1;
  return cmpParts(ap, bp, padZero: false);
}
