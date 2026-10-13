/// Native progress database file via drift_flutter (see `progress_connection.dart`).
library;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'progress_db.dart';

Future<ProgressDb> openProgressDb({String name = 'progress', String? directory}) async =>
    ProgressDb(
      driftDatabase(
        name: name,
        native: DriftNativeOptions(
          databaseDirectory:
              directory == null ? getApplicationSupportDirectory : () async => directory,
        ),
      ),
    );
