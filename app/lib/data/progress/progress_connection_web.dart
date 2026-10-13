/// Web progress database via drift's WASM support (see `progress_connection.dart`).
library;

import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

import 'progress_db.dart';

Future<ProgressDb> openProgressDb({String name = 'progress', String? directory}) async {
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
    ProgressDb? db;
    try {
      db = ProgressDb(await probed.open(impl, name));
      // Opens the database and runs migrations; a broken worker may never answer.
      await db.customSelect('SELECT 1').get().timeout(const Duration(seconds: 15));
      if (impl == WasmStorageImplementation.inMemory) {
        debugPrint('[progress] WARNING: no persistent storage available; progress is kept '
            'in memory only (${probed.missingFeatures}, last error: $lastError)');
      } else if (impl != candidates.first) {
        debugPrint('[progress] using $impl (better storage failed: $lastError)');
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
  throw StateError('Could not open the progress database: $lastError');
}
