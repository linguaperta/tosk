/// First-time explanations of the nine exercise types: the texts (all in this
/// file), the examples built from the course's own data, and which intros the
/// learner has seen (the setting `intro.seen`, account-wide).
///
/// The UI is English; the texts live here so they can be localized in one place.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/test_env.dart';
import '../../../core/core.dart';
import '../../../providers.dart' show progressStoreProvider;
import '../../settings/setting_keys.dart';

/// Title and what to do, for one exercise type.
@immutable
class ExerciseIntro {
  const ExerciseIntro({required this.title, required this.body});
  final String title;
  final String body;
}

ExerciseIntro introFor(ExerciseType t) => switch (t) {
  ExerciseType.flashcard => const ExerciseIntro(
    title: 'Flashcards',
    body: 'Think of the answer, then tap Show answer. Say how well you knew it: Again, Hard, Good or Easy.',
  ),
  ExerciseType.multipleChoice => const ExerciseIntro(
    title: 'Multiple choice',
    body: 'Pick the one right answer, then tap Check.',
  ),
  ExerciseType.matchPairs => const ExerciseIntro(
    title: 'Match the pairs',
    body:
        'Tap a word, then its meaning (or the other way round). A right pair stays marked; '
        'a wrong pair flashes and counts as a mistake for that word.',
  ),
  ExerciseType.conjPick => const ExerciseIntro(
    title: 'Pick the ending',
    body: 'Choose the ending that completes the verb for this person and tense.',
  ),
  ExerciseType.conjGrid => const ExerciseIntro(
    title: 'Fill in the table',
    body: 'Tap an empty cell, then the tile with its form. Tap a filled cell to take its tile back.',
  ),
  ExerciseType.sentenceBuilder => const ExerciseIntro(
    title: 'Build the sentence',
    body: 'Translate the sentence: tap the word tiles in the right order. Tap a placed word to take it back.',
  ),
  ExerciseType.cloze => const ExerciseIntro(
    title: 'Fill in the gap',
    body: 'Choose (or type) the word that belongs in the gap.',
  ),
  ExerciseType.spotError => const ExerciseIntro(
    title: 'Spot the error',
    body: 'One word in the sentence is wrong. Tap it. The translation tells you what is meant.',
  ),
  ExerciseType.transform => const ExerciseIntro(
    title: 'Change the tense or person',
    body:
        'Rewrite the sentence as the banner asks: in another tense (present → past) '
        'or for another person (I → we). Build the new sentence from the tiles.',
  ),
};

/// One line of an example: [from] [arrow] [to].
@immutable
class IntroLine {
  const IntroLine(this.from, this.to, {this.arrow = '→'});
  final String from;
  final String to;
  final String arrow;

  @override
  bool operator ==(Object other) => other is IntroLine && other.from == from && other.to == to && other.arrow == arrow;

  @override
  int get hashCode => Object.hash(from, to, arrow);

  @override
  String toString() => '$from $arrow $to';
}

/// A small example for [type] from [course]'s own words, verbs and sentences
/// (never the answer of [current], the exercise about to be shown). Empty when
/// the course has nothing suitable.
List<IntroLine> introExample(ExerciseType type, CourseData? course, String lang, {Exercise? current}) {
  if (course == null) return const [];
  final avoid = <String>{};
  if (current != null) {
    for (final f in current.facetIds) {
      final i = f.indexOf('#');
      avoid.add(i < 0 ? f : f.substring(0, i));
    }
  }
  final words = _sampleWords(course, lang, avoid);
  final meta = course.meta;
  final verb = _sampleVerb(course, avoid);
  String person(String p) => meta.personLabel(p, lang).split(' (').first;

  switch (type) {
    case ExerciseType.flashcard:
      return [if (words.isNotEmpty) IntroLine(words[0].$1, words[0].$2)];
    case ExerciseType.multipleChoice:
      return [if (words.isNotEmpty) IntroLine(words[0].$1, '✓ ${words[0].$2}')];
    case ExerciseType.matchPairs:
      return [for (final w in words.take(2)) IntroLine(w.$1, w.$2, arrow: '↔')];
    case ExerciseType.conjPick:
      List<VerbForm> splitForms(String id, String tense) => [
        for (final f in course.verbFormsInTense(id, tense))
          if (f.hasSplit && f.ending!.isNotEmpty && !f.form.contains(' ')) f,
      ];
      // A verb whose forms split into stem + ending (not essere).
      final v = _sampleVerb(course, avoid, ok: (id, tense) => splitForms(id, tense).length >= 4);
      if (v == null) return const [];
      final split = splitForms(v.$1, v.$2);
      final f = split.length > 3 ? split[3] : split.last;
      return [IntroLine('${person(f.person)} ${f.stem}___', '${person(f.person)} ${f.form}')];
    case ExerciseType.conjGrid:
      if (verb == null) return const [];
      final forms = course.verbFormsInTense(verb.$1, verb.$2);
      return [for (final f in forms.take(2)) IntroLine(person(f.person), f.form)];
    case ExerciseType.sentenceBuilder:
      final s = _sampleSentence(course, lang, verb?.$1);
      if (s == null) return const [];
      return [
        IntroLine(s.translation(lang)!, [for (final t in s.tokens) if (t.isWord) t.t].join(' · ')),
      ];
    case ExerciseType.cloze:
      final s = _sampleSentence(course, lang, verb?.$1);
      if (s == null) return const [];
      final gap = s.tokens.where((t) => t.isWord && t.lex != null).lastOrNull ?? s.tokens.firstWhere((t) => t.isWord);
      return [IntroLine(s.render({gap.idx: '___'}), gap.t)];
    case ExerciseType.spotError:
      if (verb == null) return const [];
      final forms = course.verbFormsInTense(verb.$1, verb.$2);
      if (forms.length < 4) return const [];
      final right = forms[3], wrong = forms[2];
      if (right.form == wrong.form) return const [];
      return [IntroLine('${person(right.person)} ${wrong.form} ✗', '${person(right.person)} ${right.form}')];
    case ExerciseType.transform:
      // A verb with forms in a second tense.
      final verb = _sampleVerb(
        course,
        avoid,
        ok: (id, tense) => meta.tenses.any((t) => t != tense && course.verbFormsInTense(id, t).isNotEmpty),
      );
      if (verb == null) return const [];
      final other = [
        for (final t in meta.tenses)
          if (t != verb.$2 && course.verbFormsInTense(verb.$1, t).isNotEmpty) t,
      ];
      // A compound past reads clearest (`mangio → ho mangiato`).
      bool compound(String t) => course.verbFormsInTense(verb.$1, t).any((f) => f.form.contains(' '));
      other.sort((a, b) => (compound(b) ? 1 : 0) - (compound(a) ? 1 : 0));
      final forms = course.verbFormsInTense(verb.$1, verb.$2);
      if (forms.isEmpty) return const [];
      final out = <IntroLine>[];
      if (other.isNotEmpty) {
        final p = forms.first.person;
        final target = course.verbForms(verb.$1)['${other.first}.$p'];
        if (target != null) {
          out.add(
            IntroLine(
              '${meta.tenseLabel(verb.$2, lang)}: ${forms.first.form}',
              '${meta.tenseLabel(other.first, lang)}: ${target.form}',
            ),
          );
        }
      }
      if (forms.length >= 4) {
        out.add(IntroLine('${person(forms[0].person)}: ${forms[0].form}', '${person(forms[3].person)}: ${forms[3].form}'));
      }
      return out;
  }
}

/// (word with article, first gloss) for frequent vocabulary items, in course order.
List<(String, String)> _sampleWords(CourseData course, String lang, Set<String> avoid) {
  final out = <(String, String)>[];
  for (final s in course.skills) {
    for (final i in course.skillItems(s.id)) {
      if (avoid.contains(i.id) || i.isVerb) continue;
      final g = i.glosses(lang);
      // Not a word that reads the same in both languages (`no → no`).
      if (g.isEmpty || i.lemma.trim().isEmpty || g.first.toLowerCase() == i.lemma.toLowerCase()) continue;
      final a = i.article;
      final word = a == null || a.isEmpty ? i.lemma : (a.endsWith("'") ? '$a${i.lemma}' : '$a ${i.lemma}');
      if (out.any((w) => w.$1 == word || w.$2 == g.first)) continue;
      out.add((word, g.first));
      if (out.length >= 2) return out;
    }
  }
  return out;
}

/// (verb item id, tense) of the course's most frequent verb with a full first
/// tense (and [ok]), preferring one not in [avoid].
(String, String)? _sampleVerb(CourseData course, Set<String> avoid, {bool Function(String id, String tense)? ok}) {
  final tenses = course.meta.tenses;
  if (tenses.isEmpty) return null;
  final verbs = [for (final i in course.allItems) if (i.isVerb) i]
    ..sort((a, b) => (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30));
  (String, String)? fallback;
  // Regular verbs read best as examples (`parlo → ho parlato`); else any.
  for (final regularOnly in [true, false]) {
    for (final v in verbs) {
      if (regularOnly && (course.verb(v.id)?.irregular ?? false)) continue;
      final forms = course.verbFormsInTense(v.id, tenses.first);
      if (forms.length < course.meta.persons.length || forms.length < 4) continue;
      if (ok != null && !ok(v.id, tenses.first)) continue;
      if (!avoid.contains(v.id)) return (v.id, tenses.first);
      fallback ??= (v.id, tenses.first);
    }
    if (fallback != null) return fallback;
  }
  return fallback;
}

/// A short sentence (3–6 words) with a translation, with [verbId] if possible.
Sentence? _sampleSentence(CourseData course, String lang, String? verbId) {
  bool ok(Sentence s) {
    final n = s.tokens.where((t) => t.isWord).length;
    return n >= 3 && n <= 6 && (s.translation(lang) ?? '').isNotEmpty;
  }

  // Words from the first skills first: the simplest sentences.
  for (final skill in course.skills.take(3)) {
    for (final item in course.skillItems(skill.id)) {
      for (final s in course.sentencesFor(item.id)) {
        if (ok(s)) return s;
      }
    }
  }
  if (verbId != null) {
    for (final s in course.sentencesFor(verbId)) {
      if (ok(s)) return s;
    }
  }
  for (final skill in course.skills) {
    for (final item in course.skillItems(skill.id)) {
      for (final s in course.sentencesFor(item.id)) {
        if (ok(s)) return s;
      }
    }
  }
  return null;
}

// ------------------------------------------------------------------ seen

/// Whether first-time intros are shown. Off under `flutter test`, so flows
/// that don't test intros aren't interrupted; intro tests override it.
final exerciseIntrosEnabledProvider = Provider<bool>((ref) => !runningInFlutterTest);

/// The exercise types whose intro the learner has seen (setting `intro.seen`).
final introSeenProvider = AsyncNotifierProvider<IntroSeenController, Set<ExerciseType>>(IntroSeenController.new);

class IntroSeenController extends AsyncNotifier<Set<ExerciseType>> {
  @override
  Future<Set<ExerciseType>> build() async =>
      parseIntroSeen(await ref.watch(progressStoreProvider).getSetting(SettingKeys.introSeen));

  /// Marks [type] as seen (at once in memory, then persisted).
  Future<void> markSeen(ExerciseType type) async {
    final current = state.value ?? await future;
    if (current.contains(type)) return;
    final next = {...current, type};
    state = AsyncData(next);
    await ref.read(progressStoreProvider).setSetting(SettingKeys.introSeen, formatIntroSeen(next));
  }
}

Set<ExerciseType> parseIntroSeen(String? v) => {
  for (final id in (v ?? '').split(',')) ?ExerciseType.tryParse(id.trim()),
};

/// Comma-separated type ids, in [ExerciseType] order.
String formatIntroSeen(Set<ExerciseType> seen) => [
  for (final t in ExerciseType.values)
    if (seen.contains(t)) t.id,
].join(',');
