/// `LocalPackSource`: the v1 [PackSource]. Pure Dart; the Flutter asset bundle
/// and the platform are injected (`AssetBundlePacks`, `data/platform`).
///
/// * Bundled packs (`assets/courses/*.sqlite`) are installed into the
///   [PackFileStore] on first use, and re-installed when the bundled version is
///   newer than the installed one (semver), e.g. after an app update.
/// * Packs added by the user ([install], from a file picker in dev) are
///   validated (meta + schema version) and replace the installed pack of the
///   same course id. A newer bundled version later wins again.
/// * Pack files copied into the store's folder by hand (`courses/{id}.sqlite`,
///   e.g. a locally built pack that must not be bundled) are found when the
///   packs are first listed, validated and registered with origin `local`. The
///   file name must be the course id. A replaced file is re-read on the next
///   start; a deleted one disappears from the list.
/// * A small manifest (`packs.json`) records version, title and origin.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/core.dart';
import '../course/course_schema.dart';
import 'pack_file_store.dart';

/// Read-only access to the packs shipped with the app.
abstract interface class BundledPacks {
  /// Keys of the bundled pack files (e.g. `assets/courses/it.sqlite`).
  Future<List<String>> list();
  Future<Uint8List> load(String key);
}

/// No bundled packs.
class NoBundledPacks implements BundledPacks {
  const NoBundledPacks();
  @override
  Future<List<String>> list() async => const [];
  @override
  Future<Uint8List> load(String key) => throw StateError('No bundled pack $key');
}

typedef PackMetaReader = Future<CourseMeta> Function(PackData data);

class LocalPackSource implements PackSource {
  LocalPackSource({
    required this.bundled,
    required this.store,
    required this.readMeta,
    this.onWarning,
  });

  final BundledPacks bundled;
  final PackFileStore store;
  final PackMetaReader readMeta;

  /// Called for bundled packs that fail validation (they are skipped).
  final void Function(String message)? onWarning;

  Future<Map<String, _Entry>>? _ready;

  /// Installs/updates bundled packs once; [available], [open] etc. call it.
  Future<Map<String, _Entry>> _sync() => _ready ??= _syncBundled();

  /// Forces the bundled packs to be checked again.
  void refresh() => _ready = null;

  Future<Map<String, _Entry>> _syncBundled() async {
    final manifest = await _readManifest();
    var changed = await _syncFolder(manifest);
    for (final key in await bundled.list()) {
      final Uint8List bytes;
      final CourseMeta meta;
      try {
        bytes = await bundled.load(key);
        meta = await readMeta(PackBytes(bytes, name: key));
      } on Object catch (e) {
        onWarning?.call('Skipping bundled pack $key: $e');
        continue;
      }
      final installed = manifest[meta.id];
      final missing = installed == null || await store.size(meta.id) == null;
      if (missing || compareVersions(meta.version, installed.version) > 0) {
        await store.writeBytes(meta.id, bytes);
        manifest[meta.id] = _Entry.fromMeta(meta, PackOrigin.bundled);
        changed = true;
      }
    }
    if (changed) await _writeManifest(manifest);
    return manifest;
  }

  /// Registers pack files the manifest doesn't know (copied in by hand),
  /// re-reads `local` packs whose file may have been replaced, and forgets
  /// `local` packs whose file is gone. Returns whether [manifest] changed.
  Future<bool> _syncFolder(Map<String, _Entry> manifest) async {
    var changed = false;
    final present = (await store.installedIds()).toSet();
    for (final id in present) {
      final known = manifest[id];
      if (known != null && known.origin != PackOrigin.local) continue;
      final CourseMeta meta;
      try {
        meta = await readMeta(await store.data(id));
      } on Object catch (e) {
        if (known == null) onWarning?.call('Skipping pack file $id.sqlite: $e');
        continue;
      }
      if (meta.id != id) {
        onWarning?.call('Skipping pack file $id.sqlite: it holds course "${meta.id}" (name it ${meta.id}.sqlite)');
        continue;
      }
      final entry = _Entry.fromMeta(meta, PackOrigin.local);
      if (known == null || !known.sameAs(entry)) {
        manifest[id] = entry;
        changed = true;
      }
    }
    for (final id in manifest.keys.toList()) {
      if (manifest[id]!.origin == PackOrigin.local && !present.contains(id)) {
        manifest.remove(id);
        changed = true;
      }
    }
    return changed;
  }

  @override
  Future<List<PackInfo>> available() async {
    final m = await _sync();
    final ids = m.keys.toList()..sort();
    return [for (final id in ids) await _info(m[id]!)];
  }

  @override
  Future<PackHandle> open(String courseId) async {
    final m = await _sync();
    final e = m[courseId];
    if (e == null) throw StateError('No pack installed for course "$courseId"');
    return PackHandle(await _info(e), await store.data(courseId));
  }

  @override
  Future<PackInfo> install(PackData data) async {
    final meta = await readMeta(data); // throws CourseFormatException if invalid
    final m = await _sync();
    switch (data) {
      case PackFile(:final path):
        await store.copyFile(meta.id, path);
      case PackBytes(:final bytes):
        await store.writeBytes(meta.id, bytes);
    }
    final e = m[meta.id] = _Entry.fromMeta(meta, PackOrigin.local);
    await _writeManifest(m);
    return _info(e);
  }

  /// Installs a staged download ([PackStaging.finish] already called):
  /// validates it as course [courseId] (and [version], when given), swaps it
  /// in, then opens it with [verify]. If that fails, the previous version is
  /// restored and the error rethrown; otherwise the backup is dropped and
  /// `packs.json` records the pack with [origin]. The manifest is written last,
  /// so after a crash at any point the folder and the manifest still agree
  /// (see `NativePackFileStore` recovery).
  Future<PackInfo> installStaged(
    String courseId,
    PackStaging staged,
    PackData data, {
    PackOrigin origin = PackOrigin.remote,
    String? version,
    Future<void> Function(PackData data)? verify,
  }) async {
    final CourseMeta meta;
    try {
      meta = await readMeta(data); // throws CourseFormatException if invalid
      if (meta.id != courseId) {
        throw CourseFormatException('The file holds course "${meta.id}", not "$courseId"');
      }
      if (version != null && meta.version != version) {
        throw CourseFormatException('The file holds version ${meta.version}, not $version');
      }
    } on Object {
      await staged.discard();
      rethrow;
    }
    final m = await _sync();
    await staged.commit();
    try {
      await verify?.call(await store.data(courseId));
    } on Object {
      await staged.rollback();
      rethrow;
    }
    await staged.dropBackup();
    final e = m[courseId] = _Entry.fromMeta(meta, origin);
    await _writeManifest(m);
    return _info(e);
  }

  @override
  Future<bool> remove(String courseId) async {
    final m = await _sync();
    final e = m[courseId];
    if (e == null || e.origin == PackOrigin.bundled) return false;
    await store.delete(courseId);
    m.remove(courseId);
    await _writeManifest(m);
    refresh(); // a bundled pack for this course (if any) is reinstalled next time
    return true;
  }

  Future<PackInfo> _info(_Entry e) async => PackInfo(
        id: e.id,
        version: e.version,
        title: e.title,
        origin: e.origin,
        schemaVersion: e.schemaVersion,
        unverified: e.unverified,
        sizeBytes: await store.size(e.id),
        location: store.location(e.id),
      );

  Future<Map<String, _Entry>> _readManifest() async {
    final text = await store.readManifest();
    if (text == null || text.isEmpty) return {};
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      return {
        for (final e in (j['packs'] as Map<String, dynamic>).entries)
          e.key: _Entry.fromJson(e.key, e.value as Map<String, dynamic>),
      };
    } on Object catch (e) {
      onWarning?.call('Ignoring corrupt pack manifest: $e');
      return {};
    }
  }

  Future<void> _writeManifest(Map<String, _Entry> m) => store.writeManifest(
        const JsonEncoder.withIndent('  ').convert({
          'packs': {for (final e in m.values) e.id: e.toJson()},
        }),
      );
}

class _Entry {
  _Entry({
    required this.id,
    required this.version,
    required this.title,
    required this.origin,
    required this.schemaVersion,
    required this.unverified,
  });

  factory _Entry.fromMeta(CourseMeta m, PackOrigin origin) => _Entry(
        id: m.id,
        version: m.version,
        title: m.title,
        origin: origin,
        schemaVersion: m.schemaVersion,
        unverified: m.unverified,
      );

  factory _Entry.fromJson(String id, Map<String, dynamic> j) => _Entry(
        id: id,
        version: j['version'] as String,
        title: (j['title'] as Map).cast<String, String>(),
        origin: PackOrigin.values.asNameMap()[j['origin']] ?? PackOrigin.local,
        schemaVersion: j['schemaVersion'] as int? ?? 1,
        unverified: j['unverified'] as bool? ?? false,
      );

  final String id;
  final String version;
  final I18n title;
  final PackOrigin origin;
  final int schemaVersion;
  final bool unverified;

  bool sameAs(_Entry o) =>
      o.id == id &&
      o.version == version &&
      o.origin == origin &&
      o.schemaVersion == schemaVersion &&
      o.unverified == unverified &&
      o.title.length == title.length &&
      title.entries.every((e) => o.title[e.key] == e.value);

  Map<String, Object?> toJson() => {
        'version': version,
        'title': title,
        'origin': origin.name,
        'schemaVersion': schemaVersion,
        'unverified': unverified,
      };
}
