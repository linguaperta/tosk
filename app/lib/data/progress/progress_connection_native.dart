/// Native progress database file via drift_flutter (see `progress_connection.dart`).
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'progress_db.dart';

Future<ProgressDb> openProgressDb({String name = 'progress', String? directory}) =>
    openDriftDatabase(ProgressDb.new, name: name, directory: directory);

/// Opens `{directory}/{name}.sqlite` (default: the app support folder) as [create]'s database.
Future<T> openDriftDatabase<T extends GeneratedDatabase>(
  T Function(QueryExecutor) create, {
  required String name,
  String? directory,
}) async =>
    create(
      driftDatabase(
        name: name,
        native: DriftNativeOptions(
          databaseDirectory:
              directory == null ? getApplicationSupportDirectory : () async => directory,
        ),
      ),
    );
