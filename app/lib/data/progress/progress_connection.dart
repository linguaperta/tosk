/// Opens the real progress database (Flutter).
///
/// `Future<ProgressDb> openProgressDb({String name = 'progress', String? directory})`
///
/// * Native: `{directory}/{name}.sqlite` via drift_flutter, by default in the
///   app support folder.
/// * Web: drift's WASM setup with `web/sqlite3.wasm` and `web/drift_worker.js`.
///   The best storage the browser supports is tried first (OPFS, then
///   IndexedDB); if it fails to open (e.g. a webview whose shared workers can't
///   fetch), the next one is used, ending with an in-memory database.
library;

export 'progress_connection_native.dart'
    if (dart.library.js_interop) 'progress_connection_web.dart';
