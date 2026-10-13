import 'package:flutter_test/flutter_test.dart';

import 'fixtures/dutch_course.dart';
import 'fixtures/italian_course.dart';
import 'template_validity.dart';

/// Pairs that must be applicable in the fixtures (so a template that silently
/// stops generating is caught). label -> skills.
const _expectIt = {
  'flashcard': ['saluti', 'persone', 'cibo', 'verbi', 'cose', 'aggettivi'],
  'multiple_choice': ['saluti', 'persone', 'cibo', 'verbi', 'cose', 'aggettivi', 'articoli'],
  'multiple_choice/sentence': ['saluti', 'persone', 'cibo', 'verbi', 'cose'],
  'match_pairs': ['saluti', 'persone', 'cibo', 'verbi', 'cose', 'aggettivi'],
  'conj_pick': ['presente-are', 'presente-ere-ire', 'essere-avere'],
  'conj_grid': ['presente-are', 'presente-ere-ire', 'essere-avere', 'passato-prossimo'],
  'sentence_builder': ['saluti', 'persone', 'cibo', 'verbi', 'cose', 'aggettivi'],
  'cloze': ['persone', 'cibo', 'verbi', 'cose', 'presente-are', 'presente-ere-ire', 'essere-avere', 'passato-prossimo', 'articoli'],
  'spot_error': ['presente-are', 'presente-ere-ire', 'essere-avere', 'passato-prossimo', 'articoli'],
  'transform': ['presente-are', 'presente-ere-ire', 'essere-avere', 'passato-prossimo'],
};

const _expectNl = {
  'flashcard': ['groeten', 'mensen', 'eten-drinken', 'werkwoorden', 'dingen', 'bijwoorden'],
  'multiple_choice': ['groeten', 'mensen', 'eten-drinken', 'werkwoorden', 'dingen', 'bijwoorden', 'de-het'],
  'multiple_choice/sentence': ['groeten', 'mensen', 'eten-drinken', 'werkwoorden', 'dingen'],
  'match_pairs': ['groeten', 'mensen', 'eten-drinken', 'werkwoorden', 'dingen', 'bijwoorden'],
  'conj_pick': ['tt-regelmatig', 'tt-onregelmatig'],
  'conj_grid': ['tt-regelmatig', 'tt-onregelmatig', 'perfectum'],
  'sentence_builder': ['groeten', 'mensen', 'eten-drinken', 'werkwoorden', 'dingen', 'bijwoorden'],
  'cloze': ['mensen', 'eten-drinken', 'werkwoorden', 'dingen', 'tt-regelmatig', 'tt-onregelmatig', 'perfectum', 'de-het'],
  'spot_error': ['tt-regelmatig', 'tt-onregelmatig', 'perfectum', 'de-het'],
  'transform': ['tt-regelmatig', 'tt-onregelmatig', 'perfectum'],
};

void _run(String name, ValidityReport Function() run, Map<String, List<String>> expected) {
  group(name, () {
    late ValidityReport report;
    setUpAll(() => report = run());

    test('every generated exercise is valid', () {
      expect(report.failures.take(10).join('\n\n'), isEmpty, reason: '${report.failures.length} failures');
    });

    test('every applicable skill x template generates >= 20 exercises', () {
      expect(report.shortfalls(20), isEmpty);
    });

    test('every template is applicable to the expected skills', () {
      final missing = [
        for (final e in expected.entries)
          for (final s in e.value)
            if (!report.applicable.contains((s, e.key))) '$s × ${e.key}',
      ];
      expect(missing, isEmpty, reason: report.toString());
    });
  });
}

void main() {
  _run('Italian fixture', () => runTemplateValidity(italianCourse()), _expectIt);
  _run('Dutch fixture', () => runTemplateValidity(dutchCourse()), _expectNl);
}
