// Word glosses, reference search, verb tables and token alignment in exercises.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/italian_course.dart';

void main() {
  final it = italianCourse();
  final ref = CourseReference.of(it);

  group('word gloss', () {
    test('a verb form shows lemma, person and tense label', () {
      final g = glossForToken(it, itemId: 'it:mangiare', form: 'presente.noi', word: 'Mangiamo', lang: 'en')!;
      expect(g.headline, 'Mangiamo → mangiare · noi · present');
      expect(g.glosses, ['to eat']);
      final nl = glossForToken(it, itemId: 'it:mangiare', form: 'presente.noi', word: 'mangiamo', lang: 'nl')!;
      expect(nl.headline, 'mangiamo → mangiare · noi · tegenwoordige tijd');
      expect(nl.glosses, ['eten']);
    });

    test('a noun shows its article; the lemma itself is not repeated', () {
      final g = glossForToken(it, itemId: 'it:ragazzo', word: 'ragazzo', lang: 'en')!;
      expect(g.headline, 'il ragazzo');
      expect(glossForToken(it, itemId: 'it:acqua', word: 'acqua', lang: 'en')!.headline, "l'acqua");
      expect(glossForToken(it, itemId: 'it:ragazzi', word: 'x', lang: 'en'), isNull);
    });

    test('unaligned tokens have no gloss', () {
      expect(glossForTokenRef(it, const TokenRef('alle'), 'en'), isNull);
    });
  });

  group('search', () {
    test('by lemma, accent- and case-insensitive', () {
      expect(ref.search('Citta', 'en').first.item.id, 'it:città');
      expect(ref.search('caffe', 'en').first.item.id, 'it:caffè');
    });

    test('by an inflected form', () {
      final hits = ref.search('mangiamo', 'en');
      expect(hits.first.item.id, 'it:mangiare');
      expect(hits.first.match, ReferenceMatch.form);
    });

    test('by a gloss in the source language', () {
      expect(ref.search('eat', 'en').first.item.id, 'it:mangiare');
      expect(ref.search('eten', 'nl').map((h) => h.item.id), contains('it:mangiare'));
      expect(ref.search('boy', 'en').first.item.id, 'it:ragazzo');
    });

    test('verbs only, and an empty query lists everything sorted', () {
      final verbs = ref.search('', 'en', verbsOnly: true);
      expect(verbs.every((h) => h.item.isVerb), isTrue);
      expect(verbs.length, ref.verbs.length);
      final all = ref.search('', 'en', limit: 10000).map((h) => h.item.lemma).toList();
      expect(all.length, it.allItems.length);
      expect(all.first, 'a');
    });
  });

  group('verb tables', () {
    test('every tense in course order, persons in course order', () {
      final t = ref.verbTable('it:mangiare', 'en');
      expect(t.tenses.map((x) => x.tense), ['presente', 'passato_prossimo']);
      expect(t.tenses.first.label, 'present');
      expect(t.tenses.first.cells.map((c) => c.person), it.meta.persons);
      expect(t.tenses.first.cells.map((c) => c.form).take(4), ['mangio', 'mangi', 'mangia', 'mangiamo']);
      expect(t.tenses.expand((x) => x.cells).any((c) => c.irregular), isFalse, reason: 'regular verb');
    });

    test('irregular forms of an irregular verb are marked', () {
      final t = ref.verbTable('it:andare', 'en');
      final present = {for (final c in t.tenses.first.cells) c.form: c.irregular};
      expect(present['vado'], isTrue);
      expect(present['vanno'], isTrue);
      expect(present['andiamo'], isFalse, reason: 'stem + the regular -are ending');
      expect(present['andate'], isFalse);
    });

    test('word entry: skills teaching it and examples', () {
      expect(ref.skillsTeaching('it:mangiare').map((s) => s.id), containsAll(['verbi', 'presente-are']));
      final ex = ref.examples('it:mangiare');
      expect(ex, isNotEmpty);
      expect(ex.every((s) => s.tokens.any((t) => t.lex == 'it:mangiare')), isTrue);
    });
  });

  group('token alignment in exercises', () {
    GenContext ctx(String skillId, {int seed = 3}) => GenContext(
      course: it,
      options: const SessionOptions(sourceLang: 'en'),
      random: Random(seed),
      skill: it.skill(skillId),
    );

    test('cloze: tokens render the sentence and the gap range matches before/after', () {
      final tpl = const ClozeTemplate();
      var checked = 0;
      for (final f in it.skillFacets('presente-are')) {
        for (var seed = 0; seed < 4; seed++) {
          final e = tpl.generate(f, ctx('presente-are', seed: seed)) as ClozeExercise?;
          if (e == null) continue;
          final tokens = e.tokens!;
          expect(e.before.startsWith(renderTokenRefs(tokens.take(e.gapFrom!))), isTrue);
          expect(e.after.endsWith(renderTokenRefs(tokens.skip(e.gapTo! + 1))), isTrue);
          expect(renderTokenRefs(tokens), it.sentence(e.sentenceId!)!.text);
          checked++;
        }
      }
      expect(checked, greaterThan(5));
    });

    test('spot the error: refs parallel to tokens, the error carries the original alignment', () {
      final tpl = const SpotErrorTemplate();
      var checked = 0;
      for (final f in it.skillFacets('presente-are')) {
        final e = tpl.generate(f, ctx('presente-are')) as SpotErrorExercise?;
        if (e == null) continue;
        expect(e.tokenRefs!.length, e.tokens.length);
        final r = e.tokenRefs![e.errorIndex];
        expect(r.itemId, f.itemId);
        expect(r.form, startsWith('presente.'));
        checked++;
      }
      expect(checked, greaterThan(2));
    });

    test('sentence multiple choice, transform and sentence builder carry the sentence tokens', () {
      final mc = const MultipleChoiceTemplate(sentenceShare: 1);
      final f = it.skillFacets('verbi').firstWhere((f) => f.facetId == 'it:mangiare#prod');
      final e = mc.generate(f, ctx('verbi')) as MultipleChoiceExercise;
      expect(renderTokenRefs(e.sentenceTokens!), e.options[e.correctIndex]);
      final sb = const SentenceBuilderTemplate().generate(f, ctx('verbi')) as SentenceBuilderExercise;
      expect(renderTokenRefs(sb.answerTokens!), it.sentence(sb.sentenceId!)!.text);
      TransformExercise? t;
      for (final g in it.skillFacets('passato-prossimo')) {
        t ??= const TransformTemplate().generate(g, ctx('passato-prossimo')) as TransformExercise?;
      }
      expect(t, isNotNull);
      expect(renderTokenRefs(t!.sourceTokens!), t.source);
    });
  });
}
