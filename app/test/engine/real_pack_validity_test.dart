// Runs the template validity suite on the real bundled packs
// (app/assets/courses/*.sqlite, built by `python -m pipeline build it nl es --install`).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'template_validity.dart';
import 'real_packs.dart';

const _templates = [
  'flashcard', 'multiple_choice', 'match_pairs', 'conj_pick', 'conj_grid',
  'sentence_builder', 'cloze', 'spot_error', 'transform', 'listen_pick',
];

void main() {
  for (final id in bundledPackIds()) {
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

      test('inflection skills get the inflection templates', () {
        // skill -> templates that must serve its #infl facets
        final expected = {
          'it': {
            'plurals': ['conj_pick', 'cloze', 'spot_error'],
            'adjectives': ['conj_pick', 'conj_grid', 'cloze', 'spot_error'],
            'possessives': ['conj_pick', 'conj_grid', 'cloze', 'spot_error'],
          },
          'es': {
            'plurals': ['conj_pick', 'cloze', 'spot_error'],
            'adjectives': ['conj_pick', 'conj_grid', 'cloze', 'spot_error'],
            'colours': ['conj_pick', 'cloze', 'spot_error'],
          },
          'nl': {
            'plurals': ['conj_pick', 'cloze', 'spot_error'],
            'adjectives': ['conj_pick', 'cloze', 'spot_error'],
            'diminutives': ['conj_pick', 'cloze'],
          },
        }[id]!;
        final tpls = validityTemplates();
        final missing = <String>[];
        for (final e in expected.entries) {
          final skill = course.skill(e.key)!;
          final facets = [for (final f in course.skillFacets(skill.id)) if (f.kind == FacetKind.infl) f];
          expect(facets, isNotEmpty, reason: '${e.key} has no #infl facets');
          for (final label in e.value) {
            final t = tpls[label]!;
            final ok = facets.any((f) => t.canGenerate(
                  f,
                  GenContext(
                    course: course,
                    options: const SessionOptions(sourceLang: 'en'),
                    random: Random(1),
                    skill: skill,
                  ),
                ));
            if (!ok) missing.add('${e.key} × $label');
          }
        }
        expect(missing, isEmpty);
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
