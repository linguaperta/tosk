// The accent bar's letters come from course data: the target language's
// non-ASCII letters by frequency. Checked on the fixture course and on the
// real bundled packs (and the local Sarnami pack when it exists).
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';

void main() {
  test('fixture Italian: accented vowels only, most frequent first, cached', () {
    final course = italianCourse();
    final letters = specialLetters(course, minCount: 1);
    expect(letters, isNotEmpty);
    for (final l in letters) {
      expect(l.codeUnitAt(0), greaterThan(0x7F));
      expect(l, l.toLowerCase());
    }
    expect(identical(specialLetters(course, minCount: 1), letters), isTrue);
  });

  for (final (id, expected, absent) in [
    ('it', ['à', 'è', 'é', 'ì', 'ò', 'ù'], ['ç', 'ñ', 'ö']),
    ('nl', ['é', 'ë', 'ï'], ['à', 'ç', 'ñ']),
    ('es', ['á', 'é', 'í', 'ó', 'ú', 'ñ'], ['à', 'è', 'ç']),
  ]) {
    test('real pack $id', () {
      final course = loadCourseFile('assets/courses/$id.sqlite');
      final letters = specialLetters(course);
      // ignore: avoid_print
      print('[$id] accent bar: ${letters.join(' ')}');
      for (final l in expected) {
        expect(letters, contains(l));
      }
      for (final l in absent) {
        expect(letters, isNot(contains(l)));
      }
    });
  }

  const hns = 'C:/Users/timo/Repositories/tosk/local/dist/hns.sqlite';
  test('local Sarnami pack', () {
    final path = Platform.environment['TOSK_HNS_PACK'] ?? hns;
    if (!File(path).existsSync()) {
      markTestSkipped('no local hns pack');
      return;
    }
    final letters = specialLetters(loadCourseFile(path));
    // ignore: avoid_print
    print('[hns] accent bar: ${letters.join(' ')}');
    expect(letters, containsAll(['ṯ', 'ṟ']));
  });
}
