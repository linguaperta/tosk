/// Course ids that come from outside the app (a pack's `meta.course_id`, a
/// course index, `packs.json`, settings) are used as file and storage names,
/// so every boundary checks them with [isValidCourseId]. Pure Dart.
///
/// Allowed: a lower-case ASCII letter followed by up to 39 of `a-z 0-9 _ -`
/// (`it`, `hns`, `it-montalbano`), optionally one expansion part after a single
/// dot (`it.cucina`, docs/extensions.md). Never `/`, `\`, `:`, `..`, spaces,
/// upper case or non-ASCII letters, and never a Windows device name (`con`,
/// `nul`, `com1`...).
library;

final RegExp kCourseIdPattern = RegExp(r'^[a-z][a-z0-9_-]{0,39}(\.[a-z0-9][a-z0-9_-]{0,39})?$');

final RegExp _windowsDevice = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$');

/// Whether [id] is safe to use as a course id (and so as a file name).
bool isValidCourseId(String id) =>
    kCourseIdPattern.hasMatch(id) && !_windowsDevice.hasMatch(id.split('.').first);

/// Returns [id], or throws [ArgumentError] when it isn't a valid course id.
String checkCourseId(String id) {
  if (!isValidCourseId(id)) throw ArgumentError.value(id, 'courseId', 'Not a valid course id');
  return id;
}
