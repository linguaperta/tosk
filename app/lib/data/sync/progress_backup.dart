/// Progress backup: export everything progress-related into one JSON-lines
/// file, and merge such a file back in. Pure Dart (the UI supplies the file
/// I/O). Until Drive sync (v0.4) this is how progress moves between devices.
///
/// Format `tosk-backup/1`, UTF-8, one JSON object per line:
///
/// 1. a header: `{"format":"tosk-backup/1","exported_at":"…Z","app":"…",
///    "counts":{"events":N,"mistakes":N,"settings":N}}`;
/// 2. the review log, exactly as `encodeReviewLogJsonl` writes it (one event
///    per line, `(at, id)` order, no `kind`);
/// 3. `{"kind":"mistake",…}` per stored mistake;
/// 4. `{"kind":"setting","key":…,"value":…}` per setting.
///
/// A plain review-log file (`encodeReviewLogJsonl`, no header)
/// imports too. Unknown `kind`s are skipped, so later versions can add
/// sections.
///
/// **Import merges, it never deletes or overwrites:** events are a union by
/// id (idempotent; `importEvents`), then every facet state is recomputed with
/// `rebuildStates()`; mistakes are added when their id is new; settings only
/// fill keys this device doesn't have (except "my courses", which is a
/// union), and device-only keys (the reminder) are never imported.
library;

import 'dart:convert';

import '../../core/core.dart';
import 'review_log_sync.dart';

const String kBackupFormat = 'tosk-backup/1';

/// Settings that belong to one device and are never imported.
const Set<String> kDeviceOnlySettings = {
  'reminder.enabled',
  'reminder.time',
  // ONYX e-reader switches (v0.5).
  'eink.full_refresh',
  'eink.onyx_pen',
  // Course downloads: index URL override, cached index, time of the last check.
  'packs.index_url',
  'packs.index_cache',
  'packs.last_check',
};

/// The setting "my courses" (comma-separated ids), merged as a union.
const String kCoursesAddedKey = 'courses.added';

/// Optional store capability: every stored setting (for the backup).
abstract interface class SettingsLister {
  Future<Map<String, String>> allSettings();
}

class ProgressBackup {
  const ProgressBackup({
    required this.events,
    this.mistakes = const [],
    this.settings = const {},
    this.exportedAt,
    this.app,
  });

  final List<ReviewEvent> events;
  final List<MistakeRecord> mistakes;
  final Map<String, String> settings;
  final DateTime? exportedAt;
  final String? app;

  /// First and last answer in the file (null when it has none).
  DateTime? get firstAt => events.isEmpty ? null : events.map((e) => e.at).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get lastAt => events.isEmpty ? null : events.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
}

Map<String, Object?> mistakeToJson(MistakeRecord m) => {
  'kind': 'mistake',
  'id': m.id,
  'facet': m.facetId,
  'at': m.at.toUtc().millisecondsSinceEpoch,
  'type': m.exerciseType,
  'prompt': m.prompt,
  'expected': m.expected,
  'given': m.given,
  if (m.skillId != null) 'skill': m.skillId,
  if (m.note != null) 'note': m.note,
  if (m.explanation != null) 'explanation': m.explanation,
};

MistakeRecord mistakeFromJson(Map<String, Object?> j) => MistakeRecord(
  id: j['id']! as String,
  facetId: j['facet']! as String,
  at: DateTime.fromMillisecondsSinceEpoch((j['at']! as num).toInt(), isUtc: true),
  exerciseType: j['type']! as String,
  prompt: j['prompt'] as String? ?? '',
  expected: j['expected'] as String? ?? '',
  given: j['given'] as String? ?? '',
  skillId: j['skill'] as String?,
  note: j['note'] as String?,
  explanation: j['explanation'] as String?,
);

/// Encodes [b] in the backup format (see the library comment).
String encodeBackup(ProgressBackup b, {DateTime? now}) {
  final out = StringBuffer();
  final at = (now ?? b.exportedAt ?? DateTime.now()).toUtc();
  final mistakes = [...b.mistakes]
    ..sort((x, y) => x.at.compareTo(y.at) != 0 ? x.at.compareTo(y.at) : x.id.compareTo(y.id));
  final keys = b.settings.keys.toList()..sort();
  out.writeln(
    jsonEncode({
      'format': kBackupFormat,
      'exported_at': at.toIso8601String(),
      'app': ?b.app,
      'counts': {
        'events': {for (final e in b.events) e.id}.length,
        'mistakes': mistakes.length,
        'settings': keys.length,
      },
    }),
  );
  out.write(encodeReviewLogJsonl(b.events));
  for (final m in mistakes) {
    out.writeln(jsonEncode(mistakeToJson(m)));
  }
  for (final k in keys) {
    out.writeln(jsonEncode({'kind': 'setting', 'key': k, 'value': b.settings[k]}));
  }
  return out.toString();
}

/// Decodes a backup, or a plain review-log file. Throws [FormatException] on
/// a line that isn't JSON, a newer major format, or an invalid event.
ProgressBackup decodeBackup(String text) {
  final events = <ReviewEvent>[];
  final mistakes = <MistakeRecord>[];
  final settings = <String, String>{};
  DateTime? exportedAt;
  String? app;
  var lineNo = 0;
  for (final line in const LineSplitter().convert(text)) {
    lineNo++;
    final t = line.trim();
    if (t.isEmpty) continue;
    final Map<String, Object?> j;
    try {
      j = (jsonDecode(t) as Map).cast<String, Object?>();
    } on Object catch (e) {
      throw FormatException('Line $lineNo is not a JSON object: $e');
    }
    final format = j['format'];
    if (format is String) {
      if (!format.startsWith('tosk-backup/')) throw FormatException('Not a tosk backup ($format)');
      final major = int.tryParse(format.split('/').last.split('.').first) ?? 0;
      if (major > 1) throw FormatException('This backup needs a newer version of the app ($format)');
      exportedAt = DateTime.tryParse(j['exported_at'] as String? ?? '');
      app = j['app'] as String?;
      continue;
    }
    try {
      switch (j['kind']) {
        case null:
          events.add(reviewEventFromJson(j));
        case 'mistake':
          mistakes.add(mistakeFromJson(j));
        case 'setting':
          final k = j['key'], v = j['value'];
          if (k is String && v is String) settings[k] = v;
        default:
          break; // a section from a newer version
      }
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      throw FormatException('Bad backup line $lineNo: $e');
    }
  }
  return ProgressBackup(events: events, mistakes: mistakes, settings: settings, exportedAt: exportedAt, app: app);
}

/// Everything in [store]: the log, every mistake and the settings ([keys]
/// when the store can't list them).
Future<ProgressBackup> exportBackup(
  ProgressStore store, {
  Iterable<String> keys = const [],
  String? app,
  DateTime? now,
}) async {
  final events = await store.log();
  final mistakes = await store.mistakes(limit: 1 << 30);
  final Map<String, String> settings;
  if (store is SettingsLister) {
    settings = await (store as SettingsLister).allSettings();
  } else {
    settings = {for (final k in keys) k: ?await store.getSetting(k)};
  }
  return ProgressBackup(events: events, mistakes: mistakes, settings: settings, exportedAt: now, app: app);
}

/// What an import changed.
class BackupImportReport {
  const BackupImportReport({
    required this.eventsInFile,
    required this.eventsAdded,
    required this.mistakesAdded,
    required this.settingsAdded,
  });

  final int eventsInFile;
  final int eventsAdded;
  final int mistakesAdded;
  final int settingsAdded;

  int get eventsKnown => eventsInFile - eventsAdded;

  @override
  String toString() =>
      'BackupImportReport(events $eventsAdded/$eventsInFile new, mistakes +$mistakesAdded, settings +$settingsAdded)';
}

/// Merges [backup] into [store] (see the library comment) and recomputes
/// every facet state. Idempotent: importing the same file twice adds nothing.
Future<BackupImportReport> importBackup(
  ProgressBackup backup, {
  required ProgressStore store,
  required EventImporter importer,
}) async {
  final unique = {for (final e in backup.events) e.id: e};
  final added = await importer.importEvents(unique.values);
  await store.rebuildStates();

  final known = {for (final m in await store.mistakes(limit: 1 << 30)) m.id};
  var mistakes = 0;
  for (final m in backup.mistakes) {
    if (known.add(m.id)) {
      await store.saveMistake(m);
      mistakes++;
    }
  }

  var settings = 0;
  for (final e in backup.settings.entries) {
    if (kDeviceOnlySettings.contains(e.key)) continue;
    final mine = await store.getSetting(e.key);
    if (e.key == kCoursesAddedKey && mine != null) {
      final ids = [
        for (final id in [...mine.split(','), ...e.value.split(',')])
          if (id.trim().isNotEmpty) id.trim(),
      ];
      final union = {...ids}.join(',');
      if (union != mine) {
        await store.setSetting(e.key, union);
        settings++;
      }
      continue;
    }
    if (mine == null) {
      await store.setSetting(e.key, e.value);
      settings++;
    }
  }
  return BackupImportReport(
    eventsInFile: unique.length,
    eventsAdded: added,
    mistakesAdded: mistakes,
    settingsAdded: settings,
  );
}
