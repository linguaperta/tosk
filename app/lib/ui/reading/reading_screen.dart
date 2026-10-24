/// `/read/:textId`: a saved text in the reader. Every word is looked up in the
/// active course ([ReadingText], `engine/reading.dart`); words the learner
/// doesn't know yet have a dotted underline (black in black & white), known
/// ones are plain or, with "Highlight known words", faintly highlighted
/// (a tint in colour, a thin grey underline in black & white). A tap on a
/// word opens the word popover: the gloss, part of speech and gender, the
/// grammar of the form (`andò → andare · lui/lei · passato remoto`), other
/// readings, ☆, "Add to my words" and "Read from here". The header says how
/// much of the text is known. Read aloud reads it sentence by sentence,
/// framing the sentence being read.
///
/// Long texts: the text is cut into lines (long lines into pieces) laid out
/// lazily by a `ListView.builder`; each piece is one `Text.rich` of plain
/// spans, and a tap is resolved to its word through the paragraph's layout,
/// so there is no widget per word. See docs/ui.md, "Reading".
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/engine.dart';
import '../../providers.dart';
import '../../speech/speech_providers.dart';
import '../common/async_view.dart';
import '../common/read_aloud.dart';
import '../common/word_popover.dart';
import '../my_words/my_words_providers.dart';
import '../my_words/my_words_screen.dart' show showMyWordSheet;
import '../reference/reference_screen.dart' show posLabel;
import '../routes.dart';
import '../theme/bw_skin.dart';
import 'reading_providers.dart';

class ReadingScreen extends ConsumerWidget {
  const ReadingScreen({super.key, required this.textId});
  final String textId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(readingTextProvider(textId));
    return AsyncView(
      value: text,
      onRetry: () => ref.invalidate(readingTextProvider(textId)),
      builder: (t) {
        final course = ref.watch(courseDataProvider).value;
        if (t == null || course == null) {
          return Scaffold(
            appBar: AppBar(leading: _back(context)),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This text is no longer saved.', key: ValueKey('reading-missing')),
              ),
            ),
          );
        }
        return _Reader(key: ValueKey('reader-$textId'), saved: t.$1, text: t.$2, course: course);
      },
    );
  }
}

Widget _back(BuildContext context) => BackButton(
  key: const ValueKey('reading-back'),
  onPressed: () => context.canPop() ? context.pop() : context.go(Routes.read),
);

class _Reader extends ConsumerStatefulWidget {
  const _Reader({super.key, required this.saved, required this.text, required this.course});
  final SavedText saved;
  final ReadingText text;
  final CourseData course;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  late final List<ReadingSentenceRef> _sentences = widget.text.sentences;

  late final ReadAloudController _aloud = ReadAloudController(
    speaker: ref.read(speakerProvider),
    languageCode: widget.course.meta.target,
    count: _sentences.length,
    textOf: (i) => widget.text.sentenceText(_sentences[i]),
    onSentence: _reveal,
  );

  @override
  void initState() {
    super.initState();
    _aloud.addListener(_onAloud);
  }

  void _onAloud() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _aloud.removeListener(_onAloud);
    _aloud.dispose(); // stops reading on leaving
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the paragraph of sentence [i] in view (estimating the offset
  /// first when the lazy list hasn't built it).
  void _reveal(int i) {
    final p = _sentences[i].paragraph;
    void ensure() {
      final c = _keys[p]?.currentContext;
      if (c != null && c.mounted) {
        unawaited(Scrollable.ensureVisible(
          c,
          alignment: 0.3,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: ref.read(reduceMotionProvider) ? Duration.zero : const Duration(milliseconds: 250),
        ));
      }
    }

    if (_keys[p]?.currentContext == null && _scroll.hasClients) {
      final n = widget.text.paragraphs.length;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((max * p / (n <= 1 ? 1 : n - 1)).clamp(0, max));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => ensure());
  }

  /// The learner knows [t]: a reading of it (or its phrase) is a practised
  /// item, or it is one of their practised own words.
  bool _known(ReadingToken t, ReadingParagraph p, Set<String> items, Map<String, UserWord> mine, Set<String> practised) {
    final analyses = t.phrase != null ? p.phrases[t.phrase!].analyses : t.analyses;
    if (analyses.any((a) => items.contains(a.itemId))) return true;
    final w = mine[readingKey(t.phrase != null ? p.phrases[t.phrase!].text : t.text)];
    return w != null && practised.contains(w.id);
  }

  (List<Set<int>>, ReadingCoverage)? _knownCache;
  Object? _knownKey;

  /// Known token indices per paragraph and the coverage (recomputed only
  /// when what the learner knows changes, not per read-aloud sentence).
  (List<Set<int>>, ReadingCoverage) _knownWords(Set<String> items, Map<String, UserWord> mine, Set<String> practised) {
    final key = (items, mine, practised);
    final cached = _knownCache;
    if (cached != null && _knownKey is (Set<String>, Map<String, UserWord>, Set<String>)) {
      final (a, b, c) = _knownKey! as (Set<String>, Map<String, UserWord>, Set<String>);
      if (identical(a, items) && identical(b, mine) && identical(c, practised)) return cached;
    }
    final text = widget.text;
    final knownTokens = HashSet<ReadingToken>.identity();
    final perParagraph = <Set<int>>[];
    for (final para in text.paragraphs) {
      final set = <int>{};
      for (var i = 0; i < para.tokens.length; i++) {
        final t = para.tokens[i];
        if (t.isWord && _known(t, para, items, mine, practised)) {
          set.add(i);
          knownTokens.add(t);
        }
      }
      perParagraph.add(set);
    }
    final out = (perParagraph, text.coverage(knownTokens.contains));
    _knownCache = out;
    _knownKey = key;
    return out;
  }

  Future<void> _tap(ReadingParagraph p, int paragraphIndex, int index, Rect anchor) async {
    final course = widget.course;
    final lang = ref.read(sourceLangProvider);
    final tok = p.tokens[index];
    final phrase = tok.phrase == null ? null : p.phrases[tok.phrase!];
    final word = phrase?.text ?? tok.text;
    final analyses = phrase?.analyses ?? tok.analyses;
    final sentence = p.sentenceText(p.sentenceAt(tok.start));
    final mine = ref.read(myWordsByFormProvider)[readingKey(word)];
    final voice = ref.read(canPronounceProvider);
    final sentenceIndex = _sentences.indexWhere((s) => s.paragraph == paragraphIndex && s.sentence == p.sentenceAt(tok.start));

    final actions = <WordPopoverAction>[
      if (mine == null)
        WordPopoverAction(
          key: const ValueKey('reading-add-word'),
          label: 'Add to my words',
          icon: Icons.bookmark_add_outlined,
          onPressed: () => unawaited(_addWord(word, analyses, sentence, lang)),
        )
      else
        WordPopoverAction(
          key: const ValueKey('reading-edit-word'),
          label: 'In my words',
          icon: Icons.bookmark_added_outlined,
          onPressed: () => unawaited(showMyWordSheet(context, ref, existing: mine)),
        ),
      if (voice && sentenceIndex >= 0)
        WordPopoverAction(
          key: const ValueKey('reading-read-from-here'),
          label: 'Read from here',
          icon: Icons.play_arrow,
          onPressed: () => unawaited(_aloud.play(sentenceIndex)),
        ),
    ];

    if (analyses.isEmpty) {
      await showPlainWordPopover(
        context,
        word: word,
        message: mine != null
            ? mine.translation
            : tok.isName
            ? 'Not in the course (a name?)'
            : 'Not in this course',
        detail: mine == null ? null : 'In my words${mine.note == null ? '' : ' · ${mine.note}'}',
        anchor: anchor,
        actions: actions,
      );
      return;
    }
    final first = analyses.first;
    final gloss = glossForToken(course, itemId: first.itemId, form: first.form, word: word, lang: lang);
    if (gloss == null) return;
    final known = ref.read(knownItemsProvider).value?.contains(first.itemId) ?? false;
    await showWordPopover(
      context,
      gloss: gloss,
      anchor: anchor,
      detail: _detail(course, gloss.item, known: known, mine: mine),
      also: _also(course, analyses, word, lang),
      actions: actions,
    );
  }

  /// `noun · masculine · plural: gatti · unit 3 · new to you`.
  static String _detail(CourseData course, Item item, {required bool known, UserWord? mine}) {
    final skills = CourseReference.of(course).skillsTeaching(item.id);
    final unit = skills.isEmpty ? null : course.units.where((u) => u.id == skills.first.unitId).firstOrNull;
    final unitNo = unit == null ? null : course.units.indexOf(unit) + 1;
    return [
      posLabel(item.pos),
      if (item.gender case final g?) _genderLabel(g),
      if (item.plural case final p?) 'plural: $p',
      if (unitNo != null) 'unit $unitNo',
      known ? 'known' : 'new to you',
      if (mine != null) 'in my words',
    ].join(' · ');
  }

  static String _genderLabel(String g) => g
      .split('|')
      .map((x) => switch (x) {
            'm' => 'masculine',
            'f' => 'feminine',
            'n' => 'neuter',
            'c' => 'common',
            _ => x,
          })
      .join(' / ');

  /// The other readings, the same item's persons of one tense joined
  /// (`lopen · jij / hij/zij · simple past`).
  static List<String> _also(CourseData course, List<WordAnalysis> analyses, String word, String lang) {
    final first = analyses.first;
    final out = <String>[];
    final byTense = <String, List<String>>{};
    for (final a in analyses.skip(1)) {
      final g = glossForToken(course, itemId: a.itemId, form: a.form, word: word, lang: lang);
      if (g == null) continue;
      if (a.itemId == first.itemId && g.tenseLabel != null && g.personLabel != null) {
        (byTense['${g.label} · ${g.tenseLabel}'] ??= []).add(g.personLabel!);
        continue;
      }
      final s = '${g.label}${[?g.personLabel, ?g.tenseLabel].map((x) => ' · $x').join()}: ${g.glosses.take(2).join(', ')}';
      if (!out.contains(s)) out.add(s);
    }
    final firstGloss = glossForToken(course, itemId: first.itemId, form: first.form, word: word, lang: lang);
    for (final e in byTense.entries) {
      final parts = e.key.split(' · ');
      final firstLabel = firstGloss == null ? null : '${firstGloss.label} · ${firstGloss.tenseLabel}';
      out.insert(0, e.key == firstLabel ? 'also ${e.value.join(' / ')}' : '${parts.first} · ${e.value.join(' / ')} · ${parts.skip(1).join(' · ')}');
    }
    return out.take(4).toList();
  }

  Future<void> _addWord(String word, List<WordAnalysis> analyses, String sentence, String lang) async {
    final course = widget.course;
    final first = analyses.firstOrNull;
    final item = first == null ? null : course.item(first.itemId);
    final gloss = first == null ? null : glossForToken(course, itemId: first.itemId, form: first.form, word: word, lang: lang);
    final formNote = gloss == null || (gloss.personLabel == null && gloss.tenseLabel == null) ? null : gloss.headline;
    final saved = await showMyWordSheet(
      context,
      ref,
      draft: MyWordDraft(
        word: item?.lemma ?? word,
        translation: item?.glosses(lang).take(3).join(', ') ?? '',
        note: formNote,
        example: sentence,
        lemmaId: item?.id,
        pos: item?.pos,
      ),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: const ValueKey('reading-word-added'), content: Text('Added "${saved.word}" to my words')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(knownItemsProvider).value ?? const <String>{};
    final mine = ref.watch(myWordsByFormProvider);
    final practised = ref.watch(myWordsPractisedProvider);
    final highlight = ref.watch(readingHighlightKnownProvider).value ?? false;
    final text = widget.text;
    final (known, coverage) = _knownWords(items, mine, practised);
    final current = _aloud.current == null ? null : _sentences[_aloud.current!];
    return Scaffold(
      appBar: AppBar(
        leading: _back(context),
        title: Text(widget.saved.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ReadAloudButtons(controller: _aloud, keyPrefix: 'reading-read-aloud'),
          IconButton(
            key: const ValueKey('reading-highlight-known'),
            tooltip: highlight ? 'Show known words plainly' : 'Highlight known words',
            isSelected: highlight,
            icon: const Icon(Icons.highlight_outlined),
            selectedIcon: const Icon(Icons.highlight),
            onPressed: () => unawaited(ref.read(readingHighlightKnownProvider.notifier).set(!highlight)),
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(coverage: coverage),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  key: const ValueKey('reading-text'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: text.paragraphs.length,
                  itemBuilder: (context, p) {
                    final para = text.paragraphs[p];
                    final next = p + 1 < text.paragraphs.length ? text.paragraphs[p + 1] : null;
                    return Padding(
                      key: _keys.putIfAbsent(p, GlobalKey.new),
                      // A blank line is a paragraph break; the pieces of one long line run on.
                      padding: EdgeInsets.only(bottom: next?.continued ?? false ? 0 : (para.isBlank ? 4 : 10)),
                      child: para.isBlank
                          ? const SizedBox(height: 8)
                          : _ParagraphView(
                              key: ValueKey('reading-p-$p'),
                              paragraph: para,
                              known: known[p],
                              highlightKnown: highlight,
                              speaking: current != null && current.paragraph == p ? para.sentences[current.sentence] : null,
                              style: theme.textTheme.titleMedium?.copyWith(height: 1.55, fontWeight: FontWeight.w400),
                              onTap: (i, rect) => unawaited(_tap(para, p, i, rect)),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "72% of words known · 180 words", with the legend.
class _Header extends StatelessWidget {
  const _Header({required this.coverage});
  final ReadingCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final c = coverage;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: mono ? kBwWhite : theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: mono ? kBwBlack : theme.colorScheme.outlineVariant, width: mono ? 2 : 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 688),
          child: Wrap(
            spacing: 12,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${c.percent}% of words known',
                key: const ValueKey('reading-known'),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text('${c.known} of ${c.words} words', key: const ValueKey('reading-counts'), style: theme.textTheme.bodySmall),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'new to you', style: _unknownStyle(context, theme.textTheme.bodySmall)),
                    const TextSpan(text: ' · tap any word'),
                  ],
                ),
                key: const ValueKey('reading-legend'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A word the learner doesn't know yet: a dotted underline (black in black & white).
TextStyle _unknownStyle(BuildContext context, TextStyle? base) {
  final scheme = Theme.of(context).colorScheme;
  return (base ?? const TextStyle()).copyWith(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
    decorationColor: isMonochrome(scheme) ? kBwBlack : scheme.onSurfaceVariant,
    decorationThickness: 2,
  );
}

/// One paragraph (or piece of a long line): plain spans, a tap resolved to a
/// word through the layout, and the frame of the sentence being read.
class _ParagraphView extends StatefulWidget {
  const _ParagraphView({
    super.key,
    required this.paragraph,
    required this.known,
    required this.highlightKnown,
    required this.speaking,
    required this.style,
    required this.onTap,
  });

  final ReadingParagraph paragraph;

  /// Token indices of known words.
  final Set<int> known;
  final bool highlightKnown;

  /// The range of the sentence being read aloud, if it is in this paragraph.
  final (int, int)? speaking;
  final TextStyle? style;
  final void Function(int token, Rect globalRect) onTap;

  @override
  State<_ParagraphView> createState() => _ParagraphViewState();
}

class _ParagraphViewState extends State<_ParagraphView> {
  final _text = GlobalKey();

  RenderParagraph? get _render => _text.currentContext?.findRenderObject() as RenderParagraph?;

  void _onTapUp(TapUpDetails d) {
    final r = _render;
    if (r == null) return;
    final pos = r.getPositionForOffset(d.localPosition);
    final p = widget.paragraph;
    for (final o in [pos.offset, pos.offset - 1]) {
      final i = p.tokenAt(o);
      if (i == null || !p.tokens[i].isWord || p.tokens[i].isNumber) continue;
      final t = p.tokens[i];
      final boxes = r.getBoxesForSelection(TextSelection(baseOffset: t.start, extentOffset: t.end));
      final hit = boxes.any((b) => b.toRect().inflate(6).contains(d.localPosition));
      if (!hit) continue;
      var rect = boxes.first.toRect();
      for (final b in boxes.skip(1)) {
        rect = rect.expandToInclude(b.toRect());
      }
      final origin = r.localToGlobal(Offset.zero);
      widget.onTap(i, rect.shift(origin));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paragraph;
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    final mono = isMonochrome(scheme);
    final knownStyle = widget.highlightKnown
        ? (mono
              ? base.copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.solid,
                  decorationColor: kBwGray,
                  decorationThickness: 1,
                )
              : base.copyWith(backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.6)))
        : base;
    final unknown = _unknownStyle(context, base);
    final spans = <InlineSpan>[];
    var pos = 0;
    for (var i = 0; i < p.tokens.length; i++) {
      final t = p.tokens[i];
      if (t.start > pos) spans.add(TextSpan(text: p.text.substring(pos, t.start)));
      final style = !t.isWord || t.isNumber
          ? null
          : widget.known.contains(i)
          ? knownStyle
          : t.isName
          ? null
          : unknown;
      spans.add(TextSpan(text: t.text, style: style));
      pos = t.end;
    }
    if (pos < p.text.length) spans.add(TextSpan(text: p.text.substring(pos)));
    final speaking = widget.speaking;
    Widget text = Text.rich(TextSpan(children: spans), key: _text, style: base);
    if (speaking != null) {
      text = CustomPaint(
        key: const ValueKey('reading-speaking'),
        painter: _SentenceFramePainter(
          paragraph: _text,
          range: speaking,
          fill: mono ? null : scheme.primaryContainer.withValues(alpha: 0.35),
          border: mono ? kBwBlack : scheme.primary,
        ),
        child: text,
      );
    }
    return Semantics(
      hint: 'Tap a word for its meaning',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: _onTapUp, child: text),
    );
  }
}

/// Frames the sentence being read aloud: a box round each of its lines
/// (2 px; filled with a tint in colour), drawn behind the text.
class _SentenceFramePainter extends CustomPainter {
  _SentenceFramePainter({required this.paragraph, required this.range, required this.fill, required this.border});
  final GlobalKey paragraph;
  final (int, int) range;
  final Color? fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final r = paragraph.currentContext?.findRenderObject();
    if (r is! RenderParagraph || !r.hasSize) return;
    final (from, to) = range;
    final text = r.text.toPlainText();
    var start = from;
    var end = to.clamp(0, text.length);
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    if (end <= start) return;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = border;
    final paintFill = fill == null ? null : (Paint()..color = fill!);
    for (final b in r.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))) {
      final rect = RRect.fromRectAndRadius(b.toRect().inflate(2), const Radius.circular(4));
      if (paintFill != null) canvas.drawRRect(rect, paintFill);
      canvas.drawRRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(_SentenceFramePainter old) => old.range != range || old.fill != fill || old.border != border;
}
