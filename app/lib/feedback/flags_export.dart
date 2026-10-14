/// Flags as JSON Lines (`tosk-flags-YYYYMMDD.jsonl`), the format the
/// developer triages with `python -m pipeline flags summarize`. One flag per
/// line, oldest first. Format: docs/feedback.md.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/core.dart';

/// Version tag on every line; bump when the line format changes incompatibly.
const String kFlagFormat = 'tosk-flag/1';

Map<String, Object?> flagToJson(FlagRecord f) => {
  'format': kFlagFormat,
  'id': f.id,
  'created_at': f.createdAt.toUtc().toIso8601String(),
  'course_id': f.courseId,
  'skill_id': f.skillId,
  'facet_id': f.facetId,
  'exercise_type': f.exerciseType,
  'sentence_id': f.exercise['sentence_id'],
  'exercise': f.exercise,
  'given': f.given,
  'expected': f.expected,
  'correct': f.correct,
  'reasons': [for (final r in f.reasons) r.id],
  'comment': f.comment,
  'ai_verdict': f.aiVerdict?.id,
  'ai_reasoning': f.aiReasoning,
  'app_version': f.appVersion,
  'pack_version': f.packVersion,
  'source_lang': f.sourceLang,
};

FlagRecord flagFromJson(Map<String, Object?> j) => FlagRecord(
  id: j['id'] as String,
  createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
  courseId: j['course_id'] as String,
  skillId: j['skill_id'] as String?,
  facetId: j['facet_id'] as String,
  exerciseType: j['exercise_type'] as String,
  exercise: (j['exercise'] as Map).cast<String, Object?>(),
  given: j['given'] as String? ?? '',
  expected: j['expected'] as String? ?? '',
  correct: j['correct'] as bool? ?? false,
  reasons: [for (final id in (j['reasons'] as List? ?? const [])) ?FlagReason.byId('$id')],
  comment: j['comment'] as String? ?? '',
  aiVerdict: FlagVerdict.byId(j['ai_verdict'] as String?),
  aiReasoning: j['ai_reasoning'] as String?,
  appVersion: j['app_version'] as String?,
  packVersion: j['pack_version'] as String?,
  sourceLang: j['source_lang'] as String?,
);

/// One JSON object per line, oldest first, ending with a newline.
String encodeFlagsJsonl(Iterable<FlagRecord> flags) {
  final list = flags.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final b = StringBuffer();
  for (final f in list) {
    b.writeln(jsonEncode(flagToJson(f)));
  }
  return b.toString();
}

List<FlagRecord> decodeFlagsJsonl(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty) flagFromJson((jsonDecode(line) as Map).cast<String, Object?>()),
];

/// `tosk-flags-YYYYMMDD.jsonl` for the local date of [now].
String flagsFileName(DateTime now) {
  final d = now.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'tosk-flags-${d.year}${two(d.month)}${two(d.day)}.jsonl';
}

/// Saves bytes under a suggested name; returns where (null when cancelled).
typedef SaveBytes = Future<Uri?> Function(String fileName, Uint8List bytes);

/// The platform's save flow through file_picker: a save dialog on desktop,
/// the system's document picker on Android and iOS (Storage Access Framework
/// / Files), a download in the browser.
Future<Uri?> saveWithFilePicker(String fileName, Uint8List bytes) => FilePicker.saveFile(
  fileName: fileName,
  bytes: bytes,
  mimeType: 'application/x-ndjson',
  dialogTitle: 'Export flags',
  type: FileType.custom,
  allowedExtensions: const ['jsonl'],
);

/// Writes [flags] as JSON Lines through [save]. Returns the saved location, or
/// null when the user cancelled.
Future<Uri?> exportFlags(List<FlagRecord> flags, {required DateTime now, SaveBytes save = saveWithFilePicker}) {
  final bytes = Uint8List.fromList(utf8.encode(encodeFlagsJsonl(flags)));
  return save(flagsFileName(now), bytes);
}
