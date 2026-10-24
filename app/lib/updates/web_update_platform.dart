/// The browser's [WebUpdateSource] on the web; null elsewhere.
library;

export 'web_update_stub.dart' if (dart.library.js_interop) 'web_update_browser.dart';
