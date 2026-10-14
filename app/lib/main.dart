import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'app.dart';
import 'app_bootstrap.dart';
import 'app_version.dart';
import 'data/bootstrap.dart' show AppDataOptions;

/// Optional data directory for QA and development runs, so they don't touch
/// the real profile: `flutter run -d windows --dart-define=TOSK_DATA_DIR=C:/tmp/tosk-qa`.
/// Empty (the default) uses the platform's application-support directory.
const _dataDirOverride = String.fromEnvironment('TOSK_DATA_DIR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real data: the progress database, course packs (falling back to the demo
  // courses while none is installed) and the FSRS scheduler.
  var overrides = <Override>[];
  try {
    // appVersion turns on course downloads (GitHubPackSource).
    final options = _dataDirOverride.isEmpty
        ? const AppDataOptions(appVersion: kAppVersion)
        : const AppDataOptions(dataDirectory: _dataDirOverride, appVersion: kAppVersion);
    if (_dataDirOverride.isNotEmpty) debugPrint('[boot] data directory override: $_dataDirOverride');
    overrides = (await bootApp(options: options)).overrides;
  } catch (e, st) {
    // Without storage the app still runs, on the demo courses with in-memory progress.
    debugPrint('Could not open the data layer, running without persistence: $e\n$st');
  }

  runApp(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const ToskApp()));
}
