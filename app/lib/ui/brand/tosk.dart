/// Tosk, the red squirrel (Ratatosk), and the tosk wordmark: where the mascot
/// appears in the UI and which asset each moment uses. The art kit lives in
/// `assets/brand/` (docs/brand-overhaul.md); every pose has a colour and a
/// pure black & white (`-mono`) PNG, chosen by the theme. A missing file
/// renders nothing, so the UI never breaks on an asset gap.
library;

import 'package:flutter/material.dart';

import '../theme/bw_skin.dart';
import '../theme/tosk_palette.dart';

/// The mascot's poses (one PNG each, colour and mono).
enum ToskPose {
  /// Variant c: upright, confident, holding the scroll (course picker, about).
  standing,

  /// Lesson complete.
  celebrating,

  /// Reading: empty states with something to look forward to (no stories yet).
  thinking,

  /// Curled up: nothing due, nothing to review.
  sleeping,

  /// Explaining: first-time exercise intros.
  pointing,

  /// Head crop without a frame, for headers.
  head,

  /// Head in a round paper badge that reads at 40–56 px: the map marker.
  marker,
}

/// Asset paths of the brand kit. One place to change when the kit's file
/// names change.
abstract final class BrandAssets {
  static const dir = 'assets/brand/png';

  /// The PNG for [pose]; [mono] picks the black & white version.
  static String tosk(ToskPose pose, {bool mono = false}) {
    final name = switch (pose) {
      ToskPose.standing => 'tosk',
      ToskPose.celebrating => 'tosk-celebrate',
      ToskPose.thinking => 'tosk-reading',
      ToskPose.sleeping => 'tosk-sleeping',
      ToskPose.pointing => 'tosk-pointing',
      ToskPose.head => 'tosk-head',
      ToskPose.marker => 'tosk-marker',
    };
    return '$dir/$name${mono ? '-mono' : ''}.png';
  }
}

/// Tosk in a [pose], [height] px tall (the image keeps its aspect ratio).
/// Decorative unless [semanticsLabel] is given. In black & white the mono
/// version is shown. A missing asset draws nothing.
class ToskImage extends StatelessWidget {
  const ToskImage({super.key, required this.pose, required this.height, this.semanticsLabel, this.alignment = Alignment.center});

  final ToskPose pose;
  final double height;
  final String? semanticsLabel;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final mono = isBw(context);
    return SizedBox(
      height: height,
      child: Image.asset(
        BrandAssets.tosk(pose, mono: mono),
        key: ValueKey('tosk-image-${pose.name}${mono ? '-mono' : ''}'),
        height: height,
        fit: BoxFit.contain,
        alignment: alignment,
        filterQuality: FilterQuality.medium,
        semanticLabel: semanticsLabel,
        excludeFromSemantics: semanticsLabel == null,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// The wordmark: "tosk" in Gelasio Bold (the same outlines as the SVG
/// wordmark, so it stays text: selectable, scalable, and black in black & white).
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 40, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'tosk',
      key: const ValueKey('wordmark'),
      semanticsLabel: 'tosk',
      style: TextStyle(
        fontFamily: Tosk.serif,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1,
        letterSpacing: -size * 0.01,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Tosk next to the wordmark: the logo lock-up (settings' About, the course
/// picker header).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.pose = ToskPose.standing, this.height = 72, this.caption});

  final ToskPose pose;
  final double height;

  /// A line under the wordmark (the version, a tagline).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToskImage(pose: pose, height: height),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wordmark(size: height * 0.52),
              if (caption case final c?) ...[
                const SizedBox(height: 2),
                Text(c, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A mascot moment: Tosk above a title and a line of text (empty states,
/// the lesson summary header).
class ToskMoment extends StatelessWidget {
  const ToskMoment({
    super.key,
    required this.pose,
    required this.title,
    this.text,
    this.height = 120,
    this.titleKey,
  });

  final ToskPose pose;
  final String title;
  final String? text;
  final double height;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToskImage(pose: pose, height: height),
        const SizedBox(height: 12),
        Text(title, key: titleKey, textAlign: TextAlign.center, style: theme.textTheme.serifTitle),
        if (text case final t?) ...[
          const SizedBox(height: 6),
          Text(t, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
