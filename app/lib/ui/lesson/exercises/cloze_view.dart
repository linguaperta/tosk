import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/core.dart';
import '../../../engine/reference.dart';
import '../../../providers.dart';
import '../../common/word_popover.dart';
import '../answer_input.dart';
import 'common.dart';

/// Fill the gap in a sentence: choice chips when the engine gives options, else
/// free input through the pluggable [AnswerInputWidget] (keyboard now, ink later).
class ClozeView extends ExerciseWidget<ClozeExercise> {
  const ClozeView({
    super.key,
    required super.exercise,
    required super.onChanged,
    super.onCheck,
    super.result,
    super.keys,
    super.reduceMotion,
    this.inputBuilder = keyboardAnswerInputBuilder,
    this.typed = false,
  });

  final AnswerInputBuilder inputBuilder;

  /// Typing mode: free text even when the engine sent options.
  final bool typed;

  @override
  State<ClozeView> createState() => _ClozeViewState();
}

class _ClozeViewState extends State<ClozeView> with ExerciseKeysMixin<ClozeView> {
  int? _selected;
  String _typed = '';

  void _select(int i) {
    if (widget.locked) return;
    setState(() => _selected = i);
    widget.onChanged(ChoiceAnswer(i));
  }

  @override
  void onDigit(int n) {
    final options = widget.typed ? null : widget.exercise.options;
    if (options != null && n >= 1 && n <= options.length) _select(n - 1);
  }

  /// The sentence with its gap. Words aligned to course items are tappable
  /// for their translation, except (before checking) those of the asked item;
  /// once checked the filled gap is tappable too.
  Widget _sentence(BuildContext context, WidgetRef ref, String gapText, Color gapColor) {
    final e = widget.exercise;
    final result = widget.result;
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    final style = Theme.of(context).textTheme.headlineSmall;
    Widget gap = Container(
      key: const ValueKey('cloze-gap'),
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: gapColor, width: 2)),
      ),
      child: Text(
        gapText.isEmpty ? ' ' : gapText,
        textAlign: TextAlign.center,
        style: style?.copyWith(color: gapColor),
      ),
    );
    var before = <InlineSpan>[TextSpan(text: e.before)];
    var after = <InlineSpan>[TextSpan(text: e.after)];
    final tokens = e.tokens, from = e.gapFrom, to = e.gapTo;
    if (tokens != null && from != null && to != null && from >= 0 && from <= to && to < tokens.length) {
      final head = renderTokenRefs(tokens.take(from));
      final tail = renderTokenRefs(tokens.skip(to + 1));
      if (e.before.startsWith(head) && e.after.endsWith(tail)) {
        final enabled = hideItemUntilAnswered(e, answered: result != null);
        before = [
          ...tokenSpans(context, tokens: tokens, course: course, lang: lang, style: style, end: from, enabled: enabled),
          TextSpan(text: e.before.substring(head.length)),
        ];
        after = [
          TextSpan(text: e.after.substring(0, e.after.length - tail.length)),
          ...tokenSpans(
            context,
            tokens: tokens,
            course: course,
            lang: lang,
            style: style,
            start: to + 1,
            enabled: enabled,
          ),
        ];
        final hash = e.facetId.lastIndexOf('#');
        final item = hash < 0 ? e.facetId : e.facetId.substring(0, hash);
        final inGap = [
          for (final t in tokens.sublist(from, to + 1))
            if (t.itemId != null) t,
        ];
        final gapToken = inGap.where((t) => t.itemId == item).firstOrNull ?? inGap.firstOrNull;
        final gloss = result == null || course == null || gapToken == null
            ? null
            : glossForTokenRef(course, gapToken, lang, word: e.expected);
        if (gloss != null) {
          final box = gap;
          gap = Builder(
            builder: (context) => Semantics(
              button: true,
              hint: 'show translation',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final r = context.findRenderObject() as RenderBox?;
                  final rect = r == null ? Rect.zero : r.localToGlobal(Offset.zero) & r.size;
                  showWordPopover(context, gloss: gloss, anchor: rect);
                },
                child: box,
              ),
            ),
          );
        }
      }
    }
    return Text.rich(
      key: const ValueKey('cloze-sentence'),
      TextSpan(
        children: [
          ...before,
          WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: gap),
          ...after,
        ],
      ),
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final theme = Theme.of(context);
    final fb = FeedbackColors.of(context);
    final options = widget.typed ? null : e.options;
    final result = widget.result;

    final String gapText;
    if (options != null) {
      gapText = _selected == null ? '' : options[_selected!];
    } else {
      gapText = _typed;
    }
    final gapColor = result == null ? theme.colorScheme.secondary : (result.correct ? fb.correct : fb.wrong);

    return ExerciseLayout(
      prompt: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InstructionText(e.instruction),
          Consumer(builder: (context, ref, _) => _sentence(context, ref, gapText, gapColor)),
          if (e.hint != null) ...[const SizedBox(height: 12), SubtleText(e.hint!, icon: Icons.lightbulb_outline)],
          if (e.translation != null) ...[
            const SizedBox(height: 8),
            SubtleText(e.translation!, italic: true, icon: Icons.translate),
          ],
        ],
      ),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (options != null)
            ChoiceGrid(
              options: [
                for (var i = 0; i < options.length; i++)
                  ChoiceOption(
                    key: ValueKey('cloze-option-$i'),
                    number: i + 1,
                    label: options[i],
                    state: choiceState(
                      index: i,
                      selected: _selected,
                      correctIndex: e.correctIndex ?? -1,
                      result: result,
                    ),
                    onTap: widget.locked ? null : () => _select(i),
                  ),
              ],
            )
          else
            widget.inputBuilder(
              enabled: !widget.locked,
              hintText: 'Type the missing word',
              preContext: e.before,
              onChanged: (answer) {
                setState(() => _typed = answer?.text.trim() ?? '');
                widget.onChanged(answer);
              },
              onSubmitted: widget.onCheck,
            ),
        ],
      ),
    );
  }
}
