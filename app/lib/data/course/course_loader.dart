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
  guardCourseDb(db);
  final raw = readRawMeta(db);
  final meta = parseCourseMeta(raw);

  // Optional tables (additive in schema 1; packs built before them have none).
  final tables = {
    for (final r in db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('sentence_features', 'skill_features', 'inflections', 'stories', 'story_sentences', "
      "'story_questions', 'topics', 'topic_units')",
    ).rows)
      r[0] as String,
  };

  // Topic trees (schema minor 3): which units belong to which topic.
  final hasTopics = tables.containsAll(const ['topics', 'topic_units']);
  final topics = hasTopics
      ? [
          for (final r in db.select(
            'SELECT id, ord, title, short_title, description, icon, anchor FROM topics ORDER BY ord',
          ).rows)
            Topic(
              id: r[0] as String,
              ord: r[1] as int,
              title: _i18n(r[2]),
              shortTitle: _i18n(r[3]),
              description: _i18n(r[4]),
              icon: r[5] as String?,
              anchor: r[6] as String,
            ),
        ]
      : const <Topic>[];
  final topicIds = {for (final t in topics) t.id};
  final unitTopic = <String, String>{
    if (hasTopics)
      for (final r in db.select('SELECT unit_id, topic_id FROM topic_units').rows)
        if (topicIds.contains(r[1])) r[0] as String: r[1] as String,
  };

  final units = [
    for (final r in db.select('SELECT id, ord, title FROM units ORDER BY ord').rows)
      Unit(id: r[0] as String, ord: r[1] as int, title: _i18n(r[2]), topic: unitTopic[r[0] as String]),
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

  // Facet kinds this app doesn't know (a pack of a newer schema minor) are skipped.
  final skillFacets = [
    for (final r in db.select(
      'SELECT skill_id, facet_id, item_id, kind, tense, ord FROM skill_facets ORDER BY skill_id, ord, facet_id',
    ).rows)
      if (FacetKind.tryParse(r[3] as String) case final kind?)
        SkillFacet(
          skillId: r[0] as String,
          facetId: r[1] as String,
          itemId: r[2] as String,
          kind: kind,
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

  // Grammar gating tables.
  final sentenceFeatures = <String, Set<String>>{};
  if (tables.contains('sentence_features')) {
    for (final r in db.select('SELECT sentence_id, feature FROM sentence_features').rows) {
      (sentenceFeatures[r[0] as String] ??= <String>{}).add(r[1] as String);
    }
  }
  final skillFeatures = <String, Set<String>>{};
  if (tables.contains('skill_features')) {
    for (final r in db.select('SELECT skill_id, feature FROM skill_features').rows) {
      (skillFeatures[r[0] as String] ??= <String>{}).add(r[1] as String);
    }
  }

  // Inflection tables (schema minor 1).
  final inflections = <InflectionForm>[
    if (tables.contains('inflections'))
      for (final r in db.select('SELECT item_id, tbl, cell, form, stem, ending, alts, wrong FROM inflections').rows)
        InflectionForm(
          itemId: r[0] as String,
          table: r[1] as String,
          cell: r[2] as String,
          form: r[3] as String,
          stem: r[4] as String?,
          ending: r[5] as String?,
          alts: _stringList(r[6]),
          wrong: _stringList(r[7]),
        ),
  ];
  // Graded stories (additive in schema 1; packs built before them have no tables).
  // Their sentences live in `sentences` but stay out of the exercise pool.
  final hasStories = tables.containsAll(const ['stories', 'story_sentences', 'story_questions']);
  final stories = hasStories ? _loadStories(db, {for (final s in sentences) s.id: s}) : const <Story>[];
  final storySentenceIds = {for (final st in stories) for (final s in st.sentences) s.id};

  final data = InMemoryCourseData(
    meta: meta,
    units: units,
    skills: skills,
    items: items,
    skillItemIds: skillItemIds,
    skillFacets: skillFacets,
    verbs: verbs,
    verbForms: verbForms,
    sentences: storySentenceIds.isEmpty
        ? sentences
        : [for (final s in sentences) if (!storySentenceIds.contains(s.id)) s],
    stories: stories,
    notes: notes,
    sentenceFeatures: sentenceFeatures,
    skillFeatures: skillFeatures,
    inflections: inflections,
    topics: topics,
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
      sentences: sentences.length - storySentenceIds.length,
      tokens: tokenCount,
      skillFacets: skillFacets.length,
      notes: noteCount,
    ),
  );
}

/// Hardens [db] (a pack that may come from anyone) before anything is read:
/// `trusted_schema` off (schema-defined code can't call functions with side
/// effects), and only plain tables and indexes are accepted, so no view
/// (e.g. a never-ending recursive query posing as `skills`), trigger or
/// virtual table can run when the app reads its tables. With [checkIntegrity]
/// (packs added from a file or downloaded, not the bundled ones), also
/// `PRAGMA quick_check`. Throws [CourseFormatException].
void guardCourseDb(CommonDatabase db, {bool checkIntegrity = false}) {
  try {
    db.execute('PRAGMA trusted_schema = OFF');
    for (final r in db.select('SELECT type, name, sql FROM sqlite_master').rows) {
      final type = r[0] as String?;
      final sql = (r[2] as String?)?.trimLeft().toUpperCase() ?? '';
      final ok = type == 'index' || (type == 'table' && !sql.startsWith('CREATE VIRTUAL'));
      if (!ok) throw CourseFormatException('Not a course pack: it contains a $type (${jsonEncode(r[1])})');
    }
    if (checkIntegrity) {
      final rows = db.select('PRAGMA quick_check').rows;
      if (rows.length != 1 || rows.single.first != 'ok') {
        throw CourseFormatException('The course file is damaged (${rows.take(3).map((r) => r.first).join('; ')})');
      }
    }
  } on SqliteException catch (e) {
    throw CourseFormatException('Not a course database: ${e.message}');
  }
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
CourseMeta readCourseMeta(CommonDatabase db, {bool checkIntegrity = false}) {
  guardCourseDb(db, checkIntegrity: checkIntegrity);
  return parseCourseMeta(readRawMeta(db));
}

/// Validates the meta rows and builds a [CourseMeta]. Throws [CourseFormatException].
CourseMeta parseCourseMeta(Map<String, String> raw) {
  final missing = [for (final k in kRequiredCourseMetaKeys) if (!raw.containsKey(k)) k];
  if (missing.isNotEmpty) {
    throw CourseFormatException('Missing meta keys: ${missing.join(', ')}');
  }
  // The id names the pack's file (`courses/{id}.sqlite`): never a path.
  if (!isValidCourseId(raw['course_id']!)) {
    throw CourseFormatException('Bad course_id: ${jsonEncode(raw['course_id'])}');
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
      tts: raw['tts'] != '0' && raw['tts'] != 'false',
      attribution: raw['attribution'] ?? '',
      schemaVersion: major,
      baseFeatures: _stringList(raw['base_features']),
      timeAdverbs: _glosses(raw['time_adverbs']),
      description: _i18n(raw['description']),
      inflectionTables: _inflectionTables(raw['inflection_tables']),
      schemaMinor: int.tryParse(raw['schema_minor'] ?? '') ?? 0,
      tensePersons: _glosses(raw['tense_persons']),
      tensePersonLabels: _tensePersonLabels(raw['tense_person_labels']),
      tenseGroups: _stringMap(raw['tense_groups']),
      recognitionSkills: _recognitionSkills(raw['recognition_skills']),
    );
  } on FormatException catch (e) {
    throw CourseFormatException('Malformed meta JSON: ${e.message}');
  } on TypeError catch (e) {
    throw CourseFormatException('Malformed meta JSON: $e');
  }
}

/// Stories with their sentences (from [sentencesById]) and questions.
List<Story> _loadStories(CommonDatabase db, Map<String, Sentence> sentencesById) {
  final sentenceIds = <String, List<String>>{};
  for (final r in db.select('SELECT story_id, sentence_id FROM story_sentences ORDER BY story_id, idx').rows) {
    (sentenceIds[r[0] as String] ??= []).add(r[1] as String);
  }
  final questions = <String, List<StoryQuestion>>{};
  for (final r in db.select(
    'SELECT story_id, prompt, prompt_tr, options, correct, explanation_tr FROM story_questions ORDER BY story_id, idx',
  ).rows) {
    final raw = _json(r[3]);
    final options = [
      if (raw is List)
        for (final o in raw)
          if (o is Map) StoryOption.translated({for (final e in o.entries) '${e.key}': '${e.value}'})
          else StoryOption.target('$o'),
    ];
    final correct = r[4] as int;
    if (correct < 0 || correct >= options.length) continue; // malformed: skip the question
    (questions[r[0] as String] ??= []).add(StoryQuestion(
      prompt: r[1] as String?,
      promptTr: _i18n(r[2]),
      options: options,
      correct: correct,
      explanationTr: _i18n(r[5]),
    ));
  }
  return [
    for (final r in db.select('SELECT id, unit_id, ord, title, title_tr, src, new_words FROM stories').rows)
      Story(
        id: r[0] as String,
        unitId: r[1] as String,
        ord: r[2] as int,
        title: r[3] as String,
        titleTr: _i18n(r[4]),
        src: r[5] as String?,
        newWords: _stringList(r[6]),
        sentences: [
          for (final id in sentenceIds[r[0] as String] ?? const <String>[])
            ?sentencesById[id],
        ],
        questions: questions[r[0] as String] ?? const [],
      ),
  ];
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

/// `{tense: {person: i18n}}` (meta.tense_person_labels).
Map<String, Map<String, I18n>> _tensePersonLabels(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  return {
    for (final e in d.entries)
      if (e.value is Map) '${e.key}': _i18nMap(jsonEncode(e.value)),
  };
}

/// `{key: value}` of strings (meta.tense_groups).
Map<String, String> _stringMap(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  return {for (final e in d.entries) '${e.key}': '${e.value}'};
}

/// `{skill: {equivalent_tense?}}` (meta.recognition_skills) -> skill -> equivalent tense or null.
Map<String, String?> _recognitionSkills(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  return {
    for (final e in d.entries)
      '${e.key}': e.value is Map && (e.value as Map)['equivalent_tense'] != null
          ? '${(e.value as Map)['equivalent_tense']}'
          : null,
  };
}

Map<String, InflectionTable> _inflectionTables(Object? v) {
  if (v == null || v == '{}' || v == '') return const {};
  final d = _json(v);
  if (d is! Map) return const {};
  final out = <String, InflectionTable>{};
  for (final e in d.entries) {
    final t = e.value;
    if (t is! Map) continue;
    final labels = t['labels'];
    out['${e.key}'] = InflectionTable(
      name: '${e.key}',
      cells: [for (final c in (t['cells'] as List? ?? const [])) '$c'],
      pos: [for (final c in (t['pos'] as List? ?? const [])) '$c'],
      base: t['base'] as String?,
      agreement: t['agreement'] == true,
      title: t['title'] is Map ? {for (final x in (t['title'] as Map).entries) '${x.key}': '${x.value}'} : const {},
      labels: labels is Map
          ? {
              for (final x in labels.entries)
                if (x.value is Map) '${x.key}': {for (final y in (x.value as Map).entries) '${y.key}': '${y.value}'},
            }
          : const {},
    );
  }
  return out;
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
