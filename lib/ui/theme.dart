import 'package:material_ui/material_ui.dart';

/// Bundled reading typeface (see pubspec.yaml).
const kSerifFont = 'Literata';

/// Hearth's dark-only palette: matte charcoal, espresso wood and warm
/// fairy-light amber, with high-contrast off-white text.
abstract final class HearthColors {
  static const background = Color(0xFF0D0C0B);
  static const surface = Color(0xFF171513);
  static const surfaceHigh = Color(0xFF211E1B);
  static const outline = Color(0xFF3A342E);

  static const text = Color(0xFFEDE8E0);
  static const textMuted = Color(0xFFA59E94);
  static const textFaint = Color(0xFF6E675F);

  static const glow = Color(0xFFFFC56E);
  static const accent = Color(0xFFE3AE62);
  static const readGreen = Color(0xFF5FAE6E);

  // Espresso wood.
  static const woodDark = Color(0xFF1A100B);
  static const wood = Color(0xFF2E1C13);
  static const woodMid = Color(0xFF3B251A);
  static const woodLight = Color(0xFF543623);

  /// Reader page and text.
  static const readerBackground = Color(0xFF000000);
  static const readerText = Color(0xFFE4DFD6);
}

ThemeData buildHearthTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: HearthColors.accent,
    onPrimary: Color(0xFF1E1408),
    secondary: HearthColors.readGreen,
    onSecondary: Color(0xFF0B1A0E),
    // Tonal buttons use the secondary container: keep them warm, not green.
    secondaryContainer: Color(0xFF3A2C1C),
    onSecondaryContainer: Color(0xFFF1D3A4),
    error: Color(0xFFE57373),
    onError: Color(0xFF1A0505),
    surface: HearthColors.surface,
    onSurface: HearthColors.text,
    onSurfaceVariant: HearthColors.textMuted,
    surfaceContainerLowest: HearthColors.background,
    surfaceContainerLow: Color(0xFF131110),
    surfaceContainer: HearthColors.surface,
    surfaceContainerHigh: HearthColors.surfaceHigh,
    surfaceContainerHighest: Color(0xFF2A2622),
    outline: HearthColors.outline,
    outlineVariant: Color(0xFF2A2622),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HearthColors.background,
    canvasColor: HearthColors.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: HearthColors.text,
      displayColor: HearthColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: HearthColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: HearthColors.surface,
      selectedColor: const Color(0xFF3A2C1C),
      side: const BorderSide(color: HearthColors.outline),
      labelStyle: const TextStyle(color: HearthColors.textMuted),
      secondaryLabelStyle: const TextStyle(color: HearthColors.text),
      checkmarkColor: HearthColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HearthColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: HearthColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: HearthColors.surfaceHigh,
      contentTextStyle: TextStyle(color: HearthColors.text),
      actionTextColor: HearthColors.accent,
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: HearthColors.outline),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: HearthColors.surfaceHigh,
      border: OutlineInputBorder(borderSide: BorderSide.none),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: HearthColors.accent,
      thumbColor: HearthColors.accent,
      inactiveTrackColor: HearthColors.outline,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: HearthColors.accent,
      selectionColor: HearthColors.accent.withValues(alpha: 0.35),
      selectionHandleColor: HearthColors.accent,
    ),
  );
}
