// Elision when a word changes (spot the error, transform): which words elide
// is read from the course's own elided tokens (French je/j', ne/n').
import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';

InMemoryCourseData _french() {
  final b = CourseBuilder(const CourseMeta(
    id: 'fr',
    version: '0.1.0',
    title: {'en': 'French'},
    target: 'fr',
    translations: ['en'],
    persons: ['je', 'tu', 'il', 'nous', 'vous', 'ils'],
    tenses: ['present', 'imparfait'],
    articles: ['le', 'la', "l'"],
  ));
  b.unit('u1', 0, 'Basics', 'Basis');
  b.word('je', 'pron', en: ['I']);
  b.word('ne', 'adv', en: ['not']);
  b.word('ce', 'pron', en: ['it']);
  b.word('pas', 'adv', en: ['not']);
  b.word('bien', 'adv', en: ['well']);
  b.verb('aller', ['to go'], tables: {
    'present': ['vais', 'vas', 'va', 'allons', 'allez', 'vont'],
    'imparfait': ['allais', 'allais', 'allait', 'allions', 'alliez', 'allaient'],
  });
  b.verb('être', ['to be'], tables: {
    'present': ['suis', 'es', 'est', 'sommes', 'êtes', 'sont'],
    'imparfait': ['étais', 'étais', 'était', 'étions', 'étiez', 'étaient'],
  });
  b.sentence('s1', 'Je vais bien.', en: "I'm fine.", align: ['Je=je', 'vais=aller@present.je', 'bien=bien']);
  b.sentence('s2', "J'allais bien.", en: 'I was fine.', align: ["J'=je", 'allais=aller@imparfait.je', 'bien=bien']);
  b.sentence('s3', "Ce n'est pas bien.", en: "It isn't good.",
      align: ['Ce=ce', "n'=ne", 'est=être@present.il', 'pas=pas', 'bien=bien']);
  return b.build();
}

void main() {
  test('the eliding words come from the elided tokens', () {
    final ix = CourseIndex.of(_french());
    expect(ix.elidingWords, containsAll(['je', 'ne']));
    expect(ix.elidingWords, isNot(contains('ce')), reason: "no c' in this course");
  });

  test('a changed word keeps the elision of the word before it', () {
    final c = _french();
    final ix = CourseIndex.of(c);
    final s1 = c.sentence('s1')!, s2 = c.sentence('s2')!, s3 = c.sentence('s3')!;
    expect(ix.breaksElision(s1, 1, 'allais'), isTrue, reason: '*je allais');
    expect(ix.breaksElision(s1, 1, 'vas'), isFalse);
    expect(ix.breaksElision(s2, 1, 'vais'), isTrue, reason: "*j'vais");
    expect(ix.breaksElision(s2, 1, 'allait'), isFalse);
    expect(ix.breaksElision(s3, 2, 'suis'), isTrue, reason: "*n'suis");
    expect(ix.breaksElision(s3, 2, 'étais'), isFalse);
  });

  test('spot the error swaps no form that breaks an elision', () {
    final c = _french();
    final ix = CourseIndex.of(c);
    for (final o in ix.formOccurrencesIn('fr:être', 'present')) {
      final words = [for (final s in formSwaps(ix, o)) s.newWord];
      expect(words, isNot(contains('suis')));
      expect(words, containsAll(['es', 'êtes']), reason: "n'es, n'êtes keep the elision");
    }
  });
}
