import 'package:tosk/data/sync/review_log_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sample_log.dart';

void main() {
  test('JSON lines round-trip, sorted and deduplicated', () {
    final log = sampleLog(count: 50);
    final text = encodeReviewLogJsonl([...log, ...log.take(10)]);
    expect(text.trim().split('\n').length, 50);
    final back = decodeReviewLogJsonl(text);
    final byId = {for (final e in log) e.id: e};
    for (final e in back) {
      final o = byId[e.id]!;
      expect(e.facetId, o.facetId);
      expect(e.at, o.at);
      expect(e.rating, o.rating);
      expect(e.exerciseType, o.exerciseType);
      expect(e.inputMode, o.inputMode);
      expect(e.responseMs, o.responseMs);
      expect(e.correct, o.correct);
      expect(e.answer, o.answer);
      expect(e.sessionId, o.sessionId);
      expect(e.mode, o.mode);
    }
    expect(() => decodeReviewLogJsonl('{"id": 1}\n'), throwsFormatException);
  });
}
