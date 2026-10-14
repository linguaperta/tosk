// Inflection tables (#infl facets): ids, token forms, glosses and the
// templates' sentence rules. Validity in general: template_validity_test.dart.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/inflection_course.dart';

GenContext _ctx(CourseData c, int seed) => GenContext(
      course: c,
      options: const SessionOptions(sourceLang: 'en'),
      random: Random(seed),
    );

SkillFacet _facet(CourseData c, String skill, String facetId) =>
    c.skillFacets(skill).firstWhere((f) => f.facetId == facetId);

void main() {
  test('facet ids and token forms', () {
    final f = FacetId.parse('it:casa#infl:number');
    expect(f.kind, FacetKind.infl);
    expect(f.table, 'number');
    expect(f.toString(), 'it:casa#infl:number');
    expect(FacetKind.tryParse('declension'), isNull);
    const t = Token(idx: 0, t: 'piccola', lex: 'it:piccolo', form: 'infl:agreement.f.sg');
    expect(t.isInflection, isTrue);
    expect(t.tense, isNull, reason: 'an inflection cell is no verb tense');
    expect(t.person, isNull);
    expect(t.inflTable, 'agreement');
    expect(t.inflCell, 'f.sg');
    const v = Token(idx: 0, t: 'mangiamo', lex: 'it:mangiare', form: 'presente.noi');
    expect((v.tense, v.person, v.inflTable), ('presente', 'noi', null));
  });

  test('course data serves tables in cell order', () {
    final c = italianInflectionCourse();
    expect([for (final f in c.inflectionTable('it:bello', 'agreement')) f.form], ['bello', 'bella', 'belli', 'belle']);
    expect(c.inflections('it:bello')['agreement.m.pl']!.accepted, ['belli', 'bei', 'begli']);
    expect(c.inflectionTable('it:bello', 'number'), isEmpty);
  });

  test('tap-for-gloss names the cell', () {
    final c = italianInflectionCourse();
    final g = glossForToken(c, itemId: 'it:piccolo', form: 'infl:agreement.f.sg', word: 'piccola', lang: 'en')!;
    expect(g.headline, 'piccola → piccolo · feminine singular');
    final n = glossForToken(c, itemId: 'it:casa', form: 'infl:number.pl', word: 'case', lang: 'en')!;
    expect(n.headline, 'case → la casa · plural');
  });

  test('plural cloze offers only non-words, never the singular', () {
    final c = italianInflectionCourse();
    const tpl = ClozeTemplate();
    final f = _facet(c, 'plurali', 'it:casa#infl:number');
    for (var seed = 0; seed < 20; seed++) {
      final e = tpl.generate(f, _ctx(c, seed)) as ClozeExercise;
      expect(e.expected, 'case', reason: 'only the plural is asked');
      expect(e.hint, 'casa (plural)');
      expect(e.options!.toSet(), {'case', ...{'casi', 'caso'}.intersection(e.options!.toSet())});
      expect(e.options, isNot(contains('casa')));
    }
  });

  test('agreement exercises swap cells of the same word', () {
    final c = italianInflectionCourse();
    final f = _facet(c, 'aggettivi', 'it:piccolo#infl:agreement');
    final cloze = const ClozeTemplate().generate(f, _ctx(c, 3)) as ClozeExercise;
    expect(cloze.hint, 'piccolo');
    expect(cloze.options!.toSet().difference({'piccolo', 'piccola', 'piccoli', 'piccole'}), isEmpty);
    final spot = const SpotErrorTemplate().generate(f, _ctx(c, 3)) as SpotErrorExercise;
    expect({'piccolo', 'piccola', 'piccoli', 'piccole'}, contains(spot.tokens[spot.errorIndex].toLowerCase()));
    expect(spot.tokens[spot.errorIndex], isNot(spot.correction));
  });

  test('the ending picker never asks the base cell; the grid always gives it', () {
    final c = italianInflectionCourse();
    final f = _facet(c, 'aggettivi', 'it:stanco#infl:agreement');
    for (var seed = 0; seed < 20; seed++) {
      final p = const ConjPickTemplate().generate(f, _ctx(c, seed)) as ConjPickExercise;
      expect(p.inflection, isTrue);
      expect(p.person, isNot('m.sg'));
      expect(p.stem, 'stanc');
      final g = const ConjGridTemplate().generate(f, _ctx(c, seed)) as ConjGridExercise;
      expect(g.cells.first.person, 'm.sg');
      expect(g.cells.first.prefilled, isTrue);
      expect(g.tiles.toSet().intersection({'stanci', 'stance'}), isNotEmpty, reason: 'wrong forms as tiles');
    }
    // A Dutch two-cell table has no grid.
    final d = dutchInflectionCourse();
    expect(const ConjGridTemplate().canGenerate(_facet(d, 'bijvoeglijk', 'nl:wit#infl:agreement'), _ctx(d, 0)), isFalse);
  });

  test('tokens the pipeline left without a cell are never used', () {
    final c = italianInflectionCourse();
    // 'Sono stanco.' (no noun: the speaker may be a woman) has no form, so no exercise uses it.
    final f = _facet(c, 'aggettivi', 'it:stanco#infl:agreement');
    for (var seed = 0; seed < 30; seed++) {
      final e = const ClozeTemplate().generate(f, _ctx(c, seed)) as ClozeExercise;
      expect(e.sentenceId, isNot('s:20'));
    }
  });
}
