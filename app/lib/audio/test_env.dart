/// Whether the code runs under `flutter test` (no audio plugin there).
library;

export 'test_env_stub.dart' if (dart.library.io) 'test_env_io.dart';
