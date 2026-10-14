import 'package:flutter/material.dart';

import '../../progression/progression.dart';
import '../theme/bw_skin.dart';
import 'progression_colors.dart';

/// Grid of verb cards; each tense is a pill that lights up with mastery.
class VerbCollectionView extends StatelessWidget {
  const VerbCollectionView({
    super.key,
    required this.collection,
    this.tenseLabel,
    this.lang = 'en',
    this.reduceMotion = false,
    this.onVerbTap,
    this.padding = const EdgeInsets.all(12),
  });

  final VerbCollection collection;

  /// Display name of a tense (e.g. from `CourseMeta.tenseLabel`); defaults to the id with spaces.
  final String Function(String tense)? tenseLabel;

  /// Source language for glosses.
  final String lang;
  final bool reduceMotion;
  final ValueChanged<VerbCard>? onVerbTap;
  final EdgeInsetsGeometry padding;

  String _label(String t) => tenseLabel?.call(t) ?? t.replaceAll('_', ' ');

  /// Card height: padding + lemma + gloss + one pill row per tense, scaled with text size.
  static double _cardExtent(TextScaler ts, int cells) =>
      36 + ts.scale(24) + ts.scale(18) + cells * (4 + TensePill.heightFor(ts));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mastered = collection.count(VerbMastery.mastered);
    final known = collection.count(VerbMastery.known);
    final total = collection.totalTables;
    final maxCells = collection.verbs.fold<int>(0, (m, v) => v.cells.length > m ? v.cells.length : m);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$mastered of $total tables mastered', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: total == 0 ? 0 : (mastered + known * 0.5) / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: ProgressionColors.gold(theme.colorScheme),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final m in VerbMastery.values)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ProgressionColors.masteryFill(m, theme.colorScheme),
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${masteryLabel(m)} ${collection.count(m)}', style: theme.textTheme.labelSmall),
                ]),
            ],
          ),
        ],
      ),
    );
    if (collection.verbs.isEmpty) {
      return Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          header,
          Text('No verbs in this course yet.', style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverPadding(
          padding: padding,
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: _cardExtent(MediaQuery.textScalerOf(context), maxCells),
            ),
            itemCount: collection.verbs.length,
            itemBuilder: (context, i) => VerbCardTile(
              card: collection.verbs[i],
              tenseLabel: _label,
              lang: lang,
              reduceMotion: reduceMotion,
              onTap: onVerbTap == null ? null : () => onVerbTap!(collection.verbs[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// One verb with its tense pills.
class VerbCardTile extends StatelessWidget {
  const VerbCardTile({
    super.key,
    required this.card,
    required this.tenseLabel,
    this.lang = 'en',
    this.reduceMotion = false,
    this.onTap,
  });

  final VerbCard card;
  final String Function(String tense) tenseLabel;
  final String lang;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final complete = card.isComplete;
    return Card(
      key: ValueKey('verb-${card.itemId}'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: complete ? ProgressionColors.gold(cs) : cs.outlineVariant,
          width: complete ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(card.lemma,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
                if (complete) Icon(Icons.star, size: 18, color: ProgressionColors.gold(cs)),
              ]),
              Text(card.item.gloss(lang),
                  style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              for (final c in card.cells)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TensePill(cell: c, label: tenseLabel(c.tense), reduceMotion: reduceMotion),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tense "chip" colored by mastery; mastered ones glow.
class TensePill extends StatelessWidget {
  const TensePill({super.key, required this.cell, required this.label, this.reduceMotion = false});

  final VerbTenseCell cell;
  final String label;
  final bool reduceMotion;

  /// Pill height for a text scaler (fits a labelMedium line).
  static double heightFor(TextScaler ts) {
    final h = ts.scale(17) + 9;
    return h < 26 ? 26 : h;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = cell.mastery;
    final fill = ProgressionColors.masteryFill(m, cs);
    final text = ProgressionColors.masteryText(m, cs);
    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(13),
      // Black & white: unseen gray outline, learning thin, known thick,
      // mastered inverted (plus the check / sparkle icons).
      border: isMonochrome(cs)
          ? Border.all(
              color: m == VerbMastery.unseen ? kBwGray : kBwBlack,
              width: m == VerbMastery.known ? 3 : (m == VerbMastery.learning ? 1.5 : kBwBorder),
            )
          : (m == VerbMastery.unseen ? Border.all(color: cs.outlineVariant) : null),
      boxShadow: m == VerbMastery.mastered && !isMonochrome(cs)
          ? [BoxShadow(color: fill.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 0.5)]
          : null,
    );
    final content = Row(
      children: [
        Expanded(
          child: Text(label,
              style: theme.textTheme.labelMedium?.copyWith(color: text), overflow: TextOverflow.ellipsis),
        ),
        if (m == VerbMastery.mastered) Icon(Icons.auto_awesome, size: 14, color: text),
        if (m == VerbMastery.known) Icon(Icons.check, size: 14, color: text),
      ],
    );
    const padding = EdgeInsets.symmetric(horizontal: 10);
    final height = heightFor(MediaQuery.textScalerOf(context));
    return Semantics(
      label: '$label: ${masteryLabel(m)}',
      excludeSemantics: true,
      child: reduceMotion
          ? Container(
              key: ValueKey('pill-${cell.facetId}'),
              height: height,
              padding: padding,
              decoration: decoration,
              child: content,
            )
          : AnimatedContainer(
              key: ValueKey('pill-${cell.facetId}'),
              duration: const Duration(milliseconds: 400),
              height: height,
              padding: padding,
              decoration: decoration,
              child: content,
            ),
    );
  }
}

/// A full page around [VerbCollectionView].
class VerbCollectionPage extends StatelessWidget {
  const VerbCollectionPage({
    super.key,
    required this.collection,
    this.tenseLabel,
    this.lang = 'en',
    this.reduceMotion = false,
    this.title = 'Verb collection',
  });

  final VerbCollection collection;
  final String Function(String tense)? tenseLabel;
  final String lang;
  final bool reduceMotion;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: VerbCollectionView(
          collection: collection,
          tenseLabel: tenseLabel,
          lang: lang,
          reduceMotion: reduceMotion,
        ),
      );
}
