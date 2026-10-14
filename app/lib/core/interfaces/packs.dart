/// Course pack sources: `LocalPackSource` (bundled assets, the app's data
/// folder, packs added from a file) and, since v0.4, `GitHubPackSource`
/// (Releases + index.json, checksums, atomic swap; see `remote_packs.dart`) behind
/// the same interface. Pure Dart.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../models/course.dart';

/// Where an installed pack came from.
enum PackOrigin {
  bundled, // shipped in the app's assets
  local, // added by the user from a file
  remote, // downloaded from the published packs (GitHubPackSource)
}

/// A pack that can be opened, as listed by a [PackSource].
@immutable
class PackInfo {
  const PackInfo({
    required this.id,
    required this.version,
    required this.title,
    required this.origin,
    this.schemaVersion = 1,
    this.unverified = false,
    this.sizeBytes,
    this.location,
  });

  final String id; // course id: 'it', 'nl', 'hns'
  final String version; // pack semver
  final I18n title;
  final PackOrigin origin;
  final int schemaVersion;
  final bool unverified;
  final int? sizeBytes;

  /// Human-readable location (file path or asset key), for debugging.
  final String? location;

  @override
  String toString() => 'PackInfo($id $version, $origin, $location)';
}

/// The database of a pack, as something the course loader can open.
@immutable
sealed class PackData {
  const PackData();
}

/// A database file on disk (native platforms).
final class PackFile extends PackData {
  const PackFile(this.path);
  final String path;
}

/// A database file in memory (web, downloads, file-picker results).
final class PackBytes extends PackData {
  const PackBytes(this.bytes, {this.name});
  final Uint8List bytes;
  final String? name; // original file name, if known
}

/// An opened pack: its info plus the data to load.
@immutable
class PackHandle {
  const PackHandle(this.info, this.data);
  final PackInfo info;
  final PackData data;
}

abstract interface class PackSource {
  /// Packs that can be opened now, one per course id (the newest version wins).
  Future<List<PackInfo>> available();

  /// The pack for [courseId]. Throws [StateError] if there is none.
  Future<PackHandle> open(String courseId);

  /// Validates and installs a pack (from a file picker now, a download later),
  /// replacing an installed pack with the same course id. Returns its info.
  Future<PackInfo> install(PackData data);

  /// Removes an installed (non-bundled) pack. Returns false if nothing was removed.
  /// Removing a newer copy of a bundled pack falls back to the bundled one.
  Future<bool> remove(String courseId);
}
