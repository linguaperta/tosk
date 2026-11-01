// Runs the template validity and grammar-gating suites on locally built packs that are never
// committed or bundled (personal or restricted courses, docs/private-importers.md).
//
// Point $TOSK_LOCAL_PACKS at one or more built `.sqlite` files (separated by ';' on Windows,
// ':' elsewhere) to run them; without it (CI, public clones) the tests are skipped. The checks
// are generic: they assume nothing about the course's language or structure beyond the pack
// format (a pack without stem/ending splits has no conj_pick).
@TestOn('vm')
library;

import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gated_validity.dart';
import 'template_validity.dart';

/// Templates every course uses somewhere: they need only glosses, tables and sentences.
const _coreTemplates = [
  'flashcard', 'multiple_choice', 'match_pairs', 'conj_grid', 'sentence_builder', 'cloze', 'spot_error',
];

List<String> localPackPaths() {
  final raw = Platform.environment['TOSK_LOCAL_PACKS'] ?? '';
  final sep = Platform.isWindows ? ';' : ':';
  return [
    for (final p in raw.split(sep))
      if (p.trim().isNotEmpty) p.trim(),
  ];
}

/// Sentences flagged as too hard for a skill: `$TOSK_LOCAL_PACK_FLAGGED` names a UTF-8 file with
/// one `course id<TAB>skill id<TAB>sentence text` per line (`#` comments). A learner who is new to
/// that skill must never be offered them. The file lives with the private packs (owner feedback),
/// so no course content enters this repository.
List<(String, String, String)> flaggedSentences() {
  final path = Platform.environment['TOSK_LOCAL_PACK_FLAGGED'] ?? '';
  if (path.isEmpty || !File(path).existsSync()) return const [];
  return [
    for (final line in File(path).readAsLinesSync())
      if (line.trim().isNotEmpty && !line.startsWith('#') && line.split('\t').length >= 3)
        (line.split('\t')[0].trim(), line.split('\t')[1].trim(), line.split('\t').sublist(2).join('\t').trim()),
  ];
}

List<String> _unitSkills(CourseData c, int unitIndex) =>
    [for (final s in c.skills) if (s.unitId == c.units[unitIndex].id) s.id];

void main() {
  final paths = localPackPaths();
  if (paths.isEmpty) {
    test('local packs', () {}, skip: 'no local packs (set TOSK_LOCAL_PACKS to built .sqlite files)');
    return;
  }
  for (final path in paths) {
    group('local pack $path', () {
      late CourseData course;
      late ValidityReport report;
      setUpAll(() {
        course = loadCourseFile(path);
        report = runTemplateValidity(course);
      });

      test('every generated exercise is valid', () {
        expect(report.failures.take(10).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
      });

      test('the core templates are used somewhere in the course', () {
        expect(report.unusedLabels(_coreTemplates), isEmpty, reason: report.toString());
      });

      // (2, not the official courses' 3: a tense with its own person list, which a pack with
      // class persons uses for every tense, has no spot_error, and a 2-person imperative no grid)
      test('every skill has at least 2 applicable templates', () {
        final thin = [
          for (final s in course.skills)
            if (report.applicable.where((k) => k.$1 == s.id).length < 2) s.id,
        ];
        expect(thin, isEmpty, reason: report.toString());
      });

      test('gated lessons: a learner who started units 1..k gets only allowed grammar', () {
        final report = GatedReport();
        final mainUnits = course.units.length;
        runGatedValidity(course, report, scenario: 'fresh', started: const {}, skills: _unitSkills(course, 0),
            perPair: 3);
        for (var k = 1; k < mainUnits; k++) {
          final started = {for (var u = 0; u < k; u++) ..._unitSkills(course, u)};
          runGatedValidity(course, report, scenario: 'u1-$k lesson', started: started,
              skills: _unitSkills(course, k), perPair: 3);
        }
        expect(report.failures.take(8).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
      });

      test('flagged sentences are never offered to a learner new to their skill', () {
        // The packs declare base_features (also as an empty list): they are gated.
        expect(SentenceGate.supports(course), isTrue);
        final flagged = [for (final f in flaggedSentences()) if (f.$1 == course.meta.id) f];
        final byText = {for (final s in CourseIndex.of(course).allSentences) s.text: s};
        final shown = <String, Set<String>>{};
        for (final (_, skillId, text) in flagged) {
          final s = byText[text];
          if (s == null) continue; // dropped from the pack: never offered
          final gate = SentenceGate(course, current: [skillId]);
          expect(gate.allows(s, SentenceGate.vocabCap), isFalse, reason: '$skillId: $text');
          final texts = shown.putIfAbsent(skillId, () {
            final report = GatedReport();
            runGatedValidity(course, report, scenario: 'flagged', started: const {}, skills: [skillId], perPair: 12);
            return report.shownTexts;
          });
          expect(texts, isNot(contains(text)), reason: '$skillId: $text');
        }
      }, skip: flaggedSentences().isEmpty ? 'no flagged sentences (TOSK_LOCAL_PACK_FLAGGED)' : false);
    }, skip: File(path).existsSync() ? false : 'no pack at $path');
  }
}
