import 'dart:io';

/// Ids of the real bundled packs (`app/assets/courses/*.sqlite`, built by
/// `python -m pipeline build it nl es --install`), sorted. Every real-pack
/// suite runs on all of them, so a new course is covered by adding its pack.
List<String> bundledPackIds() {
  final dir = Directory('assets/courses');
  if (!dir.existsSync()) return const [];
  return [
    for (final f in dir.listSync())
      if (f is File && f.path.endsWith('.sqlite')) f.uri.pathSegments.last.replaceAll('.sqlite', ''),
  ]..sort();
}
