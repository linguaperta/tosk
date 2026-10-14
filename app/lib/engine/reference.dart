/// Read-only lookups over a course for the UI's reference pages and word
/// popovers: a token's gloss (lemma, person, tense, article), an
/// accent-insensitive search over words, forms and glosses, full verb tables
/// with irregular forms marked, and word entries (skills, examples).
///
/// Pure Dart, cached per course like [CourseIndex].
library;

import 'package:collection/collection.dart';

import '../core/interfaces/course_data.dart';
import '../core/models/course.dart';
import '../core/models/exercise.dart';
import 'course_index.dart';
import 'text/normalize.dart';

/// What a tapped word means: shown in the word popover.
class WordGloss {
  const WordGloss({
    required this.item,
    required this.word,
    required this.label,
    required this.glosses,
    this.person,
    this.tense,
    this.personLabel,
    this.tenseLabel,
  });

  final Item item;

  /// The word as displayed in the sentence.
  final String word;

  /// The lemma, with its article for nouns (`il pane`, `l'acqua`).
  final String label;
  final List<String> glosses;

  /// Person and tense keys when the word is a verb form.
  final String? person;
  final String? tense;

  /// Person key as shown (`noi`), null for non-finite forms.
  final String? personLabel;

  /// Tense label in the source language (`present`).
  final String? tenseLabel;

  /// `mangiamo → mangiare · noi · present`, `pane → il pane`, `ciao`.
  String get headline {
    final parts = [?personLabel, ?tenseLabel];
    final same = foldAnswer(word) == foldAnswer(label) || foldAnswer(word) == foldAnswer(item.lemma);
    final base = same ? label : '$word → $label';
    return parts.isEmpty ? base : '$base · ${parts.join(' · ')}';
  }
}

/// The gloss of a token aligned to [itemId] (with its verb [form] key
/// `'{tense}.{person}'`), or null when the item is unknown.
WordGloss? glossForToken(CourseData course, {required String itemId, String? form, required String word, required String lang}) {
  final item = course.item(itemId);
  if (item == null) return null;
  final meta = course.meta;
  if (form != null && form.startsWith(kInflFormPrefix)) {
    // An inflected noun or adjective: `gatti → il gatto · plural`.
    final tok = Token(idx: 0, t: word, lex: itemId, form: form);
    final table = meta.inflectionTables[tok.inflTable];
    final cell = tok.inflCell;
    final base = table?.base;
    return WordGloss(
      item: item,
      word: word,
      label: CourseIndex.of(course).withArticle(item),
      glosses: item.glosses(lang),
      tenseLabel: table == null || cell == null || cell == base ? null : table.cellLabel(cell, lang),
    );
  }
  String? tense, person;
  if (form != null) {
    final i = form.indexOf('.');
    tense = i < 0 ? form : form.substring(0, i);
    person = i < 0 ? null : form.substring(i + 1);
  }
  return WordGloss(
    item: item,
    word: word,
    label: CourseIndex.of(course).withArticle(item),
    glosses: item.glosses(lang),
    person: person,
    tense: tense,
    personLabel: person == null || person == kNoPerson ? null : person,
    tenseLabel: tense == null ? null : meta.tenseLabel(tense, lang),
  );
}

/// [glossForToken] for a [TokenRef] (null for unaligned tokens).
WordGloss? glossForTokenRef(CourseData course, TokenRef t, String lang, {String? word}) =>
    t.itemId == null ? null : glossForToken(course, itemId: t.itemId!, form: t.form, word: word ?? t.text, lang: lang);

// ====================================================================== search

/// How a search hit matched, best first: whole matches before prefixes.
enum ReferenceMatch { lemma, form, gloss, lemmaPrefix, glossPrefix, contains }

class ReferenceHit {
  const ReferenceHit(this.item, this.match, {this.matched});
  final Item item;
  final ReferenceMatch match;

  /// The inflected form or gloss that matched, when it isn't the lemma.
  final String? matched;
}

/// One cell of a verb table.
class VerbCell {
  const VerbCell({required this.person, required this.form, this.alts = const [], this.irregular = false});

  /// Person key (`kNoPerson` for infinitive, participle, gerund).
  final String person;
  final String form;
  final List<String> alts;

  /// Differs from the regular pattern (see [CourseReference.isIrregular]).
  final bool irregular;
}

/// The forms of one tense, persons in course order.
class VerbTense {
  const VerbTense({required this.tense, required this.label, required this.cells});
  final String tense;
  final String label;
  final List<VerbCell> cells;
}

class VerbTable {
  const VerbTable({required this.item, required this.verb, required this.tenses, required this.nonFinite});
  final Item item;
  final Verb? verb;

  /// Finite tenses in course order ([CourseMeta.tenses]), only those with forms.
  final List<VerbTense> tenses;

  /// Infinitive, participle, gerund (whatever the pack has).
  final List<VerbTense> nonFinite;

  bool get isEmpty => tenses.isEmpty && nonFinite.isEmpty;
}

/// Cached reference lookups for one course.
class CourseReference {
  CourseReference._(this.course);

  static final Expando<CourseReference> _cache = Expando('CourseReference');

  /// The (cached) reference for [course].
  static CourseReference of(CourseData course) => _cache[course] ??= CourseReference._(course);

  final CourseData course;

  /// Every item, sorted by lemma (accent- and case-insensitive).
  late final List<Item> items = course.allItems.sortedBy((i) => '${foldAnswer(i.lemma)}\u0000${i.id}');

  /// Verb items with forms, sorted by lemma.
  late final List<Item> verbs = [for (final i in items) if (i.isVerb && course.verbForms(i.id).isNotEmpty) i];

  /// Skills that teach each item (skill item lists), in course order.
  late final Map<String, List<String>> _skillsOfItem = () {
    final out = <String, List<String>>{};
    for (final s in course.skills) {
      for (final i in course.skillItems(s.id)) {
        (out[i.id] ??= []).add(s.id);
      }
    }
    return out;
  }();

  List<Skill> skillsTeaching(String itemId) => [
        for (final id in _skillsOfItem[itemId] ?? const <String>[]) ?course.skill(id),
      ];

  /// Example sentences containing the item (shortest first).
  List<Sentence> examples(String itemId, {int limit = 5}) =>
      course.sentencesFor(itemId).sortedBy<num>((s) => s.text.length).take(limit).toList();

  /// Folded inflected form -> verb ids having it.
  late final Map<String, Set<String>> _forms = () {
    final out = <String, Set<String>>{};
    for (final v in verbs) {
      for (final f in course.verbForms(v.id).values) {
        for (final a in f.accepted) {
          (out[foldAnswer(a)] ??= {}).add(v.id);
        }
      }
    }
    return out;
  }();

  /// Searches lemmas, spelling variants, plurals and verb forms (target
  /// language) and glosses in [lang], ignoring case and accents. An empty
  /// query lists everything. Best matches first: lemma, inflected form,
  /// gloss (or one of its words), lemma prefix, gloss prefix, anywhere.
  List<ReferenceHit> search(String query, String lang, {bool verbsOnly = false, int limit = 300}) {
    final pool = verbsOnly ? verbs : items;
    final q = foldAnswer(query);
    if (q.isEmpty) return [for (final i in pool.take(limit)) ReferenceHit(i, ReferenceMatch.lemma)];
    final best = <String, ReferenceHit>{};
    void hit(Item i, ReferenceMatch m, [String? matched]) {
      final old = best[i.id];
      if (old == null || m.index < old.match.index) best[i.id] = ReferenceHit(i, m, matched: matched);
    }

    final formHits = _forms[q] ?? const <String>{};
    for (final i in pool) {
      final spellings = [...i.spellings, ?i.plural];
      for (final s in spellings) {
        final f = foldAnswer(s);
        if (f == q) {
          hit(i, ReferenceMatch.lemma, s == i.lemma ? null : s);
        } else if (f.startsWith(q)) {
          hit(i, ReferenceMatch.lemmaPrefix, s == i.lemma ? null : s);
        } else if (f.contains(q)) {
          hit(i, ReferenceMatch.contains, s == i.lemma ? null : s);
        }
      }
      if (formHits.contains(i.id)) hit(i, ReferenceMatch.form, query.trim());
      for (final g in i.glosses(lang)) {
        final f = foldAnswer(g);
        final words = f.split(' ');
        // "to eat" is found by "eat" and by "to eat".
        if (f == q || words.contains(q)) {
          hit(i, ReferenceMatch.gloss, g);
        } else if (f.startsWith(q) || words.any((w) => w.startsWith(q))) {
          hit(i, ReferenceMatch.glossPrefix, g);
        } else if (f.contains(q)) {
          hit(i, ReferenceMatch.contains, g);
        }
      }
    }
    final order = {for (var k = 0; k < pool.length; k++) pool[k].id: k};
    final list = best.values.toList()
      ..sort((a, b) {
        final c = a.match.index.compareTo(b.match.index);
        if (c != 0) return c;
        // Frequent words first within a match kind, then alphabetical.
        final fa = a.item.freq ?? 1 << 30, fb = b.item.freq ?? 1 << 30;
        final cf = fa.compareTo(fb);
        return cf != 0 ? cf : order[a.item.id]!.compareTo(order[b.item.id]!);
      });
    return list.take(limit).toList();
  }

  // ------------------------------------------------------------ verb tables

  static const _nonFiniteOrder = ['infinitive', 'participle', 'gerund'];

  /// The full table of a verb: every tense of the pack, persons in course
  /// order, tense labels in [lang].
  VerbTable verbTable(String itemId, String lang) {
    final item = course.item(itemId)!;
    final forms = course.verbForms(itemId);
    final meta = course.meta;
    VerbTense build(String tense, List<VerbForm> list) => VerbTense(
          tense: tense,
          label: meta.tenseLabel(tense, lang),
          cells: [
            for (final f in list)
              VerbCell(person: f.person, form: f.form, alts: f.alts, irregular: isIrregular(f)),
          ],
        );
    final tenses = <VerbTense>[
      for (final t in meta.tenses)
        if (course.verbFormsInTense(itemId, t) case final list when list.isNotEmpty) build(t, list),
    ];
    final known = {...meta.tenses};
    final extra = <String>{for (final f in forms.values) if (!known.contains(f.tense)) f.tense};
    final nonFinite = <VerbTense>[
      for (final t in [..._nonFiniteOrder.where(extra.contains), ...extra.where((t) => !_nonFiniteOrder.contains(t))])
        build(t, [
          for (final f in forms.values)
            if (f.tense == t) f,
        ]),
    ];
    return VerbTable(item: item, verb: course.verb(itemId), tenses: tenses, nonFinite: nonFinite);
  }

  /// Affix patterns `(prefix, suffix)` around the stem, per verb class and
  /// form key, with their counts, learned from the course's regular verbs.
  late final Map<String, Map<String, Map<(String, String), int>>> _patterns = () {
    final out = <String, Map<String, Map<(String, String), int>>>{};
    for (final v in verbs) {
      final verb = course.verb(v.id);
      if (verb == null || verb.irregular) continue;
      final stem = _stemOf(v.id);
      if (stem == null) continue;
      for (final f in course.verbForms(v.id).values) {
        final p = _affix(f.form, stem);
        if (p == null) continue;
        for (final cls in [verb.verbClass ?? '', '*']) {
          final byKey = (out[cls] ??= {})[f.key] ??= {};
          byKey[p] = (byKey[p] ?? 0) + 1;
        }
      }
    }
    return out;
  }();

  /// `(prefix, suffix)` with `form == prefix + stem + suffix` for a single
  /// word containing the stem, else null.
  static (String, String)? _affix(String form, String stem) {
    if (form.contains(' ') || stem.isEmpty) return null;
    final f = form.toLowerCase(), s = stem.toLowerCase();
    final i = f.indexOf(s);
    if (i < 0) return null;
    return (f.substring(0, i), f.substring(i + s.length));
  }

  String? _stemOf(String itemId) {
    final declared = course.verb(itemId)?.stem;
    if (declared != null && declared.isNotEmpty) return declared;
    final counts = <String, int>{};
    for (final f in course.verbForms(itemId).values) {
      final s = f.stem;
      if (s != null && s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// Whether a form of an irregular verb departs from the regular pattern:
  /// the verb's stem with an affix that at least 10 % of the course's
  /// regular verbs of the same class (or, without any, of all classes) use
  /// for that tense and person. A compound form (several words) counts as
  /// irregular when it contains an irregular participle. Verbs not marked
  /// irregular never have irregular forms. A heuristic for highlighting.
  bool isIrregular(VerbForm f) {
    final verb = course.verb(f.itemId);
    if (verb == null || !verb.irregular) return false;
    if (f.form.contains(' ')) {
      final participle = course.verbForms(f.itemId)['participle.$kNoPerson'];
      if (participle == null || participle.form.contains(' ')) return false;
      final words = splitWords(f.form).map((w) => w.toLowerCase()).toSet();
      return words.contains(participle.form.toLowerCase()) && isIrregular(participle);
    }
    final stem = _stemOf(f.itemId);
    if (stem == null) return false;
    final byClass = _patterns[verb.verbClass ?? ''];
    var pats = byClass?[f.key];
    if (pats == null || pats.isEmpty) pats = _patterns['*']?[f.key];
    if (pats == null || pats.isEmpty) return false;
    final total = pats.values.sum;
    final forms = {for (final a in f.accepted) a.toLowerCase()};
    for (final e in pats.entries) {
      if (e.value * 10 < total) continue;
      if (forms.contains('${e.key.$1}${stem.toLowerCase()}${e.key.$2}')) return false;
    }
    return true;
  }
}
