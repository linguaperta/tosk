import 'package:drift/native.dart';
import 'package:tosk/core/core.dart';
import 'package:tosk/data/progress/in_memory_progress_store.dart';
import 'package:tosk/data/progress/progress_db.dart';
import 'package:tosk/data/progress/progress_repo.dart';
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

  test('two devices converge through a file backend', () async {
    String? file;
    final backend = FileExportSyncBackend(read: () async => file, write: (s) async => file = s);
    final log = sampleLog(seed: 5, count: 300);
    final a = InMemoryProgressStore();
    final repoB = ProgressRepo(ProgressDb(NativeDatabase.memory()));
    addTearDown(repoB.close);
    for (final e in log.sublist(0, 180)) {
      await a.record(e);
    }
    for (final e in log.sublist(120)) {
      await repoB.record(e);
    }
    final r1 = await syncReviewLog(backend: backend, store: a, importer: a);
    expect(r1.imported, 0);
    expect(r1.pushed, 180);
    final r2 = await syncReviewLog(backend: backend, store: repoB, importer: repoB);
    expect(r2.imported, 120);
    await syncReviewLog(backend: backend, store: a, importer: a);
    final sa = await a.allStates();
    final sb = await repoB.allStates();
    expect(sa, sb);
    expect((await a.log()).length, 300);
    expect((await backend.pull(since: DateTime.utc(2026, 9))).every(
        (e) => !e.at.isBefore(DateTime.utc(2026, 9))), isTrue);
  });

  test('NullSyncBackend does nothing', () async {
    const backend = NullSyncBackend();
    final store = InMemoryProgressStore();
    final r = await syncReviewLog(backend: backend, store: store, importer: store);
    expect(r.pushed, 0);
    expect(await backend.pull(), isEmpty);
  });
}
