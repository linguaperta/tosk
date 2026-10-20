/// The story reader: the text sentence by sentence (Continue reveals the
/// next), every aligned word tappable, a translation toggle per sentence, then
/// the comprehension questions and a result. Finishing records one story read
/// event (`kStoryReadType`, see docs/ARCHITECTURE.md, "Stories").
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../theme/tosk_palette.dart';
import '../../core/core.dart';
import '../../engine/engine.dart' show tokenRefsOf;
import '../../progression/xp.dart';
import '../../providers.dart';
import '../common/async_view.dart';
import '../common/word_popover.dart';
import '../lesson/exercises/common.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';
import 'story_providers.dart';

enum _Phase { reading, questions, result }

/// A stable seed (FNV-1a) so a story's options keep their order everywhere.
int _seed(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

class StoryReaderScreen extends ConsumerWidget {
  const StoryReaderScreen({super.key, required this.storyId});
  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider);
    return AsyncView(
      value: course,
      builder: (c) {
        final story = c.story(storyId);
        if (story == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This story is not in the course.')),
          );
        }
        return _Reader(key: ValueKey('story-${story.id}'), course: c, story: story);
      },
    );
  }
}

class _Reader extends ConsumerStatefulWidget {
  const _Reader({super.key, required this.course, required this.story});
  final CourseData course;
  final Story story;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader> {
  final _scroll = ScrollController();
  final _watch = Stopwatch()..start();
  final _translated = <int>{};
  _Phase _phase = _Phase.reading;
  int _shown = 1;
  int _q = 0;
  final _answers = <int, int>{}; // question -> chosen option (display order)
  late final List<List<int>> _order; // question -> option indices in display order
  int? _xp;
  bool _saving = false;

  Story get story => widget.story;

  @override
  void initState() {
    super.initState();
    // Options in a stable, story-specific order (the source lists the right one first).
    _order = [
      for (var i = 0; i < story.questions.length; i++)
        List.generate(story.questions[i].options.length, (k) => k)..shuffle(math.Random(_seed('${story.id}#$i'))),
    ];
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _correct => [
    for (final e in _answers.entries)
      if (_order[e.key][e.value] == story.questions[e.key].correct) e,
  ].length;

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (ref.read(reduceMotionProvider)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _next() {
    switch (_phase) {
      case _Phase.reading:
        if (_shown < story.sentences.length) {
          setState(() => _shown++);
          _toEnd();
        } else if (story.questions.isEmpty) {
          _finish();
        } else {
          setState(() => _phase = _Phase.questions);
        }
      case _Phase.questions:
        if (_q + 1 < story.questions.length) {
          setState(() => _q++);
        } else {
          _finish();
        }
      case _Phase.result:
        context.pop();
    }
  }

  void _answer(int shownIndex) {
    if (_answers.containsKey(_q)) return;
    final right = _order[_q][shownIndex] == story.questions[_q].correct;
    setState(() => _answers[_q] = shownIndex);
    final fx = ref.read(fxProvider);
    final sounds = ref.read(soundServiceProvider);
    if (right) {
      fx.correct();
      sounds.correct();
    } else {
      fx.wrong();
      sounds.wrong();
    }
  }

  /// Appends the story read event and shows the result.
  Future<void> _finish() async {
    if (_saving) return;
    _saving = true;
    final store = ref.read(progressStoreProvider);
    final facet = storyFacetId(widget.course.meta.id, story.id);
    final event = ReviewEvent(
      id: const Uuid().v4(),
      facetId: facet,
      at: ref.read(clockProvider)().toUtc(),
      rating: Rating.good,
      exerciseType: kStoryReadType,
      inputMode: InputMode.tap,
      responseMs: _watch.elapsedMilliseconds,
      correct: true,
      answer: '$_correct/${story.questions.length}',
      sessionId: const Uuid().v4(),
      mode: kStoryMode,
    );
    int? xp;
    try {
      final before = await store.state(facet);
      xp = const XpRules().xpFor(event, before, ref.read(schedulerProvider));
      await store.record(event);
      ref.read(progressRevisionProvider.notifier).bump();
    } catch (_) {
      xp = null; // the result still shows; nothing was recorded
    }
    if (!mounted) return;
    ref.read(fxProvider).finished();
    ref.read(soundServiceProvider).complete();
    setState(() {
      _xp = xp;
      _phase = _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(sourceLangProvider);
    final unlocked = ref.watch(storyUnitsUnlockedProvider).value?.contains(story.unitId) ?? true;
    final total = story.sentences.length + story.questions.length;
    final done = switch (_phase) {
      _Phase.reading => _shown,
      _Phase.questions => story.sentences.length + _q + (_answers.containsKey(_q) ? 1 : 0),
      _Phase.result => total,
    };
    final (Widget body, String label, bool enabled, Key key) = switch (_phase) {
      _Phase.reading => (
        _reading(context, lang, unlocked),
        _shown < story.sentences.length ? 'Continue' : (story.questions.isEmpty ? 'Finish' : 'Questions'),
        true,
        ValueKey(_shown < story.sentences.length ? 'story-next' : 'story-to-questions'),
      ),
      _Phase.questions => (
        _question(context, lang),
        _q + 1 < story.questions.length ? 'Next question' : 'Finish',
        _answers.containsKey(_q),
        const ValueKey('story-question-next'),
      ),
      _Phase.result => (_result(context), 'Done', true, const ValueKey('story-done')),
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('story-close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(story.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            key: const ValueKey('story-progress'),
            value: total == 0 ? 1 : done / total,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          // Continue / Next / Done pinned at the bottom (thumb zone), clear of
          // the system navigation bar (edge-to-edge).
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: key,
                      onPressed: enabled ? _next : null,
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(label)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(List<Widget> children, {ScrollController? controller, Key? key}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(key: key, controller: controller, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: children),
    ),
  );

  Widget _reading(BuildContext context, String lang, bool unlocked) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    final newWords = [for (final id in story.newWords) ?widget.course.item(id)];
    return _column(
      key: const ValueKey('story-text'),
      controller: _scroll,
      [
        if (!unlocked)
          _Note(
            key: const ValueKey('story-preview-note'),
            icon: Icons.lock_outline,
            text: 'Preview: this story uses the words and grammar of the whole unit. '
                'It opens once you have started every skill there.',
          ),
        Text(pickLang(story.titleTr, lang), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final it in newWords)
          _Note(
            key: ValueKey('story-new-word-${it.id}'),
            icon: Icons.fiber_new_outlined,
            text: 'New word: ${it.article == null ? '' : '${it.article} '}${it.lemma} = ${it.glosses(lang).take(2).join(', ')}',
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < _shown && i < story.sentences.length; i++)
          _SentenceRow(
            key: ValueKey('story-sentence-$i'),
            index: i,
            sentence: story.sentences[i],
            translated: _translated.contains(i),
            lang: lang,
            latest: i == _shown - 1 && !mono,
            onToggle: () => setState(() => _translated.contains(i) ? _translated.remove(i) : _translated.add(i)),
          ),
      ],
    );
  }

  Widget _question(BuildContext context, String lang) {
    final theme = Theme.of(context);
    final q = story.questions[_q];
    final answered = _answers[_q];
    final explanation = pickLang(q.explanationTr, lang);
    // The question at the top, the options at the bottom (thumb zone); taller
    // content scrolls.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: ValueKey('story-question-$_q'),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight, maxWidth: 640),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Question ${_q + 1} of ${story.questions.length}', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    if (q.prompt case final p?) ...[
                      Text(p, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(pickLang(q.promptTr, lang), style: theme.textTheme.bodyLarge),
                    ] else
                      Text(pickLang(q.promptTr, lang), style: theme.textTheme.titleLarge),
                    const Spacer(),
                    const SizedBox(height: 16),
                    for (var k = 0; k < _order[_q].length; k++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OptionButton(
                          key: ValueKey('story-option-$k'),
                          label: q.options[_order[_q][k]].label(lang),
                          number: k + 1,
                          state: answered == null
                              ? OptionState.idle
                              : _order[_q][k] == q.correct
                              ? OptionState.correct
                              : k == answered
                              ? OptionState.wrong
                              : OptionState.dimmed,
                          onTap: answered == null ? () => _answer(k) : null,
                        ),
                      ),
                    if (answered != null) ...[
                      _Verdict(right: _order[_q][answered] == q.correct),
                      if (explanation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(explanation, key: const ValueKey('story-explanation'), style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final n = story.questions.length;
    final xp = _xp;
    return _column(key: const ValueKey('story-result'), [
      const SizedBox(height: 24),
      Icon(Icons.auto_stories, size: 64, color: isBw(context) ? kBwBlack : theme.colorScheme.primary),
      const SizedBox(height: 12),
      Text('Story complete!', textAlign: TextAlign.center, style: theme.textTheme.serifHeadline),
      const SizedBox(height: 8),
      if (n > 0)
        Text(
          '$_correct of $n questions right',
          key: const ValueKey('story-score'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      if (xp != null)
        Text('+$xp XP', key: const ValueKey('story-xp'), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
      const SizedBox(height: 16),
      Center(
        child: TextButton.icon(
          key: const ValueKey('story-all'),
          onPressed: () => context.go(Routes.stories),
          icon: const Icon(Icons.list),
          label: const Text('All stories'),
        ),
      ),
    ]);
  }
}

/// One sentence: tappable words, and a button that shows its translation.
class _SentenceRow extends StatelessWidget {
  const _SentenceRow({
    super.key,
    required this.index,
    required this.sentence,
    required this.translated,
    required this.lang,
    required this.latest,
    required this.onToggle,
  });
  final int index;
  final Sentence sentence;
  final bool translated;
  final String lang;
  final bool latest;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = sentence.translation(lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TappableSentence(
                    tokens: tokenRefsOf(sentence),
                    keyPrefix: 's$index-',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: latest ? FontWeight.w600 : null,
                    ),
                  ),
                  if (translated && tr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr,
                        key: ValueKey('story-translation-$index'),
                        style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: ValueKey('story-translate-$index'),
            tooltip: translated ? 'Hide translation' : 'Show translation',
            isSelected: translated,
            onPressed: onToggle,
            icon: const Icon(Icons.translate),
            selectedIcon: const Icon(Icons.subtitles_off_outlined),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isBw(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mono ? kBwWhite : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: mono ? Border.all(color: kBwBlack, width: kBwBorder) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: mono ? kBwBlack : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// ✓ Right / ✗ Not quite, with an icon and words (never color alone).
class _Verdict extends StatelessWidget {
  const _Verdict({required this.right});
  final bool right;

  @override
  Widget build(BuildContext context) {
    final fb = FeedbackColors.of(context);
    final color = right ? fb.correct : fb.wrong;
    return Row(
      key: ValueKey(right ? 'story-verdict-right' : 'story-verdict-wrong'),
      children: [
        Icon(right ? Icons.check_circle_outline : Icons.highlight_off, color: color),
        const SizedBox(width: 8),
        Text(
          right ? 'Right!' : 'Not quite',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
