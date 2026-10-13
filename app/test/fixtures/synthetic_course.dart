/// A large synthetic course database (realistic shape, nonsense words) for
/// load-time tests. Built from `schema/course_db.sql`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/common.dart' show CommonDatabase;

import 'course_fixture.dart' show courseDdl, fixturePersons;

/// Fills [db] with [items] items (a quarter verbs with 4 tenses × 6 persons),
/// [sentences] sentences of ~8 tokens, and skills of 40 items each.
void populateSyntheticCourse(CommonDatabase db,
    {int items = 8000, int sentences = 12000, int seed = 1}) {
  final rnd = Random(seed);
  String word() => List.generate(4 + rnd.nextInt(6), (_) => 'abcdefghilmnoprstuvz'[rnd.nextInt(20)]).join();
  const tenses = ['presente', 'passato_prossimo', 'imperfetto', 'futuro'];
  db.execute(courseDdl());
  db.execute('BEGIN');
  final meta = {
    'schema_version': '1',
    'course_id': 'zz',
    'version': '1.0.0',
    'title': jsonEncode({'en': 'Synthetic'}),
    'target': 'zz',
    'translations': jsonEncode(['en', 'nl']),
    'persons': jsonEncode(fixturePersons),
    'tenses': jsonEncode(tenses),
    'tense_labels': '{}',
    'articles': jsonEncode(['il', 'la']),
    'unverified': '1',
    'built_at': '2026-10-13T00:00:00Z',
    'attribution': '',
  };
  meta.forEach((k, v) => db.execute('INSERT INTO meta VALUES (?, ?)', [k, v]));
  const units = 3;
  for (var u = 0; u < units; u++) {
    db.execute('INSERT INTO units VALUES (?, ?, ?)', ['u$u', u, jsonEncode({'en': 'Unit $u'})]);
  }
  final ins = db.prepare('INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,?)');
  final tag = db.prepare('INSERT INTO item_tags VALUES (?,?)');
  final verb = db.prepare('INSERT INTO verbs VALUES (?,?,?,?,?)');
  final form = db.prepare('INSERT INTO verb_forms VALUES (?,?,?,?,?,?,?)');
  final ids = <String>[];
  for (var i = 0; i < items; i++) {
    final isVerb = i % 4 == 0;
    final lemma = '${word()}$i';
    final id = 'zz:$lemma';
    ids.add(id);
    final tags = ['t${i % 50}'];
    ins.execute([
      id, isVerb ? 'verb' : 'noun', lemma, isVerb ? null : 'il', isVerb ? null : 'm', null, i + 1,
      'u${i % units}', jsonEncode({'en': [word(), word()], 'nl': [word()]}), '[]', jsonEncode(tags),
    ]);
    tag.execute([id, tags.first]);
    if (isVerb) {
      verb.execute([id, 'are', lemma.substring(0, 3), 0, 'avere']);
      for (final t in tenses) {
        for (final p in fixturePersons) {
          form.execute([id, t, p, '${lemma}_$p', lemma, '_$p', '[]']);
        }
      }
    }
  }
  ins.close();
  tag.close();
  verb.close();
  form.close();
  final sk = db.prepare('INSERT INTO skills VALUES (?,?,?,?,?,?,?,?,?,?,?)');
  final si = db.prepare('INSERT INTO skill_items VALUES (?,?,?)');
  final sf = db.prepare('INSERT INTO skill_facets VALUES (?,?,?,?,?,?)');
  for (var s = 0; s * 40 < items; s++) {
    sk.execute(['s$s', 'u${s % units}', s, 'vocab', jsonEncode({'en': 'Skill $s'}), null, null, '[]', null, null, '{}']);
    for (var k = 0; k < 40 && s * 40 + k < items; k++) {
      final id = ids[s * 40 + k];
      si.execute(['s$s', id, k]);
      sf.execute(['s$s', '$id#rec', id, 'rec', null, k]);
      sf.execute(['s$s', '$id#prod', id, 'prod', null, k]);
    }
  }
  sk.close();
  si.close();
  sf.close();
  final sn = db.prepare('INSERT INTO sentences VALUES (?,?,?,?,?)');
  final tk = db.prepare('INSERT INTO tokens VALUES (?,?,?,?,?,?,?)');
  for (var i = 0; i < sentences; i++) {
    final toks = [for (var k = 0; k < 7; k++) ids[rnd.nextInt(ids.length)]];
    final words = [for (final t in toks) t.substring(3)];
    final id = 's:$i';
    sn.execute([id, '${words.join(' ')}.', jsonEncode({'en': 'Sentence $i', 'nl': 'Zin $i'}), 'tatoeba:$i', null]);
    for (var k = 0; k < toks.length; k++) {
      tk.execute([id, k, words[k], k == 0 ? '' : ' ', 1, toks[k], null]);
    }
    tk.execute([id, toks.length, '.', '', 0, null, null]);
  }
  sn.close();
  tk.close();
  db.execute('COMMIT');
}
