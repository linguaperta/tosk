import 'package:tosk/core/core.dart';
import 'package:tosk/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nfc', () {
    test('composes combining marks', () {
      expect(nfc('città'), 'città');
      expect(nfc('é'), 'é');
      expect(nfc('ṯ'), 'ṯ'); // Sarnami retroflex
      expect(nfc('ã'), 'ã');
    });
    test('orders marks canonically before composing', () {
      expect(nfc('ệ'), 'ệ');
      expect(nfc('ệ'), 'ệ');
      expect(nfc('ệ'), 'ệ');
    });
    test('leaves precomposed and plain text alone', () {
      expect(nfc('perché città'), 'perché città');
      expect(nfc('hello'), 'hello');
      expect(nfc(''), '');
    });
  });

  group('foldDiacritics', () {
    test('removes accents', () {
      expect(foldDiacritics('città perché è'), 'citta perche e');
      expect(foldDiacritics('ṯ ṟ ã'), 't r a');
      expect(foldDiacritics('Ærø'), 'Æro');
      expect(foldDiacritics('é'), 'e');
    });
  });

  group('normalizeAnswer', () {
    test('case, surrounding and inner punctuation, whitespace', () {
      expect(normalizeAnswer('  Ciao,   come stai?! '), 'ciao come stai');
      expect(normalizeAnswer('«Sì», disse.'), 'sì disse');
      expect(normalizeAnswer('Hello\tworld\n'), 'hello world');
    });
    test('apostrophe variants and elision spacing', () {
      expect(normalizeAnswer('L’acqua'), "l'acqua");
      expect(normalizeAnswer("l' acqua"), "l'acqua");
      expect(normalizeAnswer('l‘acqua'), "l'acqua");
      expect(normalizeAnswer("auto's"), "auto's");
    });
    test('keeps word-internal hyphens, drops dashes', () {
      expect(normalizeAnswer('e-mail'), 'e-mail');
      expect(normalizeAnswer('ciao - ciao'), 'ciao ciao');
    });
    test('NFC: decomposed equals precomposed', () {
      expect(normalizeAnswer('città'), normalizeAnswer('città'));
    });
    test('keeps diacritics (strict key)', () {
      expect(normalizeAnswer('È'), 'è');
      expect(foldAnswer('È'), 'e');
    });
  });

  group('matchAnswer', () {
    test('exact (normalized) match', () {
      final m = matchAnswer('Ho mangiato!', ['ho mangiato'], AccentStrictness.strict);
      expect(m.correct, isTrue);
      expect(m.accentSlip, isFalse);
    });
    test('strict rejects missing accents', () {
      expect(matchAnswer('citta', ['città'], AccentStrictness.strict).correct, isFalse);
    });
    test('lenient accepts missing accents with a slip flag', () {
      final m = matchAnswer('citta', ['città'], AccentStrictness.lenient);
      expect(m.correct, isTrue);
      expect(m.accentSlip, isTrue);
    });
    test('lenient prefers an exact match (no slip)', () {
      final m = matchAnswer('è', ['e', 'è'], AccentStrictness.lenient);
      expect(m.correct, isTrue);
      expect(m.accentSlip, isFalse);
    });
    test('all accepted forms and spelling variants count', () {
      expect(matchAnswer('ho veduto', ['ho visto', 'ho veduto'], AccentStrictness.strict).correct, isTrue);
      expect(matchAnswer('Kado', ['cadeau', 'kado'], AccentStrictness.strict).correct, isTrue);
    });
    test('recognizer candidates: accepted if any matches', () {
      final m = matchAnswer('mangiano', ['mangiamo'], AccentStrictness.strict, candidates: ['mangiarno', 'mangiamo']);
      expect(m.correct, isTrue);
    });
    test('empty answers are wrong', () {
      expect(matchAnswer('  ', [''], AccentStrictness.lenient).correct, isFalse);
      expect(matchAnswer('?!', ['ciao'], AccentStrictness.lenient).correct, isFalse);
    });
  });

  test('matchCase and lowerFirst', () {
    expect(matchCase('abbiamo', 'Ho'), 'Abbiamo');
    expect(matchCase('abbiamo', 'ho'), 'abbiamo');
    expect(matchCase("l'", 'La'), "L'");
    expect(lowerFirst('Mangiamo'), 'mangiamo');
  });
}
