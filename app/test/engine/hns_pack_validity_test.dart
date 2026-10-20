// Runs the template validity suite on the locally built Sarnami pack.
//
// The Sarnami (hns) pack is built from all-rights-reserved sources, so it is never committed or
// bundled: it is built locally by a private pipeline plugin (docs/private-importers.md). Point
// $TOSK_HNS_PACK (or the older $TOSK_HNS_PACK) at the built `hns.sqlite` to run these tests;
// without it (CI, public clones) they are skipped.
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'template_validity.dart';

/// The templates every Sarnami pack must use somewhere. Transform needs person changes in
/// pro-drop sentences or same-length tense swaps; Sarnami examples rarely allow that, so it is
/// reported but not required.
const _requiredTemplates = [
  'flashcard', 'multiple_choice', 'match_pairs', 'conj_pick', 'conj_grid',
  'sentence_builder', 'cloze', 'spot_error',
];

void main() {
  final env = Platform.environment;
  final path = env['TOSK_HNS_PACK'] ?? env['TOSK_HNS_PACK'] ?? '';
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
  }, skip: path.isNotEmpty && File(path).existsSync()
      ? false
      : 'no local Sarnami pack (set TOSK_HNS_PACK to its path)');
}
