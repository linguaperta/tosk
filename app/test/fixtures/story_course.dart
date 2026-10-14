/// The demo Italian course plus two graded stories, for the story UI tests.
library;

import 'package:tosk/core/core.dart';
import 'package:tosk/ui/demo/demo_courses.dart';

/// A sentence from `(text, lex, form)` tokens; a token after the first gets a
/// space before it unless it is punctuation.
Sentence storySentence(String id, Map<String, String> tr, List<(String, String?, String?)> toks) {
  final punct = RegExp(r'^[.,!?;:]$');
  final tokens = [
    for (var i = 0; i < toks.length; i++)
      Token(
        idx: i,
        t: toks[i].$1,
        pre: i == 0 || punct.hasMatch(toks[i].$1) ? '' : ' ',
        isWord: !punct.hasMatch(toks[i].$1),
        lex: toks[i].$2,
        form: toks[i].$3,
      ),
  ];
  final text = tokens.map((t) => t.pre + t.t).join();
  return Sentence(id: id, text: text, tr: tr, tokens: tokens, src: 'claude-gen (story)');
}

final testStories = [
  Story(
    id: 'u1-pane',
    unitId: 'u1',
    ord: 0,
    title: 'Il pane',
    titleTr: const {'en': 'The bread', 'nl': 'Het brood'},
    newWords: const ['it:mangiare'],
    sentences: [
      storySentence('st:u1-pane.1', const {'en': 'Hi, mum!', 'nl': 'Hoi, mama!'}, [
        ('Ciao', 'it:ciao', null),
        (',', null, null),
        ('madre', 'it:madre', null),
        ('!', null, null),
      ]),
      storySentence('st:u1-pane.2', const {'en': 'Bread and water.', 'nl': 'Brood en water.'}, [
        ('Pane', 'it:pane', null),
        ('e', null, null),
        ('acqua', 'it:acqua', null),
        ('.', null, null),
      ]),
      storySentence('st:u1-pane.3', const {'en': 'We eat bread.', 'nl': 'We eten brood.'}, [
        ('Mangiamo', 'it:mangiare', 'presente.noi'),
        ('pane', 'it:pane', null),
        ('.', null, null),
      ]),
      storySentence('st:u1-pane.4', const {'en': 'Thank you!', 'nl': 'Dank je!'}, [
        ('Grazie', 'it:grazie', null),
        ('!', null, null),
      ]),
    ],
    questions: const [
      StoryQuestion(
        promptTr: {'en': 'What do they eat?', 'nl': 'Wat eten ze?'},
        options: [StoryOption.target('pane'), StoryOption.target('mela'), StoryOption.target('formaggio')],
        correct: 0,
        explanationTr: {'en': 'Sentence 3: Mangiamo pane.', 'nl': 'Zin 3: Mangiamo pane.'},
      ),
      StoryQuestion(
        prompt: 'Che cosa dice alla fine?',
        promptTr: {'en': 'What does she say at the end?', 'nl': 'Wat zegt ze aan het eind?'},
        options: [
          StoryOption.translated({'en': 'Thank you', 'nl': 'Dank je'}),
          StoryOption.translated({'en': 'Goodbye', 'nl': 'Tot ziens'}),
          StoryOption.translated({'en': 'Good morning', 'nl': 'Goedemorgen'}),
        ],
        correct: 0,
      ),
    ],
  ),
  Story(
    id: 'u2-dormire',
    unitId: 'u2',
    ord: 0,
    title: 'Dormire',
    titleTr: const {'en': 'Sleeping', 'nl': 'Slapen'},
    sentences: [
      storySentence('st:u2-dormire.1', const {'en': 'The brother sleeps.', 'nl': 'De broer slaapt.'}, [
        ('Il', null, null),
        ('fratello', 'it:fratello', null),
        ('dorme', 'it:dormire', 'presente.lui/lei'),
        ('.', null, null),
      ]),
    ],
    questions: const [
      StoryQuestion(
        promptTr: {'en': 'Who sleeps?', 'nl': 'Wie slaapt er?'},
        options: [StoryOption.target('il fratello'), StoryOption.target('la sorella'), StoryOption.target('il padre')],
        correct: 0,
      ),
    ],
  ),
];

CourseData storyCourse() => buildDemoItalian(stories: testStories);
