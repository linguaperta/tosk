// Course data flags the engine must respect (pipeline seed.yaml): nouns with
// both articles (`article: "de|het"`, Dutch `het mens`) are never asked or
// swapped as article errors, and uncountable nouns (no `plural`) never show up
// as plural options.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';

InMemoryCourseData _course() {
  final b = CourseBuilder(const CourseMeta(
    id: 'nl',
    version: '0.1.0',
    title: {'en': 'Dutch'},
    target: 'nl',
    translations: ['en'],
    persons: ['ik', 'jij', 'hij/zij', 'wij', 'jullie', 'zij'],
    tenses: ['tegenwoordige_tijd'],
    articles: ['de', 'het'],
  ));
  b.unit('u1', 0, 'Basics', 'Basis');
  b.word('de', 'det', en: ['the'], freq: 1);
  b.word('het', 'det', en: ['the'], freq: 2);
  b.word('een', 'det', en: ['a'], freq: 3);
  b.word('is', 'verb', en: ['is'], freq: 4);
  b.word('ik', 'pron', en: ['I'], freq: 5);
  b.word('eet', 'verb', en: ['eat'], freq: 6);
  b.noun('de|het', 'mens', ['person'], plural: 'mensen', freq: 50);
  b.noun('de', 'man', ['man'], plural: 'mannen', freq: 60);
  b.noun('het', 'ei', ['egg'], plural: 'eieren', freq: 70, tags: ['food']);
  b.noun('de', 'appel', ['apple'], plural: 'appels', freq: 80, tags: ['food']);
  b.noun('de', 'boter', ['butter'], freq: 90, tags: ['food']); // uncountable: no plural
  b.noun('de', 'peer', ['pear'], plural: 'peren', freq: 95, tags: ['food']);
  b.articleSkill('de-het', 0, 'De or het', 'De of het', ['mens', 'man']);
  b.vocabSkill('food', 1, 'Food', 'Eten', ['ei', 'appel', 'boter', 'peer']);
  b.sentence('s:1', 'De mens is een man.', en: 'The person is a man.', align: ['De=de', 'mens=mens', 'is=is', 'een=een', 'man=man']);
  b.sentence('s:2', 'De man is een mens.', en: 'The man is a person.', align: ['De=de', 'man=man', 'is=is', 'een=een', 'mens=mens']);
  b.sentence('s:3', 'Ik eet eieren.', en: 'I eat eggs.', align: ['Ik=ik', 'eet=eet', 'eieren=ei']);
  b.sentence('s:4', 'Ik eet de boter.', en: 'I eat the butter.', align: ['Ik=ik', 'eet=eet', 'de=de', 'boter=boter']);
  return b.build();
}

GenContext _ctx(CourseData c, String skill, int seed) =>
    GenContext(course: c, options: const SessionOptions(sourceLang: 'en'), random: Random(seed), skill: c.skill(skill));

SkillFacet _facet(CourseData c, String skillId, String facetId) =>
    c.skillFacets(skillId).firstWhere((f) => f.facetId == facetId);

void main() {
  final c = _course();

  test('a noun with both articles gets no article question or article error', () {
    final mens = _facet(c, 'de-het', 'nl:mens#article');
    final man = _facet(c, 'de-het', 'nl:man#article');
    for (final t in [const MultipleChoiceTemplate(sentenceShare: 0), const SpotErrorTemplate()]) {
      expect(t.canGenerate(mens, _ctx(c, 'de-het', 0)), isFalse, reason: '${t.runtimeType} on de/het mens');
      expect(t.canGenerate(man, _ctx(c, 'de-het', 0)), isTrue, reason: '${t.runtimeType} on de man');
    }
    expect(CourseIndex.of(c).articlesOf(c.item('nl:mens')!), ['de', 'het']);
  });

  test('an uncountable noun is never offered as a plural', () {
    final f = _facet(c, 'food', 'nl:ei#prod');
    var plurals = 0;
    for (var seed = 0; seed < 40; seed++) {
      final e = const ClozeTemplate().generate(f, _ctx(c, 'food', seed));
      if (e is! ClozeExercise || e.expected != 'eieren') continue;
      plurals++;
      expect(e.options, isNot(contains('boters')));
      expect(e.options, isNot(contains('boter')), reason: 'a singular is no plural option');
    }
    expect(plurals, greaterThan(0));
  });
}
