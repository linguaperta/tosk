/// A small but realistic Italian course database for tests, built from the
/// authoritative DDL in `schema/course_db.sql`.
///
/// Reusable by any test (engine, progression, ui):
///
/// ```dart
/// import '../fixtures/course_fixture.dart';
/// final course = fixtureCourse();            // InMemoryCourseData
/// final repo = fixtureCourseRepo();          // CourseRepo (counts, raw meta)
/// final bytes = fixtureCourseBytes();        // the .sqlite file as bytes
/// writeFixtureCourseFile('/tmp/it.sqlite');  // the .sqlite file on disk
/// ```
///
/// Contents: 2 units, 5 skills (greetings and food vocab; essere/avere and
/// regular -are presente grammar with full tables; an article skill), 21 items
/// (incl. 2 distractor-pool items with no unit), 8 verbs with full presente
/// tables (+ some passato prossimo, infinitive and participle forms), 11
/// sentences with aligned tokens, notes in en/nl.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/data/course/course_repo.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

/// Finds `schema/course_db.sql` from the current directory (app/ or repo root) upwards.
File courseDdlFile() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}${Platform.pathSeparator}schema${Platform.pathSeparator}course_db.sql');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  throw StateError('schema/course_db.sql not found above ${Directory.current.path}');
}

String courseDdl() => courseDdlFile().readAsStringSync();

/// Persons and presente endings for the fixture's regular -are verbs.
const fixturePersons = ['io', 'tu', 'lui/lei', 'noi', 'voi', 'loro'];

/// Creates the schema and inserts the fixture course into [db].
/// [overrideMeta] replaces/adds meta values (e.g. `{'schema_version': '2'}` for negative tests).
void populateFixtureCourse(CommonDatabase db, {Map<String, String> overrideMeta = const {}}) {
  db.execute(courseDdl());
  db.execute('BEGIN');
  _insert(db, overrideMeta);
  db.execute('COMMIT');
}

/// An in-memory native database holding the fixture course (caller closes it).
Database openFixtureCourseDb({Map<String, String> overrideMeta = const {}}) {
  final db = sqlite3.openInMemory();
  populateFixtureCourse(db, overrideMeta: overrideMeta);
  return db;
}

/// Writes the fixture course to a database file at [path] (overwrites).
String writeFixtureCourseFile(String path, {Map<String, String> overrideMeta = const {}}) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  final db = sqlite3.open(path);
  try {
    populateFixtureCourse(db, overrideMeta: overrideMeta);
  } finally {
    db.close();
  }
  return path;
}

/// The fixture course database file as bytes.
Uint8List fixtureCourseBytes({Map<String, String> overrideMeta = const {}}) {
  final dir = Directory.systemTemp.createTempSync('tosk_fixture_');
  try {
    final path = writeFixtureCourseFile('${dir.path}${Platform.pathSeparator}it.sqlite',
        overrideMeta: overrideMeta);
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The fixture loaded through the real loader.
CourseRepo fixtureCourseRepo() {
  final db = openFixtureCourseDb();
  try {
    return loadCourseRepoFromSqlite(db);
  } finally {
    db.close();
  }
}

InMemoryCourseData fixtureCourse() => fixtureCourseRepo().data;

// ---------------------------------------------------------------------------- data

String _j(Object o) => jsonEncode(o);

void _insert(CommonDatabase db, Map<String, String> overrideMeta) {
  final meta = <String, String>{
    'schema_version': '1',
    'course_id': 'it',
    'version': '0.1.0',
    'title': _j({'en': 'Italian', 'nl': 'Italiaans'}),
    'target': 'it',
    'translations': _j(['en', 'nl']),
    'persons': _j(fixturePersons),
    'tenses': _j(['presente', 'passato_prossimo']),
    'tense_labels': _j({
      'presente': {'en': 'present', 'nl': 'tegenwoordige tijd'},
      'passato_prossimo': {'en': 'present perfect', 'nl': 'voltooid tegenwoordige tijd'},
    }),
    'person_labels': _j({
      'lui/lei': {'en': 'he/she', 'nl': 'hij/zij'},
    }),
    'articles': _j(['il', 'lo', 'la', "l'", 'i', 'gli', 'le']),
    'unverified': '0',
    'built_at': '2026-10-13T00:00:00Z',
    'attribution': 'Test fixture, hand-written.',
    'description': _j({'en': 'Fixture course', 'nl': 'Testcursus'}),
    ...overrideMeta,
  };
  final m = db.prepare('INSERT INTO meta(key, value) VALUES (?, ?)');
  meta.forEach((k, v) => m.execute([k, v]));
  m.close();

  db.execute("INSERT INTO units VALUES ('u1', 0, ?), ('u2', 1, ?)", [
    _j({'en': 'Basics', 'nl': 'Basis'}),
    _j({'en': 'Food and verbs', 'nl': 'Eten en werkwoorden'}),
  ]);

  // id, unit, ord, kind, title, icon, tense, exercises, pos_x, pos_y, query
  final skills = [
    ['greetings', 'u1', 0, 'vocab', {'en': 'Greetings', 'nl': 'Begroetingen'}, 'wave', null, <String>[], null, null, {'tags': ['greetings']}],
    ['essere-avere', 'u1', 1, 'grammar', {'en': 'Essere and avere', 'nl': 'Essere en avere'}, 'star', 'presente', ['conj_pick', 'conj_grid', 'cloze'], null, null, {'verbs': {'lemmas': ['essere', 'avere'], 'tense': 'presente'}}],
    ['food', 'u2', 0, 'vocab', {'en': 'Food', 'nl': 'Eten'}, 'food', null, <String>[], 0, 2, {'tags': ['food']}],
    ['present-are', 'u2', 1, 'grammar', {'en': 'Present: -are verbs', 'nl': 'Presente: werkwoorden op -are'}, 'verb', 'presente', ['conj_pick', 'conj_grid', 'cloze', 'transform', 'spot_error'], null, null, {'verbs': {'class': 'are', 'tense': 'presente', 'top': 4}}],
    ['articles', 'u2', 2, 'grammar', {'en': 'Articles', 'nl': 'Lidwoorden'}, null, null, ['multiple_choice'], null, null, {'items': {'tags': ['food'], 'pos': 'noun'}, 'facet': 'article'}],
  ];
  final s = db.prepare('INSERT INTO skills VALUES (?,?,?,?,?,?,?,?,?,?,?)');
  for (final r in skills) {
    s.execute([r[0], r[1], r[2], r[3], _j(r[4]!), r[5], r[6], _j(r[7]!), r[8], r[9], _j(r[10]!)]);
  }
  s.close();
  db.execute('''INSERT INTO skill_requires VALUES
    ('essere-avere','greetings'), ('food','greetings'),
    ('present-are','essere-avere'), ('present-are','food'), ('articles','food')''');

  db.execute('INSERT INTO notes VALUES (?,?,?), (?,?,?), (?,?,?), (?,?,?)', [
    'present-are', 'en', '# Present tense of -are verbs\n\nDrop **-are** and add *-o, -i, -a, -iamo, -ate, -ano*.',
    'present-are', 'nl', '# Presente van werkwoorden op -are\n\nHaal **-are** weg en voeg *-o, -i, -a, -iamo, -ate, -ano* toe.',
    'essere-avere', 'en', '# Essere and avere\n\nThe two most important irregular verbs.',
    'greetings', 'nl', '# Begroetingen\n\n*Ciao* is informeel.',
  ]);

  // id, pos, lemma, article, gender, plural, freq, unit, tr, variants, tags
  final items = <List<Object?>>[
    ['it:ciao', 'intj', 'ciao', null, null, null, 120, 'u1', {'en': ['hi', 'bye'], 'nl': ['hoi', 'doei']}, <String>[], ['greetings']],
    ['it:grazie', 'intj', 'grazie', null, null, null, 80, 'u1', {'en': ['thank you', 'thanks'], 'nl': ['dank je', 'bedankt']}, <String>[], ['greetings']],
    ['it:buongiorno', 'intj', 'buongiorno', null, null, null, 300, 'u1', {'en': ['good morning'], 'nl': ['goedemorgen']}, ['buon giorno'], ['greetings']],
    ['it:prego', 'intj', 'prego', null, null, null, 400, 'u1', {'en': ["you're welcome"], 'nl': ['graag gedaan']}, <String>[], ['greetings']],
    ['it:arrivederci', 'intj', 'arrivederci', null, null, null, 900, 'u1', {'en': ['goodbye'], 'nl': ['tot ziens']}, <String>[], ['greetings']],
    ['it:essere', 'verb', 'essere', null, null, null, 5, 'u1', {'en': ['to be'], 'nl': ['zijn']}, <String>[], <String>[]],
    ['it:avere', 'verb', 'avere', null, null, null, 8, 'u1', {'en': ['to have'], 'nl': ['hebben']}, <String>[], <String>[]],
    ['it:parlare', 'verb', 'parlare', null, null, null, 200, 'u2', {'en': ['to speak', 'to talk'], 'nl': ['spreken', 'praten']}, <String>[], <String>[]],
    ['it:lavorare', 'verb', 'lavorare', null, null, null, 260, 'u2', {'en': ['to work'], 'nl': ['werken']}, <String>[], <String>[]],
    ['it:mangiare', 'verb', 'mangiare', null, null, null, 312, 'u2', {'en': ['to eat'], 'nl': ['eten']}, <String>[], ['food']],
    ['it:abitare', 'verb', 'abitare', null, null, null, 900, 'u2', {'en': ['to live'], 'nl': ['wonen']}, <String>[], <String>[]],
    ['it:bere', 'verb', 'bere', null, null, null, 1200, 'u2', {'en': ['to drink'], 'nl': ['drinken']}, <String>[], ['food']],
    ['it:acqua', 'noun', 'acqua', 'la', 'f', 'acque', 350, 'u2', {'en': ['water'], 'nl': ['water']}, <String>[], ['food']],
    ['it:pane', 'noun', 'pane', 'il', 'm', 'pani', 500, 'u2', {'en': ['bread'], 'nl': ['brood']}, <String>[], ['food']],
    ['it:vino', 'noun', 'vino', 'il', 'm', 'vini', 700, 'u2', {'en': ['wine'], 'nl': ['wijn']}, <String>[], ['food']],
    ['it:mela', 'noun', 'mela', 'la', 'f', 'mele', 1500, 'u2', {'en': ['apple'], 'nl': ['appel']}, <String>[], ['food']],
    ['it:formaggio', 'noun', 'formaggio', 'il', 'm', 'formaggi', 1800, 'u2', {'en': ['cheese'], 'nl': ['kaas']}, <String>[], ['food']],
    ['it:gatto', 'noun', 'gatto', 'il', 'm', 'gatti', 1100, 'u2', {'en': ['cat'], 'nl': ['kat']}, <String>[], ['animals']],
    ['it:italiano', 'adj', 'italiano', null, null, null, 450, 'u2', {'en': ['Italian'], 'nl': ['Italiaans']}, <String>[], <String>[]],
    // Distractor pool only (no unit).
    ['it:camminare', 'verb', 'camminare', null, null, null, 1300, null, {'en': ['to walk'], 'nl': ['lopen', 'wandelen']}, <String>[], <String>[]],
    ['it:casa', 'noun', 'casa', 'la', 'f', 'case', 150, null, {'en': ['house', 'home'], 'nl': ['huis']}, <String>[], ['home']],
  ];
  final i = db.prepare('INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,?)');
  final t = db.prepare('INSERT INTO item_tags VALUES (?, ?)');
  for (final r in items) {
    i.execute([r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], _j(r[8]!), _j(r[9]!), _j(r[10]!)]);
    for (final tag in r[10]! as List<String>) {
      t.execute([r[0], tag]);
    }
  }
  i.close();
  t.close();

  // Verbs: id, class, stem, irregular, auxiliary
  final verbs = [
    ['it:essere', 'ere', null, 1, 'essere'],
    ['it:avere', 'ere', null, 1, 'avere'],
    ['it:parlare', 'are', 'parl', 0, 'avere'],
    ['it:lavorare', 'are', 'lavor', 0, 'avere'],
    ['it:mangiare', 'are', 'mang', 0, 'avere'],
    ['it:abitare', 'are', 'abit', 0, 'avere'],
    ['it:bere', 'ere', 'bev', 1, 'avere'],
    ['it:camminare', 'are', 'cammin', 0, 'avere'],
  ];
  final v = db.prepare('INSERT INTO verbs VALUES (?,?,?,?,?)');
  for (final r in verbs) {
    v.execute(r);
  }
  v.close();

  final f = db.prepare('INSERT INTO verb_forms VALUES (?,?,?,?,?,?,?)');
  void form(String id, String tense, String person, String form,
      {String? stem, String? ending, List<String> alts = const []}) {
    f.execute([id, tense, person, form, stem, ending, _j(alts)]);
  }

  void table(String id, String tense, List<String> forms, {String? stem, List<String>? endings}) {
    for (var k = 0; k < fixturePersons.length; k++) {
      form(id, tense, fixturePersons[k], forms[k], stem: stem, ending: endings?[k]);
    }
  }

  const areEndings = ['o', 'i', 'a', 'iamo', 'ate', 'ano'];
  for (final (id, stem) in [
    ('it:parlare', 'parl'),
    ('it:lavorare', 'lavor'),
    ('it:abitare', 'abit'),
    ('it:camminare', 'cammin'),
  ]) {
    table(id, 'presente', [for (final e in areEndings) '$stem$e'], stem: stem, endings: areEndings);
    form(id, 'infinitive', '_', '${stem}are');
    form(id, 'participle', '_', '${stem}ato');
  }
  // mangiare: stem 'mang', the i belongs to the ending (mang|io, mang|i, ...).
  const mangEndings = ['io', 'i', 'ia', 'iamo', 'iate', 'iano'];
  table('it:mangiare', 'presente', [for (final e in mangEndings) 'mang$e'],
      stem: 'mang', endings: mangEndings);
  form('it:mangiare', 'infinitive', '_', 'mangiare');
  form('it:mangiare', 'participle', '_', 'mangiato');
  table('it:essere', 'presente', ['sono', 'sei', 'è', 'siamo', 'siete', 'sono']);
  // An accepted alternative spelling.
  db.execute("UPDATE verb_forms SET alts = ? WHERE item_id = 'it:essere' AND tense = 'presente' AND person = 'lui/lei'",
      [_j(["e'"])]);
  form('it:essere', 'infinitive', '_', 'essere');
  form('it:essere', 'participle', '_', 'stato');
  table('it:avere', 'presente', ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno']);
  form('it:avere', 'infinitive', '_', 'avere');
  form('it:avere', 'participle', '_', 'avuto');
  const bevEndings = ['o', 'i', 'e', 'iamo', 'ete', 'ono'];
  table('it:bere', 'presente', [for (final e in bevEndings) 'bev$e'], stem: 'bev', endings: bevEndings);
  form('it:bere', 'infinitive', '_', 'bere');
  form('it:bere', 'participle', '_', 'bevuto');
  // Passato prossimo (multi-word forms, no stem/ending split).
  for (final (id, part) in [('it:parlare', 'parlato'), ('it:mangiare', 'mangiato')]) {
    table(id, 'passato_prossimo', [
      for (final aux in ['ho', 'hai', 'ha', 'abbiamo', 'avete', 'hanno']) '$aux $part',
    ]);
  }
  f.close();

  // Skill membership + facets, the way the pipeline resolves them.
  final skillItems = <String, List<String>>{
    'greetings': ['it:grazie', 'it:ciao', 'it:buongiorno', 'it:prego', 'it:arrivederci'],
    'essere-avere': ['it:essere', 'it:avere'],
    'food': ['it:mangiare', 'it:acqua', 'it:pane', 'it:vino', 'it:bere', 'it:mela', 'it:formaggio'],
    'present-are': ['it:parlare', 'it:lavorare', 'it:mangiare', 'it:abitare'],
    'articles': ['it:acqua', 'it:pane', 'it:vino', 'it:mela', 'it:formaggio'],
  };
  final si = db.prepare('INSERT INTO skill_items VALUES (?,?,?)');
  final sf = db.prepare('INSERT INTO skill_facets VALUES (?,?,?,?,?,?)');
  skillItems.forEach((skill, ids) {
    for (var k = 0; k < ids.length; k++) {
      si.execute([skill, ids[k], k]);
      switch (skill) {
        case 'greetings' || 'food':
          sf.execute([skill, '${ids[k]}#rec', ids[k], 'rec', null, k]);
          sf.execute([skill, '${ids[k]}#prod', ids[k], 'prod', null, k]);
        case 'essere-avere' || 'present-are':
          sf.execute([skill, '${ids[k]}#form:presente', ids[k], 'form', 'presente', k]);
        case 'articles':
          sf.execute([skill, '${ids[k]}#article', ids[k], 'article', null, k]);
      }
    }
  });
  si.close();
  sf.close();

  // Sentences: id, text, tr, unit, tokens [(t, lex, form)].
  final sentences = <(String, String, Map<String, String>, String?, List<(String, String?, String?)>)>[
    ('s:1001', 'Ciao, come stai?', {'en': 'Hi, how are you?', 'nl': 'Hoi, hoe gaat het?'}, 'u1',
        [('Ciao', 'it:ciao', null), (',', null, null), ('come', null, null), ('stai', null, null), ('?', null, null)]),
    ('s:1002', 'Grazie mille!', {'en': 'Thanks a lot!', 'nl': 'Heel erg bedankt!'}, 'u1',
        [('Grazie', 'it:grazie', null), ('mille', null, null), ('!', null, null)]),
    ('s:1003', 'Lei è molto gentile.', {'en': 'She is very kind.', 'nl': 'Zij is heel aardig.'}, 'u1',
        [('Lei', null, null), ('è', 'it:essere', 'presente.lui/lei'), ('molto', null, null), ('gentile', null, null), ('.', null, null)]),
    ('s:1004', 'Abbiamo un gatto.', {'en': 'We have a cat.', 'nl': 'We hebben een kat.'}, 'u2',
        [('Abbiamo', 'it:avere', 'presente.noi'), ('un', null, null), ('gatto', 'it:gatto', null), ('.', null, null)]),
    ('s:1005', 'Mangiamo alle otto.', {'en': 'We eat at eight.', 'nl': 'We eten om acht uur.'}, 'u2',
        [('Mangiamo', 'it:mangiare', 'presente.noi'), ('alle', null, null), ('otto', null, null), ('.', null, null)]),
    ('s:1006', 'Io parlo italiano.', {'en': 'I speak Italian.', 'nl': 'Ik spreek Italiaans.'}, 'u2',
        [('Io', null, null), ('parlo', 'it:parlare', 'presente.io'), ('italiano', 'it:italiano', null), ('.', null, null)]),
    ('s:1007', 'Il pane è buono.', {'en': 'The bread is good.', 'nl': 'Het brood is lekker.'}, 'u2',
        [('Il', null, null), ('pane', 'it:pane', null), ('è', 'it:essere', 'presente.lui/lei'), ('buono', null, null), ('.', null, null)]),
    ('s:1008', 'Loro lavorano a Roma.', {'en': 'They work in Rome.', 'nl': 'Zij werken in Rome.'}, 'u2',
        [('Loro', null, null), ('lavorano', 'it:lavorare', 'presente.loro'), ('a', null, null), ('Roma', null, null), ('.', null, null)]),
    ('s:1009', 'Tu bevi acqua o vino?', {'en': 'Do you drink water or wine?', 'nl': 'Drink jij water of wijn?'}, 'u2',
        [('Tu', null, null), ('bevi', 'it:bere', 'presente.tu'), ('acqua', 'it:acqua', null), ('o', null, null), ('vino', 'it:vino', null), ('?', null, null)]),
    ('s:1010', 'Ho mangiato una mela.', {'en': 'I ate an apple.', 'nl': 'Ik heb een appel gegeten.'}, 'u2',
        [('Ho', 'it:avere', 'presente.io'), ('mangiato', 'it:mangiare', 'participle._'), ('una', null, null), ('mela', 'it:mela', null), ('.', null, null)]),
    ('s:1011', 'Voi abitate qui?', {'en': 'Do you live here?', 'nl': 'Wonen jullie hier?'}, 'u2',
        [('Voi', null, null), ('abitate', 'it:abitare', 'presente.voi'), ('qui', null, null), ('?', null, null)]),
  ];
  final sn = db.prepare('INSERT INTO sentences VALUES (?,?,?,?,?)');
  final tk = db.prepare('INSERT INTO tokens VALUES (?,?,?,?,?,?,?)');
  final wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  for (final (id, text, tr, unit, toks) in sentences) {
    sn.execute([id, text, _j(tr), 'tatoeba:${id.substring(2)}', unit]);
    var pos = 0;
    for (var k = 0; k < toks.length; k++) {
      final (tok, lex, frm) = toks[k];
      final at = text.indexOf(tok, pos);
      if (at < 0) throw StateError('token "$tok" not in "$text"');
      final pre = text.substring(pos, at);
      pos = at + tok.length;
      tk.execute([id, k, tok, pre, wordChar.hasMatch(tok) ? 1 : 0, lex, frm]);
    }
    if (pos != text.length) throw StateError('tokens do not cover "$text"');
  }
  sn.close();
  tk.close();
}

/// Every facet id of the fixture (handy for progress tests).
List<String> fixtureFacetIds(CourseData course) => <String>{
      for (final s in course.skills)
        for (final f in course.skillFacets(s.id)) f.facetId,
    }.toList();
