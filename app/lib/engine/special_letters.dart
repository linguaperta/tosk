/// The letters of a course's target language that a plain (US) keyboard
/// lacks, for the accent bar shown above typed answers. Derived from the
/// course data, never hardcoded per language.
library;

import '../core/interfaces/course_data.dart';
import 'course_index.dart';
import 'text/normalize.dart';

final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// Non-ASCII letters of the target language, most frequent first.
///
/// Counted (lower-cased, NFC) over every spelling of the course's words
/// (lemmas, variants, plurals), every accepted verb form and every word of
/// every sentence. A letter is kept when it occurs at least [minCount] times
/// and at least [minShare] as often as the most frequent one, which drops
/// stray letters of loanwords and names (`ç` in an Italian `garçon`); at most
/// [max] letters. Cached per course.
List<String> specialLetters(CourseData course, {int max = 12, int minCount = 3, double minShare = 0.002}) =>
    CourseIndex.of(course).memo('special_letters/$max/$minCount/$minShare', () {
      final counts = <String, int>{};
      void count(String? s) {
        if (s == null) return;
        for (final m in _letter.allMatches(nfc(s.toLowerCase()))) {
          final ch = m[0]!;
          if (ch.codeUnitAt(0) < 0x80) continue;
          // A letter whose upper case is itself (ß, ʼ-like letters) still counts.
          counts[ch] = (counts[ch] ?? 0) + 1;
        }
      }

      for (final i in course.allItems) {
        for (final s in i.spellings) {
          count(s);
        }
        count(i.plural);
        if (i.isVerb) {
          for (final f in course.verbForms(i.id).values) {
            for (final a in {f.form, ...f.accepted}) {
              count(a);
            }
          }
        }
      }
      for (final s in CourseIndex.of(course).allSentences) {
        for (final t in s.tokens) {
          if (t.isWord) count(t.t);
        }
      }
      if (counts.isEmpty) return const <String>[];
      final top = counts.values.reduce((a, b) => a > b ? a : b);
      final kept = [
        for (final e in counts.entries)
          if (e.value >= minCount && e.value >= top * minShare) e,
      ]..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
      return [for (final e in kept.take(max)) e.key];
    });
