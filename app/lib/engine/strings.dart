/// Instruction lines shown above exercises, per source language.
/// These are UI language strings (the learner's language), not course content.
library;

const Map<String, Map<String, String>> _strings = {
  'en': {
    'flashcard.rec': 'What does this mean?',
    'flashcard.prod': 'How do you say this?',
    'mc.rec': 'Pick the right translation',
    'mc.prod': 'Pick the right word',
    'mc.sentence.rec': 'What does this sentence mean?',
    'mc.sentence.prod': 'Pick the correct sentence',
    'mc.article': 'Pick the right article',
    'match': 'Match the pairs',
    'conj_pick': 'Pick the right ending',
    'conj_grid': 'Fill in the table',
    'conj_grid.partial': 'Complete the table',
    'sentence_builder': 'Translate this sentence',
    'cloze': 'Fill in the gap',
    'cloze.form': 'Fill in the right form',
    'cloze.article': 'Fill in the right article',
    'spot_error': 'Tap the wrong word',
    'transform': 'Change the sentence',
    'transform.tense': 'Change the tense',
    'transform.person': 'Change the person',
  },
  'nl': {
    'flashcard.rec': 'Wat betekent dit?',
    'flashcard.prod': 'Hoe zeg je dit?',
    'mc.rec': 'Kies de juiste vertaling',
    'mc.prod': 'Kies het juiste woord',
    'mc.sentence.rec': 'Wat betekent deze zin?',
    'mc.sentence.prod': 'Kies de juiste zin',
    'mc.article': 'Kies het juiste lidwoord',
    'match': 'Koppel de paren',
    'conj_pick': 'Kies de juiste uitgang',
    'conj_grid': 'Vul de tabel in',
    'conj_grid.partial': 'Maak de tabel af',
    'sentence_builder': 'Vertaal deze zin',
    'cloze': 'Vul het ontbrekende woord in',
    'cloze.form': 'Vul de juiste vorm in',
    'cloze.article': 'Vul het juiste lidwoord in',
    'spot_error': 'Tik op het foute woord',
    'transform': 'Verander de zin',
    'transform.tense': 'Verander de tijd',
    'transform.person': 'Verander de persoon',
  },
};

/// Instruction text for [key] in [lang], falling back to English.
String instruction(String key, String lang) =>
    _strings[lang]?[key] ?? _strings['en']![key] ?? key;
