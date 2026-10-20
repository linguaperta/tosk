/// A [PackFileStore] over a key/value store of byte blobs: on the web that is
/// IndexedDB (`data/platform/idb_blob_store.dart`), so downloaded and bundled
/// packs survive a reload; tests use [MemoryBlobStore]. Pure Dart.
///
/// Packs are written whole (the stores have no rename), so a staged download
/// stays in memory until [PackStaging.commit] puts it; the previous version is
/// kept in memory as the backup until [PackStaging.dropBackup].
library;

import 'dart:typed_data';

import '../../core/core.dart';
import 'pack_file_store.dart';

abstract interface class BlobStore {
  Future<Uint8List?> get(String key);
  Future<void> put(String key, Uint8List bytes);
  Future<void> delete(String key);
  Future<List<String>> keys();
  Future<String?> getText(String key);
  Future<void> putText(String key, String value);
}

class MemoryBlobStore implements BlobStore {
  final Map<String, Uint8List> blobs = {};
  final Map<String, String> texts = {};
  @override
  Future<Uint8List?> get(String key) async => blobs[key];
  @override
  Future<void> put(String key, Uint8List bytes) async => blobs[key] = bytes;
  @override
  Future<void> delete(String key) async => blobs.remove(key);
  @override
  Future<List<String>> keys() async => blobs.keys.toList();
  @override
  Future<String?> getText(String key) async => texts[key];
  @override
  Future<void> putText(String key, String value) async => texts[key] = value;
}

class BlobPackFileStore implements PackFileStore {
  BlobPackFileStore(this.blobs, {this.name = 'indexeddb'});
  final BlobStore blobs;
  final String name;

  static const _manifestKey = 'packs.json';

  @override
  Future<PackData> data(String courseId) async {
    final b = await blobs.get(courseId);
    if (b == null) throw StateError('Pack $courseId is not installed');
    return PackBytes(b, name: '$courseId.sqlite');
  }

  @override
  Future<int?> size(String courseId) async => (await blobs.get(courseId))?.length;

  @override
  Future<void> writeBytes(String courseId, Uint8List bytes) => blobs.put(courseId, bytes);

  @override
  Future<void> copyFile(String courseId, String sourcePath) =>
      throw UnsupportedError('Copying files is not supported in the browser');

  @override
  Future<bool> delete(String courseId) async {
    final had = await blobs.get(courseId) != null;
    await blobs.delete(courseId);
    return had;
  }

  @override
  Future<List<String>> installedIds() async => (await blobs.keys())..sort();

  @override
  Future<String?> readManifest() => blobs.getText(_manifestKey);

  @override
  Future<void> writeManifest(String json) => blobs.putText(_manifestKey, json);

  @override
  String location(String courseId) => '$name:$courseId.sqlite';

  @override
  Future<PackStaging> stage(String courseId) async => _BlobStaging(this, courseId);
}

class _BlobStaging implements PackStaging {
  _BlobStaging(this.store, this.id);
  final BlobPackFileStore store;
  final String id;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  Uint8List? _staged;
  Uint8List? _backup;
  bool _committed = false;

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
    _backup = await store.blobs.get(id);
    await store.blobs.put(id, staged);
    _committed = true;
    _staged = null;
  }

  @override
  Future<void> rollback() async {
    if (!_committed) return;
    if (_backup != null) {
      await store.blobs.put(id, _backup!);
    } else {
      await store.blobs.delete(id);
    }
    _backup = null;
  }

  @override
  Future<void> dropBackup() async => _backup = null;
}

/// Uses [primary] until it fails once (e.g. IndexedDB refused in a private
/// window), then [fallback] (memory) for the rest of the session, so packs
/// keep working, just without persistence.
class FallbackBlobStore implements BlobStore {
  FallbackBlobStore(this.primary, {BlobStore? fallback, this.onFallback}) : fallback = fallback ?? MemoryBlobStore();
  final BlobStore primary;
  final BlobStore fallback;
  final void Function(Object error)? onFallback;
  bool _failed = false;

  bool get usingFallback => _failed;

  Future<T> _run<T>(Future<T> Function(BlobStore s) op) async {
    if (!_failed) {
      try {
        return await op(primary);
      } on Object catch (e) {
        _failed = true;
        onFallback?.call(e);
      }
    }
    return op(fallback);
  }

  @override
  Future<Uint8List?> get(String key) => _run((s) => s.get(key));
  @override
  Future<void> put(String key, Uint8List bytes) => _run((s) => s.put(key, bytes));
  @override
  Future<void> delete(String key) => _run((s) => s.delete(key));
  @override
  Future<List<String>> keys() => _run((s) => s.keys());
  @override
  Future<String?> getText(String key) => _run((s) => s.getText(key));
  @override
  Future<void> putText(String key, String value) => _run((s) => s.putText(key, value));
}
