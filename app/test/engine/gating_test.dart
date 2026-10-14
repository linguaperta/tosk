// Grammar gating, the vocabulary cap, sentence variety and the transform /
// hint / synonym quality rules on a small hand-built course with gating data.
import 'dart:math';

import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'fixtures/course_builder.dart';
import 'helpers.dart';

const _pres = 'presente';
const _pp = 'passato_prossimo';

InMemoryCourseData _course({bool gated = true}) {
  final b = CourseBuilder(CourseMeta(
    id: 'it',
    version: '0.1.0',
    title: const {'en': 'Italian'},
    target: 'it',
    translations: const ['en'],
    persons: const ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'],
    tenses: const [_pres, _pp],
    articles: const ['il', 'lo', 'la', "l'"],
    baseFeatures: gated ? const ['tense:presente'] : const [],
    timeAdverbs: const {
      'adesso': [_pres],
      'ieri': [_pp],
    },
  ));
  b.unit('u1', 0, 'Basics', 'Basis');
  b.word('il', 'det', en: ['the'], freq: 1);
  b.word("l'", 'det', en: ['the'], freq: 2);
  b.noun('il', 'pane', ['bread'], gender: 'm', freq: 300);
  b.noun("l'", 'acqua', ['water'], gender: 'f', freq: 310);
  b.noun('il', 'vino', ['wine'], gender: 'm', freq: 320);
  b.word('e', 'conj', en: ['and'], freq: 3);
  b.word('adesso', 'adv', en: ['now'], freq: 100);
  b.word('ieri', 'adv', en: ['yesterday'], freq: 110);
  b.word('lo', 'pron', en: ['the', 'it'], freq: 5);
  b.word('un', 'det', en: ['a'], freq: 4);
  b.word('sempre', 'adv', en: ['always'], freq: 120);
  b.word('buono', 'adj', en: ['good'], freq: 130);
  b.verb('mangiare', ['to eat'], freq: 200, cls: 'are', aux: 'avere', tables: {
    _pres: ['mangi|o', 'mangi|', 'mangi|a', 'mang|iamo', 'mangi|ate', 'mangi|ano'],
    _pp: ['ho mangiato', 'hai mangiato', 'ha mangiato', 'abbiamo mangiato', 'avete mangiato', 'hanno mangiato'],
  });
  b.verb('bere', ['to drink'], freq: 210, cls: 'ere', aux: 'avere', tables: {
    _pres: ['bev|o', 'bev|i', 'bev|e', 'bev|iamo', 'bev|ete', 'bev|ono'],
    _pp: ['ho bevuto', 'hai bevuto', 'ha bevuto', 'abbiamo bevuto', 'avete bevuto', 'hanno bevuto'],
  });
  b.verb('andare', ['to go'], freq: 220, cls: 'are', aux: 'essere', tables: {
    _pres: ['vado', 'vai', 'va', 'and|iamo', 'and|ate', 'vanno'],
    _pp: [
      'sono andato;sono andata', 'sei andato;sei andata', 'è andato;è andata',
      'siamo andati;siamo andate', 'siete andati;siete andate', 'sono andati;sono andate',
    ],
  });
  b.vocabSkill('food', 0, 'Food', 'Eten', ['il', "l'", 'pane', 'acqua', 'vino', 'e', 'adesso', 'ieri', 'lo']);
  b.verbSkill('present', 1, 'Present', 'Heden', _pres, ['mangiare', 'bere', 'andare'], requires: ['food']);
  b.unit('u2', 1, 'Past', 'Verleden');
  b.verbSkill('past', 0, 'Past', 'Verleden', _pp, ['mangiare', 'bere'], requires: ['present']);
  b.verbSkill('past-essere', 1, 'Past with essere', 'Verleden met zijn', _pp, ['andare'], requires: ['past']);
  b.skillFeatures('present', ['tense:presente']);
  b.skillFeatures('past', ['tense:passato_prossimo']);
  b.skillFeatures('past-essere', ['tense:passato_prossimo', 'aux:essere']);

  void s(String id, String text, String en, List<String> align, Set<String> features) {
    b.sentence(id, text, en: en, align: align);
    b.sentenceFeatures(id, features);
  }

  const pres = {'tense:presente'};
  const pp = {'tense:passato_prossimo'};
  s('s:1', 'Mangio il pane.', 'I eat the bread.', ['Mangio=mangiare@presente.io', 'il=il', 'pane=pane'], pres);
  s('s:2', 'Ho mangiato il pane.', 'I ate the bread.', ['Ho=mangiare', 'mangiato=mangiare@passato_prossimo.io', 'il=il', 'pane=pane'], pp);
  s('s:3', 'Sono andato.', 'I went.', ['Sono=andare', 'andato=andare@passato_prossimo.io'], {...pp, 'aux:essere'});
  s('s:4', 'Tom mangia il pane.', 'Tom eats the bread.', ['mangia=mangiare@presente.lui/lei', 'il=il', 'pane=pane'], pres);
  s('s:5', 'Bevo il vino.', 'I drink the wine.', ['Bevo=bere@presente.io', 'il=il', 'vino=vino'], pres);
  s('s:6', 'Comprai il pane.', 'I bought the bread.', ['il=il', 'pane=pane'], const {});
  s('s:7', 'Adesso mangio il pane.', 'Now I eat the bread.', ['Adesso=adesso', 'mangio=mangiare@presente.io', 'il=il', 'pane=pane'], pres);
  s('s:8', 'Ieri ho mangiato il pane.', 'Yesterday I ate the bread.',
      ['Ieri=ieri', 'ho=mangiare', 'mangiato=mangiare@passato_prossimo.io', 'il=il', 'pane=pane'], pp);
  s('s:9', 'Mangio e bevo.', 'I eat and drink.', ['Mangio=mangiare@presente.io', 'e=e', 'bevo=bere@presente.io'], pres);
  s('s:10', 'Bevo il vino e mangio il pane.', 'I drink the wine and eat the bread.',
      ['Bevo=bere@presente.io', 'il=il', 'vino=vino', 'e=e', 'mangio=mangiare@presente.io', 'il=il', 'pane=pane'], pres);
  s('s:11', 'Ho bevuto il vino.', 'I drank the wine.', ['Ho=bere', 'bevuto=bere@passato_prossimo.io', 'il=il', 'vino=vino'], pp);
  s('s:12', "Bevo l'acqua.", 'I drink the water.', ['Bevo=bere@presente.io', "l'=l'", 'acqua=acqua'], pres);
  s('s:13', 'Lo mangio.', 'I eat it.', ['Lo=lo', 'mangio=mangiare@presente.io'], pres);
  s('s:14', 'Mangiamo il pane.', 'We eat the bread.', ['Mangiamo=mangiare@presente.noi', 'il=il', 'pane=pane'], pres);
  s('s:15', 'Beviamo il vino.', 'We drink the wine.', ['Beviamo=bere@presente.noi', 'il=il', 'vino=vino'], pres);
  s('s:16', 'Il pane e Tom.', 'The bread and Tom.', ['Il=il', 'pane=pane', 'e=e'], const {});
  s('s:17', 'Mangia sempre.', 'It is always eating.', ['Mangia=mangiare@presente.lui/lei'], pres);
  s('s:18', 'Beviamo il vino buono.', 'We drink the good wine.',
      ['Beviamo=bere@presente.noi', 'il=il', 'vino=vino', 'buono=buono'], pres);
  s('s:19', 'Ha un bevuto.', 'He has a drunk one.', ['Ha=bere', 'un=un', 'bevuto=bere@passato_prossimo.lui/lei'], pp);
  return b.build();
}

SkillFacet _facet(CourseData c, String skillId, String facetId) =>
    c.skillFacets(skillId).firstWhere((f) => f.facetId == facetId);

GenContext _ctx(CourseData c, String skillId, {SentenceGate? gate, SentenceHistory? history, int seed = 0, int? cap}) {
  final skill = c.skill(skillId);
  return GenContext(
    course: c,
    options: const SessionOptions(sourceLang: 'en'),
    random: Random(seed),
    skill: skill,
    gate: gate,
    history: history,
    wordCap: cap ?? SentenceGate.capFor(LessonFocus.mixed, skill),
    now: DateTime.utc(2026, 10, 14),
  );
}

FacetState _stable(String id) => FacetState(
      facetId: id,
      stability: 40,
      difficulty: 5,
      due: DateTime.utc(2027),
      lastReview: DateTime.utc(2026, 10, 1),
      reps: 5,
      lapses: 0,
      phase: CardPhase.review,
    );

String? _sentenceOf(Exercise e) => switch (e) {
      ClozeExercise() => e.sentenceId,
      SpotErrorExercise() => e.sentenceId,
      TransformExercise() => e.sentenceId,
      SentenceBuilderExercise() => e.sentenceId,
      _ => null,
    };

void main() {
  group('SentenceGate', () {
    test('known features: base, started and current skills, prerequisites of both', () {
      final c = _course();
      final fresh = SentenceGate(c, current: ['food']);
      expect(fresh.knownFeatures, {'tense:presente'});
      expect(fresh.featuresKnown('s:1'), isTrue);
      expect(fresh.featuresKnown('s:2'), isFalse);

      // The current skill's prerequisites count (past-essere requires past).
      final essere = SentenceGate(c, current: ['past-essere']);
      expect(essere.knownFeatures, containsAll(['tense:passato_prossimo', 'aux:essere']));

      final started = SentenceGate(c, started: ['food', 'present'], current: ['present']);
      expect(started.featuresKnown('s:2'), isFalse);
      expect(started.markStarted(['past']), isTrue);
      expect(started.featuresKnown('s:2'), isTrue);
      expect(started.featuresKnown('s:3'), isFalse, reason: 'aux:essere is only introduced by past-essere');
      expect(started.markStarted(['past']), isFalse);
    });

    test('unknown words: unknown items 1, names and numbers 0, other unaligned words 2', () {
      final c = _course();
      final g = SentenceGate(c, current: ['food']);
      expect(g.unknownWords(c.sentence('s:1')!), 1); // mangiare
      // Tom is a name (it also appears inside a sentence), mangia is unknown.
      expect(g.unknownWords(c.sentence('s:4')!), 1);
      expect(g.unknownWords(c.sentence('s:16')!), 0);
      expect(g.unknownWords(c.sentence('s:6')!), 2); // Comprai: unaligned, not a name
      expect(g.unknownWords(c.sentence('s:10')!), 2);
      expect(g.allows(c.sentence('s:1')!, 1), isTrue);
      expect(g.allows(c.sentence('s:6')!, 1), isFalse);
      expect(g.allows(c.sentence('s:10')!, 1), isFalse);
      expect(g.allows(c.sentence('s:10')!, 2), isTrue);
      g.markStarted(['present']);
      expect(g.unknownWords(c.sentence('s:10')!), 0);
    });

    test('caps: 1 for grammar focus or grammar skills, 2 otherwise', () {
      final c = _course();
      expect(SentenceGate.capFor(LessonFocus.mixed, c.skill('food')), 2);
      expect(SentenceGate.capFor(LessonFocus.vocab, c.skill('food')), 2);
      expect(SentenceGate.capFor(LessonFocus.grammar, c.skill('food')), 1);
      expect(SentenceGate.capFor(LessonFocus.mixed, c.skill('present')), 1);
    });

    test('a course without base_features is not gated', () {
      expect(SentenceGate.supports(_course(gated: false)), isFalse);
      expect(SentenceGate.supports(_course()), isTrue);
    });
  });

  group('gated templates', () {
    test('cloze, spot the error and the sentence builder only use allowed sentences', () {
      final c = _course();
      final gate = SentenceGate(c, started: ['food'], current: ['present']);
      final templates = defaultTemplates();
      final used = <String>{};
      for (final f in c.skillFacets('present')) {
        for (final t in templates) {
          if (!t.supports(f)) continue;
          for (var seed = 0; seed < 20; seed++) {
            final ctx = _ctx(c, 'present', gate: gate, seed: seed);
            if (!t.canGenerate(f, ctx)) continue;
            final e = t.generate(f, ctx);
            final sid = e == null ? null : _sentenceOf(e);
            if (sid == null) continue;
            used.add(sid);
            final s = c.sentence(sid)!;
            expect(gate.featuresKnown(sid), isTrue, reason: '${t.type.id} $sid');
            expect(gate.unknownWords(s), lessThanOrEqualTo(1), reason: '${t.type.id} $sid');
          }
        }
      }
      expect(used, isNotEmpty);
      expect(used.intersection({'s:2', 's:3', 's:6', 's:8', 's:11'}), isEmpty);
    });

    test('canGenerate is false when gating leaves no sentence, and the selector falls back', () {
      final c = _course();
      final f = _facet(c, 'present', 'it:andare#form:presente');
      // No sentence shows andare in the present.
      final gate = SentenceGate(c, current: ['present']);
      final ctx = _ctx(c, 'present', gate: gate);
      expect(const ClozeTemplate().canGenerate(f, ctx), isFalse);
      // A fresh learner in "present": bevo/mangio sentences need `il vino` etc. (food) known? food
      // is a prerequisite only, so its words are unknown: `Mangio il pane` has 2 unknown words.
      final mangiare = _facet(c, 'present', 'it:mangiare#form:presente');
      expect(gate.unknownWords(c.sentence('s:1')!), 2);
      expect(const ClozeTemplate().canGenerate(mangiare, ctx), isTrue, reason: '`Lo mangio`: only `lo` is unknown');
      final selector = ExerciseSelector();
      for (var seed = 0; seed < 10; seed++) {
        final e = selector.generate(f, _ctx(c, 'present', gate: gate, seed: seed));
        expect(e, isNotNull);
        expect(e!.type, isIn([ExerciseType.conjPick, ExerciseType.conjGrid]));
      }
    });

    test('a sentence with an unknown construct is never used, even when nothing else is left', () {
      final c = _course();
      final gate = SentenceGate(c, started: ['food', 'present', 'past'], current: ['present']);
      final f = _facet(c, 'present', 'it:andare#form:presente');
      final ctx = _ctx(c, 'present', gate: gate);
      // andare only appears in `Sono andato` (aux:essere): no transform from it.
      expect(const TransformTemplate().canGenerate(f, ctx), isFalse);
      expect(const ClozeTemplate().canGenerate(f, ctx), isFalse);
    });

    test('transform: the target tense must be known', () {
      final c = _course();
      final present = _facet(c, 'present', 'it:bere#form:presente');
      final past = _facet(c, 'past', 'it:bere#form:passato_prossimo');
      // Learner in "present" who has not started "past": no rewrite of
      // `Ho bevuto il vino` (unknown source tense) nor into the past.
      final g1 = SentenceGate(c, started: ['food'], current: ['present']);
      final g2 = SentenceGate(c, started: ['food', 'past'], current: ['present']);
      final sources1 = <String?>{};
      final sources2 = <String?>{};
      for (var seed = 0; seed < 40; seed++) {
        sources1.add((const TransformTemplate().generate(present, _ctx(c, 'present', gate: g1, seed: seed)) as TransformExercise?)?.sentenceId);
        sources2.add((const TransformTemplate().generate(present, _ctx(c, 'present', gate: g2, seed: seed)) as TransformExercise?)?.sentenceId);
      }
      expect(sources1, isNot(contains('s:11')));
      // Started "past": `Ho bevuto il vino.` -> present is fine.
      expect(sources2, contains('s:11'));
      // In "past" (current), the present sentences may be turned into the past.
      final g3 = SentenceGate(c, started: ['food', 'present'], current: ['past']);
      expect(const TransformTemplate().canGenerate(past, _ctx(c, 'past', gate: g3)), isTrue);
      // A review in "present" whose past skill is unknown never rewrites into the past.
      final g4 = SentenceGate(c, started: ['food', 'present']);
      expect(const TransformTemplate().canGenerate(past, _ctx(c, 'past', gate: g4)), isFalse);
    });

    test('MC sentence options in the target language only show known grammar', () {
      final c = _course();
      final gate = SentenceGate(c, started: ['food', 'present'], current: ['food']);
      const t = MultipleChoiceTemplate(sentenceShare: 1);
      final f = _facet(c, 'food', 'it:pane#prod');
      final texts = {for (final s in CourseIndex.of(c).allSentences) s.text: s.id};
      for (var seed = 0; seed < 20; seed++) {
        final ctx = _ctx(c, 'food', gate: gate, seed: seed);
        final e = t.generate(f, ctx) as MultipleChoiceExercise?;
        if (e == null) continue;
        for (final o in e.options) {
          final id = texts[o];
          if (id != null) expect(gate.featuresKnown(id), isTrue, reason: o);
        }
      }
    });
  });

  group('transform quality', () {
    TransformExercise? gen(CourseData c, SkillFacet f, int seed) =>
        const TransformTemplate().generate(f, _ctx(c, f.skillId, seed: seed)) as TransformExercise?;

    test('never rewrites a sentence with a second finite verb', () {
      final c = _course(gated: false);
      for (final f in [_facet(c, 'past', 'it:mangiare#form:passato_prossimo'), _facet(c, 'past', 'it:bere#form:passato_prossimo')]) {
        for (var seed = 0; seed < 40; seed++) {
          final e = gen(c, f, seed);
          expect(e?.sentenceId, isNot(isIn(['s:9', 's:10'])));
        }
      }
    });

    test('time adverbs keep their tense', () {
      final c = _course(gated: false);
      final toPast = _facet(c, 'past', 'it:mangiare#form:passato_prossimo');
      final toPresent = _facet(c, 'present', 'it:mangiare#form:presente');
      final pastSources = <String?>{};
      final presentSources = <String?>{};
      for (var seed = 0; seed < 60; seed++) {
        pastSources.add(gen(c, toPast, seed)?.sentenceId);
        presentSources.add(gen(c, toPresent, seed)?.sentenceId);
      }
      expect(pastSources, isNot(contains('s:7')), reason: '`Adesso mangio` never becomes a past tense');
      expect(pastSources, contains('s:1'));
      expect(presentSources, isNot(contains('s:8')), reason: '`Ieri ho mangiato` never becomes the present');
      expect(presentSources, contains('s:2'));
    });

    test('person changes: no impersonal third person, no number change next to an adjective', () {
      final c = _course(gated: false);
      final mangiare = _facet(c, 'present', 'it:mangiare#form:presente');
      final bere = _facet(c, 'present', 'it:bere#form:presente');
      final plain = <String>{}; // Beviamo il vino.
      final adjective = <String>{}; // Beviamo il vino buono.
      for (var seed = 0; seed < 120; seed++) {
        expect(gen(c, mangiare, seed)?.sentenceId, isNot('s:17'), reason: '"It is always eating": maybe impersonal');
        final e = gen(c, bere, seed);
        if (e?.sentenceId == 's:15') plain.add(e!.targetDescription);
        if (e?.sentenceId == 's:18') adjective.add(e!.targetDescription);
      }
      bool singular(String t) => t.contains('io') || t.contains('tu') || t.contains('lui');
      expect(plain.any(singular), isTrue, reason: '$plain');
      expect(adjective.any(singular), isFalse, reason: '$adjective');
    });

    test('a participle right after a determiner is no verb form', () {
      final c = _course(gated: false);
      final occ = CourseIndex.of(c).formOccurrences('it:bere');
      expect(occ.map((o) => o.sentence.id), isNot(contains('s:19')));
      expect(occ.map((o) => o.sentence.id), contains('s:11'));
    });
  });

  group('hints and synonyms', () {
    test('cloze hints pick the gloss that fits the translation', () {
      final c = _course(gated: false);
      final lo = c.item('it:lo')!;
      expect(contextGloss(lo, c.sentence('s:13')!, 'en'), 'it');
      expect(contextGloss(lo, c.sentence('s:1')!, 'en'), 'the');
      final noMatch = Sentence(id: 'x', text: 'Lo.', tr: const {'en': 'Hm.'}, tokens: const []);
      expect(contextGloss(lo, noMatch, 'en'), 'the, it');
      final mangiare = c.item('it:mangiare')!;
      expect(contextGloss(mangiare, c.sentence('s:1')!, 'en'), 'to eat');
    });

    test('multiple choice: no option shares a meaning with the target or its synonyms', () {
      final b = CourseBuilder(const CourseMeta(
        id: 'it', version: '0', title: {'en': 'It'}, target: 'it', translations: ['en'],
        persons: ['io'], tenses: ['presente'],
      ));
      b.unit('u1', 0, 'Basics', 'Basis');
      b.word('ciao', 'intj', en: ['hi', 'bye'], freq: 1, tags: ['greetings']);
      b.word('ehi', 'intj', en: ['hey', 'hi', 'hello'], freq: 2, tags: ['greetings']);
      b.word('salve', 'intj', en: ['hello'], freq: 3, tags: ['greetings']);
      for (final (i, w) in ['grazie:thanks', 'prego:please', 'scusa:sorry', 'basta:enough'].indexed) {
        final p = w.split(':');
        b.word(p[0], 'intj', en: [p[1]], freq: 10 + i, tags: ['greetings']);
      }
      b.vocabSkill('greetings', 0, 'Greetings', 'Groeten', ['ciao', 'ehi', 'salve', 'grazie', 'prego', 'scusa', 'basta']);
      final c = b.build();
      final f = _facet(c, 'greetings', 'it:ciao#rec');
      for (var seed = 0; seed < 30; seed++) {
        final e = const MultipleChoiceTemplate(sentenceShare: 0).generate(f, _ctx(c, 'greetings', seed: seed))
            as MultipleChoiceExercise;
        final wrong = [for (final (i, o) in e.options.indexed) if (i != e.correctIndex) o];
        expect(wrong, isNot(contains('hello')));
        expect(wrong, isNot(contains('hey')));
      }
    });
  });

  group('variety', () {
    test('prefer: unseen first, then least recently seen; session repeats last', () {
      final c = _course(gated: false);
      final ids = ['s:1', 's:4', 's:5', 's:12', 's:14'];
      final sentences = [for (final id in ids) c.sentence(id)!];
      final history = SentenceHistory(recent: ['s:5', 's:1', 's:4']); // s:4 seen last
      for (var seed = 0; seed < 20; seed++) {
        final ctx = _ctx(c, 'food', history: history, seed: seed);
        final order = [for (final s in ctx.prefer(sentences, (s) => s)) s.id];
        expect(order.take(2).toSet(), {'s:12', 's:14'});
      }
      // Seen long ago beats seen just now (penalty 1..3 against a jitter below 1).
      final long = SentenceHistory(recent: ['s:5', for (var i = 0; i < 600; i++) 'filler$i', 's:4'], capacity: 1000);
      expect(long.penalty('s:4'), greaterThan(long.penalty('s:5') + 1));
      history.use('s:12');
      final ctx = _ctx(c, 'food', history: history, seed: 1);
      expect(ctx.prefer(sentences, (s) => s).last.id, 's:12', reason: 'used in this session: last resort');
    });

    test('history: merge keeps the newest, bounded; save merges with what is stored', () async {
      expect(SentenceHistory.merge(['a', 'b', 'c'], ['b', 'd'], 3), ['c', 'b', 'd']);
      final store = InMemoryProgressStore();
      final h1 = SentenceHistory()..use('s:1')..use('s:2');
      final h2 = SentenceHistory()..use('s:3');
      // Two sessions ending at the same time keep both exposures.
      await Future.wait([h1.save(store, 'it'), h2.save(store, 'it')]);
      final loaded = await SentenceHistory.load(store, 'it');
      expect(loaded.seen('s:1') && loaded.seen('s:2') && loaded.seen('s:3'), isTrue);
      // Saving again writes nothing new; a later use is appended.
      h1.use('s:4');
      await h1.save(store, 'it');
      expect(SentenceHistory.decode(store.settings[SentenceHistory.settingKey('it')]), ['s:1', 's:2', 's:3', 's:4']);
      // A corrupt value is ignored.
      store.settings[SentenceHistory.settingKey('it')] = '{oops';
      expect((await SentenceHistory.load(store, 'it')).loadedCount, 0);
    });

    test('the selector does not repeat the previous type while another one can serve the facet', () {
      final c = _course(gated: false);
      final f = _facet(c, 'present', 'it:mangiare#form:presente');
      final selector = ExerciseSelector();
      final states = {f.facetId: _stable(f.facetId)};
      for (var seed = 0; seed < 40; seed++) {
        final ctx = GenContext(
            course: c, options: const SessionOptions(sourceLang: 'en'), random: Random(seed), states: states, skill: c.skill('present'));
        final e = selector.generate(f, ctx, avoid: ExerciseType.conjGrid);
        expect(e!.type, isNot(ExerciseType.conjGrid));
      }
      // Only the avoided type is allowed: it is still used.
      final ctx = GenContext(course: c, options: const SessionOptions(sourceLang: 'en'), random: Random(1), skill: c.skill('present'));
      expect(selector.generate(f, ctx, avoid: ExerciseType.conjGrid, only: {ExerciseType.conjGrid})?.type, ExerciseType.conjGrid);
    });

    test('a session never repeats a sentence while others are left, and stores what it showed', () async {
      final c = _course(gated: false);
      final store = InMemoryProgressStore();
      final factory = EngineSessionFactory(
        course: c,
        store: store,
        scheduler: const FakeScheduler(),
        options: const SessionOptions(sourceLang: 'en', seed: 3),
        clock: () => DateTime.utc(2026, 10, 14),
      );
      final session = await factory.lab(
        skillIds: ['present', 'past'],
        types: [ExerciseType.cloze, ExerciseType.spotError],
        length: 8,
      );
      final seen = <String>[];
      for (var e = await session.next(); e != null; e = await session.next()) {
        final id = _sentenceOf(e);
        if (id != null) seen.add(id);
        await session.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 3));
      }
      expect(seen.length, greaterThanOrEqualTo(6));
      final repeated = {for (final (i, id) in seen.indexed) if (seen.indexOf(id) != i) id};
      // Only sentences that are the single one for their facet (bere and
      // andare in the passato prossimo) may come back.
      expect(repeated.difference({'s:11', 's:3'}), isEmpty, reason: '$seen');
      final stored = SentenceHistory.decode(store.settings[SentenceHistory.settingKey('it')]);
      expect(stored.toSet(), seen.toSet());

      // The next session starts with sentences it has not shown yet.
      final next = await factory.lab(skillIds: ['present'], types: [ExerciseType.cloze], length: 4);
      for (var e = await next.next(); e != null; e = await next.next()) {
        final f = next.facetFor(e.facetId, e.skillId)!;
        final unseen = {for (final s in c.sentencesFor(f.itemId, tense: f.tense)) s.id}.difference(seen.toSet());
        if (unseen.isNotEmpty) expect(unseen, contains(_sentenceOf(e)));
        seen.add(_sentenceOf(e)!);
        await next.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 3));
      }
    });

    test('a session marks answered skills as started (non-stop opens their grammar)', () async {
      final c = _course();
      final store = InMemoryProgressStore();
      for (final f in [...c.skillFacets('food'), ...c.skillFacets('present')]) {
        store.seed(_stable(f.facetId));
      }
      final factory = EngineSessionFactory(
        course: c,
        store: store,
        scheduler: const FakeScheduler(),
        options: const SessionOptions(sourceLang: 'en', seed: 1),
        clock: () => DateTime.utc(2026, 10, 14),
      );
      final session = await factory.nonStop();
      await session.prepare();
      expect(session.gate!.featureKnown('tense:passato_prossimo'), isFalse);
      expect(session.gate!.startedSkillIds, containsAll(['food', 'present']));
      final f = _facet(c, 'past', 'it:mangiare#form:passato_prossimo');
      final e = ExerciseSelector().generate(f, session.genContext(f), only: {ExerciseType.conjGrid})!;
      await session.submit(e, correctAnswer(e), elapsed: const Duration(seconds: 3));
      expect(session.gate!.featureKnown('tense:passato_prossimo'), isTrue);
      session.stop();
    });
  });
}
