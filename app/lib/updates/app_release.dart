/// App releases on GitHub (`linguaperta/tosk`), for the update notice of
/// sideloaded builds (Android, desktop): version parsing and comparison, the
/// newest release newer than this app, the download that fits this device,
/// and a short excerpt of the release notes. Pure Dart, no I/O.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A version `X.Y.Z` with an optional pre-release part (`0.8.0-rc.1`), as in
/// semantic versioning: build metadata (`+19`) is ignored, and a pre-release
/// sorts before its release (`0.8.0-rc.1 < 0.8.0`).
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.pre = const []]);

  final int major;
  final int minor;
  final int patch;

  /// Pre-release identifiers (`['rc', '1']`), empty for a release.
  final List<String> pre;

  bool get isPreRelease => pre.isNotEmpty;

  static final _pattern = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$');

  /// `0.7.6`, `0.7.6+19`, `0.8`, `0.8.0-beta.2`; null for anything else.
  static AppVersion? parse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    final pre = m.group(4);
    return AppVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
      pre == null ? const [] : pre.split('.').where((p) => p.isNotEmpty).toList(),
    );
  }

  static final _tagPrefix = RegExp(r'^(?:v|preview-?)', caseSensitive: false);

  /// A release tag: `preview-0.7.6`, `v0.7.6`, `v0.8.0-rc.1` (and a bare
  /// `0.7.6`). Null for other tags (`packs-20261024`).
  static AppVersion? fromTag(String tag) => parse(tag.trim().replaceFirst(_tagPrefix, ''));

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    // A release is newer than any of its pre-releases.
    if (pre.isEmpty || other.pre.isEmpty) return (pre.isEmpty ? 1 : 0) - (other.pre.isEmpty ? 1 : 0);
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final c = _comparePart(pre[i], other.pre[i]);
      if (c != 0) return c;
    }
    return pre.length.compareTo(other.pre.length);
  }

  /// Semver: numeric parts compare as numbers and sort before text parts.
  static int _comparePart(String a, String b) {
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, const ListEquality<String>().hash(pre));

  /// `0.7.6` or `0.8.0-rc.1` (no build number).
  @override
  String toString() => '$major.$minor.$patch${pre.isEmpty ? '' : '-${pre.join('.')}'}';
}

/// One downloadable file of a release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size = 0});

  final String name;
  final Uri url;
  final int size;

  Map<String, Object?> toJson() => {'name': name, 'browser_download_url': '$url', 'size': size};
}

/// One release from the GitHub Releases API (only the fields the notice uses).
@immutable
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.title,
    required this.notes,
    required this.page,
    this.prerelease = false,
    this.draft = false,
    this.publishedAt,
    this.assets = const [],
  });

  final String tag;
  final AppVersion version;

  /// The release title ("Preview 7.6 (0.7.6)"); the tag when it has none.
  final String title;

  /// The release notes (markdown), possibly empty.
  final String notes;

  /// The release page on github.com.
  final Uri page;
  final bool prerelease;
  final bool draft;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// Only https links to GitHub are ever opened.
  static Uri? _safeUrl(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    return host == 'github.com' || host.endsWith('.github.com') || host.endsWith('.githubusercontent.com') ? uri : null;
  }

  /// One entry of `GET /repos/{owner}/{repo}/releases`; null when it isn't an
  /// app release (no version in the tag, or malformed).
  static AppRelease? fromJson(Object? json, {required String repo}) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = AppVersion.fromTag(tag);
    if (version == null) return null;
    final name = json['name'];
    final body = json['body'];
    final assets = <ReleaseAsset>[];
    final list = json['assets'];
    if (list is List) {
      for (final a in list) {
        if (a is! Map || a['name'] is! String) continue;
        final url = _safeUrl(a['browser_download_url']);
        if (url == null) continue;
        assets.add(ReleaseAsset(name: a['name'] as String, url: url, size: a['size'] is int ? a['size'] as int : 0));
      }
    }
    return AppRelease(
      tag: tag,
      version: version,
      title: name is String && name.trim().isNotEmpty ? name.trim() : tag,
      notes: body is String ? body : '',
      page: _safeUrl(json['html_url']) ?? Uri.https('github.com', '/$repo/releases/tag/${Uri.encodeComponent(tag)}'),
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
      publishedAt: json['published_at'] is String ? DateTime.tryParse(json['published_at'] as String) : null,
      assets: assets,
    );
  }

  /// Every app release in an API response (a JSON list); other entries are skipped.
  static List<AppRelease> listFromJson(String body, {required String repo}) {
    final json = jsonDecode(body);
    if (json is! List) throw const FormatException('Expected a list of releases');
    return [for (final r in json) ?AppRelease.fromJson(r, repo: repo)];
  }

  /// The same shape as the API, for the cache.
  Map<String, Object?> toJson() => {
    'tag_name': tag,
    'name': title,
    'body': notes,
    'html_url': '$page',
    'prerelease': prerelease,
    'draft': draft,
    if (publishedAt != null) 'published_at': publishedAt!.toUtc().toIso8601String(),
    'assets': [for (final a in assets) a.toJson()],
  };

  /// The first [maxLines] non-empty lines of the notes as plain text (markdown
  /// marks stripped), at most [maxChars] characters.
  String notesExcerpt({int maxLines = 3, int maxChars = 280}) {
    final lines = <String>[];
    for (var line in const LineSplitter().convert(notes)) {
      line = line
          .trim()
          .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
          .replaceFirst(RegExp(r'^([-*+]|\d+\.)\s+'), '• ')
          .replaceAll(RegExp(r'\*\*|__|`'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);
      if (line.isEmpty || line.startsWith('<!--')) continue;
      lines.add(line);
      if (lines.length == maxLines) break;
    }
    final text = lines.join('\n');
    return text.length <= maxChars ? text : '${text.substring(0, maxChars - 1).trimRight()}…';
  }
}

/// The newest release that is newer than [current]: drafts are skipped,
/// pre-releases count (every preview is one). Null when there is none.
AppRelease? pickUpdate(Iterable<AppRelease> releases, AppVersion current) {
  AppRelease? best;
  for (final r in releases) {
    if (r.draft || !(r.version > current)) continue;
    if (best == null ||
        r.version > best.version ||
        (r.version == best.version && (r.publishedAt?.isAfter(best.publishedAt ?? DateTime(0)) ?? false))) {
      best = r;
    }
  }
  return best;
}

/// What the Download button opens on this kind of device.
enum UpdatePlatform { android, windows, macos, linux, other }

/// File name tokens per Android ABI (`Build.SUPPORTED_ABIS`), most specific first.
const Map<String, List<String>> _abiTokens = {
  'arm64-v8a': ['arm64-v8a', 'arm64', 'aarch64'],
  'armeabi-v7a': ['armeabi-v7a', 'armv7', 'arm32', 'armeabi'],
  'x86_64': ['x86_64', 'x64'],
};

const Map<UpdatePlatform, ({List<String> tokens, List<String> extensions})> _desktop = {
  UpdatePlatform.windows: (tokens: ['windows', 'win64', 'win'], extensions: ['.zip', '.msix', '.exe']),
  UpdatePlatform.macos: (tokens: ['macos', 'mac', 'darwin'], extensions: ['.dmg', '.zip']),
  UpdatePlatform.linux: (tokens: ['linux'], extensions: ['.tar.gz', '.appimage', '.deb', '.zip']),
};

bool _hasToken(String name, String token) => RegExp('(^|[-_. ])${RegExp.escape(token)}(\$|[-_. ])').hasMatch(name);

/// The release file for this device, or null (then the release page opens).
///
/// Android: the APK for the first of [abis] (the device's preference order)
/// that has one, else an APK without an ABI in its name (a universal APK).
/// Desktop: the platform's archive.
ReleaseAsset? pickAsset(AppRelease release, UpdatePlatform platform, {List<String> abis = const []}) {
  switch (platform) {
    case UpdatePlatform.android:
      final apks = [
        for (final a in release.assets)
          if (a.name.toLowerCase().endsWith('.apk')) a,
      ];
      for (final abi in abis) {
        final tokens = _abiTokens[abi.toLowerCase()];
        if (tokens == null) continue;
        for (final apk in apks) {
          if (tokens.any((t) => _hasToken(apk.name.toLowerCase(), t))) return apk;
        }
      }
      final allTokens = _abiTokens.values.expand((t) => t).toList();
      return apks.firstWhereOrNull((a) => !allTokens.any((t) => _hasToken(a.name.toLowerCase(), t)));
    case UpdatePlatform.windows || UpdatePlatform.macos || UpdatePlatform.linux:
      final spec = _desktop[platform]!;
      return release.assets.firstWhereOrNull((a) {
        final n = a.name.toLowerCase();
        return spec.extensions.any(n.endsWith) && spec.tokens.any((t) => _hasToken(n, t));
      });
    case UpdatePlatform.other:
      return null;
  }
}

/// Where Download goes: the fitting file, else the release page.
Uri downloadUrl(AppRelease release, UpdatePlatform platform, {List<String> abis = const []}) =>
    pickAsset(release, platform, abis: abis)?.url ?? release.page;
