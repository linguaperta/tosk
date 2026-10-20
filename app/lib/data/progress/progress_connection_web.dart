/// Web progress database via drift's WASM support (see `progress_connection.dart`).
library;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

import 'progress_db.dart';

Future<ProgressDb> openProgressDb({String name = 'progress', String? directory}) =>
    openDriftDatabase(ProgressDb.new, name: name, directory: directory);

/// Opens the browser database [name] as [create]'s database, with the best
/// storage that works (see the library comment).
Future<T> openDriftDatabase<T extends GeneratedDatabase>(
  T Function(QueryExecutor) create, {
  required String name,
  String? directory,
}) async {
  final probed = await WasmDatabase.probe(
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
    databaseName: name,
  );
  // Enum order is drift's order of preference.
  final candidates = probed.availableStorages.toList()..sort((a, b) => a.index.compareTo(b.index));
  if (!candidates.contains(WasmStorageImplementation.inMemory)) {
    candidates.add(WasmStorageImplementation.inMemory);
  }
  Object? lastError;
  for (final impl in candidates) {
    T? db;
    try {
      db = create(await probed.open(impl, name));
      // Opens the database and runs migrations; a broken worker may never answer.
      await db.customSelect('SELECT 1').get().timeout(const Duration(seconds: 15));
      if (impl == WasmStorageImplementation.inMemory) {
        debugPrint('[$name] WARNING: no persistent storage available; data is kept '
            'in memory only (${probed.missingFeatures}, last error: $lastError)');
      } else if (impl != candidates.first) {
        debugPrint('[$name] using $impl (better storage failed: $lastError)');
      }
      return db;
    } on Object catch (e) {
      lastError = e;
      try {
        await db?.close();
      } on Object {
        // ignore: the connection never opened
      }
    }
  }
  throw StateError('Could not open the $name database: $lastError');
}
