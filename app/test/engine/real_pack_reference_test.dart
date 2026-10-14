// The reference lookups and token alignment on the real bundled packs.
@TestOn('vm')
library;

import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'real_packs.dart';

void main() {
  for (final id in bundledPackIds()) {
    group('real pack $id reference', () {
      late CourseData course;
      late CourseReference ref;
      setUpAll(() {
        course = loadCourseFile('assets/courses/$id.sqlite');
        ref = CourseReference.of(course);
      });

      test('every verb has a table, persons in course order', () {
        for (final v in ref.verbs) {
          final t = ref.verbTable(v.id, 'en');
          expect(t.isEmpty, isFalse, reason: v.id);
          for (final tense in t.tenses) {
            final persons = tense.cells.map((c) => c.person).toList();
            final order = [for (final p in course.meta.persons) if (persons.contains(p)) p];
            expect(persons, order, reason: '${v.id} ${tense.tense}');
          }
        }
      });

      test('irregular forms: only in irregular verbs, and some are found', () {
        var marked = 0;
        for (final v in ref.verbs) {
          final irregular = course.verb(v.id)?.irregular ?? false;
          for (final c in ref.verbTable(v.id, 'en').tenses.expand((t) => t.cells)) {
            if (c.irregular) {
              expect(irregular, isTrue, reason: '${v.id} ${c.form}');
              marked++;
            }
          }
        }
        expect(marked, greaterThan(20));
      });

      test('a form of a frequent verb finds the verb; glosses find words; fast', () {
        final verbs = ref.verbs.where((v) => v.freq != null).toList()..sort((a, b) => a.freq!.compareTo(b.freq!));
        final sw = Stopwatch()..start();
        for (final v in verbs.take(20)) {
          final form = course.verbFormsInTense(v.id, course.meta.tenses.first).firstOrNull;
          if (form == null) continue;
          final hits = ref.search(form.form, 'en').take(10).map((h) => h.item.id);
          expect(hits, contains(v.id), reason: form.form);
          final gloss = v.gloss('en');
          if (gloss.isNotEmpty) expect(ref.search(gloss, 'en').map((h) => h.item.id), contains(v.id), reason: gloss);
        }
        // ignore: avoid_print
        print('[$id] 40 searches incl. index build: ${sw.elapsedMilliseconds} ms');
        expect(sw.elapsedMilliseconds, lessThan(5000));
      });

      test('cloze and spot-the-error token alignment renders back the sentence', () {
        final random = Random(7);
        var checked = 0;
        for (final skill in course.skills) {
          for (final f in course.skillFacets(skill.id).take(6)) {
            final ctx = GenContext(
              course: course,
              options: const SessionOptions(sourceLang: 'en'),
              random: random,
              skill: skill,
            );
            final cloze = const ClozeTemplate().generate(f, ctx) as ClozeExercise?;
            if (cloze != null) {
              expect(renderTokenRefs(cloze.tokens!), course.sentence(cloze.sentenceId!)!.text);
              expect(cloze.before.startsWith(renderTokenRefs(cloze.tokens!.take(cloze.gapFrom!))), isTrue);
              expect(cloze.after.endsWith(renderTokenRefs(cloze.tokens!.skip(cloze.gapTo! + 1))), isTrue);
              checked++;
            }
            final spot = const SpotErrorTemplate().generate(f, ctx) as SpotErrorExercise?;
            if (spot != null) {
              expect(spot.tokenRefs!.length, spot.tokens.length);
              checked++;
            }
          }
        }
        expect(checked, greaterThan(30));
      });
    });
  }
}
