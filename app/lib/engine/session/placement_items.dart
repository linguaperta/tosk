/// Placement items (docs/engine.md, "Placement"): production without
/// context, so a learner who recognises a word in a sentence but can't
/// produce it doesn't pass.
///
/// * **Form** (`#form`): the verb, its meaning, the person and the tense;
///   give the whole form (`finir` · nous · imparfait → `finissions`). Built
///   as a [ConjPickExercise] with an empty stem: typed or handwritten in
///   those input modes, and in tap mode a pick among forms of the **same**
///   verb (other persons of the tense, the person in other tenses, a wrong
///   auxiliary), so nothing but the conjugation tells them apart.
/// * **Inflection** (`#infl`): the same for a cell of an inflection table
///   (`ragazzo` · plural → `ragazzi`), distractors from the item's other
///   cells and its plausible wrong forms.
/// * **Word** (`#prod`): the meaning alone, no sentence; give the word. A
///   "bare" [ClozeExercise] (no text around the gap, the meaning in
///   [ClozeExercise.translation]) with near distractors of the same part of
///   speech for tap mode.
library;

import '../../core/interfaces/course_data.dart';
import '../../core/models/course.dart';
import '../../core/models/exercise.dart';
import '../../core/models/facet.dart';
import '../course_index.dart';
import '../gen_context.dart';
import '../reference.dart';
import '../strings.dart';
import '../template.dart';
import '../text/normalize.dart';
import '../templates/alterations.dart' show contextKeys;
import '../templates/inflection.dart' show inflTableOf;

/// Whether [f] is grammar for placement: a verb form, an inflection or an
/// article, or a word of a grammar skill that is all function words (no
/// forms, inflections or articles: pronouns, prepositions, negation). Placement
/// credits grammar per unit; every other facet (`#prod`, `#rec` of a word)
/// is vocabulary, credited per word through the word check.
bool isPlacementGrammarFacet(CourseData course, SkillFacet f) {
  switch (f.kind) {
    case FacetKind.form || FacetKind.infl || FacetKind.article:
      return true;
    case FacetKind.prod || FacetKind.rec:
      final skill = course.skill(f.skillId);
      if (skill == null || skill.kind != SkillKind.grammar) return false;
      return CourseIndex.of(course).memo('placement.functionWords|${skill.id}', () {
        return course.skillFacets(skill.id).every((g) => g.kind == FacetKind.prod || g.kind == FacetKind.rec);
      });
  }
}

/// The word facets (`#prod`, `#rec`) of [itemId] that the course trains.
List<String> wordFacetIds(CourseData course, String itemId) => [
      for (final k in const [FacetKind.prod, FacetKind.rec])
        if (course.skillsForFacet(FacetId(itemId, k).toString()).isNotEmpty) FacetId(itemId, k).toString(),
    ];

/// A placement item that asks for production without context: a whole form
/// ([placementFormItem], [placementInflItem]) or a word from its meaning
/// ([placementWordItem]).
bool isContextFreeProduction(Exercise e) => switch (e) {
      ConjPickExercise() => e.stem.isEmpty,
      ClozeExercise() => isBareCloze(e),
      _ => false,
    };

/// A cloze with nothing around the gap: give the word for the meaning in
/// [ClozeExercise.translation] (placement).
bool isBareCloze(ClozeExercise e) => e.before.isEmpty && e.after.isEmpty && e.tokens == null;

/// The meaning shown for [item]: its first two glosses in [lang].
String placementPrompt(Item item, String lang) => item.glosses(lang).take(2).join(', ');

/// Every typed answer accepted for [item] given [placementPrompt]: its
/// spellings, with the article, and the spellings of items that share a
/// shown meaning (a synonym is right too).
List<String> placementAccepted(CourseIndex ix, Item item, String lang) {
  final shown = {for (final g in item.glosses(lang).take(2)) foldAnswer(g)};
  final out = <String>{
    ...item.spellings,
    ix.withArticle(item),
    for (final s in ix.synonymsOf(item))
      if (ix.glossKeysIn(s, lang).any(shown.contains)) ...[...s.spellings, ix.withArticle(s)],
  };
  return out.toList();
}

/// The person cells of [facet]'s tense still to prefer: not asked yet in
/// this probe ([usedPersons]), irregular ones first.
List<VerbForm> _orderedCells(GenContext ctx, String verbId, String tense, Set<String> usedPersons) {
  final cells = ctx.index.finiteForms(verbId, tense);
  final fresh = [for (final c in cells) if (!usedPersons.contains(c.person)) c];
  final pool = ctx.shuffled(fresh.isEmpty ? cells : fresh);
  final ref = CourseReference.of(ctx.course);
  return [
    for (final c in pool) if (ref.isIrregular(c)) c,
    for (final c in pool) if (!ref.isIrregular(c)) c,
  ];
}

/// Wrong forms of [cell]'s own verb: another person of the tense, the person
/// in another tense, a compound form with the other auxiliary, then any.
List<String> _formDistractors(GenContext ctx, VerbForm cell, {int max = 3}) {
  final course = ctx.course;
  final ix = ctx.index;
  final forbidden = contextKeys(ix, cell.itemId, cell.tense, cell.person);
  final picker = OptionPicker(forbidden: [...cell.accepted, ...forbidden], max: max);
  final all = [for (final f in course.verbForms(cell.itemId).values) if (f.person != kNoPerson && f.key != cell.key) f];
  final sameTense = [for (final f in all) if (f.tense == cell.tense) f.form];
  final samePerson = [for (final f in all) if (f.tense != cell.tense && f.person == cell.person) f.form];
  final aux = _auxiliarySwaps(ix, cell);
  final rest = [for (final f in all) f.form];
  // One of each kind first, so the options differ in person and in tense.
  for (final g in [sameTense, aux, samePerson]) {
    for (final o in ctx.shuffled(g)) {
      if (picker.add(o)) break;
    }
  }
  picker.addGroups([sameTense, samePerson, aux, rest], ctx.random);
  return picker.picked;
}

/// [cell]'s compound form with the other perfect auxiliary (`ho andato` for
/// `sono andato`, `je suis mangé`): plausible, and wrong.
List<String> _auxiliarySwaps(CourseIndex ix, VerbForm cell) {
  final words = splitWords(cell.form);
  if (words.length < 2) return const [];
  final course = ix.course;
  final auxes = [for (final v in ix.verbs) if (ix.auxiliaryLemmas.contains(v.lemma)) v];
  final first = foldAnswer(words.first);
  final out = <String>[];
  for (final a in auxes) {
    for (final f in course.verbForms(a.id).values) {
      if (f.person != cell.person || foldAnswer(f.form) != first) continue;
      for (final b in auxes) {
        if (b.id == a.id) continue;
        final g = course.verbForms(b.id)['${f.tense}.${cell.person}'];
        if (g != null && splitWords(g.form).length == 1) out.add([g.form, ...words.skip(1)].join(' '));
      }
    }
  }
  return out;
}

/// "Give the form": [facet]'s verb in its tense for one person, the whole
/// form, no sentence. Null when the verb has fewer than two other forms to
/// offer in tap mode.
ConjPickExercise? placementFormItem(SkillFacet facet, GenContext ctx, {Set<String> usedPersons = const {}}) {
  final tense = facet.tense;
  final verb = ctx.course.item(facet.itemId);
  if (tense == null || verb == null || facet.kind != FacetKind.form) return null;
  final meta = ctx.course.meta;
  for (final cell in _orderedCells(ctx, verb.id, tense, usedPersons)) {
    final wrong = _formDistractors(ctx, cell);
    if (wrong.length < 2) continue;
    final (options, idx) = placeOptions(cell.form, wrong, ctx.random);
    final person = meta.personLabel(cell.person, ctx.lang, tense: cell.tense);
    return ConjPickExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('placement.form', ctx.lang),
      lemma: verb.lemma,
      gloss: verb.gloss(ctx.lang),
      tense: cell.tense,
      tenseLabel: meta.tenseLabel(cell.tense, ctx.lang),
      person: cell.person,
      personLabel: person,
      stem: '',
      endings: options,
      correctIndex: idx,
      fullForm: cell.form,
      accepted: {
        ...cell.accepted,
        // With the pronoun typed too (`noi mangiamo`).
        if (_plainLabel(person)) for (final a in cell.accepted) '$person $a',
      }.toList(),
    );
  }
  return null;
}

/// A person label that reads as a pronoun (`noi`, `ik`), not `he/she` or `lei (formal)`.
bool _plainLabel(String label) => label.isNotEmpty && !label.contains(RegExp(r'[\s/()]'));

/// "Give the form" for an inflection cell (`ragazzo` · plural → `ragazzi`).
ConjPickExercise? placementInflItem(SkillFacet facet, GenContext ctx, {Set<String> usedCells = const {}}) {
  final item = ctx.course.item(facet.itemId);
  final spec = inflTableOf(ctx, facet);
  if (item == null || spec == null || facet.kind != FacetKind.infl) return null;
  final table = ctx.course.inflectionTable(item.id, spec.name);
  final cells = [for (final c in table) if (c.cell != spec.base) c];
  final fresh = [for (final c in cells) if (!usedCells.contains(c.cell)) c];
  for (final cell in ctx.shuffled(fresh.isEmpty ? cells : fresh)) {
    final picker = OptionPicker(forbidden: cell.accepted, max: 3);
    picker.addGroups([
      [for (final c in table) if (c.cell != cell.cell) c.form],
      cell.wrong,
      [for (final c in ctx.course.inflections(item.id).values) if (c.table != spec.name) c.form],
      _analogicalForms(ctx, item, spec.name, cell.cell),
      [item.lemma],
    ], ctx.random);
    if (picker.picked.length < 2) continue;
    final (options, idx) = placeOptions(cell.form, picker.picked, ctx.random);
    return ConjPickExercise(
      id: ctx.nextId(),
      facetId: facet.facetId,
      skillId: ctx.skill?.id,
      instruction: instruction('placement.infl', ctx.lang),
      lemma: item.lemma,
      gloss: item.gloss(ctx.lang),
      tense: spec.name,
      tenseLabel: spec.titleIn(ctx.lang),
      person: cell.cell,
      personLabel: spec.cellLabel(cell.cell, ctx.lang),
      stem: '',
      endings: options,
      correctIndex: idx,
      fullForm: cell.form,
      accepted: cell.accepted,
      inflection: true,
    );
  }
  return null;
}

/// Forms [item] would have in [cell] of [table] if it followed another
/// item's pattern (`ragazzo` → `ragazze`, `ragazzos`): the endings other
/// items of the course swap from their lemma to that cell. Plausible, and
/// (once the accepted forms are excluded) wrong. Patterns are cached per course.
List<String> _analogicalForms(GenContext ctx, Item item, String table, String cell) {
  final patterns = ctx.index.memo('placement.inflPatterns|$table|$cell', () {
    final counts = <(String, String), int>{};
    for (final o in ctx.course.allItems) {
      final f = ctx.course.inflections(o.id)['$table.$cell'];
      if (f == null || f.form.contains(' ')) continue;
      final a = o.lemma.toLowerCase(), b = f.form.toLowerCase();
      var k = 0;
      while (k < a.length && k < b.length && a[k] == b[k]) {
        k++;
      }
      if (k == 0 || a.length - k > 3 || b.length - k > 4) continue;
      final key = (a.substring(k), b.substring(k));
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final list = counts.entries.where((e) => e.value >= 2).toList()..sort((x, y) => y.value.compareTo(x.value));
    return [for (final e in list.take(12)) e.key];
  });
  final lemma = item.lemma;
  final lower = lemma.toLowerCase();
  return {
    for (final (from, to) in patterns)
      if (lower.endsWith(from) && lower.length > from.length) lemma.substring(0, lemma.length - from.length) + to,
  }.toList();
}

/// "How do you say this?": the meaning of [facet]'s word, nothing else; give
/// the word. Tap mode picks among near words of the same part of speech.
ClozeExercise? placementWordItem(SkillFacet facet, GenContext ctx) {
  final item = ctx.course.item(facet.itemId);
  if (item == null) return null;
  final ix = ctx.index;
  final prompt = placementPrompt(item, ctx.lang);
  if (prompt.trim().isEmpty || item.lemma.trim().isEmpty) return null;
  final accepted = placementAccepted(ix, item, ctx.lang);
  final picker = OptionPicker(
    forbidden: [...accepted, for (final s in ix.synonymsOf(item)) ...s.spellings],
    max: 3,
  );
  for (final g in ix.relatedItems(item)) {
    for (final o in ctx.shuffled(g)) {
      if (picker.full) break;
      // A word whose meaning overlaps the shown one would be right too.
      if (ix.overlaps(item, o)) continue;
      picker.add(o.lemma);
    }
  }
  if (picker.picked.length < 2) return null;
  final (options, idx) = placeOptions(item.lemma, picker.picked, ctx.random);
  return ClozeExercise(
    id: ctx.nextId(),
    facetId: facet.facetId,
    skillId: ctx.skill?.id,
    instruction: instruction('placement.word', ctx.lang),
    before: '',
    after: '',
    expected: item.lemma,
    accepted: accepted,
    options: options,
    correctIndex: idx,
    translation: prompt,
  );
}
