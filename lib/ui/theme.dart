import 'package:flutter/material.dart';

/// Thème « épuré » : une seule couleur d'accent, beaucoup d'espace,
/// séparateurs fins, pas de cartes lourdes. Voir docs/SPEC.md, section 13.
class CarabinTheme {
  const CarabinTheme._();

  /// L'unique couleur d'accent de l'application.
  static const Color accent = Color(0xFF2F6FED);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
