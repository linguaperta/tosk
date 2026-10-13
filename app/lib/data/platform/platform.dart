/// Platform-specific data access behind one API (conditional imports):
///
/// * `loadCoursePack(PackData)`: loads a pack into a [CourseRepo]. Native: files
///   are opened read-only on a background isolate; web: bytes go through
///   sqlite3 WASM (`web/sqlite3.wasm`) in an in-memory VFS.
/// * `readPackMeta(PackData)`: validates a pack and reads only its meta.
/// * `defaultPackFileStore(dir)`: where installed packs live (a `courses/`
///   folder natively; memory on the web).
/// * `supportsPackFiles`: whether [PackFile] data is usable.
///
/// Pure Dart (no Flutter imports).
library;

export 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    if (dart.library.ffi) 'platform_native.dart';
