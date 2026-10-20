import 'dart:io';

import 'package:tosk/data/course/course_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fixtures/synthetic_course.dart';

void main() {
  test('a multi-MB pack loads well under a second', () {
    final dir = Directory.systemTemp.createTempSync('tosk_perf_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/zz.sqlite';
    final db = sqlite3.open(path);
    populateSyntheticCourse(db);
    db.close();
    final mb = File(path).lengthSync() / (1 << 20);

    loadCourseRepoFile(path); // warm-up (JIT)
    final sw = Stopwatch()..start();
    final repo = loadCourseRepoFile(path);
    sw.stop();
    // ignore: avoid_print
    print('Loaded ${mb.toStringAsFixed(1)} MB pack (${repo.counts}) in ${sw.elapsedMilliseconds} ms');
    expect(mb, greaterThan(3));
    expect(repo.itemCount, 8000);
    expect(repo.counts.verbForms, 2000 * 24);
    expect(repo.sentenceCount, 12000);
    // Shared CI runners are slower than a dev machine.
    expect(sw.elapsedMilliseconds, lessThan(Platform.environment['CI'] == null ? 1000 : 4000));
  });
}
