import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _lenient = AccentStrictness.lenient;
const _strict = AccentStrictness.strict;

/// The words of a diff line with their marks: `mangio!wrong`, plain when same.
List<String> marks(List<DiffToken> line) => [
      for (final t in line)
        if (t.isWord) t.mark == DiffMark.same ? t.text : '${t.text}!${t.mark.name}',
    ];

AnswerDiff diff(String given, String expected, {AccentStrictness s = _lenient}) =>
    diffAnswer([given], textTokens(expected), s);

void main() {
  group('tokens', () {
    test('words, punctuation and elisions', () {
      final ts = textTokens("L'acqua è fredda, vero ?");
      expect([for (final t in ts) t.text], ["L'", 'acqua', 'è', 'fredda,', 'vero', '?']);
      expect([for (final t in ts) t.pre], ['', '', ' ', ' ', ' ', ' ']);
      expect([for (final t in ts) t.isWord], [true, true, true, true, true, false]);
      expect(renderTokenRefs(ts), "L'acqua è fredda, vero ?");
    });

    test("a Dutch plural or contraction with an apostrophe is one word, not an elision", () {
      expect([for (final t in textTokens("Oma liet ons oude foto's zien")) t.text],
          ['Oma', 'liet', 'ons', 'oude', "foto's", 'zien']);
      // French words with an apostrophe inside stay whole; elisions split
      expect([for (final t in textTokens("Aujourd'hui quelqu'un l'attend")) t.text],
          ["Aujourd'hui", "quelqu'un", "l'", 'attend']);
      expect([for (final t in textTokens("Ik heb m'n sleutel")) t.text], ['Ik', 'heb', "m'n", 'sleutel']);
      // Italian c'è is still an elision
      expect([for (final t in textTokens("C'è il sole")) t.text], ["C'", 'è', 'il', 'sole']);
      // one swapped tile is one error
      final d = diffAnswer(['Oma', 'liet', 'ons', 'oude', 'bruiloft', 'zien'], textTokens("Oma liet ons oude foto's zien"),
          _lenient);
      expect(d.errors, 1);
    });

    test('aligned tokens keep their alignment when split', () {
      final ts = alignedTokens(const [
        TokenRef('La', itemId: 'it:il'),
        TokenRef("dell'acqua", pre: ' ', itemId: 'it:acqua'),
        TokenRef('.', isWord: false),
      ]);
      expect([for (final t in ts) t.text], ['La', "dell'", 'acqua', '.']);
      expect([for (final t in ts) t.pre], ['', ' ', '', '']);
      expect([for (final t in ts) t.itemId], ['it:il', 'it:acqua', 'it:acqua', null]);
    });
  });

  group('diffAnswer', () {
    test('one wrong word: marked on both lines, the rest untouched', () {
      final d = diff('il ragazzo mangio una mela', 'Il ragazzo mangia una mela.');
      expect(marks(d.given), ['il', 'ragazzo', 'mangio!wrong', 'una', 'mela']);
      expect(marks(d.expected), ['Il', 'ragazzo', 'mangia!wrong', 'una', 'mela.']);
      expect(d.errors, 1);
      expect(d.matched, 4);
      expect(d.partial, isTrue);
    });

    test('a missing word: a marker in the learner line, the word in the correct one', () {
      final d = diff('ragazzo mangia una mela', 'Il ragazzo mangia una mela.');
      expect(marks(d.expected), ['Il!missing', 'ragazzo', 'mangia', 'una', 'mela.']);
      expect(d.given.first.mark, DiffMark.missing);
      expect(d.given.first.text, isEmpty);
      expect(marks(d.given), ['!missing', 'ragazzo', 'mangia', 'una', 'mela']);
      expect(d.errors, 1);
      expect(d.partial, isTrue);
    });

    test('a missing word at the end and in the middle', () {
      final end = diff('il ragazzo mangia una', 'il ragazzo mangia una mela');
      expect(end.given.last.mark, DiffMark.missing);
      final mid = diff('il ragazzo una mela', 'il ragazzo mangia una mela');
      expect(marks(mid.given), ['il', 'ragazzo', '!missing', 'una', 'mela']);
      expect(marks(mid.expected), ['il', 'ragazzo', 'mangia!missing', 'una', 'mela']);
    });

    test('an extra word', () {
      final d = diff('il ragazzo mangia una mela rossa', 'il ragazzo mangia una mela');
      expect(marks(d.given), ['il', 'ragazzo', 'mangia', 'una', 'mela', 'rossa!extra']);
      expect(marks(d.expected), ['il', 'ragazzo', 'mangia', 'una', 'mela']);
      expect(d.errors, 1);
    });

    test('reorderings: a moved word is marked moved on both sides, not wrong', () {
      final d = diff('mangia il ragazzo', 'il ragazzo mangia');
      expect(marks(d.given), ['mangia!moved', 'il', 'ragazzo']);
      expect(marks(d.expected), ['il', 'ragazzo', 'mangia!moved']);
      expect(d.errors, 1);
      expect(d.partial, isTrue);

      final swap = diff('ragazzo il mangia una mela', 'il ragazzo mangia una mela');
      expect(swap.errors, 1);
      expect(swap.given.where((t) => t.mark == DiffMark.moved).length, 1);
      expect(swap.expected.where((t) => t.mark == DiffMark.moved).length, 1);
      expect(swap.partial, isTrue);
    });

    test('a moved word next to a wrong one', () {
      final d = diff('una mela il ragazzo mangio', 'il ragazzo mangia una mela');
      expect(d.expected.where((t) => t.mark == DiffMark.wrong).map((t) => t.text), ['mangia']);
      expect(d.given.where((t) => t.mark == DiffMark.wrong).map((t) => t.text), ['mangio']);
      expect(d.errors, 3, reason: 'two moved words and one wrong');
    });

    test('accents follow the strictness: lenient folds them, strict marks them', () {
      final lenient = diff('la citta e grande', 'La città è grande.');
      expect(lenient.errors, 0);
      expect(lenient.partial, isFalse, reason: 'nothing to fix');
      final strict = diff('la citta e grande', 'La città è grande.', s: _strict);
      expect(marks(strict.given), ['la', 'citta!wrong', 'e!wrong', 'grande']);
      expect(marks(strict.expected), ['La', 'città!wrong', 'è!wrong', 'grande.']);
      expect(strict.partial, isTrue);
    });

    test('case, punctuation and apostrophe variants never count', () {
      expect(diff('ciao come stai', '¡Ciao, come stai?').errors, 0);
      expect(diff('l’acqua è fredda', "L'acqua è fredda.").errors, 0);
      // Tiles split an elision differently: still the same words.
      final tiles = diffAnswer(["l'", 'acqua', 'è', 'fredda'], textTokens("L'acqua è fredda."), _strict);
      expect(tiles.errors, 0);
      expect([for (final t in tiles.given) t.source], [0, 1, 2, 3]);
    });

    test('a mostly wrong answer is not partial', () {
      expect(diff('xxx', 'il ragazzo mangia').partial, isFalse);
      expect(diff('la ragazza beve acqua', 'il ragazzo mangia una mela').partial, isFalse);
      // Two of three words in place but a three-word sentence allows one fix only.
      expect(diff('il ragazzo', 'il ragazzo mangia').partial, isTrue);
      expect(diff('il gatto dorme', 'il ragazzo mangia').partial, isFalse);
    });

    test('tile sources mark which tile each word came from', () {
      final d = diffAnswer(['il', 'ragazzo', 'mangio', 'una', 'mela'], textTokens('Il ragazzo mangia una mela.'), _strict);
      final wrong = d.given.firstWhere((t) => t.mark == DiffMark.wrong);
      expect(wrong.source, 2);
      expect(AnswerDiff.render(d.given), 'il ragazzo mangio una mela');
      expect(AnswerDiff.render(d.expected), 'Il ragazzo mangia una mela.');
    });

    test('bestAnswerDiff picks the closest accepted answer', () {
      final d = bestAnswerDiff(['come', 'sta', 'lei'], [textTokens('Come stai?'), textTokens('Come sta lei?')], _strict)!;
      expect(d.answerIndex, 1);
      expect(d.errors, 0);
      final e = bestAnswerDiff(['come', 'stai', 'tu', 'oggi'], [textTokens('Come stai?'), textTokens('Come sta?')], _strict)!;
      expect(e.answerIndex, 0);
      expect(e.errors, 2);
    });
  });

  group('facet mapping', () {
    test('facetOfToken: verb forms, inflections, other words', () {
      expect(facetOfToken('it:mangiare', 'presente.lui/lei'), 'it:mangiare#form:presente');
      expect(facetOfToken('it:gatto', 'infl:number.pl'), 'it:gatto#infl:number');
      expect(facetOfToken('it:bello', 'infl:agreement.f.sg'), 'it:bello#infl:agreement');
      expect(facetOfToken('it:mela', null), 'it:mela#prod');
      expect(facetOfToken(null, null), isNull);
    });

    test('changedWords: what a transform changed', () {
      final src = textTokens('Io mangio la mela.');
      final out = textTokens('io ho mangiato la mela');
      expect(changedWords(src, out).map((j) => out[j].text), ['ho', 'mangiato']);
      expect(changedWords(src, textTokens('Io mangio la mela.')), isEmpty);
    });
  });
}
