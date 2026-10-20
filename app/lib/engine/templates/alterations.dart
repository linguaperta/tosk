/// Ways to make a real sentence wrong in exactly one word: swap a verb form
/// for another person/tense, or an article for a wrong one. Shared by
/// spot_error and the "pick the correct sentence" multiple choice.
library;

import '../../core/models/course.dart';
import '../course_index.dart';
import '../text/normalize.dart';

/// Replacing one word of a verb form occurrence with the matching word of
/// another cell's form.
class FormSwap {
  FormSwap(this.occ, this.replacement, this.partIndex, this.newWord);
  final FormOccurrence occ;
  final VerbForm replacement;

  /// Index into [FormOccurrence.positions] of the replaced word.
  final int partIndex;

  /// The new word, cased like the original.
  final String newWord;

  int get tokenPos => occ.positions[partIndex];

  /// The sentence tokens as (pre, text) with the swap applied.
  List<(String, String)> render() => [
        for (var i = 0; i < occ.sentence.tokens.length; i++)
          (occ.sentence.tokens[i].pre, i == tokenPos ? newWord : occ.sentence.tokens[i].t),
      ];
}

/// Folded keys of every form that would be correct (or ambiguous) in the
/// position of [o]: all accepted spellings of the cell, plus forms of persons
/// that share a pronoun with the cell's person (Dutch `hij/zij` vs `zij`).
Set<String> contextKeys(CourseIndex ix, String verbId, String tense, String person) {
  final forms = ix.course.verbForms(verbId);
  final keys = <String>{};
  final cell = forms['$tense.$person'];
  if (cell != null) keys.addAll(ix.acceptedKeys(cell));
  for (final p in ix.ambiguousPersons(person, tense: tense)) {
    final f = forms['$tense.$p'];
    if (f != null) keys.addAll(ix.acceptedKeys(f));
  }
  return keys;
}

/// Single-word swaps for [o], in priority order: other persons in the same
/// tense, then the same person in other tenses. Each swap yields a form that
/// is not an accepted form of the cell (homographs such as Italian `sono`
/// io/loro, or Dutch `eet` ik/jij/hij, are excluded) and not a form of an
/// ambiguous person.
List<FormSwap> formSwaps(CourseIndex ix, FormOccurrence o) {
  final forms = ix.course.verbForms(o.verbId);
  final forbidden = contextKeys(ix, o.verbId, o.tense, o.person);
  final ambiguous = ix.ambiguousPersons(o.person, tense: o.tense).toSet();
  final sameTense = <VerbForm>[];
  final otherTense = <VerbForm>[];
  for (final f in forms.values) {
    if (f.person == kNoPerson || f.key == o.cell.key) continue;
    if (f.tense == o.tense && f.person != o.person && !ambiguous.contains(f.person)) {
      sameTense.add(f);
    } else if (f.tense != o.tense && f.person == o.person) {
      otherTense.add(f);
    }
  }
  final out = <FormSwap>[];
  final seen = <String>{};
  for (final f in [...sameTense, ...otherTense]) {
    if (forbidden.contains(foldAnswer(f.form))) continue;
    final w = splitWords(f.form);
    if (w.length != o.wordCount) continue;
    final surface = o.surface;
    final diff = [
      for (var k = 0; k < w.length; k++)
        if (foldAnswer(w[k]) != foldAnswer(surface[k])) k,
    ];
    if (diff.length != 1) continue;
    final k = diff.single;
    final newWord = matchCase(w[k], surface[k]);
    if (!seen.add('$k:${foldAnswer(newWord)}')) continue;
    out.add(FormSwap(o, f, k, newWord));
  }
  return out;
}

/// Articles from the course's article list that are wrong for [noun].
List<String> wrongArticles(CourseIndex ix, Item noun) {
  final valid = {for (final a in ix.articlesOf(noun)) foldAnswer(a)};
  final seen = <String>{};
  return [
    for (final a in ix.meta.articles)
      if (!valid.contains(foldAnswer(a)) && foldAnswer(a).isNotEmpty && seen.add(foldAnswer(a))) a,
  ];
}

/// The sentence tokens as (pre, text) with the article of [o] replaced by
/// [replacement]. Spacing is fixed for elision (`l'` <-> `la`).
List<(String, String)> renderArticleSwap(ArticleOccurrence o, String replacement) {
  final tokens = o.sentence.tokens;
  final elidedNew = normalizeApostrophes(replacement).endsWith("'");
  final rep = matchCase(replacement, o.article);
  final out = <(String, String)>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (o.withinToken && i == o.nounPos) {
      out.add((t.pre, elidedNew ? '$rep${o.nounText}' : '$rep ${o.nounText}'));
    } else if (!o.withinToken && i == o.articlePos) {
      out.add((t.pre, rep));
    } else if (!o.withinToken && i == o.nounPos) {
      out.add((elidedNew ? '' : (t.pre.isEmpty ? ' ' : t.pre), t.t));
    } else {
      out.add((t.pre, t.t));
    }
  }
  return out;
}
