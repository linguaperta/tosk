/// The tosk palette (storybook ink style, docs/brand-overhaul.md): warm sepia
/// ink on parchment, russet fur, bark, ash leaves and three metals. The light
/// theme is paper; the dark theme is deep bark with paper-coloured text and
/// the same accents. Black & white (e-ink) is a separate skin (`bw_skin.dart`).
library;

import 'package:flutter/material.dart';

abstract final class Tosk {
  static const ink = Color(0xFF3B2A1F);
  static const paper = Color(0xFFF7F0E2);
  static const fur = Color(0xFFC96A3B);
  static const furDark = Color(0xFF9C4C27);
  static const furLight = Color(0xFFE8A872);
  static const cream = Color(0xFFF4E5C8);
  static const bark = Color(0xFF8E6C4E);
  static const barkDark = Color(0xFF5B4333);
  static const leaf = Color(0xFF7E9B5F);
  static const leafDark = Color(0xFF55733F);
  static const gold = Color(0xFFD8B15C);
  static const silver = Color(0xFFB9BDBD);
  static const bronze = Color(0xFFB5713E);

  // Derived shades (not in the brand sheet; used for containers and the dark theme).
  static const paperLow = Color(0xFFF1E8D5);
  static const paperMid = Color(0xFFEADFC7);
  static const paperHigh = Color(0xFFE3D5B9);
  static const paperHighest = Color(0xFFDBCBAB);
  static const leafTint = Color(0xFFDCE4C8);
  static const inkSoft = Color(0xFF6B5443);
  static const ruleSoft = Color(0xFFD6C8AE);
  static const error = Color(0xFF9E3B2E);
  static const errorTint = Color(0xFFF5D5CC);

  static const night = Color(0xFF221912);
  static const nightLow = Color(0xFF2B2119);
  static const nightMid = Color(0xFF352A20);
  static const nightHigh = Color(0xFF3F3227);
  static const nightHighest = Color(0xFF4A3B2E);
  static const nightRule = Color(0xFF5E4C3D);
  static const furNight = Color(0xFF7A3B1E);
  static const leafNight = Color(0xFF3B4F2C);
  static const leafLight = Color(0xFFA9C28C);
  static const paperSoft = Color(0xFFD9CDB6);

  /// Heading and wordmark font (SIL OFL, `assets/fonts/`).
  static const serif = 'Gelasio';
}

/// The light scheme: parchment surfaces, sepia text, russet primary, leaf
/// secondary, bark tertiary.
ColorScheme toskLightScheme() => ColorScheme.fromSeed(seedColor: Tosk.fur, brightness: Brightness.light).copyWith(
  primary: Tosk.furDark,
  onPrimary: Tosk.paper,
  primaryContainer: Tosk.furLight,
  onPrimaryContainer: Tosk.ink,
  secondary: Tosk.leafDark,
  onSecondary: Tosk.paper,
  secondaryContainer: Tosk.leafTint,
  onSecondaryContainer: Tosk.ink,
  tertiary: Tosk.barkDark,
  onTertiary: Tosk.paper,
  tertiaryContainer: Tosk.cream,
  onTertiaryContainer: Tosk.ink,
  error: Tosk.error,
  onError: Tosk.paper,
  errorContainer: Tosk.errorTint,
  onErrorContainer: Tosk.ink,
  surface: Tosk.paper,
  onSurface: Tosk.ink,
  surfaceDim: Tosk.paperHigh,
  surfaceBright: Tosk.paper,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Tosk.paperLow,
  surfaceContainer: Tosk.paperMid,
  surfaceContainerHigh: Tosk.paperHigh,
  surfaceContainerHighest: Tosk.paperHighest,
  onSurfaceVariant: Tosk.inkSoft,
  outline: Tosk.bark,
  outlineVariant: Tosk.ruleSoft,
  inverseSurface: Tosk.ink,
  onInverseSurface: Tosk.paper,
  inversePrimary: Tosk.furLight,
  surfaceTint: Tosk.furDark,
  shadow: Tosk.ink,
  scrim: Tosk.ink,
);

/// The dark scheme: deep bark surfaces, paper text, sunlit-fur primary.
ColorScheme toskDarkScheme() => ColorScheme.fromSeed(seedColor: Tosk.fur, brightness: Brightness.dark).copyWith(
  primary: Tosk.furLight,
  onPrimary: Tosk.ink,
  primaryContainer: Tosk.furNight,
  onPrimaryContainer: Tosk.cream,
  secondary: Tosk.leafLight,
  onSecondary: Tosk.ink,
  secondaryContainer: Tosk.leafNight,
  onSecondaryContainer: Tosk.paper,
  tertiary: Tosk.cream,
  onTertiary: Tosk.ink,
  tertiaryContainer: Tosk.nightHighest,
  onTertiaryContainer: Tosk.paper,
  error: const Color(0xFFF2A698),
  onError: Tosk.ink,
  errorContainer: const Color(0xFF6E2A20),
  onErrorContainer: Tosk.paper,
  surface: Tosk.night,
  onSurface: Tosk.paper,
  surfaceDim: Tosk.night,
  surfaceBright: Tosk.nightHighest,
  surfaceContainerLowest: const Color(0xFF1A120D),
  surfaceContainerLow: Tosk.nightLow,
  surfaceContainer: Tosk.nightMid,
  surfaceContainerHigh: Tosk.nightHigh,
  surfaceContainerHighest: Tosk.nightHighest,
  onSurfaceVariant: Tosk.paperSoft,
  outline: Tosk.bark,
  outlineVariant: Tosk.nightRule,
  inverseSurface: Tosk.paper,
  onInverseSurface: Tosk.ink,
  inversePrimary: Tosk.furDark,
  surfaceTint: Tosk.furLight,
  shadow: Colors.black,
  scrim: Colors.black,
);

/// [base] in Gelasio Bold: for headings only (screen titles, section
/// headers, "Session complete"), never for exercise content, which keeps the
/// UI font. The text theme itself stays the platform font, because exercises
/// use headline and title styles for prompts and words.
TextStyle? toskSerif(TextStyle? base, {FontWeight weight = FontWeight.w700}) =>
    base?.copyWith(fontFamily: Tosk.serif, fontWeight: weight);

/// Heading styles in the brand serif.
extension ToskHeadings on TextTheme {
  /// Screen and sheet titles (app bars, "Session complete").
  TextStyle? get serifTitle => toskSerif(titleLarge);

  /// Big headings ("Session complete", the intro title).
  TextStyle? get serifHeadline => toskSerif(headlineSmall);

  /// Section and band titles.
  TextStyle? get serifSection => toskSerif(titleMedium, weight: FontWeight.w600);
}
