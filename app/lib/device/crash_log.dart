/// Where the last run's crash details are kept until the next start: files
/// in the app support directory natively (the Android side writes its own
/// there too), the browser's localStorage on the web.
library;

export 'crash_log_stub.dart' if (dart.library.io) 'crash_log_io.dart' if (dart.library.js_interop) 'crash_log_web.dart';

/// What the previous run left: a JVM or native crash (Android) and uncaught
/// Dart/Flutter errors.
typedef CrashParts = ({String? native, String? dart});
