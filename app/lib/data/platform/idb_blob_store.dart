/// [BlobStore] on the browser's IndexedDB (web only): installed course packs
/// persist across reloads. Database `tosk-packs`, object stores `blobs`
/// (course id → pack bytes) and `texts` (the manifest).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../packs/blob_pack_file_store.dart';

class IdbBlobStore implements BlobStore {
  IdbBlobStore({this.dbName = 'tosk-packs'});

  final String dbName;
  Future<web.IDBDatabase>? _db;

  static const _blobs = 'blobs';
  static const _texts = 'texts';

  /// IndexedDB is usable here (not in some private modes and old webviews).
  static bool get available {
    try {
      return web.window.indexedDB.isA<web.IDBFactory>();
    } on Object {
      return false;
    }
  }

  Future<web.IDBDatabase> _open() => _db ??= () {
        final c = Completer<web.IDBDatabase>();
        final req = web.window.indexedDB.open(dbName, 1);
        req.onupgradeneeded = ((web.Event _) {
          final db = req.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_blobs)) db.createObjectStore(_blobs);
          if (!db.objectStoreNames.contains(_texts)) db.createObjectStore(_texts);
        }).toJS;
        req.onsuccess = ((web.Event _) => c.complete(req.result as web.IDBDatabase)).toJS;
        req.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
        req.onblocked = ((web.Event _) => c.completeError(StateError('IndexedDB is blocked'))).toJS;
        return c.future;
      }();

  static Future<JSAny?> _result(web.IDBRequest req) {
    final c = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => c.complete(req.result)).toJS;
    req.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
    return c.future;
  }

  static Future<void> _done(web.IDBTransaction tx) {
    final c = Completer<void>();
    tx.oncomplete = ((web.Event _) => c.complete()).toJS;
    tx.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB: ${tx.error?.message}'))).toJS;
    tx.onabort = ((web.Event _) => c.completeError(StateError('IndexedDB: aborted (${tx.error?.message})'))).toJS;
    return c.future;
  }

  Future<JSAny?> _read(String store, JSAny Function(web.IDBObjectStore s) op) async {
    final tx = (await _open()).transaction(store.toJS, 'readonly');
    return _result(op(tx.objectStore(store)) as web.IDBRequest);
  }

  Future<void> _write(String store, void Function(web.IDBObjectStore s) op) async {
    final tx = (await _open()).transaction(store.toJS, 'readwrite');
    op(tx.objectStore(store));
    await _done(tx);
  }

  @override
  Future<Uint8List?> get(String key) async {
    final r = await _read(_blobs, (s) => s.get(key.toJS));
    if (r == null || r.isUndefinedOrNull) return null;
    return (r as JSUint8Array).toDart;
  }

  @override
  Future<void> put(String key, Uint8List bytes) => _write(_blobs, (s) => s.put(bytes.toJS, key.toJS));

  @override
  Future<void> delete(String key) => _write(_blobs, (s) => s.delete(key.toJS));

  @override
  Future<List<String>> keys() async {
    final r = await _read(_blobs, (s) => s.getAllKeys());
    if (r == null) return const [];
    return [for (final k in (r as JSArray<JSAny?>).toDart) if (k != null && k.isA<JSString>()) (k as JSString).toDart];
  }

  @override
  Future<String?> getText(String key) async {
    final r = await _read(_texts, (s) => s.get(key.toJS));
    if (r == null || r.isUndefinedOrNull || !r.isA<JSString>()) return null;
    return (r as JSString).toDart;
  }

  @override
  Future<void> putText(String key, String value) => _write(_texts, (s) => s.put(value.toJS, key.toJS));
}
