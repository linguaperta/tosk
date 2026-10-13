/// Review-log export/import (JSON lines) and a file-based [SyncBackend]. Pure Dart.
///
/// The file format is one JSON object per line, sorted by `(at, id)`:
/// `{"id":"…","facet":"it:mangiare#rec","at":1767254400000,"rating":3,
///   "type":"flashcard","input":"self","ms":1500,"ok":true,"answer":null,
///   "session":"…","mode":"lesson"}`
library;

import 'dart:convert';

import '../../core/core.dart';
import '../progress/event_importer.dart';
import '../progress/replay.dart';

export '../progress/event_importer.dart';

Map<String, Object?> reviewEventToJson(ReviewEvent e) => {
      'id': e.id,
      'facet': e.facetId,
      'at': e.at.millisecondsSinceEpoch,
      'rating': e.rating.value,
      'type': e.exerciseType,
      'input': e.inputMode.name,
      'ms': e.responseMs,
      'ok': e.correct,
      if (e.answer != null) 'answer': e.answer,
      if (e.sessionId != null) 'session': e.sessionId,
      if (e.mode != null) 'mode': e.mode,
    };

ReviewEvent reviewEventFromJson(Map<String, Object?> j) => ReviewEvent(
      id: j['id']! as String,
      facetId: j['facet']! as String,
      at: DateTime.fromMillisecondsSinceEpoch((j['at']! as num).toInt(), isUtc: true),
      rating: Rating.fromValue((j['rating']! as num).toInt()),
      exerciseType: j['type']! as String,
      inputMode: InputMode.values.asNameMap()[j['input']] ?? InputMode.tap,
      responseMs: (j['ms'] as num?)?.toInt() ?? 0,
      correct: j['ok'] as bool? ?? false,
      answer: j['answer'] as String?,
      sessionId: j['session'] as String?,
      mode: j['mode'] as String?,
    );

/// Encodes events as JSON lines in `(at, id)` order, deduplicated by id.
String encodeReviewLogJsonl(Iterable<ReviewEvent> events) {
  final byId = {for (final e in events) e.id: normalizeEvent(e)};
  final sorted = byId.values.toList()..sort(compareEvents);
  final b = StringBuffer();
  for (final e in sorted) {
    b.writeln(jsonEncode(reviewEventToJson(e)));
  }
  return b.toString();
}

/// Decodes JSON lines (blank lines ignored). Throws [FormatException] on bad input.
List<ReviewEvent> decodeReviewLogJsonl(String text) {
  final out = <ReviewEvent>[];
  var lineNo = 0;
  for (final line in const LineSplitter().convert(text)) {
    lineNo++;
    if (line.trim().isEmpty) continue;
    try {
      out.add(reviewEventFromJson((jsonDecode(line) as Map).cast<String, Object?>()));
    } on Object catch (e) {
      throw FormatException('Bad review log line $lineNo: $e');
    }
  }
  return out;
}

/// A [SyncBackend] over one JSON-lines file (desktop/web export and import).
/// The caller supplies the file I/O, so this works with `dart:io`, a save
/// dialog, or a browser download alike.
class FileExportSyncBackend implements SyncBackend {
  FileExportSyncBackend({required this.read, required this.write});

  /// Returns the file contents, or null if the file doesn't exist yet.
  final Future<String?> Function() read;
  final Future<void> Function(String contents) write;

  @override
  String get id => 'file';
  @override
  bool get isConfigured => true;

  @override
  Future<void> push(List<ReviewEvent> events) async {
    final existing = await _readAll();
    await write(encodeReviewLogJsonl([...existing, ...events]));
  }

  @override
  Future<List<ReviewEvent>> pull({DateTime? since}) async {
    final all = await _readAll();
    if (since == null) return all;
    final ms = since.millisecondsSinceEpoch;
    return [for (final e in all) if (e.at.millisecondsSinceEpoch >= ms) e];
  }

  Future<List<ReviewEvent>> _readAll() async {
    final text = await read();
    return text == null ? const [] : decodeReviewLogJsonl(text);
  }
}

/// Result of [syncReviewLog].
class SyncReport {
  const SyncReport({required this.pulled, required this.imported, required this.pushed});
  final int pulled; // events received from the backend
  final int imported; // of those, new to this device
  final int pushed; // events sent
  @override
  String toString() => 'SyncReport(pulled=$pulled, imported=$imported, pushed=$pushed)';
}

/// Two-way sync: pull remote events and merge them (union by id, affected
/// facets replayed), then push the full local log.
Future<SyncReport> syncReviewLog({
  required SyncBackend backend,
  required ProgressStore store,
  required EventImporter importer,
}) async {
  if (!backend.isConfigured) return const SyncReport(pulled: 0, imported: 0, pushed: 0);
  final remote = await backend.pull();
  final imported = await importer.importEvents(remote);
  final local = await store.log();
  await backend.push(local);
  return SyncReport(pulled: remote.length, imported: imported, pushed: local.length);
}
