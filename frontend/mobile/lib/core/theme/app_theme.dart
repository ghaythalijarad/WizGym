import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand palette ──────────────────────────────────────────────────────────
  static const Color gold        = Color(0xFFE4B84D); // premium gold — primary accent
  static const Color goldDeep    = Color(0xFFA07820); // deeper gold for surfaces / containers
  static const Color goldLight   = Color(0xFFF5D98A); // lighter gold for tints
  static const Color black       = Color(0xFF090912); // deepest background
  static const Color white       = Color(0xFFFFFFFF);

  // ── Kept for backwards-compat (alias to gold variants) ────────────────────
  /// @deprecated  Use [gold] instead.
  static const Color purple = gold;

  /// @deprecated  Use [goldDeep] instead.
  static const Color purpleDeep = goldDeep;

  /// @deprecated  Use [goldLight] instead.
  static const Color purpleLight = goldLight;
  static const Color pink = gold;
  static const Color pinkLight = goldLight;

  // ── Card accent tints (trainer/profile pages) ──────────────────────────────
  static const Color cardLime =
      Color(0xFF34D399); // emerald on dark — 7.1:1 on #1A1A2E ✓
  static const Color cardLavender = gold; // was purple → now gold
  static const Color cardPink = goldLight; // was pink   → now goldLight
  /// Elevated card surface — slightly lighter than surface1, used for inner containers
  static const Color cardSurfaceHigh = Color(0xFF1E1E35); // = surface2

  // ── Semantic text helpers ──────────────────────────────────────────────────
  static const Color textPrimary =
      Color(0xFFF2F0FF); // near-white, 18:1 on black ✓
  static const Color textSecondary =
      Color(0xFFB8B0D8); // muted warm-white, 7.2:1 ✓
  static const Color textMuted =
      Color(0xFF7A7295); // subtle, 4.5:1 on darkSurface ✓
  static const Color textOnGold = Color(0xFF1A0A00); // dark on gold — 13:1 ✓
  // Legacy aliases
  static const Color textOnPurple = textOnGold;
  static const Color textOnPurpleContainer = textOnGold;
  static const Color success = Color(0xFF34D399); // emerald green
  static const Color successContainer = Color(0xFF052E16);

  static ThemeData get lightTheme => _buildTheme();

  // Single entry-point so we can easily add darkTheme later
  static ThemeData _buildTheme() {
    // ── Surface stack (dark → slightly lighter) ────────────────────────────
    const surface0 = Color(0xFF0F0F1C); // scaffold / page bg
    const surface1 = Color(0xFF16162A); // cards
    const surface2 = Color(0xFF1E1E35); // elevated / chip bg
    const ink = textPrimary; // F2F0FF
    const muted = textMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,

        // Primary — gold  #E4B84D — 9.3:1 on surface0 ✓
        primary: gold,
        onPrimary: Color(0xFF1A0A00), // dark-on-gold — 13:1 ✓
        primaryContainer: Color(0xFF3A2800),
        onPrimaryContainer: goldLight,

        // Secondary — deep gold
        secondary: goldDeep,
        onSecondary: Color(0xFF1A0A00),
        secondaryContainer: Color(0xFF2A1800),
        onSecondaryContainer: goldLight,

        // Tertiary — gold light tint
        tertiary: goldLight,
        onTertiary: Color(0xFF1A0A00),
        tertiaryContainer: Color(0xFF3A2800),
        onTertiaryContainer: goldLight,

        // Error
        error: Color(0xFFFF6B6B),
        onError: Color(0xFF200000),
        errorContainer: Color(0xFF3D0A0A),
        onErrorContainer: Color(0xFFFFB4B4),

        // Surfaces
        surface: surface0,
        onSurface: ink,
        surfaceContainerHighest: surface2,
        onSurfaceVariant: textSecondary,

        // Borders — very subtle on dark
        outline: Color(0xFF2E2B4A),
        outlineVariant: Color(0xFF201E38),

        shadow: Color(0x55000000),
        scrim: Color(0xBB000000),
        inverseSurface: Color(0xFFF2F0FF),
        onInverseSurface: surface0,
        inversePrimary: goldDeep,
      ),

      scaffoldBackgroundColor: surface0,

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: CardThemeData(
        color: surface1,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF2E2B4A)),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFF2E2B4A),
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        backgroundColor: Color(0xFF1E1E35),
        contentTextStyle: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        actionTextColor: gold,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            const Color(0xFF16162A), // surface1 — solid, no transparency
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: gold.withValues(alpha: 0.22),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
        ),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(color: muted, size: 22),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: Color(0xFF2E2B4A)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        backgroundColor: surface2,
        selectedColor: goldDeep,
        checkmarkColor: goldLight,
        secondaryLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, color: goldLight),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        titleTextStyle:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
        subtitleTextStyle: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        labelStyle:
            const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: muted, fontWeight: FontWeight.w400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E2B4A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 2.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E2B4A)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: textOnGold,
          disabledBackgroundColor: surface2,
          disabledForegroundColor: muted,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: textOnGold,
          disabledBackgroundColor: surface2,
          disabledForegroundColor: muted,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: gold, width: 1.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      textTheme: _textTheme(ink),
    );
  }

  static TextTheme _textTheme(Color ink) {
    const base = Typography.whiteCupertino; // white-on-dark base
    return base.copyWith(
      displayLarge:
          base.displayLarge?.copyWith(color: ink, fontWeight: FontWeight.w800),
      displayMedium:
          base.displayMedium?.copyWith(color: ink, fontWeight: FontWeight.w800),
      displaySmall: base.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.05,
          color: ink),
      headlineLarge:
          base.headlineLarge?.copyWith(color: ink, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium
          ?.copyWith(color: ink, fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.1,
          color: ink),
      titleLarge: base.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800, height: 1.2, color: ink),
      titleMedium: base.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.2, color: ink),
      titleSmall:
          base.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: ink),
      bodyLarge: base.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w500, height: 1.45, color: ink),
      bodyMedium: base.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w500, height: 1.45, color: ink),
      bodySmall: base.bodySmall?.copyWith(
          fontWeight: FontWeight.w500, height: 1.4, color: textSecondary),
      labelLarge:
          base.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: ink),
      labelMedium:
          base.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: ink),
      labelSmall: base.labelSmall
          ?.copyWith(fontWeight: FontWeight.w600, color: textMuted),
    );
  }
}
