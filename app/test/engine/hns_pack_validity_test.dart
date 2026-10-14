// Runs the template validity suite on the locally built Sarnami pack.
//
// The Sarnami (hns) content comes from the [source] Suriname dictionary (all rights reserved), so the
// pack is never committed or bundled: it is built with `python -m pipeline build hns --local` into
// the git-ignored `local/dist/hns.sqlite` of the main checkout (see docs/sarnami.md). Without that
// file (CI, public clones) the tests are skipped. Override the location with $TOSK_HNS_PACK.
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'template_validity.dart';

const _defaultPath = 'C:/Users/timo/Repositories/tosk/local/dist/hns.sqlite';

/// The templates every Sarnami pack must use somewhere. Transform needs person changes in
/// pro-drop sentences or same-length tense swaps; Sarnami examples rarely allow that, so it is
/// reported but not required.
const _requiredTemplates = [
  'flashcard', 'multiple_choice', 'match_pairs', 'conj_pick', 'conj_grid',
  'sentence_builder', 'cloze', 'spot_error',
];

void main() {
  final path = Platform.environment['TOSK_HNS_PACK'] ?? _defaultPath;
  group('local Sarnami pack', () {
    late CourseData course;
    late ValidityReport report;
    setUpAll(() {
      course = loadCourseFile(path);
      report = runTemplateValidity(course);
    });

    test('is a Dutch-only, unverified hns course', () {
      expect(course.meta.id, 'hns');
      expect(course.meta.translations, ['nl']);
      expect(course.meta.unverified, isTrue);
    });

    test('every generated exercise is valid', () {
      expect(report.failures.take(10).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
    });

    test('every applicable skill x template generates >= 20 exercises', () {
      expect(report.shortfalls(20), isEmpty, reason: report.toString());
    });

    test('the core templates are used somewhere in the course', () {
      expect(report.unusedLabels(_requiredTemplates), isEmpty, reason: report.toString());
    });

    test('every skill has at least 3 applicable templates', () {
      final thin = [
        for (final s in course.skills)
          if (report.applicable.where((k) => k.$1 == s.id).length < 3) s.id,
      ];
      expect(thin, isEmpty, reason: report.toString());
    });

    test('an English source-language setting still yields Dutch prompts', () {
      final r = runTemplateValidity(course, perPair: 3, langs: ['en']);
      expect(r.failures.take(5).join('\n\n'), isEmpty, reason: '${r.failures.length} failures');
    });
  }, skip: File(path).existsSync() ? false : 'Sarnami pack $path not built (local only)');
}
