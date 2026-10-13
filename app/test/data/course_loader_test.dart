import 'dart:io';

import 'package:tosk/core/core.dart';
import 'package:tosk/data/course/course_bytes.dart';
import 'package:tosk/data/course/course_file.dart';
import 'package:tosk/data/course/course_loader.dart';
import 'package:tosk/data/course/course_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fixtures/course_fixture.dart';

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('tosk_loader_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('fixture course via loadCourseFromSqlite', () {
    final repo = fixtureCourseRepo();
    final c = repo.data;

    test('meta is parsed from JSON', () {
      expect(c.meta.id, 'it');
      expect(c.meta.version, '0.1.0');
      expect(c.meta.title, {'en': 'Italian', 'nl': 'Italiaans'});
      expect(c.meta.persons, fixturePersons);
      expect(c.meta.tenses, ['presente', 'passato_prossimo']);
      expect(c.meta.tenseLabel('presente', 'nl'), 'tegenwoordige tijd');
      expect(c.meta.personLabel('lui/lei', 'en'), 'he/she');
      expect(c.meta.articles, contains("l'"));
      expect(c.meta.unverified, isFalse);
      expect(c.meta.schemaVersion, kCourseDbSchemaVersion);
      expect(repo.builtAt, '2026-10-13T00:00:00Z');
    });

    test('units and skills are ordered, with requires', () {
      expect(c.units.map((u) => u.id), ['u1', 'u2']);
      expect(c.skills.map((s) => s.id),
          ['greetings', 'essere-avere', 'food', 'present-are', 'articles']);
      final pa = c.skill('present-are')!;
      expect(pa.kind, SkillKind.grammar);
      expect(pa.tense, 'presente');
      expect(pa.requires.toSet(), {'essere-avere', 'food'});
      expect(pa.exercises, contains('conj_grid'));
      expect(c.skill('food')!.posX, 0);
      expect(c.skill('food')!.posY, 2);
      expect(c.skill('greetings')!.exercises, isEmpty);
      expect(repo.skillsInUnit('u2').map((s) => s.id), ['food', 'present-are', 'articles']);
    });

    test('items with glosses, variants, tags', () {
      expect(repo.itemCount, 21);
      final pane = c.item('it:pane')!;
      expect(pane.article, 'il');
      expect(pane.gender, 'm');
      expect(pane.plural, 'pani');
      expect(pane.tags, ['food']);
      expect(c.item('it:grazie')!.glosses('nl'), ['dank je', 'bedankt']);
      expect(c.item('it:buongiorno')!.spellings, ['buongiorno', 'buon giorno']);
      expect(c.item('it:casa')!.unitId, isNull);
      expect(c.itemsByTag('food').length, 7);
    });

    test('skill items and facets in introduction order', () {
      expect(c.skillItems('food').map((i) => i.id).first, 'it:mangiare');
      expect(repo.skillItemCount('greetings'), 5);
      expect(repo.skillFacetCount('greetings'), 10);
      final f = c.skillFacets('present-are');
      expect(f.map((x) => x.facetId), [
        'it:parlare#form:presente',
        'it:lavorare#form:presente',
        'it:mangiare#form:presente',
        'it:abitare#form:presente',
      ]);
      expect(f.first.kind, FacetKind.form);
      expect(f.first.tense, 'presente');
      expect(c.skillFacets('articles').first.kind, FacetKind.article);
      expect(c.skillsForFacet('it:mangiare#rec'), ['food']);
      expect(repo.allFacetIds.length, 10 + 2 + 14 + 4 + 5);
    });

    test('verbs and full presente tables', () {
      expect(repo.verbCount, 8);
      expect(c.verb('it:bere')!.irregular, isTrue);
      expect(c.verb('it:mangiare')!.stem, 'mang');
      final pres = c.verbFormsInTense('it:mangiare', 'presente');
      expect(pres.map((f) => f.form),
          ['mangio', 'mangi', 'mangia', 'mangiamo', 'mangiate', 'mangiano']);
      for (final f in pres) {
        expect('${f.stem}${f.ending}', f.form);
      }
      final essere = c.verbForms('it:essere');
      expect(essere['presente.lui/lei']!.accepted, ['è', "e'"]);
      expect(essere['participle._']!.form, 'stato');
      expect(c.verbFormsInTense('it:parlare', 'passato_prossimo').last.form, 'hanno parlato');
      for (final v in ['it:essere', 'it:avere', 'it:parlare', 'it:lavorare', 'it:mangiare', 'it:abitare', 'it:bere']) {
        expect(c.verbFormsInTense(v, 'presente').length, 6, reason: v);
      }
    });

    test('sentences with aligned tokens', () {
      expect(repo.sentenceCount, 11);
      final s = c.sentence('s:1005')!;
      expect(s.render(), s.text);
      expect(s.tokens.first.form, 'presente.noi');
      expect(s.tokens.first.person, 'noi');
      expect(s.tokens.last.isWord, isFalse);
      expect(s.translation('nl'), 'We eten om acht uur.');
      expect(s.src, 'tatoeba:1005');
      expect(c.sentencesFor('it:essere').map((s) => s.id).toSet(), {'s:1003', 's:1007'});
      expect(c.sentencesFor('it:avere', form: 'presente.noi').map((s) => s.id), ['s:1004']);
      expect(c.sentencesFor('it:mangiare', tense: 'participle').map((s) => s.id), ['s:1010']);
      for (final id in ['s:1001', 's:1002', 's:1003', 's:1004', 's:1005', 's:1006', 's:1007', 's:1008', 's:1009', 's:1010', 's:1011']) {
        expect(c.sentence(id)!.render(), c.sentence(id)!.text);
      }
    });

    test('notes fall back en then any', () {
      expect(c.note('present-are', 'nl'), startsWith('# Presente'));
      expect(c.note('essere-avere', 'nl'), startsWith('# Essere and avere'));
      expect(c.note('greetings', 'en'), startsWith('# Begroetingen'));
      expect(c.note('food', 'en'), isNull);
    });

    test('loads fast', () {
      expect(repo.loadTime, isNotNull);
      expect(repo.loadTime!.inMilliseconds, lessThan(500));
    });
  });

  test('loadCourseFile opens a file read-only', () {
    final path = writeFixtureCourseFile('${tmp.path}/it.sqlite');
    final course = loadCourseFile(path);
    expect(course.skills.length, 5);
    expect(readCourseMetaFile(path).id, 'it');
    final db = openCourseFile(path);
    addTearDown(db.close);
    expect(() => db.execute("INSERT INTO units VALUES ('u9', 9, '{}')"),
        throwsA(isA<SqliteException>()));
  });

  test('bytes path (in-memory VFS, as on the web) loads the same course', () {
    final bytes = fixtureCourseBytes();
    final repo = loadCourseRepoFromBytes(sqlite3, bytes);
    expect(repo.itemCount, 21);
    expect(repo.skills.map((s) => s.id), fixtureCourse().skills.map((s) => s.id));
    expect(readCourseMetaFromBytes(sqlite3, bytes).version, '0.1.0');
    // Repeatable: the VFS is unregistered after each use.
    expect(loadCourseRepoFromBytes(sqlite3, bytes).sentenceCount, 11);
  });

  test('refuses unknown major schema version, accepts a minor bump', () {
    final v2 = openFixtureCourseDb(overrideMeta: {'schema_version': '2'});
    addTearDown(v2.close);
    expect(() => loadCourseFromSqlite(v2), throwsA(isA<CourseFormatException>()));
    final v11 = openFixtureCourseDb(overrideMeta: {'schema_version': '1.1'});
    addTearDown(v11.close);
    expect(loadCourseFromSqlite(v11).meta.id, 'it');
  });

  test('refuses databases that are not course packs', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(() => loadCourseFromSqlite(db), throwsA(isA<CourseFormatException>()));
    db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    db.execute("INSERT INTO meta VALUES ('schema_version', '1')");
    expect(() => readCourseMeta(db), throwsA(isA<CourseFormatException>()));
    expect(() => loadCourseFile('${tmp.path}/missing.sqlite'), throwsA(isA<CourseFormatException>()));
  });
}
