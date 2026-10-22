// Arah's look: "Mochi" — soft pastel, no outlines, pillowy pink-tinted
// shadows, everything round, Nunito type (bundled, works offline). Anything
// read while driving (turns, distances, limits) keeps strong contrast and big
// type. Design: docs/design/cute-ui/index.html (direction 1).
import 'package:flutter/material.dart';

class ArahColors {
  static const brand = Color(0xFFC2336C); // mochi pink, dark enough for white text
  static const brandDark = Color(0xFFA42A5C);
  static const pink = Color(0xFFFF6FA0); // the bright pink of the route and accents
  static const blush = Color(0xFFFFB3C9);
  static const soft = Color(0xFFFFF0F4); // pink-tinted surface
  static const ink = Color(0xFF5A3E4B); // body text on light
  static const muted = Color(0xFF86596D);
  static const route = Color(0xFFFF6FA0);
  static const routeCasing = Color(0xFFFFFFFF);
  static const routeAlt = Color(0xFFCDBFE6); // lavender for the other options
  static const banner = Color(0xFFC2336C);
  static const warn = Color(0xFFE5484D);
  static const amber = Color(0xFFFFD66B); // butter yellow (report button)
  static const toll = Color(0xFF9C5A06);
  static const sky = Color(0xFF9FD3FF);
  static const leaf = Color(0xFF7CCB8E);

  // Night: plum instead of pink-white.
  static const nightBg = Color(0xFF241C29);
  static const nightCard = Color(0xFF34283B);
  static const nightPink = Color(0xFFFF8DB3);

  static const report = {
    'polis': Color(0xFF4A6FD6),
    'kemalangan': Color(0xFFE5484D),
    'kesesakan': Color(0xFFEE8A3C),
    'bahaya': Color(0xFFE8B21E),
    'banjir': Color(0xFF2EA3C7),
    'ditutup': Color(0xFF8A6FC9),
  };

  /// The soft pink shadow under cards and buttons.
  static List<BoxShadow> shadow(BuildContext context, {double blur = 22, double y = 8}) => [
    BoxShadow(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.black.withValues(alpha: 0.30)
          : const Color(0xFFF078A0).withValues(alpha: 0.22),
      blurRadius: blur,
      offset: Offset(0, y),
    ),
  ];
}

ThemeData arahTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: ArahColors.pink, brightness: b).copyWith(
    primary: light ? ArahColors.brand : ArahColors.nightPink,
    onPrimary: light ? Colors.white : const Color(0xFF3A1426),
    primaryContainer: light ? const Color(0xFFFFE1EA) : const Color(0xFF5A2E45),
    onPrimaryContainer: light ? const Color(0xFF7A1F45) : const Color(0xFFFFD9E6),
    secondaryContainer: light ? ArahColors.soft : const Color(0xFF4A3550),
    onSecondaryContainer: light ? ArahColors.ink : const Color(0xFFF3E6EE),
    surface: light ? Colors.white : ArahColors.nightCard,
    onSurface: light ? ArahColors.ink : const Color(0xFFF3E6EE),
    onSurfaceVariant: light ? ArahColors.muted : const Color(0xFFCDB6C4),
    surfaceContainerLowest: light ? Colors.white : ArahColors.nightBg,
    surfaceContainerLow: light ? const Color(0xFFFFF8FA) : const Color(0xFF2C2232),
    surfaceContainer: light ? const Color(0xFFFFF3F6) : ArahColors.nightCard,
    surfaceContainerHigh: light ? ArahColors.soft : const Color(0xFF3D3044),
    surfaceContainerHighest: light ? const Color(0xFFFFE8EF) : const Color(0xFF47384F),
    outline: light ? const Color(0xFFE9C9D5) : const Color(0xFF6A5672),
    outlineVariant: light ? const Color(0xFFF6DCE5) : const Color(0xFF4F3F57),
    error: ArahColors.warn,
    tertiary: light ? const Color(0xFF3F8F5A) : const Color(0xFF9ADBA9),
  );
  const pill = StadiumBorder();
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Nunito');
  return base.copyWith(
    scaffoldBackgroundColor: light ? const Color(0xFFFFF7F0) : ArahColors.nightBg,
    visualDensity: VisualDensity.standard,
    textTheme: base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: scheme.onSurface),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? const Color(0xFFFFF7F0) : ArahColors.nightBg,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w900),
        shape: pill,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
        shape: pill,
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: scheme.outline),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: const CircleBorder(),
      elevation: 3,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      backgroundColor: light ? ArahColors.ink : const Color(0xFFF3E6EE),
      contentTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        color: light ? Colors.white : ArahColors.nightBg,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
