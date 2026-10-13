import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'app.dart';
import 'app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real data: the progress database, course packs (falling back to the demo
  // courses while none is installed) and the FSRS scheduler.
  var overrides = <Override>[];
  try {
    overrides = (await bootApp()).overrides;
  } catch (e, st) {
    // Without storage the app still runs, on the demo courses with in-memory progress.
    debugPrint('Could not open the data layer, running without persistence: $e\n$st');
  }

  runApp(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const ToskApp()));
}
