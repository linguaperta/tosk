/// The Google sign-in button the web needs (Google Identity Services draws it
/// itself; `GoogleSignIn.authenticate()` isn't available there). Other
/// platforms draw their own button and call `authenticate()`.
library;

export 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';
