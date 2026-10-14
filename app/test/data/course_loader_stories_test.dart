import 'dart:convert';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fixtures/course_fixture.dart';

/// Adds one story (two sentences, two questions) to the fixture course.
void addStory(Database db) {
  db.execute(
    "INSERT INTO stories VALUES ('u1-ciao', 'u1', 0, 'Ciao!', ?, 'claude-gen (story)', ?)",
    [jsonEncode({'en': 'Hi!', 'nl': 'Hoi!'}), jsonEncode(['it:mangiare'])],
  );
  final rows = [
    ('st:u1-ciao.1', 'Ciao, Marco!', {'en': 'Hi, Marco!', 'nl': 'Hoi, Marco!'},
        [('Ciao', '', 1, 'it:ciao', null), (',', '', 0, null, null), ('Marco', ' ', 1, null, null), ('!', '', 0, null, null)]),
    ('st:u1-ciao.2', 'Mangiamo.', {'en': 'We eat.', 'nl': 'We eten.'},
        [('Mangiamo', '', 1, 'it:mangiare', 'presente.noi'), ('.', '', 0, null, null)]),
  ];
  for (var i = 0; i < rows.length; i++) {
    final (id, text, tr, toks) = rows[i];
    db.execute("INSERT INTO sentences VALUES (?, ?, ?, 'claude-gen (story: u1-ciao)', 'u1')", [id, text, jsonEncode(tr)]);
    for (var k = 0; k < toks.length; k++) {
      final (t, pre, isWord, lex, form) = toks[k];
      db.execute('INSERT INTO tokens VALUES (?,?,?,?,?,?,?)', [id, k, t, pre, isWord, lex, form]);
    }
    db.execute("INSERT INTO story_sentences VALUES ('u1-ciao', ?, ?)", [i, id]);
  }
  db.execute(
    "INSERT INTO story_questions VALUES ('u1-ciao', 0, NULL, ?, ?, 1, '{}')",
    [jsonEncode({'en': 'Who is it?', 'nl': 'Wie is het?'}), jsonEncode(['Luca', 'Marco', 'Anna'])],
  );
  db.execute(
    "INSERT INTO story_questions VALUES ('u1-ciao', 1, 'Che cosa fanno?', ?, ?, 0, ?)",
    [
      jsonEncode({'en': 'What do they do?', 'nl': 'Wat doen ze?'}),
      jsonEncode([
        {'en': 'They eat', 'nl': 'Ze eten'},
        {'en': 'They sleep', 'nl': 'Ze slapen'},
        {'en': 'They sing', 'nl': 'Ze zingen'},
      ]),
      jsonEncode({'en': 'Sentence 2.', 'nl': 'Zin 2.'}),
    ],
  );
}

void main() {
  test('stories load with their sentences, tokens and questions; their sentences stay out of the pool', () {
    final db = openFixtureCourseDb();
    addStory(db);
    final repo = loadCourseRepoFromSqlite(db);
    db.close();
    final c = repo.data;
    expect(c.stories.map((s) => s.id), ['u1-ciao']);
    final st = c.story('u1-ciao')!;
    expect(st.unitId, 'u1');
    expect(st.title, 'Ciao!');
    expect(st.titleTr, {'en': 'Hi!', 'nl': 'Hoi!'});
    expect(st.newWords, ['it:mangiare']);
    expect(st.src, 'claude-gen (story)');
    expect(st.sentences.map((s) => s.text), ['Ciao, Marco!', 'Mangiamo.']);
    expect(st.sentences[1].tokens.first.lex, 'it:mangiare');
    expect(st.sentences[1].tokens.first.form, 'presente.noi');
    expect(st.sentences[0].tokens[2].pre, ' ');
    expect(st.questions, hasLength(2));
    expect(st.questions[0].prompt, isNull);
    expect(st.questions[0].options.map((o) => o.label('en')), ['Luca', 'Marco', 'Anna']);
    expect(st.questions[0].options.every((o) => o.isTarget), isTrue);
    expect(st.questions[0].correct, 1);
    expect(st.questions[1].prompt, 'Che cosa fanno?');
    expect(st.questions[1].options[2].label('nl'), 'Ze zingen');
    expect(st.questions[1].explanationTr['en'], 'Sentence 2.');
    // Not part of the exercise pool.
    expect(c.sentence('st:u1-ciao.2'), isNull);
    expect(c.sentencesFor('it:mangiare').map((s) => s.id), isNot(contains('st:u1-ciao.2')));
    expect(c.sentencesFor('it:mangiare'), isNotEmpty);
    expect(repo.counts.sentences, 11);
    // The repo delegates.
    expect(repo.stories, same(c.stories));
    expect(repo.story('u1-ciao'), same(st));
  });

  test('packs without story tables (built before stories) load with no stories', () {
    final db = openFixtureCourseDb();
    db.execute('DROP TABLE story_questions');
    db.execute('DROP TABLE story_sentences');
    db.execute('DROP TABLE stories');
    final c = loadCourseFromSqlite(db);
    db.close();
    expect(c.stories, isEmpty);
    expect(c.story('u1-ciao'), isNull);
    expect(c.sentencesFor('it:mangiare'), isNotEmpty);
  });

  test('a question whose correct index is out of range is skipped', () {
    final db = openFixtureCourseDb();
    addStory(db);
    db.execute("UPDATE story_questions SET correct = 7 WHERE idx = 0");
    final c = loadCourseFromSqlite(db);
    db.close();
    expect(c.story('u1-ciao')!.questions.map((q) => q.prompt), ['Che cosa fanno?']);
  });

  test('story facet ids and scores', () {
    expect(storyFacetId('it', 'u1-ciao'), 'it:story:u1-ciao#story');
    expect(storyIdOfFacet('it:story:u1-ciao#story'), 'u1-ciao');
    expect(storyIdOfFacet('it:mangiare#rec'), isNull);
    final e = ReviewEvent(
      id: 'x',
      facetId: storyFacetId('it', 'u1-ciao'),
      at: DateTime.utc(2026),
      rating: Rating.good,
      exerciseType: kStoryReadType,
      inputMode: InputMode.tap,
      responseMs: 1000,
      correct: true,
      answer: '3/4',
    );
    expect(e.isStory, isTrue);
    expect(storyScoreOf(e), (correct: 3, total: 4));
  });
}
