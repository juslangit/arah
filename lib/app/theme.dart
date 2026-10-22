// Arah's look: a deep jungle green brand colour, a strong blue route line,
// big type for anything read while driving.
import 'package:flutter/material.dart';

class ArahColors {
  static const brand = Color(0xFF0B6E4F); // hutan green
  static const brandDark = Color(0xFF07523A);
  static const route = Color(0xFF2F6BFF);
  static const routeCasing = Color(0xFF1B3FA6);
  static const routeAlt = Color(0xFF9AA4B2);
  static const banner = Color(0xFF0B6E4F);
  static const warn = Color(0xFFE0362C);
  static const amber = Color(0xFFF2A900);

  static const report = {
    'polis': Color(0xFF2457C5),
    'kemalangan': Color(0xFFE0362C),
    'kesesakan': Color(0xFFE5701A),
    'bahaya': Color(0xFFF2A900),
    'banjir': Color(0xFF0E8FB3),
    'ditutup': Color(0xFF5B4B8A),
  };
}

ThemeData arahTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: ArahColors.brand, brightness: b, primary: b == Brightness.light ? ArahColors.brand : const Color(0xFF6FD3AE));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  );
}
