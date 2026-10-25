// Reading any text (engine/reading.dart) on the real bundled packs (it, nl,
// es) and a small French fixture: words found by their written form through
// the lexicon, verb tables and inflection tables; elisions; phrases and
// multi-word forms; names, numbers and unknown words; sentences; long lines in
// pieces; and the share of known words.
@TestOn('vm')
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/course_builder.dart';

/// The token [word] (case-sensitive) of [t].
ReadingToken tok(ReadingText t, String word) =>
    t.words.firstWhere((x) => x.text == word, orElse: () => throw StateError('no "$word"'));

/// The phrase [word] belongs to.
ReadingPhrase? phraseOf(ReadingText t, String word) {
  for (final p in t.paragraphs) {
    for (final x in p.tokens) {
      if (x.text == word && x.phrase != null) return p.phrases[x.phrase!];
    }
  }
  return null;
}

void main() {
  group('Italian (real pack)', () {
    late CourseData it;
    setUpAll(() => it = loadCourseFile('assets/courses/it.sqlite'));

    test('verb forms find their verb, person and tense, passato remoto included', () {
      final t = ReadingText.analyze('Ieri Marco andò al mercato e comprò il pane.', it);
      final ando = tok(t, 'andò').analyses.first;
      expect(ando.itemId, 'it:andare');
      expect(ando.form, startsWith('passato_remoto.'));
      final g = glossForToken(it, itemId: ando.itemId, form: ando.form, word: 'andò', lang: 'en')!;
      expect(g.headline, contains('andare'));
      expect(g.tenseLabel, contains('passato remoto'));
      expect(tok(t, 'comprò').analyses.first.itemId, 'it:comprare');
      expect(tok(t, 'pane').analyses.first, const WordAnalysis('it:pane'));
      expect(tok(t, 'Ieri').inCourse, isTrue, reason: 'sentence-initial capitals are looked up in lower case');
    });

    test('inflected nouns and adjectives find their lemma and cell; a lemma is no cell of itself', () {
      final t = ReadingText.analyze('I gatti sono piccoli. Il mercato.', it);
      final gatti = tok(t, 'gatti').analyses.first;
      expect(gatti.itemId, 'it:gatto');
      expect(gatti.form, '${kInflFormPrefix}number.pl');
      expect(tok(t, 'mercato').analyses, [const WordAnalysis('it:mercato')]);
    });

    test("elisions: dell'acqua and L'amico split, the article read by its full forms", () {
      final t = ReadingText.analyze("Comprò dell'acqua. L'amico beve.", it);
      final words = t.words.map((w) => w.text).toList();
      expect(words, containsAllInOrder(["dell'", 'acqua', "L'", 'amico']));
      expect(tok(t, 'acqua').analyses.first.itemId, 'it:acqua');
      expect(tok(t, "L'").inCourse, isTrue, reason: "l' is read as la / lo / il");
      expect(tok(t, 'amico').inCourse, isTrue);
      // A vowel before the apostrophe is no elision to guess: un po' stays unknown, not "poi".
      final po = tok(ReadingText.analyze("Un po' di pane.", it), "po'");
      expect(po.analyses.map((a) => a.itemId), isNot(contains('it:poi')));
    });

    test('phrases and compound forms are read together', () {
      final t = ReadingText.analyze('Sono andata a Roma. Ha mangiato una mela, per favore!', it);
      final andata = phraseOf(t, 'andata')!;
      expect(andata.text, 'Sono andata');
      expect(andata.analyses.first.itemId, 'it:andare');
      expect(andata.analyses.first.form, 'passato_prossimo.io');
      final mangiato = phraseOf(t, 'mangiato')!;
      expect(mangiato.analyses.first.itemId, 'it:mangiare');
      expect(mangiato.analyses.first.form, startsWith('passato_prossimo.'));
      expect(phraseOf(t, 'favore')!.text, 'per favore');
      expect(phraseOf(t, 'mela'), isNull, reason: 'punctuation ends a phrase');
    });

    test('names and numbers are not counted; unknown words are', () {
      final t = ReadingText.analyze('Ieri Marco ha 3 gatti e un xyzzyq.', it);
      expect(tok(t, 'Marco').isName, isTrue);
      expect(tok(t, '3').isNumber, isTrue);
      expect(tok(t, 'xyzzyq').inCourse, isFalse);
      expect(tok(t, 'xyzzyq').counts, isTrue);
      expect(t.wordCount, t.words.length - 2);
    });

    test('the share of known words', () {
      final t = ReadingText.analyze('Il gatto mangia il pane. Il gatto dorme.', it);
      final known = {'it:gatto', 'it:il'};
      final c = t.coverage((w) => w.analyses.any((a) => known.contains(a.itemId)));
      expect(c.words, 8);
      expect(c.known, 5, reason: 'Il ×3 and gatto ×2');
      expect(c.percent, 62);
      expect(c.distinct, 5);
      expect(c.distinctKnown, 2);
      expect(ReadingText.analyze('', it).coverage((_) => true).percent, 0);
    });

    test('sentences, lines and long lines in pieces', () {
      final t = ReadingText.analyze('Primo. Secondo!\n\nTerzo? «Quarto.»\n', it);
      expect(t.paragraphs, hasLength(3));
      expect(t.paragraphs[1].isBlank, isTrue);
      expect(t.sentences.map(t.sentenceText), ['Primo.', 'Secondo!', 'Terzo?', '«Quarto.»']);
      final long = List.filled(400, 'Il gatto mangia il pane.').join(' ');
      final lt = ReadingText.analyze(long, it);
      expect(lt.paragraphs.length, greaterThan(5));
      expect(lt.paragraphs.skip(1).every((p) => p.continued), isTrue);
      expect(lt.paragraphs.map((p) => p.text).join(), long, reason: 'the pieces give the line back');
      expect(lt.wordCount, 2000);
      for (final p in lt.paragraphs) {
        expect(p.text.length, lessThanOrEqualTo(ReadingText.pieceLength * 2));
      }
    });

    test('tokens give their place back: offsets, the token and sentence at a position', () {
      final t = ReadingText.analyze('Il gatto, oggi, mangia.', it);
      final p = t.paragraphs.single;
      for (final x in p.tokens) {
        expect(p.text.substring(x.start, x.end), x.text);
      }
      expect(p.tokens[p.tokenAt(4)!].text, 'gatto');
      expect(p.tokenAt(2), isNull, reason: 'a space');
      expect(p.tokens[p.tokenAt(8)!].isWord, isFalse, reason: 'the comma');
      expect(p.sentenceAt(20), 0);
    });

    test('a long text is quick', () {
      final text = List.filled(
        2000,
        "Ieri Marco andò al mercato e comprò dell'acqua, poi ha mangiato una mela.",
      ).join('\n');
      final sw = Stopwatch()..start();
      final t = ReadingText.analyze(text, it);
      expect(t.wordCount, greaterThan(20000));
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('Dutch (real pack)', () {
    late CourseData nl;
    setUpAll(() => nl = loadCourseFile('assets/courses/nl.sqlite'));

    test("strong past, participles, and words with an apostrophe (foto's) stay whole", () {
      final t = ReadingText.analyze(
        "Gisteren liep ik naar de markt. Hij heeft een appel gegeten. De foto's zijn mooi.",
        nl,
      );
      expect(tok(t, 'liep').analyses.first.itemId, 'nl:lopen');
      expect(tok(t, 'liep').analyses.map((a) => a.form), everyElement(startsWith('verleden_tijd.')));
      expect(tok(t, 'gegeten').analyses.first.itemId, 'nl:eten');
      final fotos = tok(t, "foto's");
      expect(fotos.analyses.first.itemId, 'nl:foto');
      expect(fotos.analyses.first.form, '${kInflFormPrefix}number.pl');
    });
  });

  group('Spanish (real pack)', () {
    late CourseData es;
    setUpAll(() => es = loadCourseFile('assets/courses/es.sqlite'));

    test('imperfect, compound perfect, inverted punctuation', () {
      final t = ReadingText.analyze('Ayer hablaba con mi madre. Hemos comido pan. ¿Dónde está el perro?', es);
      expect(tok(t, 'hablaba').analyses.first.itemId, 'es:hablar');
      expect(tok(t, 'hablaba').analyses.first.form, startsWith('imperfecto.'));
      final hemos = phraseOf(t, 'comido')!;
      expect(hemos.analyses.first.itemId, 'es:comer');
      expect(tok(t, 'Dónde').inCourse, isTrue);
      expect(t.paragraphs.single.tokens.firstWhere((x) => !x.isWord).text, '.');
      expect(t.paragraphs.single.tokens.any((x) => x.text == '¿'), isTrue);
    });
  });

  test("French elision with a fixture: l'eau and qu'il", () {
    final b = CourseBuilder(
      const CourseMeta(
        id: 'fr',
        version: '0.1.0',
        title: {'en': 'French'},
        target: 'fr',
        translations: ['en'],
        persons: ['je', 'tu', 'il', 'nous', 'vous', 'ils'],
        tenses: ['present'],
        tenseLabels: {
          'present': {'en': 'present'},
        },
      ),
    );
    b.unit('u1', 0, 'Basics', 'Basis');
    b.word('le', 'det', en: ['the']);
    b.word('que', 'conj', en: ['that']);
    b.word('il', 'pron', en: ['he']);
    b.noun('l\'', 'eau', ['water'], gender: 'f');
    final fr = b.build();
    final t = ReadingText.analyze("Je bois l'eau qu'il aime.", fr);
    expect(tok(t, "l'").analyses.first.itemId, 'fr:le');
    expect(tok(t, 'eau').analyses.first.itemId, 'fr:eau');
    expect(tok(t, "qu'").analyses.first.itemId, 'fr:que');
    expect(tok(t, 'il').inCourse, isTrue);
    expect(tok(t, 'Je').inCourse, isFalse);
  });

  test('any script: Cyrillic and Greek words are split and looked up', () {
    final b = CourseBuilder(
      const CourseMeta(
        id: 'ru',
        version: '0.1.0',
        title: {'en': 'Russian'},
        target: 'ru',
        translations: ['en'],
        persons: ['я'],
        tenses: ['present'],
        tenseLabels: {
          'present': {'en': 'present'},
        },
      ),
    );
    b.unit('u1', 0, 'Basics', 'Basis');
    b.word('кошка', 'noun', en: ['cat']);
    final ru = b.build();
    final t = ReadingText.analyze('Кошка спит. Η γάτα.', ru);
    expect(t.words.map((w) => w.text), ['Кошка', 'спит', 'Η', 'γάτα']);
    expect(tok(t, 'Кошка').analyses.single.itemId, 'ru:кошка');
    expect(tok(t, 'спит').inCourse, isFalse);
  });
}
