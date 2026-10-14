// Runs the template validity suite on the real bundled packs
// (app/assets/courses/*.sqlite, built by `python -m pipeline build it nl --install`).
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'template_validity.dart';

const _templates = [
  'flashcard', 'multiple_choice', 'match_pairs', 'conj_pick', 'conj_grid',
  'sentence_builder', 'cloze', 'spot_error', 'transform', 'listen_pick',
];

void main() {
  for (final id in ['it', 'nl']) {
    final path = 'assets/courses/$id.sqlite';
    group('real pack $id', () {
      late CourseData course;
      late ValidityReport report;
      setUpAll(() {
        course = loadCourseFile(path);
        report = runTemplateValidity(course);
      });

      test('every generated exercise is valid', () {
        expect(report.failures.take(10).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
      });

      test('every applicable skill x template generates >= 20 exercises', () {
        expect(report.shortfalls(20), isEmpty, reason: report.toString());
      });

      test('every template is used somewhere in the course', () {
        expect(report.unusedLabels(_templates), isEmpty, reason: report.toString());
      });

      test('every skill has at least 3 applicable templates', () {
        final thin = [
          for (final s in course.skills)
            if (report.applicable.where((k) => k.$1 == s.id).length < 3) s.id,
        ];
        expect(thin, isEmpty, reason: report.toString());
      });
    }, skip: File(path).existsSync() ? false : 'pack $path not built');
  }
}
