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

  /// Course ids of every pack file present (`{id}.sqlite`), including files
  /// copied in by hand that the manifest doesn't know yet.
  Future<List<String>> installedIds();

  /// Small JSON manifest kept next to the packs (versions and origins).
  Future<String?> readManifest();
  Future<void> writeManifest(String json);

  /// Where a pack is stored, for display.
  String location(String courseId);

  /// Starts writing a new version of [courseId] next to the installed one
  /// (a download). Nothing changes for the installed pack until
  /// [PackStaging.commit].
  Future<PackStaging> stage(String courseId);
}

/// A new pack version being written (natively `{id}.sqlite.download`), then
/// swapped in with a backup of the previous version kept until the new one
/// has been opened successfully:
///
/// ```
/// add(chunk)... -> finish() -> [validate] -> commit() -> [open] -> dropBackup()
///                                                          \-> rollback() on failure
/// ```
abstract interface class PackStaging {
  /// Appends downloaded bytes.
  Future<void> add(List<int> chunk);

  /// Finishes writing; returns the staged data (not installed yet) to validate.
  Future<PackData> finish();

  /// Throws the staged data away (cancel, failed checks). Safe to call twice.
  Future<void> discard();

  /// Swaps the staged pack in; the previous version (if any) becomes the backup.
  Future<void> commit();

  /// Restores the backup (the new version failed to open); without one,
  /// removes the new file.
  Future<void> rollback();

  /// Deletes the backup: the new version is final.
  Future<void> dropBackup();
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
  Future<List<String>> installedIds() async => _packs.keys.toList()..sort();

  @override
  Future<String?> readManifest() async => _manifest;

  @override
  Future<void> writeManifest(String json) async => _manifest = json;

  @override
  String location(String courseId) => 'memory:$courseId.sqlite';

  @override
  Future<PackStaging> stage(String courseId) async => _MemoryStaging(this, courseId);
}

class _MemoryStaging implements PackStaging {
  _MemoryStaging(this.store, this.id);
  final MemoryPackFileStore store;
  final String id;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  Uint8List? _staged;
  Uint8List? _backup;
  bool _hadPrevious = false;

  @override
  Future<void> add(List<int> chunk) async => _bytes.add(chunk);

  @override
  Future<PackData> finish() async => PackBytes(_staged = _bytes.takeBytes(), name: '$id.sqlite');

  @override
  Future<void> discard() async {
    _bytes.clear();
    _staged = null;
  }

  @override
  Future<void> commit() async {
    final staged = _staged ?? (throw StateError('Nothing staged for $id'));
    _backup = store._packs[id];
    _hadPrevious = _backup != null;
    store._packs[id] = staged;
    _staged = null;
  }

  @override
  Future<void> rollback() async {
    if (_hadPrevious) {
      store._packs[id] = _backup!;
    } else {
      store._packs.remove(id);
    }
    _backup = null;
  }

  @override
  Future<void> dropBackup() async => _backup = null;
}
