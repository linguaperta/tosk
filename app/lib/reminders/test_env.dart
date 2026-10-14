/// Whether the app runs under `flutter test` (no platform plugins there).
library;

export 'test_env_stub.dart' if (dart.library.io) 'test_env_io.dart';
