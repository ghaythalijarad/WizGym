import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand palette ──────────────────────────────────────────────
  static const Color cardLime = Color(0xFF00A68C); // primary green
  static const Color cardPink = Color(0xFFFF5C7A); // accent warm / danger
  static const Color cardLavender = Color(0xFF7C83FF); // accent cool / purple
  static const Color cardSurfaceHigh =
      Color(0xFF1A2336); // dark elevated surface
  static const Color textPrimary = Color(0xFFEAF0FB); // near-white
  static const Color textSecondary = Color(0xFF8A96A8); // muted grey

  static ThemeData get lightTheme {
    const ink = Color(0xFF0B1220);
    const accent = Color(0xFF00A68C);
    const accentCool = Color(0xFF2B5BFF);
    const accentWarm = Color(0xFFFF5C7A);
    const canvas = Color(0xFFF6F4EF);
    const surface = Color(0xFFFFFFFF);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: accent,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD2FFF3),
        onPrimaryContainer: ink,
        secondary: accentCool,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFDCE6FF),
        onSecondaryContainer: ink,
        tertiary: accentWarm,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFFFD7DE),
        onTertiaryContainer: ink,
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFF9DEDC),
        onErrorContainer: ink,
        surface: canvas,
        onSurface: ink,
        surfaceContainerHighest: Color(0xFFF1F3F7),
        onSurfaceVariant: Color(0xFF4B5563),
        outline: Color(0xFFE5E7EB),
        outlineVariant: Color(0xFFD1D5DB),
        shadow: Color(0x1A000000),
        scrim: Color(0x66000000),
        inverseSurface: ink,
        onInverseSurface: canvas,
        inversePrimary: accent,
      ),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0.0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: Color(0x14FFFFFF)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE5E7EB), thickness: 1, space: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.92),
        indicatorColor: accent.withValues(alpha: 0.14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: 0.90),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textTheme: _textTheme(ink),
    );
  }

  static TextTheme _textTheme(Color ink) {
    // Keep system font (SF Arabic on iOS, Roboto on Android) but tune weights/sizes.
    const base = Typography.blackCupertino;

    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.05,
        color: ink,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.1,
        color: ink,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: ink,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: ink,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: ink,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: ink,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    );
  }
}
