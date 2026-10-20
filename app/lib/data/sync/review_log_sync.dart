/// Review-log JSON lines: the event codec shared by the backup file
/// (`progress_backup.dart`) and cloud sync batches (`lib/sync/`). Pure Dart.
///
/// The file format is one JSON object per line, sorted by `(at, id)`:
/// `{"id":"…","facet":"it:mangiare#rec","at":1767254400000,"rating":3,
///   "type":"flashcard","input":"self","ms":1500,"ok":true,"answer":null,
///   "session":"…","mode":"lesson"}`
library;

import 'dart:convert';

import '../../core/core.dart';
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
