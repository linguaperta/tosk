/// Glossing free text (v0.4, AI conversation replies): split a target-language
/// text into [TokenRef]s and align each word to a course item by its
/// spelling, so the UI's word popovers work on text that isn't a pack
/// sentence. Lowercase matching only (accents matter: Italian `è` is not `e`).
/// Pure Dart.
library;

import '../core/core.dart';

/// Course words by written form: lemmas, spelling variants and plurals, verb
/// forms (with their `'{tense}.{person}'` key) and inflection cells (with
/// their `'infl:{table}.{cell}'` key). When several items share a form, the
/// more frequent one wins; a lemma beats an inflected form.
class WordLookup {
  WordLookup._(CourseData course) {
    final items = course.allItems.toList()..sort((a, b) => (a.freq ?? 1 << 30).compareTo(b.freq ?? 1 << 30));
    void put(String form, String itemId, String? key) {
      final f = form.trim().toLowerCase();
      if (f.isEmpty || f.contains(' ')) return;
      _byForm.putIfAbsent(f, () => (itemId, key));
    }

    for (final i in items) {
      for (final s in i.spellings) {
        put(s, i.id, null);
      }
    }
    for (final i in items) {
      if (i.plural case final p?) put(p, i.id, null);
      for (final f in course.verbForms(i.id).values) {
        for (final a in f.accepted) {
          put(a, i.id, f.key);
        }
      }
      for (final f in course.inflections(i.id).values) {
        put(f.form, i.id, '$kInflFormPrefix${f.table}.${f.cell}');
      }
    }
  }

  static final Expando<WordLookup> _cache = Expando();

  static WordLookup of(CourseData course) => _cache[course] ??= WordLookup._(course);

  final Map<String, (String, String?)> _byForm = {};

  /// `(itemId, form key)` of [word], or null.
  (String, String?)? lookup(String word) => _byForm[word.toLowerCase()] ?? _byForm[_stripElision(word.toLowerCase())];

  /// `l'acqua` → `l'`, `dell'` → `dell'` stay; a trailing curly apostrophe is
  /// read as a straight one.
  static String _stripElision(String w) => w.replaceAll('’', "'");

  static final RegExp _word = RegExp(r"[\p{L}\p{M}]+(?:['’](?=\p{L}))?|\d+", unicode: true);

  /// [text] as tokens: words (aligned when [lookup] knows them) and the text
  /// between them (whitespace in `pre`, punctuation as non-word tokens).
  List<TokenRef> tokenize(String text) {
    final out = <TokenRef>[];
    var pos = 0;
    for (final m in _word.allMatches(text)) {
      final between = text.substring(pos, m.start);
      final word = m.group(0)!;
      final hit = lookup(word);
      _addBetween(out, between);
      final pre = out.isNotEmpty && !out.last.isWord && out.last.text.isEmpty ? out.removeLast().pre : '';
      out.add(TokenRef(word, pre: pre, itemId: hit?.$1, form: hit?.$2));
      pos = m.end;
    }
    _addBetween(out, text.substring(pos));
    if (out.isNotEmpty && !out.last.isWord && out.last.text.isEmpty) {
      final last = out.removeLast();
      if (last.pre.isNotEmpty) out.add(TokenRef('', pre: last.pre, isWord: false));
    }
    return out;
  }

  /// Punctuation runs become non-word tokens; trailing whitespace is kept as
  /// an empty placeholder whose `pre` the next word takes.
  static void _addBetween(List<TokenRef> out, String between) {
    if (between.isEmpty) return;
    final ws = RegExp(r'^\s*');
    var rest = between;
    while (rest.isNotEmpty) {
      final lead = ws.firstMatch(rest)!.group(0)!;
      rest = rest.substring(lead.length);
      if (rest.isEmpty) {
        out.add(TokenRef('', pre: lead, isWord: false));
        return;
      }
      final punct = RegExp(r'^\S+').firstMatch(rest)!.group(0)!;
      out.add(TokenRef(punct, pre: lead, isWord: false));
      rest = rest.substring(punct.length);
    }
  }
}
