/// A small DSL for hand-built [InMemoryCourseData] fixtures.
///
/// Facets are derived like the pipeline does (docs/ARCHITECTURE.md):
/// vocab skills get `#rec` + `#prod` per item, verb grammar skills
/// `#form:{tense}` per verb, article skills `#article` per noun.
library;

import 'package:tosk/core/core.dart';

class CourseBuilder {
  CourseBuilder(this.meta);

  final CourseMeta meta;
  final List<Unit> _units = [];
  final List<Skill> _skills = [];
  final Map<String, Item> _items = {};
  final List<Verb> _verbs = [];
  final List<VerbForm> _forms = [];
  final List<Sentence> _sentences = [];
  final Map<String, List<String>> _skillItems = {};
  final List<SkillFacet> _facets = [];
  final Map<String, Map<String, String>> _notes = {};
  final Map<String, Set<String>> _sentenceFeatures = {};
  final Map<String, Set<String>> _skillFeatures = {};
  final List<InflectionForm> _infl = [];
  String? _unit;

  /// An inflection table of a non-verb. [cells] maps cell -> entry with the
  /// verb syntax (`stem|ending`, `;` alternatives); [wrong] the cell's wrong
  /// forms.
  void inflection(String lemmaOrId, String table, Map<String, String> cells,
      {Map<String, List<String>> wrong = const {}}) {
    final itemId = id(lemmaOrId);
    _check(itemId);
    for (final e in cells.entries) {
      final variants = e.value.split(';');
      final canon = variants.first;
      final bar = canon.indexOf('|');
      _infl.add(InflectionForm(
        itemId: itemId,
        table: table,
        cell: e.key,
        form: canon.replaceAll('|', ''),
        stem: bar >= 0 ? canon.substring(0, bar) : null,
        ending: bar >= 0 ? canon.substring(bar + 1) : null,
        alts: variants.skip(1).toList(),
        wrong: wrong[e.key] ?? const [],
      ));
    }
  }

  /// A grammar skill training `#infl:{table}` of [items] (course.yaml
  /// `facet: infl`); with [withVocab] also `#rec`/`#prod` (`inflections:`
  /// added to an items skill).
  void inflSkill(String sid, int ord, String en, String nl, String table, List<String> items,
      {List<String> requires = const [], List<String> exercises = const [], bool withVocab = false}) {
    _skill(sid, ord, SkillKind.grammar, en, nl, requires: requires, exercises: exercises);
    final ids = [for (final i in items) id(i)];
    _skillItems[sid] = ids;
    for (var o = 0; o < ids.length; o++) {
      _check(ids[o]);
      if (withVocab) {
        _facets.add(SkillFacet(skillId: sid, facetId: '${ids[o]}#rec', itemId: ids[o], kind: FacetKind.rec, ord: o));
        _facets.add(SkillFacet(skillId: sid, facetId: '${ids[o]}#prod', itemId: ids[o], kind: FacetKind.prod, ord: o));
      }
      _facets.add(SkillFacet(
          skillId: sid, facetId: '${ids[o]}#infl:$table', itemId: ids[o], kind: FacetKind.infl, tense: table, ord: o));
    }
  }

  /// Grammar features of a sentence (`sentence_features`).
  void sentenceFeatures(String sentenceId, Iterable<String> features) =>
      (_sentenceFeatures[sentenceId] ??= {}).addAll(features);

  /// Features a skill introduces (`skill_features`).
  void skillFeatures(String skillId, Iterable<String> features) => (_skillFeatures[skillId] ??= {}).addAll(features);

  String get _c => meta.id;

  String id(String lemmaOrId) => lemmaOrId.contains(':') ? lemmaOrId : '$_c:$lemmaOrId';

  void unit(String id, int ord, String en, String nl, {String? topic}) {
    _units.add(Unit(id: id, ord: ord, title: {'en': en, 'nl': nl}, topic: topic));
    _unit = id;
  }

  final List<Topic> _topics = [];

  /// A built-in topic tree (schema minor 3); its units are added with
  /// `unit(..., topic: id)` after every main-tree unit.
  void topic(String id, int ord, String en, String nl, {required String anchor, String? shortEn, String? icon}) =>
      _topics.add(Topic(
        id: id,
        ord: ord,
        title: {'en': en, 'nl': nl},
        shortTitle: shortEn == null ? const {} : {'en': shortEn},
        anchor: anchor,
        icon: icon,
      ));

  Item word(
    String lemma,
    String pos, {
    List<String> en = const [],
    List<String> nl = const [],
    String? itemId,
    String? article,
    String? gender,
    String? plural,
    int? freq,
    List<String> tags = const [],
    List<String> variants = const [],
  }) {
    final item = Item(
      id: id(itemId ?? lemma),
      pos: pos,
      lemma: lemma,
      tr: {if (en.isNotEmpty) 'en': en, if (nl.isNotEmpty) 'nl': nl},
      article: article,
      gender: gender,
      plural: plural,
      freq: freq,
      unitId: _unit,
      tags: tags,
      variants: variants,
    );
    if (_items.containsKey(item.id)) throw StateError('duplicate item ${item.id}');
    _items[item.id] = item;
    return item;
  }

  /// A noun with its definite article.
  Item noun(String article, String lemma, List<String> en,
          {List<String> nl = const [],
          String? gender, String? plural, int? freq, List<String> tags = const [], List<String> variants = const []}) =>
      word(lemma, 'noun',
          en: en, nl: nl, article: article, gender: gender, plural: plural, freq: freq, tags: tags, variants: variants);

  /// A verb with full tables. [tables] maps tense -> one entry per person in
  /// [CourseMeta.persons] order. Entry syntax: `stem|ending` for a split
  /// form, `;` separates accepted alternatives (`sono partito;sono partita`).
  void verb(
    String lemma,
    List<String> en, {
    List<String> nl = const [],
    required Map<String, List<String>> tables,
    String? cls,
    String? aux,
    bool irregular = false,
    int? freq,
    List<String> tags = const [],
  }) {
    final item = word(lemma, 'verb', en: en, nl: nl, freq: freq, tags: tags);
    String? stem;
    for (final e in tables.entries) {
      if (e.value.length != meta.persons.length) {
        throw StateError('$lemma ${e.key}: ${e.value.length} forms');
      }
      for (var i = 0; i < e.value.length; i++) {
        final variants = e.value[i].split(';');
        final canon = variants.first;
        final bar = canon.indexOf('|');
        final form = canon.replaceAll('|', '');
        if (bar >= 0) stem ??= canon.substring(0, bar);
        _forms.add(VerbForm(
          itemId: item.id,
          tense: e.key,
          person: meta.persons[i],
          form: form,
          stem: bar >= 0 ? canon.substring(0, bar) : null,
          ending: bar >= 0 ? canon.substring(bar + 1) : null,
          alts: variants.skip(1).toList(),
        ));
      }
    }
    _verbs.add(Verb(itemId: item.id, verbClass: cls, stem: stem, irregular: irregular, auxiliary: aux));
  }

  /// Forms of [tense] for some persons only (an imperative without `io`).
  void partialTable(String lemma, String tense, Map<String, String> forms) {
    for (final e in forms.entries) {
      _forms.add(VerbForm(itemId: id(lemma), tense: tense, person: e.key, form: e.value));
    }
  }

  static const _leading = '¿¡"«(“‘';
  static const _trailing = '.,!?;:"»)”…';

  /// A sentence. [align] entries are `surface=lex` or `surface=lex@tense.person`,
  /// applied in order to the first unaligned word token with that surface.
  void sentence(String sid, String text,
      {required String en, String? nl, List<String> align = const [], bool splitElision = true, String src = 'fixture'}) {
    final tokens = <Token>[];
    final chunks = RegExp(r'(\s*)(\S+)').allMatches(text);
    for (final m in chunks) {
      var pre = m[1]!;
      var chunk = m[2]!;
      final lead = <String>[];
      final trail = <String>[];
      while (chunk.isNotEmpty && _leading.contains(chunk[0])) {
        lead.add(chunk[0]);
        chunk = chunk.substring(1);
      }
      while (chunk.isNotEmpty && _trailing.contains(chunk[chunk.length - 1])) {
        trail.insert(0, chunk[chunk.length - 1]);
        chunk = chunk.substring(0, chunk.length - 1);
      }
      void add(String t, bool isWord) {
        tokens.add(Token(idx: tokens.length, t: t, pre: pre, isWord: isWord));
        pre = '';
      }

      for (final l in lead) {
        add(l, false);
      }
      if (chunk.isNotEmpty) {
        final ap = RegExp("['’]").firstMatch(chunk);
        if (splitElision && ap != null && ap.start > 0 && ap.end < chunk.length) {
          add(chunk.substring(0, ap.end), true);
          add(chunk.substring(ap.end), true);
        } else {
          add(chunk, true);
        }
      }
      for (final t in trail) {
        add(t, false);
      }
    }
    final aligned = List<Token>.of(tokens);
    final done = <int>{};
    for (final a in align) {
      final eq = a.indexOf('=');
      final surface = a.substring(0, eq);
      final rest = a.substring(eq + 1);
      final at = rest.indexOf('@');
      final lex = id(at < 0 ? rest : rest.substring(0, at));
      final form = at < 0 ? null : rest.substring(at + 1);
      if (!_items.containsKey(lex)) throw StateError('$sid: unknown item $lex');
      final i = aligned.indexWhere((t) => t.isWord && t.t == surface && !done.contains(t.idx));
      if (i < 0) throw StateError('$sid: no token "$surface" in "$text"');
      final t = aligned[i];
      aligned[i] = Token(idx: t.idx, t: t.t, pre: t.pre, isWord: t.isWord, lex: lex, form: form);
      done.add(t.idx);
    }
    final rebuilt = aligned.map((t) => t.pre + t.t).join();
    if (rebuilt != text) throw StateError('$sid: tokens rebuild "$rebuilt" != "$text"');
    _sentences.add(Sentence(id: sid, text: text, tr: {'en': en, 'nl': ?nl}, tokens: aligned, src: src));
  }

  Skill _skill(String sid, int ord, SkillKind kind, String en, String nl,
      {String? tense, List<String> requires = const [], List<String> exercises = const []}) {
    final s = Skill(
      id: sid,
      unitId: _unit!,
      ord: ord,
      kind: kind,
      title: {'en': en, 'nl': nl},
      tense: tense,
      requires: requires,
      exercises: exercises,
    );
    _skills.add(s);
    return s;
  }

  void vocabSkill(String sid, int ord, String en, String nl, List<String> items,
      {List<String> requires = const [], List<String> exercises = const []}) {
    _skill(sid, ord, SkillKind.vocab, en, nl, requires: requires, exercises: exercises);
    final ids = [for (final i in items) id(i)];
    _skillItems[sid] = ids;
    for (var o = 0; o < ids.length; o++) {
      _check(ids[o]);
      _facets.add(SkillFacet(skillId: sid, facetId: '${ids[o]}#rec', itemId: ids[o], kind: FacetKind.rec, ord: o));
      _facets.add(SkillFacet(skillId: sid, facetId: '${ids[o]}#prod', itemId: ids[o], kind: FacetKind.prod, ord: o));
    }
  }

  void verbSkill(String sid, int ord, String en, String nl, String tense, List<String> verbs,
      {List<String> requires = const [], List<String> exercises = const []}) {
    _skill(sid, ord, SkillKind.grammar, en, nl, tense: tense, requires: requires, exercises: exercises);
    final ids = [for (final v in verbs) id(v)];
    _skillItems[sid] = ids;
    for (var o = 0; o < ids.length; o++) {
      _check(ids[o]);
      _facets.add(SkillFacet(
          skillId: sid, facetId: '${ids[o]}#form:$tense', itemId: ids[o], kind: FacetKind.form, tense: tense, ord: o));
    }
  }

  void articleSkill(String sid, int ord, String en, String nl, List<String> nouns,
      {List<String> requires = const [], List<String> exercises = const []}) {
    _skill(sid, ord, SkillKind.grammar, en, nl, requires: requires, exercises: exercises);
    final ids = [for (final n in nouns) id(n)];
    _skillItems[sid] = ids;
    for (var o = 0; o < ids.length; o++) {
      _check(ids[o]);
      _facets.add(SkillFacet(skillId: sid, facetId: '${ids[o]}#article', itemId: ids[o], kind: FacetKind.article, ord: o));
    }
  }

  void _check(String itemId) {
    if (!_items.containsKey(itemId)) throw StateError('unknown item $itemId');
  }

  void note(String skillId, String en, String nl) => _notes[skillId] = {'en': en, 'nl': nl};

  InMemoryCourseData build() => InMemoryCourseData(
        meta: meta,
        units: _units,
        skills: _skills,
        items: _items.values.toList(),
        skillItemIds: _skillItems,
        skillFacets: _facets,
        verbs: _verbs,
        verbForms: _forms,
        sentences: _sentences,
        notes: _notes,
        sentenceFeatures: _sentenceFeatures,
        skillFeatures: _skillFeatures,
        inflections: _infl,
        topics: _topics,
      );
}
