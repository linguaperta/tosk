/// Read access to one course, synchronous and in memory.
///
/// A course pack is a few MB, so the data layer loads it once when the course
/// opens and hands an [InMemoryCourseData] to the engine. The engine and
/// progression code stay pure, synchronous Dart, and tests build fixtures directly.
library;

import 'package:collection/collection.dart';

import '../models/course.dart';
import '../models/facet.dart';
import '../models/story.dart';

abstract interface class CourseData {
  CourseMeta get meta;
  List<Unit> get units; // ordered
  List<Skill> get skills; // ordered by unit ord, then skill ord
  Skill? skill(String id);

  Item? item(String id);
  Iterable<Item> get allItems;

  /// Items of a skill in introduction order.
  List<Item> skillItems(String skillId);

  /// Facets a skill trains, in introduction order.
  List<SkillFacet> skillFacets(String skillId);

  /// Skills that train [facetId].
  List<String> skillsForFacet(String facetId);

  List<Item> itemsByTag(String tag);

  /// Items of the same [pos] ordered by distance in frequency rank to [freq] (nearest first).
  List<Item> itemsNearFreq(String pos, int? freq, {int limit = 50});

  Verb? verb(String itemId);

  /// All forms of a verb, keyed by `'{tense}.{person}'`.
  Map<String, VerbForm> verbForms(String itemId);

  /// Forms of a verb in one tense, in [CourseMeta.persons] order (missing persons skipped).
  List<VerbForm> verbFormsInTense(String itemId, String tense);

  /// A non-verb's inflection cells, keyed by `'{table}.{cell}'` (empty for packs
  /// before schema minor 1 and for items without tables).
  Map<String, InflectionForm> inflections(String itemId);

  /// One inflection table of an item, cells in [InflectionTable.cells] order
  /// (empty when the item has no such table).
  List<InflectionForm> inflectionTable(String itemId, String table);

  /// Sentences containing a token aligned to [itemId] (optionally a given `'{tense}.{person}'` form or tense prefix).
  List<Sentence> sentencesFor(String itemId, {String? form, String? tense});

  Sentence? sentence(String id);

  /// Grammar note markdown for [skillId] in [lang], falling back to 'en' then any.
  String? note(String skillId, String lang);

  /// Grammar features a sentence uses (`tense:passato_prossimo`, `aux:essere`, ...);
  /// empty for an unknown sentence or a pack built before grammar gating.
  Set<String> sentenceFeatures(String sentenceId);

  /// Grammar features a skill introduces (its tense for a verb skill, plus declared constructs).
  Set<String> skillFeatures(String skillId);

  /// Graded mini-stories in unit order, then story order; empty for packs
  /// without stories. Their sentences are not in [sentencesFor] / [sentence].
  List<Story> get stories;

  Story? story(String id);
}

/// Straightforward indexed implementation used by both the data layer and tests.
class InMemoryCourseData implements CourseData {
  InMemoryCourseData({
    required this.meta,
    required List<Unit> units,
    required List<Skill> skills,
    required List<Item> items,
    required Map<String, List<String>> skillItemIds, // skillId -> item ids in order
    required List<SkillFacet> skillFacets,
    List<Verb> verbs = const [],
    List<VerbForm> verbForms = const [],
    List<Sentence> sentences = const [],
    Map<String, Map<String, String>> notes = const {}, // skillId -> lang -> md
    Map<String, Set<String>> sentenceFeatures = const {}, // sentenceId -> features
    Map<String, Set<String>> skillFeatures = const {}, // skillId -> features
    List<Story> stories = const [],
    List<InflectionForm> inflections = const [],
  }) : units = (List.of(units)..sort((a, b) => a.ord.compareTo(b.ord))) {
    _notes = notes;
    _sentenceFeatures = sentenceFeatures;
    _skillFeatures = skillFeatures;
    final unitOrd = {for (final u in this.units) u.id: u.ord};
    this.stories = List.unmodifiable(List.of(stories)
      ..sort((a, b) {
        final c = (unitOrd[a.unitId] ?? 1 << 20).compareTo(unitOrd[b.unitId] ?? 1 << 20);
        return c != 0 ? c : a.ord.compareTo(b.ord);
      }));
    _stories = {for (final s in this.stories) s.id: s};
    this.skills = List.of(skills)
      ..sort((a, b) {
        final c = (unitOrd[a.unitId] ?? 0).compareTo(unitOrd[b.unitId] ?? 0);
        return c != 0 ? c : a.ord.compareTo(b.ord);
      });
    _skills = {for (final s in this.skills) s.id: s};
    _items = {for (final i in items) i.id: i};
    _skillItems = {
      for (final e in skillItemIds.entries)
        e.key: [for (final id in e.value) if (_items[id] != null) _items[id]!],
    };
    for (final f in skillFacets) {
      (_skillFacets[f.skillId] ??= []).add(f);
      (_facetSkills[f.facetId] ??= []).add(f.skillId);
    }
    for (final l in _skillFacets.values) {
      l.sort((a, b) => a.ord.compareTo(b.ord));
    }
    for (final i in items) {
      for (final t in i.tags) {
        (_byTag[t] ??= []).add(i);
      }
      (_byPos[i.pos] ??= []).add(i);
    }
    for (final l in _byPos.values) {
      l.sort((a, b) => (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30));
    }
    _verbs = {for (final v in verbs) v.itemId: v};
    for (final f in verbForms) {
      (_forms[f.itemId] ??= {})[f.key] = f;
    }
    for (final f in inflections) {
      (_infl[f.itemId] ??= {})[f.key] = f;
    }
    for (final s in sentences) {
      _sentences[s.id] = s;
      final seen = <String>{};
      for (final t in s.tokens) {
        final lex = t.lex;
        if (lex != null && seen.add(lex)) (_sentencesByItem[lex] ??= []).add(s);
      }
    }
  }

  @override
  final CourseMeta meta;
  @override
  final List<Unit> units;
  @override
  late final List<Skill> skills;

  late final Map<String, Skill> _skills;
  late final Map<String, Item> _items;
  late final Map<String, List<Item>> _skillItems;
  final Map<String, List<SkillFacet>> _skillFacets = {};
  final Map<String, List<String>> _facetSkills = {};
  final Map<String, List<Item>> _byTag = {};
  final Map<String, List<Item>> _byPos = {};
  late final Map<String, Verb> _verbs;
  final Map<String, Map<String, VerbForm>> _forms = {};
  final Map<String, Map<String, InflectionForm>> _infl = {};
  final Map<String, Sentence> _sentences = {};
  final Map<String, List<Sentence>> _sentencesByItem = {};
  late final Map<String, Map<String, String>> _notes;
  late final Map<String, Set<String>> _sentenceFeatures;
  late final Map<String, Set<String>> _skillFeatures;
  @override
  late final List<Story> stories;
  late final Map<String, Story> _stories;

  @override
  Skill? skill(String id) => _skills[id];
  @override
  Item? item(String id) => _items[id];
  @override
  Iterable<Item> get allItems => _items.values;
  @override
  List<Item> skillItems(String skillId) => _skillItems[skillId] ?? const [];
  @override
  List<SkillFacet> skillFacets(String skillId) => _skillFacets[skillId] ?? const [];
  @override
  List<String> skillsForFacet(String facetId) => _facetSkills[facetId] ?? const [];
  @override
  List<Item> itemsByTag(String tag) => _byTag[tag] ?? const [];

  @override
  List<Item> itemsNearFreq(String pos, int? freq, {int limit = 50}) {
    final pool = _byPos[pos] ?? const <Item>[];
    if (freq == null) return pool.take(limit).toList();
    int key(Item i) => i.freq ?? 1 << 30;
    // The pool is sorted by frequency, so the nearest [limit] items lie within
    // [limit] positions of where [freq] would be inserted. Only that window is
    // sorted (stably, like a sort of the whole pool). Equal distances on the
    // left mean equal frequencies, and those earlier items rank first, so the
    // window is widened over a run of equal frequencies at its left edge.
    var lo = 0;
    var hi = pool.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (key(pool[mid]) < freq) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var start = lo - limit < 0 ? 0 : lo - limit;
    while (start > 0 && key(pool[start - 1]) == key(pool[start])) {
      start--;
    }
    final end = lo + limit > pool.length ? pool.length : lo + limit;
    final window = pool.sublist(start, end);
    return window.sortedBy<num>((i) => (key(i) - freq).abs()).take(limit).toList();
  }

  @override
  Verb? verb(String itemId) => _verbs[itemId];
  @override
  Map<String, VerbForm> verbForms(String itemId) => _forms[itemId] ?? const {};

  @override
  List<VerbForm> verbFormsInTense(String itemId, String tense) {
    final forms = _forms[itemId];
    if (forms == null) return const [];
    return [
      for (final p in meta.persons)
        if (forms['$tense.$p'] != null) forms['$tense.$p']!,
    ];
  }

  @override
  Map<String, InflectionForm> inflections(String itemId) => _infl[itemId] ?? const {};

  @override
  List<InflectionForm> inflectionTable(String itemId, String table) {
    final forms = _infl[itemId];
    if (forms == null) return const [];
    final cells = meta.inflectionTables[table]?.cells ??
        [for (final f in forms.values) if (f.table == table) f.cell];
    return [
      for (final c in cells)
        if (forms['$table.$c'] != null) forms['$table.$c']!,
    ];
  }

  @override
  List<Sentence> sentencesFor(String itemId, {String? form, String? tense}) {
    final all = _sentencesByItem[itemId] ?? const <Sentence>[];
    if (form == null && tense == null) return all;
    return all
        .where((s) => s.tokens.any((t) =>
            t.lex == itemId &&
            (form == null || t.form == form) &&
            (tense == null || t.tense == tense)))
        .toList();
  }

  @override
  Sentence? sentence(String id) => _sentences[id];

  @override
  String? note(String skillId, String lang) {
    final n = _notes[skillId];
    if (n == null || n.isEmpty) return null;
    return n[lang] ?? n['en'] ?? n.values.first;
  }

  @override
  Set<String> sentenceFeatures(String sentenceId) => _sentenceFeatures[sentenceId] ?? const {};

  @override
  Set<String> skillFeatures(String skillId) => _skillFeatures[skillId] ?? const {};

  @override
  Story? story(String id) => _stories[id];
}
