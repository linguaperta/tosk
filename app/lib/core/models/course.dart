/// Course content domain model. Mirrors `schema/course_db.sql`.
/// Pure Dart: no Flutter, no drift. Shared by data, engine, progression and ui.
library;

import 'package:meta/meta.dart';

/// Text keyed by source-language code, e.g. `{'en': 'Basics', 'nl': 'Basis'}`.
typedef I18n = Map<String, String>;

/// Picks [lang], falling back to English, then to any available value, then ''.
String pickLang(I18n text, String lang) => text[lang] ?? text['en'] ?? (text.isEmpty ? '' : text.values.first);

@immutable
class CourseMeta {
  const CourseMeta({
    required this.id,
    required this.version,
    required this.title,
    required this.target,
    required this.translations,
    required this.persons,
    required this.tenses,
    this.tenseLabels = const {},
    this.personLabels = const {},
    this.articles = const [],
    this.unverified = false,
    this.attribution = '',
    this.schemaVersion = 1,
    this.baseFeatures = const [],
    this.timeAdverbs = const {},
    this.description = const {},
    this.inflectionTables = const {},
    this.schemaMinor = 0,
  });

  final String id; // 'it'
  final String version; // '1.0.0'
  final I18n title;
  final String target; // target language code
  final List<String> translations; // source languages with glosses, e.g. ['en','nl']
  final List<String> persons; // display order, e.g. ['io','tu','lui/lei','noi','voi','loro']
  final List<String> tenses;
  final Map<String, I18n> tenseLabels;
  final Map<String, I18n> personLabels;
  final List<String> articles; // options for article exercises, e.g. ['de','het']
  final bool unverified;
  final String attribution;
  final int schemaVersion;

  /// Grammar features allowed from the start (`meta.base_features`, e.g. `tense:presente`).
  /// See [CourseData.sentenceFeatures] and docs/ARCHITECTURE.md, "Grammar gating".
  final List<String> baseFeatures;

  /// Time adverbs that tie a sentence to some tenses (`meta.time_adverbs`):
  /// adverb (one or more words, e.g. `ieri`, `l'anno scorso`) -> the tenses it
  /// fits. A transform never rewrites a sentence with such an adverb into
  /// another tense (`Ieri ho mangiato` never becomes the present).
  final Map<String, List<String>> timeAdverbs;

  /// Optional one-line course description per source language (meta key `description`).
  final I18n description;

  /// Inflection tables of non-verbs (`meta.inflection_tables`, schema minor 1): noun number,
  /// adjective agreement, ... keyed by table name.
  final Map<String, InflectionTable> inflectionTables;

  /// `meta.schema_minor` (0 when absent).
  final int schemaMinor;

  String tenseLabel(String tense, String lang) =>
      tenseLabels[tense] == null ? tense.replaceAll('_', ' ') : pickLang(tenseLabels[tense]!, lang);

  String personLabel(String person, String lang) =>
      personLabels[person] == null ? person : pickLang(personLabels[person]!, lang);
}

/// A non-verb inflection table of a course (`meta.inflection_tables`).
@immutable
class InflectionTable {
  const InflectionTable({
    required this.name,
    required this.cells,
    this.pos = const [],
    this.base,
    this.agreement = false,
    this.title = const {},
    this.labels = const {},
  });

  final String name; // 'number'
  final List<String> cells; // display order: ['sg', 'pl'], ['m.sg', 'f.sg', 'm.pl', 'f.pl']
  final List<String> pos;

  /// The cell equal to the lemma: given, never asked by the ending picker.
  final String? base;

  /// The cell is chosen by agreement (adjective with its noun): in an aligned
  /// sentence every other cell of the table is wrong. Otherwise the cells
  /// differ in meaning and sentence exercises offer only `wrong` forms.
  final bool agreement;
  final I18n title;
  final Map<String, I18n> labels;

  String titleIn(String lang) => title.isEmpty ? name.replaceAll('_', ' ') : pickLang(title, lang);

  String cellLabel(String cell, String lang) =>
      labels[cell] == null ? cell.replaceAll('.', ' ') : pickLang(labels[cell]!, lang);
}

/// Prefix of [Token.form] for inflected non-verbs: `infl:{table}.{cell}`.
const String kInflFormPrefix = 'infl:';

/// The token form key of an inflection cell: `infl:number.pl`.
String inflFormKey(String table, String cell) => '$kInflFormPrefix$table.$cell';

/// One cell of a non-verb's inflection table (row of `inflections`).
@immutable
class InflectionForm {
  const InflectionForm({
    required this.itemId,
    required this.table,
    required this.cell,
    required this.form,
    this.stem,
    this.ending,
    this.alts = const [],
    this.wrong = const [],
  });
  final String itemId;
  final String table;
  final String cell;
  final String form;
  final String? stem;
  final String? ending;
  final List<String> alts;

  /// Plausible wrong forms that are no word of the language (`katen`, `wite`):
  /// safe distractors in sentence exercises.
  final List<String> wrong;

  /// `'{table}.{cell}'`, the key in [CourseData.inflections].
  String get key => '$table.$cell';

  /// `'infl:{table}.{cell}'`, the format used in [Token.form].
  String get tokenKey => inflFormKey(table, cell);

  List<String> get accepted => [form, ...alts];

  bool get hasSplit => stem != null && ending != null;
}

@immutable
class Unit {
  const Unit({required this.id, required this.ord, required this.title});
  final String id;
  final int ord;
  final I18n title;
}

enum SkillKind { vocab, grammar }

@immutable
class Skill {
  const Skill({
    required this.id,
    required this.unitId,
    required this.ord,
    required this.kind,
    required this.title,
    this.icon,
    this.tense,
    this.exercises = const [],
    this.posX,
    this.posY,
    this.requires = const [],
  });

  final String id;
  final String unitId;
  final int ord;
  final SkillKind kind;
  final I18n title;
  final String? icon;
  final String? tense; // tense trained by a verb grammar skill
  /// Allowed exercise type ids (see [ExerciseType.id]); empty = all applicable.
  final List<String> exercises;
  final int? posX;
  final int? posY;
  final List<String> requires; // prerequisite skill ids
}

@immutable
class Item {
  const Item({
    required this.id,
    required this.pos,
    required this.lemma,
    required this.tr,
    this.article,
    this.gender,
    this.plural,
    this.freq,
    this.unitId,
    this.variants = const [],
    this.tags = const [],
  });

  final String id; // 'it:mangiare'
  final String pos; // 'noun','verb',...
  final String lemma;
  final String? article;
  final String? gender;
  final String? plural;
  final int? freq; // rank, 1 = most frequent
  final String? unitId;

  /// Glosses per source language, primary first: `{'en': ['to eat'], 'nl': ['eten']}`.
  final Map<String, List<String>> tr;
  final List<String> variants;
  final List<String> tags;

  bool get isVerb => pos == 'verb';
  bool get isNoun => pos == 'noun';

  /// All glosses for [lang], falling back to English then any language.
  List<String> glosses(String lang) => tr[lang] ?? tr['en'] ?? (tr.isEmpty ? const [] : tr.values.first);

  /// Primary gloss for [lang] or '' if none.
  String gloss(String lang) {
    final g = glosses(lang);
    return g.isEmpty ? '' : g.first;
  }

  /// The lemma plus accepted spelling variants.
  List<String> get spellings => [lemma, ...variants];
}

@immutable
class Verb {
  const Verb({required this.itemId, this.verbClass, this.stem, this.irregular = false, this.auxiliary});
  final String itemId;
  final String? verbClass;
  final String? stem;
  final bool irregular;
  final String? auxiliary;
}

/// Person key for non-finite forms (infinitive, participle, gerund).
const String kNoPerson = '_';

@immutable
class VerbForm {
  const VerbForm({
    required this.itemId,
    required this.tense,
    required this.person,
    required this.form,
    this.stem,
    this.ending,
    this.alts = const [],
  });
  final String itemId;
  final String tense;
  final String person;
  final String form;
  final String? stem;
  final String? ending;
  final List<String> alts;

  /// `'{tense}.{person}'`, the format used in [Token.form].
  String get key => '$tense.$person';

  /// The canonical form plus accepted alternatives.
  List<String> get accepted => [form, ...alts];

  bool get hasSplit => stem != null && ending != null;
}

@immutable
class Token {
  const Token({required this.idx, required this.t, this.pre = '', this.isWord = true, this.lex, this.form});
  final int idx;
  final String t;
  final String pre; // whitespace before the token
  final bool isWord;
  final String? lex; // aligned item id

  /// `'{tense}.{person}'` when the token is a verb form; `'infl:{table}.{cell}'`
  /// when it is an inflected non-verb (`infl:number.pl`, `infl:agreement.f.sg`).
  final String? form;

  /// Whether [form] is an inflection cell (`infl:...`), not a verb form.
  bool get isInflection => form?.startsWith(kInflFormPrefix) ?? false;

  /// Verb tense (null for inflection cells).
  String? get tense => form == null || isInflection ? null : form!.split('.').first;

  /// Verb person (null for inflection cells).
  String? get person {
    final f = form;
    if (f == null || isInflection) return null;
    final i = f.indexOf('.');
    return i < 0 ? null : f.substring(i + 1);
  }

  /// Inflection table of an `infl:` form (`number`).
  String? get inflTable {
    if (!isInflection) return null;
    final rest = form!.substring(kInflFormPrefix.length);
    final i = rest.indexOf('.');
    return i < 0 ? null : rest.substring(0, i);
  }

  /// Inflection cell of an `infl:` form (`pl`, `f.sg`): everything after the table's dot.
  String? get inflCell {
    if (!isInflection) return null;
    final rest = form!.substring(kInflFormPrefix.length);
    final i = rest.indexOf('.');
    return i < 0 ? null : rest.substring(i + 1);
  }

  /// The verb form key, or null for inflection cells and unaligned tokens.
  String? get verbFormKey => isInflection ? null : form;
}

@immutable
class Sentence {
  const Sentence({required this.id, required this.text, required this.tr, required this.tokens, this.src, this.unitId});
  final String id;
  final String text;
  final Map<String, String> tr; // translation per source language
  final List<Token> tokens;
  final String? src;
  final String? unitId;

  String? translation(String lang) => tr[lang] ?? tr['en'] ?? (tr.isEmpty ? null : tr.values.first);

  /// Rebuilds text from tokens (optionally replacing some by index).
  String render([Map<int, String> replace = const {}]) {
    final b = StringBuffer();
    for (final tok in tokens) {
      b.write(tok.pre);
      b.write(replace[tok.idx] ?? tok.t);
    }
    return b.toString();
  }
}
