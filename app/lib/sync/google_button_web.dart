import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google Identity Services' own button; its sign-ins arrive on
/// `GoogleSignIn.instance.authenticationEvents`.
///
/// In English like the rest of the app (Google otherwise uses the browser's
/// language, e.g. "Inloggen met Google" next to English text), and filled
/// black on a dark theme, where the white outline button glared. Keyed by
/// brightness, so switching the theme renders it again.
Widget renderGoogleButton() => Builder(
  builder: (context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return KeyedSubtree(
      key: ValueKey('gsi-button-$dark'),
      child: web.renderButton(
        configuration: web.GSIButtonConfiguration(
          locale: 'en',
          theme: dark ? web.GSIButtonTheme.filledBlack : web.GSIButtonTheme.outline,
          shape: web.GSIButtonShape.pill,
        ),
      ),
    );
  },
);
