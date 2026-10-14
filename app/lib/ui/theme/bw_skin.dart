/// Black & white (e-ink) skin: pure black on white, one mid gray for disabled
/// states, no shadows, tints, translucent overlays, ripples or gradients, and
/// borders of at least 2 px. Nothing may rely on color: widgets check
/// [isMonochrome] and switch to icons, labels, borders and patterns.
library;

import 'package:flutter/material.dart';

import 'skin.dart';

const Color kBwBlack = Color(0xFF000000);
const Color kBwWhite = Color(0xFFFFFFFF);

/// The one gray, for disabled states only (4.54:1 on white: WCAG AA).
const Color kBwGray = Color(0xFF767676);

/// Every color the black & white theme may use (plus fully transparent).
const List<Color> kBwPalette = [kBwBlack, kBwWhite, kBwGray];

/// Border width of buttons, cards, chips, options and map nodes in black & white.
const double kBwBorder = 2;

/// Whether [scheme] is the black & white scheme (so leaf widgets that only
/// see a theme can switch to patterns and icons).
bool isMonochrome(ColorScheme scheme) =>
    scheme.primary == kBwBlack && scheme.surface == kBwWhite && scheme.secondaryContainer == kBwBlack;

/// Whether the current theme is black & white.
bool isBw(BuildContext context) => isMonochrome(Theme.of(context).colorScheme);

/// The black & white [ColorScheme]: containers are white with black content,
/// except the "selected" role (secondary container), which is inverted.
const ColorScheme kBwScheme = ColorScheme(
  brightness: Brightness.light,
  primary: kBwBlack,
  onPrimary: kBwWhite,
  primaryContainer: kBwWhite,
  onPrimaryContainer: kBwBlack,
  primaryFixed: kBwWhite,
  primaryFixedDim: kBwWhite,
  onPrimaryFixed: kBwBlack,
  onPrimaryFixedVariant: kBwBlack,
  secondary: kBwBlack,
  onSecondary: kBwWhite,
  secondaryContainer: kBwBlack,
  onSecondaryContainer: kBwWhite,
  secondaryFixed: kBwWhite,
  secondaryFixedDim: kBwWhite,
  onSecondaryFixed: kBwBlack,
  onSecondaryFixedVariant: kBwBlack,
  tertiary: kBwBlack,
  onTertiary: kBwWhite,
  tertiaryContainer: kBwWhite,
  onTertiaryContainer: kBwBlack,
  tertiaryFixed: kBwWhite,
  tertiaryFixedDim: kBwWhite,
  onTertiaryFixed: kBwBlack,
  onTertiaryFixedVariant: kBwBlack,
  error: kBwBlack,
  onError: kBwWhite,
  errorContainer: kBwWhite,
  onErrorContainer: kBwBlack,
  surface: kBwWhite,
  onSurface: kBwBlack,
  surfaceDim: kBwWhite,
  surfaceBright: kBwWhite,
  surfaceContainerLowest: kBwWhite,
  surfaceContainerLow: kBwWhite,
  surfaceContainer: kBwWhite,
  surfaceContainerHigh: kBwWhite,
  surfaceContainerHighest: kBwWhite,
  onSurfaceVariant: kBwBlack,
  outline: kBwBlack,
  outlineVariant: kBwGray,
  shadow: kBwBlack,
  scrim: kBwBlack,
  inverseSurface: kBwBlack,
  onInverseSurface: kBwWhite,
  inversePrimary: kBwWhite,
  surfaceTint: kBwWhite,
);

class BwSkin extends Skin {
  const BwSkin();

  @override
  String get id => 'bw';
  @override
  String get name => 'Black & white';
  @override
  Color get seedColor => kBwBlack;

  /// Always the light black-on-white theme, whatever [brightness] asks.
  @override
  ThemeData theme(Brightness brightness) => bwTheme();

  @override
  MapStyle mapStyle(ColorScheme scheme) => const MapStyle(
    vocabColor: kBwWhite,
    grammarColor: kBwWhite,
    lockedColor: kBwWhite,
    ringTrack: kBwBlack,
    ringColor: kBwBlack,
    edgeColor: kBwBlack,
    bandColors: [kBwWhite],
    bandTitleColor: kBwBlack,
    onNode: kBwBlack,
    monochrome: true,
  );
}

const _transparent = Color(0x00000000);
const _side = BorderSide(color: kBwBlack, width: kBwBorder);
const _graySide = BorderSide(color: kBwGray, width: kBwBorder);

WidgetStateProperty<T> _states<T>(T normal, {required T disabled, T? selected}) => WidgetStateProperty.resolveWith(
  (s) => s.contains(WidgetState.disabled)
      ? disabled
      : (selected != null && s.contains(WidgetState.selected) ? selected : normal),
);

ButtonStyle _buttonStyle({required Color bg, required Color fg}) => ButtonStyle(
  backgroundColor: _states(bg, disabled: kBwWhite),
  foregroundColor: _states(fg, disabled: kBwGray),
  iconColor: _states(fg, disabled: kBwGray),
  overlayColor: const WidgetStatePropertyAll(_transparent),
  shadowColor: const WidgetStatePropertyAll(_transparent),
  surfaceTintColor: const WidgetStatePropertyAll(_transparent),
  elevation: const WidgetStatePropertyAll(0),
  side: _states(_side, disabled: _graySide),
  splashFactory: NoSplash.splashFactory,
);

/// The black & white [ThemeData].
ThemeData bwTheme() {
  const scheme = kBwScheme;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.light);
  final text = base.textTheme.apply(bodyColor: kBwBlack, displayColor: kBwBlack, decorationColor: kBwBlack);
  return base.copyWith(
    textTheme: text,
    primaryTextTheme: base.primaryTextTheme.apply(bodyColor: kBwWhite, displayColor: kBwWhite),
    scaffoldBackgroundColor: kBwWhite,
    canvasColor: kBwWhite,
    cardColor: kBwWhite,
    dividerColor: kBwBlack,
    disabledColor: kBwGray,
    hintColor: kBwGray,
    unselectedWidgetColor: kBwBlack,
    secondaryHeaderColor: kBwWhite,
    primaryColor: kBwBlack,
    primaryColorDark: kBwBlack,
    primaryColorLight: kBwWhite,
    shadowColor: _transparent,
    splashFactory: NoSplash.splashFactory,
    splashColor: _transparent,
    highlightColor: _transparent,
    hoverColor: _transparent,
    focusColor: _transparent,
    applyElevationOverlayColor: false,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kBwBlack,
      contentTextStyle: text.bodyMedium?.copyWith(color: kBwWhite),
      actionTextColor: kBwWhite,
      elevation: 0,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBwWhite,
      foregroundColor: kBwBlack,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: _transparent,
      shadowColor: _transparent,
      shape: Border(bottom: _side),
    ),
    cardTheme: const CardThemeData(
      color: kBwWhite,
      elevation: 0,
      shadowColor: _transparent,
      surfaceTintColor: _transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: _side),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(bg: kBwBlack, fg: kBwWhite),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(bg: kBwWhite, fg: kBwBlack),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buttonStyle(bg: kBwWhite, fg: kBwBlack),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: _states(kBwBlack, disabled: kBwGray),
        iconColor: _states(kBwBlack, disabled: kBwGray),
        overlayColor: const WidgetStatePropertyAll(_transparent),
        splashFactory: NoSplash.splashFactory,
        // Built on labelLarge: a bare TextStyle would replace the theme's
        // style (no family, no size) and fall back to the default font.
        textStyle: WidgetStatePropertyAll(
          // ThemeData's textTheme has no sizes (Theme.of adds them later):
          // take labelLarge's geometry from the typography explicitly.
          Typography.material2021(platform: base.platform).englishLike.labelLarge!
              .merge(text.labelLarge)
              .copyWith(fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: kBwBlack),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: _states(kBwBlack, disabled: kBwGray, selected: kBwWhite),
        backgroundColor: _states(_transparent, disabled: _transparent, selected: kBwBlack),
        overlayColor: const WidgetStatePropertyAll(_transparent),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _states(kBwWhite, disabled: kBwWhite, selected: kBwBlack),
        foregroundColor: _states(kBwBlack, disabled: kBwGray, selected: kBwWhite),
        iconColor: _states(kBwBlack, disabled: kBwGray, selected: kBwWhite),
        overlayColor: const WidgetStatePropertyAll(_transparent),
        side: _states(_side, disabled: _graySide),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kBwWhite,
      foregroundColor: kBwBlack,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      splashColor: _transparent,
      focusColor: _transparent,
      hoverColor: _transparent,
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: kBwBlack),
      shape: StadiumBorder(side: _side),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kBwWhite,
      selectedColor: kBwBlack,
      disabledColor: kBwWhite,
      secondarySelectedColor: kBwBlack,
      checkmarkColor: kBwWhite,
      deleteIconColor: kBwBlack,
      labelStyle: text.labelLarge?.copyWith(color: kBwBlack),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: kBwWhite),
      iconTheme: IconThemeData(color: kBwBlack),
      side: _side,
      elevation: 0,
      pressElevation: 0,
      shadowColor: _transparent,
      selectedShadowColor: _transparent,
      surfaceTintColor: _transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kBwWhite,
      indicatorColor: kBwBlack,
      elevation: 0,
      shadowColor: _transparent,
      surfaceTintColor: _transparent,
      overlayColor: const WidgetStatePropertyAll(_transparent),
      iconTheme: _states(
        const IconThemeData(color: kBwBlack),
        disabled: const IconThemeData(color: kBwGray),
        selected: const IconThemeData(color: kBwWhite),
      ),
      labelTextStyle: _states(
        text.labelMedium!.copyWith(color: kBwBlack),
        disabled: text.labelMedium!.copyWith(color: kBwGray),
        selected: text.labelMedium!.copyWith(color: kBwBlack, fontWeight: FontWeight.w800),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: kBwWhite,
      indicatorColor: kBwBlack,
      elevation: 0,
      selectedIconTheme: IconThemeData(color: kBwWhite),
      unselectedIconTheme: IconThemeData(color: kBwBlack),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: kBwBlack, fontWeight: FontWeight.w800),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: kBwBlack),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kBwBlack,
      linearTrackColor: kBwGray,
      circularTrackColor: kBwGray,
      refreshBackgroundColor: kBwWhite,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: _states(kBwBlack, disabled: kBwGray, selected: kBwWhite),
      trackColor: _states(kBwWhite, disabled: kBwWhite, selected: kBwBlack),
      trackOutlineColor: _states(kBwBlack, disabled: kBwGray),
      trackOutlineWidth: const WidgetStatePropertyAll(kBwBorder),
      overlayColor: const WidgetStatePropertyAll(_transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: _states(kBwWhite, disabled: kBwWhite, selected: kBwBlack),
      checkColor: const WidgetStatePropertyAll(kBwWhite),
      side: _side,
      overlayColor: const WidgetStatePropertyAll(_transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: _states(kBwBlack, disabled: kBwGray),
      overlayColor: const WidgetStatePropertyAll(_transparent),
    ),
    dividerTheme: const DividerThemeData(color: kBwBlack, thickness: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: kBwBlack,
      textColor: kBwBlack,
      selectedColor: kBwBlack,
      selectedTileColor: kBwWhite,
      tileColor: kBwWhite,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBwWhite,
      border: OutlineInputBorder(borderSide: _side),
      enabledBorder: OutlineInputBorder(borderSide: _side),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kBwBlack, width: 3)),
      disabledBorder: OutlineInputBorder(borderSide: _graySide),
      hintStyle: text.bodyLarge?.copyWith(color: kBwGray),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: kBwBlack,
      selectionColor: kBwGray,
      selectionHandleColor: kBwBlack,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kBwWhite,
      modalBackgroundColor: kBwWhite,
      surfaceTintColor: _transparent,
      shadowColor: _transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: _transparent,
      dragHandleColor: kBwBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kBwBlack, width: 3),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kBwWhite,
      surfaceTintColor: _transparent,
      shadowColor: _transparent,
      elevation: 0,
      barrierColor: _transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: kBwBlack, width: 3),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: kBwWhite,
      surfaceTintColor: _transparent,
      shadowColor: _transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)), side: _side),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(kBwWhite),
        surfaceTintColor: WidgetStatePropertyAll(_transparent),
        shadowColor: WidgetStatePropertyAll(_transparent),
        elevation: WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(_side),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: kBwBlack),
      textStyle: text.bodySmall?.copyWith(color: kBwWhite),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: kBwBlack, textColor: kBwWhite),
    drawerTheme: const DrawerThemeData(
      backgroundColor: kBwWhite,
      surfaceTintColor: _transparent,
      shadowColor: _transparent,
      elevation: 0,
    ),
    bannerTheme: const MaterialBannerThemeData(backgroundColor: kBwWhite, surfaceTintColor: _transparent),
  );
}
