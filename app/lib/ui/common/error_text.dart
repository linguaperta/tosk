/// An exception as a short, readable detail for an error message: without the
/// Dart class prefix ("Exception: ", "Bad state: "…) and at most 160
/// characters. The sentence around it says what happened and what to do.
library;

String errorDetail(Object e) {
  var s = '$e'
      .replaceFirst(RegExp(r'^(Exception|Bad state|StateError|FormatException|FileSystemException|PathAccessException): '), '')
      .trim();
  if (s.length > 160) s = '${s.substring(0, 160)}…';
  return s;
}

/// "[what] Please try again. (detail)", the shape of the app's error snack bars.
String tryAgainMessage(String what, Object e) {
  final d = errorDetail(e);
  return d.isEmpty ? '$what Please try again.' : '$what Please try again. ($d)';
}
