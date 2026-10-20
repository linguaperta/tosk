// Pack format 1.1: recognition-only skills, tense groups (moods), tense-specific person labels,
// started skills from introducing facets, and the gloss language of wrong options.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';
import 'template_validity.dart';

const _pres = 'presente';
const _pp = 'passato_prossimo';
const _rem = 'passato_remoto';
const _imp = 'imperativo';
const _cong = 'congiuntivo_presente';
final _now = DateTime.utc(2026, 10, 20, 12);

List<String> _t(String stem, List<String> endings) => [for (final e in endings) '$stem$e'];

InMemoryCourseData moodsCourse() {
  final b = CourseBuilder(const CourseMeta(
    id: 'it',
    version: '0.1.0',
    title: {'en': 'Italian'},
    target: 'it',
    translations: ['en', 'nl'],
    persons: ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
    tenses: [_pres, _pp, _cong, _imp, _rem],
    tenseLabels: {
      _pres: {'en': 'present'},
      _pp: {'en': 'present perfect'},
      _rem: {'en': 'simple past (passato remoto)'},
      _imp: {'en': 'imperative'},
      _cong: {'en': 'present subjunctive'},
    },
    personLabels: {'lui/lei': {'en': 'lui/lei (he/she)'}, 'loro': {'en': 'loro (they)'}},
    tensePersonLabels: {
      _imp: {
        'tu': {'en': 'tu (you)'},
        'lui/lei': {'en': 'Lei (you, formal)'},
        'noi': {'en': "noi (let's)"},
        'voi': {'en': 'voi (you, plural)'},
      },
    },
    tensePersons: {_imp: ['tu', 'lui/lei', 'noi', 'voi']},
    tenseGroups: {_imp: 'imperative', _cong: 'subjunctive'},
    recognitionSkills: {'remoto': _pp},
  ));
  b.unit('u1', 0, 'Words', 'Woorden');
  for (final w in ['gatto', 'pane', 'vino', 'casa']) {
    b.noun('il', w, [w == 'gatto' ? 'cat' : w == 'pane' ? 'bread' : w == 'vino' ? 'wine' : 'house'],
        nl: [w == 'gatto' ? 'kat' : w == 'pane' ? 'brood' : w == 'vino' ? 'wijn' : 'huis'], gender: 'm', freq: 100);
  }
  // English-only glosses (a pack whose later units lack Dutch)
  b.noun('la', 'sveglia', ['alarm clock'], gender: 'f', freq: 200);
  b.noun('la', 'doccia', ['shower'], gender: 'f', freq: 210);
  b.noun('il', 'sapone', ['soap'], gender: 'm', freq: 220);
  b.noun('il', 'pettine', ['comb'], gender: 'm', freq: 230);
  b.word('con', 'prep', en: ['with'], nl: ['met'], freq: 5);
  b.word('a', 'prep', en: ['to'], nl: ['naar'], freq: 6);
  b.vocabSkill('words', 0, 'Words', 'Woorden', ['gatto', 'pane', 'vino', 'casa', 'sveglia', 'doccia', 'sapone', 'pettine']);

  b.unit('u2', 1, 'Verbs', 'Werkwoorden');
  const are = ['o', 'i', 'a', 'iamo', 'ate', 'ano'];
  const rem = ['ai', 'asti', 'ò', 'ammo', 'aste', 'arono'];
  for (final (v, en) in [('parlare', 'to speak'), ('cantare', 'to sing'), ('guardare', 'to look'), ('lavorare', 'to work')]) {
    final s = v.substring(0, v.length - 3);
    b.verb(v, [en], nl: ['x$v'], cls: 'are', aux: 'avere', freq: 50, tables: {
      _pres: _t(s, are),
      _pp: ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno'].map((a) => '$a ${s}ato').toList(),
      _rem: _t(s, rem),
      _cong: _t(s, ['i', 'i', 'i', 'iamo', 'iate', 'ino']),
    });
    b.partialTable(v, _imp, {'tu': '${s}a', 'lui/lei': '${s}i', 'noi': '${s}iamo', 'voi': '${s}ate'});
  }
  b.verbSkill('presente', 0, 'Present', 'Tt', _pres, ['parlare', 'cantare', 'guardare', 'lavorare'], requires: ['words']);
  b.verbSkill('imperativo', 1, 'Imperative', 'Gw', _imp, ['parlare', 'cantare', 'guardare', 'lavorare'], requires: ['presente']);
  b.verbSkill('congiuntivo', 2, 'Subjunctive', 'Aw', _cong, ['parlare', 'cantare', 'guardare', 'lavorare'], requires: ['presente']);
  b.verbSkill('pp', 3, 'Perfect', 'Vtt', _pp, ['parlare', 'cantare', 'guardare', 'lavorare'], requires: ['presente']);
  b.verbSkill('remoto', 4, 'Passato remoto', 'Pr', _rem, ['parlare', 'cantare', 'guardare', 'lavorare'],
      requires: ['pp'], exercises: ['multiple_choice']);
  // a late skill sharing an early facet (like Italian progressive and stare#form:presente)
  b.verbSkill('progressive', 5, 'Progressive', 'Pg', _pres, ['parlare'], requires: ['remoto']);

  var n = 0;
  void s(String text, String en, String nl, List<String> align) => b.sentence('s:${++n}', text, en: en, nl: nl, align: align);
  for (final (v, f) in [('parlare', 'parl'), ('cantare', 'cant'), ('guardare', 'guard'), ('lavorare', 'lavor')]) {
    s('Il gatto $fò con il pane.', 'The cat ${v.substring(0, v.length - 3)}ed with the bread.', 'De kat x.',
        ['gatto=gatto', '$fò=$v@$_rem.lui/lei', 'con=con', 'pane=pane']);
    s('${f[0].toUpperCase()}${f.substring(1)}arono a casa.', 'They did it at home.', 'Zij x.',
        ['${f[0].toUpperCase()}${f.substring(1)}arono=$v@$_rem.loro', 'a=a', 'casa=casa']);
    s('${f[0].toUpperCase()}${f.substring(1)}o con il gatto.', 'I do it with the cat.', 'Ik x.',
        ['${f[0].toUpperCase()}${f.substring(1)}o=$v@$_pres.io', 'con=con', 'gatto=gatto']);
    s('${f[0].toUpperCase()}${f.substring(1)}a con il gatto!', 'Do it with the cat!', 'Doe x!',
        ['${f[0].toUpperCase()}${f.substring(1)}a=$v@$_imp.tu', 'con=con', 'gatto=gatto']);
  }
  return b.build();
}

GenContext _ctx(CourseData c, {String lang = 'en', int seed = 1, String? skill}) => GenContext(
      course: c,
      options: SessionOptions(sourceLang: lang),
      random: Random(seed),
      states: const {},
      skill: skill == null ? null : c.skill(skill),
      now: _now,
    );

void main() {
  final c = moodsCourse();
  final ix = CourseIndex.of(c);

  test('recognition-only facets get recognition types only, in every mode', () {
    final selector = ExerciseSelector();
    for (final f in c.skillFacets('remoto')) {
      expect(ix.recognitionOnly(f), isTrue);
      for (final ignore in [false, true]) {
        final types = selector.allowedTypes(f, _ctx(c, skill: 'remoto'), ignoreSkillRestriction: ignore);
        expect(types, contains(ExerciseType.multipleChoice));
        expect(types.every(kRecognitionTypes.contains), isTrue, reason: '$types');
      }
    }
    // a production skill's form facets are unaffected and get no multiple choice
    final pres = c.skillFacets('presente').first;
    expect(ix.recognitionOnly(pres), isFalse);
    expect(const MultipleChoiceTemplate().canGenerate(pres, _ctx(c, skill: 'presente')), isFalse);
  });

  test('recognition multiple choice: equivalent form, person and sentence variants are valid', () {
    final mc = const MultipleChoiceTemplate();
    final kinds = <String>{};
    for (var seed = 0; seed < 60; seed++) {
      final f = c.skillFacets('remoto')[seed % 4];
      final e = mc.generate(f, _ctx(c, seed: seed, skill: 'remoto')) as MultipleChoiceExercise?;
      expect(e, isNotNull);
      kinds.add(e!.isSentence ? 'sentence' : e.options.any((o) => o.startsWith('ha ') || o.startsWith('hanno ')) ? 'equivalent' : 'person');
      expect(validateExercise(e, mc, c, 'en'), isEmpty, reason: formatExercise(e));
    }
    expect(kinds, {'sentence', 'equivalent', 'person'});
    final report = runTemplateValidity(c, perPair: 10, langs: ['en']);
    expect(report.failures, isEmpty, reason: report.failures.take(3).join('\n'));
  });

  test('transform never changes the tense across tense groups', () {
    final t = const TransformTemplate();
    final imp = c.skillFacets('imperativo').firstWhere((f) => f.itemId == 'it:parlare');
    final cong = c.skillFacets('congiuntivo').firstWhere((f) => f.itemId == 'it:parlare');
    expect(t.canGenerate(imp, _ctx(c, skill: 'imperativo')), isFalse);
    expect(t.canGenerate(cong, _ctx(c, skill: 'congiuntivo')), isFalse);
    // within the default (indicative) group a passato remoto sentence becomes a present one
    final pres = c.skillFacets('presente').firstWhere((f) => f.itemId == 'it:parlare');
    final e = t.generate(pres, _ctx(c, skill: 'presente')) as TransformExercise?;
    expect(e, isNotNull);
  });

  test('tense-specific person labels: imperative tu, Lei and voi are all "you"', () {
    expect(c.meta.personLabel('lui/lei', 'en', tense: _imp), 'Lei (you, formal)');
    expect(c.meta.personLabel('lui/lei', 'en', tense: _pres), 'lui/lei (he/she)');
    expect(ix.ambiguousPersons('tu', tense: _imp), containsAll(['lui/lei', 'voi']));
    expect(ix.ambiguousPersons('tu', tense: _imp), isNot(contains('noi')));
    expect(ix.ambiguousPersons('tu'), isNot(contains('lui/lei')));
    // so no imperative cloze offers the Lei form as wrong for "Do it ...!"
    final cloze = const ClozeTemplate();
    for (var seed = 0; seed < 20; seed++) {
      final f = c.skillFacets('imperativo')[seed % 4];
      final e = cloze.generate(f, _ctx(c, seed: seed, skill: 'imperativo'));
      if (e is ClozeExercise && e.options != null) {
        final lei = c.verbForms(f.itemId)['$_imp.lui/lei']!.form;
        expect(e.options, isNot(contains(lei)));
      }
    }
  });

  test('a facet shared with a later skill starts only the skill that introduces it', () {
    expect(SentenceGate.startedSkills(c, ['it:parlare#form:presente']), {'presente'});
    expect(ix.introducingSkill('it:parlare#form:presente'), 'presente');
  });

  test('wrong meanings come in the language the right one is shown in', () {
    final mc = const MultipleChoiceTemplate(sentenceShare: 0);
    final dutchOnly = {'kat', 'brood', 'wijn', 'huis'};
    final english = {'alarm clock', 'shower', 'soap', 'comb', 'cat', 'bread', 'wine', 'house'};
    for (var seed = 0; seed < 20; seed++) {
      for (final (item, expected) in [('it:sveglia', english), ('it:gatto', dutchOnly)]) {
        final f = c.skillFacets('words').firstWhere((x) => x.itemId == item && x.kind == FacetKind.rec);
        final e = mc.generate(f, _ctx(c, lang: 'nl', seed: seed, skill: 'words')) as MultipleChoiceExercise?;
        if (e == null) continue;
        expect(e.options.every(expected.contains), isTrue, reason: '${e.options}');
      }
    }
  });

  test('the loader reads the 1.1 meta keys', () {
    final m = parseCourseMeta({
      'schema_version': '1',
      'schema_minor': '2',
      'course_id': 'it',
      'version': '1.3.0',
      'title': '{"en":"Italian"}',
      'target': 'it',
      'persons': '["io","tu","lui/lei","noi","voi","loro"]',
      'tenses': '["presente","imperativo","passato_remoto"]',
      'tense_persons': '{"imperativo":["tu","lui/lei","noi","voi"]}',
      'tense_person_labels': '{"imperativo":{"lui/lei":{"en":"Lei (you, formal)"}}}',
      'tense_groups': '{"imperativo":"imperative"}',
      'recognition_skills': '{"passato-remoto":{"equivalent_tense":"passato_prossimo"},"words":{}}',
    });
    expect(m.schemaMinor, 2);
    expect(m.tensePersons['imperativo'], ['tu', 'lui/lei', 'noi', 'voi']);
    expect(m.personLabel('lui/lei', 'en', tense: 'imperativo'), 'Lei (you, formal)');
    expect(m.tenseGroup('imperativo'), 'imperative');
    expect(m.tenseGroup('presente'), '');
    expect(m.recognitionSkills, {'passato-remoto': 'passato_prossimo', 'words': null});
  });
}
