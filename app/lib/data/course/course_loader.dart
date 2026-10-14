/// Loads a compiled course database (see `schema/course_db.sql`) fully into memory.
///
/// Pure Dart and platform independent: it only uses `package:sqlite3/common.dart`,
/// so the same code reads a native file (`course_file.dart`), bytes in an
/// in-memory VFS on the web or in tests (`course_bytes.dart`), and runs under
/// `dart run` for CLI tools.
///
/// One `SELECT` per table, rows read by column index, JSON decoded once per row.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../core/core.dart';
import 'course_repo.dart';
import 'course_schema.dart';

/// Loads the whole course from an open database. The caller owns [db] (and closes it).
InMemoryCourseData loadCourseFromSqlite(CommonDatabase db) => loadCourseRepoFromSqlite(db).data;

/// Like [loadCourseFromSqlite], but returns a [CourseRepo] with raw meta and counts.
CourseRepo loadCourseRepoFromSqlite(CommonDatabase db) {
  final sw = Stopwatch()..start();
  final raw = readRawMeta(db);
  final meta = parseCourseMeta(raw);

  final units = [
    for (final r in db.select('SELECT id, ord, title FROM units ORDER BY ord').rows)
      Unit(id: r[0] as String, ord: r[1] as int, title: _i18n(r[2])),
  ];

  final requires = <String, List<String>>{};
  for (final r in db.select('SELECT skill_id, requires_id FROM skill_requires').rows) {
    (requires[r[0] as String] ??= []).add(r[1] as String);
  }

  final skills = [
    for (final r in db.select(
      'SELECT id, unit_id, ord, kind, title, icon, tense, exercises, pos_x, pos_y FROM skills',
    ).rows)
      Skill(
        id: r[0] as String,
        unitId: r[1] as String,
        ord: r[2] as int,
        kind: SkillKind.values.byName(r[3] as String),
        title: _i18n(r[4]),
        icon: r[5] as String?,
        tense: r[6] as String?,
        exercises: _stringList(r[7]),
        posX: r[8] as int?,
        posY: r[9] as int?,
        requires: requires[r[0] as String] ?? const [],
      ),
  ];

  final items = [
    for (final r in db.select(
      'SELECT id, pos, lemma, article, gender, plural, freq, unit_id, tr, variants, tags FROM items',
    ).rows)
      Item(
        id: r[0] as String,
        pos: r[1] as String,
        lemma: r[2] as String,
        article: r[3] as String?,
        gender: r[4] as String?,
        plural: r[5] as String?,
        freq: r[6] as int?,
        unitId: r[7] as String?,
        tr: _glosses(r[8]),
        variants: _stringList(r[9]),
        tags: _stringList(r[10]),
      ),
  ];

  final skillItemIds = <String, List<String>>{};
  for (final r in db.select('SELECT skill_id, item_id FROM skill_items ORDER BY skill_id, ord').rows) {
    (skillItemIds[r[0] as String] ??= []).add(r[1] as String);
  }

  final skillFacets = [
    for (final r in db.select(
      'SELECT skill_id, facet_id, item_id, kind, tense, ord FROM skill_facets ORDER BY skill_id, ord, facet_id',
    ).rows)
      SkillFacet(
        skillId: r[0] as String,
        facetId: r[1] as String,
        itemId: r[2] as String,
        kind: FacetKind.parse(r[3] as String),
        tense: r[4] as String?,
        ord: r[5] as int,
      ),
  ];

  final verbs = [
    for (final r in db.select('SELECT item_id, class, stem, irregular, auxiliary FROM verbs').rows)
      Verb(
        itemId: r[0] as String,
        verbClass: r[1] as String?,
        stem: r[2] as String?,
        irregular: (r[3] as int? ?? 0) != 0,
        auxiliary: r[4] as String?,
      ),
  ];

  final verbForms = [
    for (final r in db.select(
      'SELECT item_id, tense, person, form, stem, ending, alts FROM verb_forms',
    ).rows)
      VerbForm(
        itemId: r[0] as String,
        tense: r[1] as String,
        person: r[2] as String,
        form: r[3] as String,
        stem: r[4] as String?,
        ending: r[5] as String?,
        alts: _stringList(r[6]),
      ),
  ];

  final tokensBySentence = <String, List<Token>>{};
  var tokenCount = 0;
  for (final r in db.select(
    'SELECT sentence_id, idx, t, pre, is_word, lex, form FROM tokens ORDER BY sentence_id, idx',
  ).rows) {
    tokenCount++;
    (tokensBySentence[r[0] as String] ??= []).add(Token(
      idx: r[1] as int,
      t: r[2] as String,
      pre: r[3] as String? ?? '',
      isWord: (r[4] as int? ?? 1) != 0,
      lex: r[5] as String?,
      form: r[6] as String?,
    ));
  }

  final sentences = [
    for (final r in db.select('SELECT id, text, tr, src, unit_id FROM sentences').rows)
      Sentence(
        id: r[0] as String,
        text: r[1] as String,
        tr: _i18n(r[2]),
        tokens: tokensBySentence[r[0] as String] ?? const [],
        src: r[3] as String?,
        unitId: r[4] as String?,
      ),
  ];

  final notes = <String, Map<String, String>>{};
  var noteCount = 0;
  for (final r in db.select('SELECT skill_id, lang, md FROM notes').rows) {
    noteCount++;
    (notes[r[0] as String] ??= {})[r[1] as String] = r[2] as String;
  }

  final data = InMemoryCourseData(
    meta: meta,
    units: units,
    skills: skills,
    items: items,
    skillItemIds: skillItemIds,
    skillFacets: skillFacets,
    verbs: verbs,
    verbForms: verbForms,
    sentences: sentences,
    notes: notes,
  );
  sw.stop();
  return CourseRepo(
    data,
    rawMeta: raw,
    loadTime: sw.elapsed,
    counts: CourseCounts(
      items: items.length,
      verbs: verbs.length,
      verbForms: verbForms.length,
      sentences: sentences.length,
      tokens: tokenCount,
      skillFacets: skillFacets.length,
      notes: noteCount,
    ),
  );
}

/// All `meta` rows. Throws [CourseFormatException] if the table is missing.
Map<String, String> readRawMeta(CommonDatabase db) {
  try {
    return {
      for (final r in db.select('SELECT key, value FROM meta').rows) r[0] as String: '${r[1]}',
    };
  } on SqliteException catch (e) {
    throw CourseFormatException('Not a course database (no meta table): ${e.message}');
  }
}

/// Reads and validates just the meta (cheap; used to list packs without loading them).
CourseMeta readCourseMeta(CommonDatabase db) => parseCourseMeta(readRawMeta(db));

/// Validates the meta rows and builds a [CourseMeta]. Throws [CourseFormatException].
CourseMeta parseCourseMeta(Map<String, String> raw) {
  final missing = [for (final k in kRequiredCourseMetaKeys) if (!raw.containsKey(k)) k];
  if (missing.isNotEmpty) {
    throw CourseFormatException('Missing meta keys: ${missing.join(', ')}');
  }
  final major = parseSchemaMajor(raw['schema_version']);
  if (major == null) {
    throw CourseFormatException('Bad schema_version: ${raw['schema_version']}');
  }
  if (major != kCourseDbSchemaVersion) {
    throw CourseFormatException(
      'Unsupported course schema version ${raw['schema_version']} '
      '(this app reads version $kCourseDbSchemaVersion); update the app or the pack.',
    );
  }
  try {
    return CourseMeta(
      id: raw['course_id']!,
      version: raw['version']!,
      title: _i18n(raw['title']),
      target: raw['target']!,
      translations: _stringList(raw['translations']),
      persons: _stringList(raw['persons']),
      tenses: _stringList(raw['tenses']),
      tenseLabels: _i18nMap(raw['tense_labels']),
      personLabels: _i18nMap(raw['person_labels']),
      articles: _stringList(raw['articles']),
      unverified: raw['unverified'] == '1' || raw['unverified'] == 'true',
      attribution: raw['attribution'] ?? '',
      schemaVersion: major,
      description: _i18n(raw['description']),
    );
  } on FormatException catch (e) {
    throw CourseFormatException('Malformed meta JSON: ${e.message}');
  } on TypeError catch (e) {
    throw CourseFormatException('Malformed meta JSON: $e');
  }
}

// ------------------------------------------------------------------- JSON helpers

Object? _json(Object? v) {
  if (v == null) return null;
  final s = v as String;
  if (s.isEmpty) return null;
  return jsonDecode(s);
}

List<String> _stringList(Object? v) {
  if (v == null || v == '[]' || v == '') return const [];
  final d = _json(v);
  if (d is! List) return const [];
  return List<String>.unmodifiable(d.map((e) => '$e'));
}

Map<String, String> _i18n(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is String) return {'en': d}; // tolerate a plain string title
  if (d is! Map) return const {};
  return {for (final e in d.entries) '${e.key}': '${e.value}'};
}

Map<String, I18n> _i18nMap(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  return {
    for (final e in d.entries)
      '${e.key}': e.value is Map
          ? {for (final x in (e.value as Map).entries) '${x.key}': '${x.value}'}
          : {'en': '${e.value}'},
  };
}

Map<String, List<String>> _glosses(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  return {
    for (final e in d.entries)
      '${e.key}': e.value is List
          ? List<String>.unmodifiable((e.value as List).map((x) => '$x'))
          : ['${e.value}'],
  };
}
