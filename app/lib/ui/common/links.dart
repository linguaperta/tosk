/// The project's public addresses (Settings → About, the sync section, the
/// welcome's sign-in page, feedback and crash reports). A fork can point them
/// elsewhere with `--dart-define`s.
library;

/// The privacy policy: `app/web/privacy.html`, deployed with the web app.
const kPrivacyPolicyUrl = String.fromEnvironment(
  'TOSK_PRIVACY_URL',
  defaultValue: 'https://linguaperta.github.io/tosk/privacy.html',
);

/// The source code.
const kSourceUrl = String.fromEnvironment('TOSK_SOURCE_URL', defaultValue: 'https://github.com/linguaperta/tosk');

/// The public issue tracker (bug reports and questions without an account).
const kIssuesUrl = '$kSourceUrl/issues';
