// The graded stories of the real bundled packs (app/assets/courses/*.sqlite):
// every unit has stories, every story word is aligned (or a name or a number),
// taught by the story's unit (except its declared new word), its grammar is
// allowed there, and the questions are well formed.
@TestOn('vm')
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'real_packs.dart';

/// Main-tree units left with one story when a story moved into a topic with
/// its skill (docs/topic-split.md): Italian u15's crime story went to the
/// topic `crimine` (pack 1.4.0). A second u15 story is still to be written.
const _oneStoryLeft = {
  'it': {'u15'},
};

void main() {
  for (final id in bundledPackIds()) {
    group('real pack $id stories', () {
      late CourseData course;
      setUpAll(() => course = loadCourseFile('assets/courses/$id.sqlite'));

      test('2-3 stories per main-tree unit, 5-10 sentences and 3-5 questions each', () {
        final trees = CourseTrees.of(course);
        for (final u in trees.mainUnits) {
          final n = course.stories.where((s) => s.unitId == u.id).length;
          expect(n, inInclusiveRange(_oneStoryLeft[id]?.contains(u.id) ?? false ? 1 : 2, 3), reason: 'unit ${u.id}');
        }
        // A topic's units may have stories of their own (none is fine).
        for (final t in trees.topics) {
          for (final u in trees.unitsOf(t.id)) {
            expect(course.stories.where((s) => s.unitId == u.id).length, lessThanOrEqualTo(3), reason: 'unit ${u.id}');
          }
        }
        for (final s in course.stories) {
          expect(s.sentences.length, inInclusiveRange(5, 10), reason: s.id);
          expect(s.questions.length, inInclusiveRange(3, 5), reason: s.id);
          expect(s.newWords.length, lessThanOrEqualTo(1), reason: s.id);
          // English is always there; another source language may fall back to
          // it (pack format 1.1 `required_translations`), so check what is shown.
          expect(s.titleTr['en'], isNotEmpty, reason: '${s.id} title en');
          for (final lang in course.meta.translations) {
            expect(pickLang(s.titleTr, lang), isNotEmpty, reason: '${s.id} title $lang');
            for (final sent in s.sentences) {
              expect(sent.tr['en'], isNotEmpty, reason: '${sent.id} en');
              expect(sent.translation(lang), isNotEmpty, reason: '${sent.id} $lang');
            }
          }
        }
      });

      test('story sentences are aligned, taught by their unit and gated', () {
        // The unit at which each item is taught: the first skill selecting it.
        final unitIndex = {for (var i = 0; i < course.units.length; i++) course.units[i].id: i};
        final taughtAt = <String, int>{};
        for (final s in course.skills) {
          for (final it in course.skillItems(s.id)) {
            taughtAt.putIfAbsent(it.id, () => unitIndex[s.unitId]!);
          }
        }
        final problems = <String>[];
        for (final st in course.stories) {
          final k = unitIndex[st.unitId]!;
          final allowed = {
            ...course.meta.baseFeatures,
            for (final s in course.skills)
              if (unitIndex[s.unitId]! <= k) ...course.skillFeatures(s.id),
          };
          final later = <String>{};
          for (final sent in st.sentences) {
            expect(sent.render(), sent.text, reason: sent.id);
            expect(course.sentence(sent.id), isNull, reason: '${sent.id} must stay out of the exercise pool');
            final words = sent.tokens.where((t) => t.isWord).toList();
            for (var w = 0; w < words.length; w++) {
              final t = words[w];
              final capital = t.t[0] != t.t[0].toLowerCase();
              final lex = t.lex;
              if (lex == null) {
                if (!capital && !RegExp(r'^\d').hasMatch(t.t)) problems.add('${sent.id}: unaligned word ${t.t}');
                continue;
              }
              expect(course.item(lex), isNotNull, reason: '${sent.id}: $lex');
              final at = taughtAt[lex];
              // A capitalized word inside the sentence is a name (Roma), even when it is an item.
              if ((at == null || at > k) && !(capital && w > 0)) later.add(lex);
            }
            final extra = course.sentenceFeatures(sent.id).difference(allowed);
            if (extra.isNotEmpty) problems.add('${sent.id}: features $extra not allowed at ${st.unitId}');
          }
          final undeclared = later.difference(st.newWords.toSet());
          if (undeclared.isNotEmpty) problems.add('${st.id}: words taught after ${st.unitId}: $undeclared');
        }
        expect(problems, isEmpty);
      });

      test('questions: one correct option, distinct options, prompts in every source language', () {
        for (final st in course.stories) {
          for (final q in st.questions) {
            expect(q.options.length, inInclusiveRange(3, 4), reason: st.id);
            expect(q.correct, inInclusiveRange(0, q.options.length - 1), reason: st.id);
            expect(q.promptTr['en'], isNotEmpty, reason: '${st.id} en');
            for (final lang in course.meta.translations) {
              expect(pickLang(q.promptTr, lang), isNotEmpty, reason: '${st.id} $lang');
              final labels = [for (final o in q.options) foldAnswer(o.label(lang))];
              expect(labels.toSet().length, labels.length, reason: '${st.id}: $labels');
              expect(labels.every((l) => l.isNotEmpty), isTrue, reason: st.id);
            }
          }
        }
      });
    });
  }
}
