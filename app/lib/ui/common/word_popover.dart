/// Tap a word for its translation: target-language sentences whose aligned
/// words show a small popover with the gloss in the source language (verbs:
/// lemma, person and tense; nouns: the article), and a link to the reference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import '../../engine/reference.dart';
import '../../providers.dart';
import '../routes.dart';
import '../theme/bw_skin.dart';
import '../bookmarks/bookmarks_ui.dart' show WordStarButton;
import 'pronounce_button.dart';

/// Decoration of a tappable word: a dotted underline (black in black & white).
TextStyle tappableWordStyle(BuildContext context, TextStyle? base) {
  final scheme = Theme.of(context).colorScheme;
  return (base ?? const TextStyle()).copyWith(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
    decorationColor: isMonochrome(scheme) ? kBwBlack : scheme.onSurfaceVariant,
    decorationThickness: 2,
  );
}

/// Builds the spans of [tokens]: words aligned to a known item become
/// tappable (`word-{keyPrefix}{index}` keys) when [enabled] says so; the rest
/// is plain text. [display] overrides the shown text of some tokens, and
/// [glossWord] the word named in the popover (spot the error: the correction).
List<InlineSpan> tokenSpans(
  BuildContext context, {
  required List<TokenRef> tokens,
  required CourseData? course,
  required String lang,
  TextStyle? style,
  bool Function(int index, TokenRef token)? enabled,
  int start = 0,
  int? end,
  String keyPrefix = '',
  Map<int, TextStyle> styles = const {},
}) {
  final spans = <InlineSpan>[];
  final stop = end ?? tokens.length;
  for (var i = start; i < stop; i++) {
    final t = tokens[i];
    if (t.pre.isNotEmpty) spans.add(TextSpan(text: t.pre));
    final own = styles[i] ?? style;
    final gloss = course == null || !t.isWord ? null : glossForTokenRef(course, t, lang);
    final on = gloss != null && (enabled?.call(i, t) ?? true);
    if (!on) {
      spans.add(TextSpan(text: t.text, style: styles[i]));
      continue;
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: TappableWord(key: ValueKey('word-$keyPrefix$i'), text: t.text, gloss: gloss, style: own),
      ),
    );
  }
  return spans;
}

/// One tappable word.
class TappableWord extends StatelessWidget {
  const TappableWord({super.key, required this.text, required this.gloss, this.style});
  final String text;
  final WordGloss gloss;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Semantics(
      button: true,
      hint: 'show translation',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          final rect = box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
          showWordPopover(context, gloss: gloss, anchor: rect);
        },
        child: Text(text, style: tappableWordStyle(context, base)),
      ),
    );
  }
}

/// A whole sentence with tappable words (used where the sentence stands alone).
class TappableSentence extends ConsumerWidget {
  const TappableSentence({
    super.key,
    required this.tokens,
    this.style,
    this.textAlign = TextAlign.start,
    this.enabled,
    this.keyPrefix = '',
    this.styles = const {},
  });

  final List<TokenRef> tokens;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool Function(int index, TokenRef token)? enabled;
  final String keyPrefix;
  final Map<int, TextStyle> styles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDataProvider).value;
    final lang = ref.watch(sourceLangProvider);
    return Text.rich(
      TextSpan(
        children: tokenSpans(
          context,
          tokens: tokens,
          course: course,
          lang: lang,
          style: style,
          enabled: enabled,
          keyPrefix: keyPrefix,
          styles: styles,
        ),
      ),
      textAlign: textAlign,
      style: style,
    );
  }
}

/// Before answering, words of the exercise's own item are not tappable (their
/// gloss or the reference link would give the answer away).
bool Function(int, TokenRef) hideItemUntilAnswered(Exercise e, {required bool answered}) {
  final item = _itemOf(e.facetId);
  return (_, t) => answered || t.itemId != item;
}

String? _itemOf(String facetId) {
  final hash = facetId.lastIndexOf('#');
  return hash <= 0 ? null : facetId.substring(0, hash);
}

/// An extra button at the bottom of a word popover (the reader's "Add to my
/// words"). The popover closes before [onPressed] runs.
class WordPopoverAction {
  const WordPopoverAction({required this.label, required this.icon, required this.onPressed, this.key});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Key? key;
}

/// Shows the popover for [gloss] next to [anchor] (global coordinates).
/// The reader adds a [detail] line (part of speech, gender), other readings
/// of the word ([also]) and [actions].
Future<void> showWordPopover(
  BuildContext context, {
  required WordGloss gloss,
  required Rect anchor,
  String? detail,
  List<String> also = const [],
  List<WordPopoverAction> actions = const [],
}) {
  final router = GoRouter.maybeOf(context);
  return Navigator.of(context, rootNavigator: true).push(
    _WordPopoverRoute(
      anchor: anchor,
      gloss: gloss,
      word: gloss.word,
      detail: detail,
      also: also,
      actions: actions,
      onOpenReference: router == null ? null : () => router.push(Routes.word(gloss.item.id)),
      capturedTheme: Theme.of(context),
    ),
  );
}

/// The popover for a word the course doesn't have (the reader): the word,
/// [message] ("Not in the Italian course"), the pronounce button and [actions].
Future<void> showPlainWordPopover(
  BuildContext context, {
  required String word,
  required String message,
  required Rect anchor,
  String? detail,
  List<WordPopoverAction> actions = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push(
    _WordPopoverRoute(
      anchor: anchor,
      word: word,
      message: message,
      detail: detail,
      actions: actions,
      onOpenReference: null,
      capturedTheme: Theme.of(context),
    ),
  );
}

class _WordPopoverRoute extends PopupRoute<void> {
  _WordPopoverRoute({
    required this.anchor,
    required this.word,
    this.gloss,
    this.message,
    this.detail,
    this.also = const [],
    this.actions = const [],
    required this.onOpenReference,
    required this.capturedTheme,
  });

  final Rect anchor;
  final WordGloss? gloss;
  final String word;
  final String? message;
  final String? detail;
  final List<String> also;
  final List<WordPopoverAction> actions;
  final VoidCallback? onOpenReference;
  final ThemeData capturedTheme;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Close translation';

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return Theme(
      data: capturedTheme,
      child: SafeArea(
        child: CustomSingleChildLayout(
          delegate: _PopoverLayout(anchor, MediaQuery.paddingOf(context)),
          child: _WordPopoverCard(
            gloss: gloss,
            word: word,
            message: message,
            detail: detail,
            also: also,
            actions: [
              for (final a in actions)
                WordPopoverAction(
                  key: a.key,
                  label: a.label,
                  icon: a.icon,
                  onPressed: () {
                    Navigator.of(context).pop();
                    a.onPressed();
                  },
                ),
            ],
            onOpenReference: onOpenReference == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onOpenReference!();
                  },
          ),
        ),
      ),
    );
  }
}

/// Below the word when there is room, else above it; kept on screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.padding);
  final Rect anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: (constraints.maxWidth - 16).clamp(0, 340), maxHeight: constraints.maxHeight - 16);

  @override
  Offset getPositionForChild(Size size, Size child) {
    // [anchor] is global; the layout box starts below the top padding.
    final a = anchor.shift(Offset(-padding.left, -padding.top));
    var x = a.center.dx - child.width / 2;
    x = x.clamp(8.0, (size.width - child.width - 8).clamp(8.0, double.infinity));
    var y = a.bottom + 6;
    if (y + child.height > size.height - 8) y = a.top - child.height - 6;
    y = y.clamp(8.0, (size.height - child.height - 8).clamp(8.0, double.infinity));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor || old.padding != padding;
}

class _WordPopoverCard extends StatelessWidget {
  const _WordPopoverCard({
    required this.gloss,
    required this.word,
    this.message,
    this.detail,
    this.also = const [],
    this.actions = const [],
    this.onOpenReference,
  });
  final WordGloss? gloss;
  final String word;
  final String? message;
  final String? detail;
  final List<String> also;
  final List<WordPopoverAction> actions;
  final VoidCallback? onOpenReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = isMonochrome(theme.colorScheme);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('word-popover'),
      color: mono ? kBwWhite : scheme.surfaceContainerHigh,
      elevation: mono ? 0 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: mono ? const BorderSide(color: kBwBlack, width: 3) : BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      gloss?.headline ?? word,
                      key: const ValueKey('word-popover-headline'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                // v0.5: hear the word (only with a voice for the language).
                PronounceButton(text: word, buttonKey: const ValueKey('word-popover-pronounce')),
                // v0.4: star the word for later.
                if (gloss case final g?) WordStarButton(itemId: g.item.id, buttonKey: const ValueKey('word-popover-star')),
              ],
            ),
            if (detail case final d?)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: Text(d, key: const ValueKey('word-popover-detail'), style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                switch (gloss) {
                  null => message ?? '—',
                  final g when g.glosses.isEmpty => '—',
                  final g => g.glosses.join(', '),
                },
                key: const ValueKey('word-popover-glosses'),
                style: gloss == null ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge,
              ),
            ),
            if (also.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: Text(
                  'Also: ${also.join('; ')}',
                  key: const ValueKey('word-popover-also'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (actions.isNotEmpty || onOpenReference != null)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    for (final a in actions)
                      TextButton.icon(
                        key: a.key,
                        onPressed: a.onPressed,
                        icon: Icon(a.icon, size: 18),
                        label: Text(a.label),
                      ),
                    if (onOpenReference != null)
                      TextButton.icon(
                        key: const ValueKey('word-popover-reference'),
                        onPressed: onOpenReference,
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        label: const Text('Open in reference'),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
