/// Storage for installed course packs. Pure Dart.
///
/// Natively this is a `courses/` folder (`NativePackFileStore` in
/// `data/platform/platform_native.dart`); on the web and in tests it is
/// [MemoryPackFileStore].
library;

import 'dart:typed_data';

import '../../core/core.dart';

abstract interface class PackFileStore {
  /// The data of the installed pack [courseId] (a [PackFile] natively, [PackBytes] in memory).
  Future<PackData> data(String courseId);

  /// Size in bytes of the installed pack, or null if unknown / not installed.
  Future<int?> size(String courseId);

  /// Installs [bytes] as the pack for [courseId], atomically replacing an existing one.
  Future<void> writeBytes(String courseId, Uint8List bytes);

  /// Installs a copy of the database file at [sourcePath] (native only).
  Future<void> copyFile(String courseId, String sourcePath);

  Future<bool> delete(String courseId);

  /// Small JSON manifest kept next to the packs (versions and origins).
  Future<String?> readManifest();
  Future<void> writeManifest(String json);

  /// Where a pack is stored, for display.
  String location(String courseId);
}

class MemoryPackFileStore implements PackFileStore {
  final Map<String, Uint8List> _packs = {};
  String? _manifest;

  @override
  Future<PackData> data(String courseId) async {
    final b = _packs[courseId];
    if (b == null) throw StateError('Pack $courseId is not installed');
    return PackBytes(b, name: '$courseId.sqlite');
  }

  @override
  Future<int?> size(String courseId) async => _packs[courseId]?.length;

  @override
  Future<void> writeBytes(String courseId, Uint8List bytes) async => _packs[courseId] = bytes;

  @override
  Future<void> copyFile(String courseId, String sourcePath) =>
      throw UnsupportedError('Copying files is not supported by the in-memory pack store');

  @override
  Future<bool> delete(String courseId) async => _packs.remove(courseId) != null;

  @override
  Future<String?> readManifest() async => _manifest;

  @override
  Future<void> writeManifest(String json) async => _manifest = json;

  @override
  String location(String courseId) => 'memory:$courseId.sqlite';
}
