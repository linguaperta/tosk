// Partly right answers on the real bundled packs: one tile of a generated
// sentence builder or transform answer swapped for a wrong tile is a partial
// diff against the canonical answer, marks exactly that word, and (sentence
// builder, when the swapped word isn't the tested one) credits the tested facet.
@TestOn('vm')
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'real_packs.dart';

void main() {
  for (final id in realPackIds()) {
    test('real pack $id: one swapped tile is a partial answer', () async {
      final course = loadCourseFile(realPackPath(id));
      final factory = EngineSessionFactory(
        course: course,
        store: InMemoryProgressStore(),
        scheduler: const FakeScheduler(),
        options: const SessionOptions(sourceLang: 'en', seed: 11),
      );
      final s = await factory.lab(
        skillIds: [for (final k in course.skills) k.id],
        types: [ExerciseType.sentenceBuilder, ExerciseType.transform],
        length: 80,
      );
      var checked = 0, credited = 0, sentences = 0;
      for (var next = await s.next(); next != null; next = await s.next()) {
        final e = next;
        final (answers, tiles) = switch (e) {
          SentenceBuilderExercise() => (e.answers, e.tiles),
          TransformExercise() => (e.answers, e.tiles),
          _ => (const <List<String>>[], const <String>[]),
        };
        final words = answers.first;
        final keys = {for (final a in answers) for (final w in a) foldAnswer(w)};
        final wrong = tiles.where((t) => !keys.contains(foldAnswer(t))).firstOrNull;
        if (words.length < 4 || wrong == null) {
          await s.submit(e, TilesAnswer(words), elapsed: const Duration(seconds: 5));
          continue;
        }
        final at = words.length - 2;
        final given = [...words]..[at] = wrong;
        final r = defaultTemplates()
            .firstWhere((t) => t.type == e.type)
            .grade(e, TilesAnswer(given), elapsed: const Duration(seconds: 5));
        final d = r.diff;
        expect(r.correct, isFalse, reason: '${e.type.id} $given');
        expect(d, isNotNull);
        expect(d!.partial, isTrue, reason: '${e.type.id}: $given vs ${answers.first}');
        expect(d.errors, 1, reason: '$given vs ${answers.first}');
        final marked = [for (final t in d.given) if (t.isError) t.text];
        expect(marked, [wrong]);
        if (e is SentenceBuilderExercise && d.answerIndex == 0 && e.answerTokens != null) {
          sentences++;
          if (sameWords(alignedTokens(e.answerTokens!), textTokens(words.join(' ')))) {
            expect(AnswerDiff.render(d.expected), renderTokenRefs(e.answerTokens!).trim());
          }
        }
        final tested = r.outcomes.firstWhere((o) => o.facetId == e.facetId);
        if (tested.partial) credited++;
        expect(r.outcomes.where((o) => o.facetId == e.facetId).length, 1);
        checked++;
        await s.submit(e, TilesAnswer(words), elapsed: const Duration(seconds: 5));
      }
      expect(checked, greaterThan(10), reason: 'too few sentence answers in $id');
      expect(sentences, greaterThan(0));
      expect(credited, greaterThan(0), reason: 'no partial credit at all in $id');
    });
  }
}
