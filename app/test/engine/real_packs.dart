import 'dart:io';

/// Ids of the real bundled packs (`app/assets/courses/*.sqlite`, built by
/// `python -m pipeline build it nl es --install`), sorted.
List<String> bundledPackIds() {
  final dir = Directory('assets/courses');
  if (!dir.existsSync()) return const [];
  return [
    for (final f in dir.listSync())
      if (f is File && f.path.endsWith('.sqlite')) f.uri.pathSegments.last.replaceAll('.sqlite', ''),
  ]..sort();
}

/// Every real pack the real-pack suites run on, id -> file path: the bundled
/// packs plus the packs named by `$TOSK_EXTRA_PACKS`, so a course that is only
/// a catalog download (French: `tosk-data/dist/fr.sqlite`, not bundled to keep
/// the APK small) is tested too. `TOSK_EXTRA_PACKS` lists directories (every
/// `*.sqlite` in them) or `.sqlite` files, separated by `;` or `,`, e.g.
/// `TOSK_EXTRA_PACKS=../../tosk-data/dist flutter test test/engine`. A bundled
/// pack wins over an extra one with the same id.
Map<String, String> realPackPaths() {
  final out = <String, String>{for (final id in bundledPackIds()) id: 'assets/courses/$id.sqlite'};
  final extra = Platform.environment['TOSK_EXTRA_PACKS'] ?? '';
  for (final entry in extra.split(RegExp('[;,]'))) {
    final p = entry.trim();
    if (p.isEmpty) continue;
    final files = <File>[];
    if (Directory(p).existsSync()) {
      files.addAll(Directory(p).listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')));
    } else if (File(p).existsSync() && p.endsWith('.sqlite')) {
      files.add(File(p));
    }
    for (final f in files) {
      final id = f.uri.pathSegments.last.replaceAll('.sqlite', '');
      out.putIfAbsent(id, () => f.path);
    }
  }
  return out;
}

/// Ids of [realPackPaths], sorted.
List<String> realPackIds() => realPackPaths().keys.toList()..sort();

/// The file of real pack [id] (bundled or from `$TOSK_EXTRA_PACKS`).
String realPackPath(String id) => realPackPaths()[id] ?? 'assets/courses/$id.sqlite';
