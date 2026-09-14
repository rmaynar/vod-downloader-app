import 'package:flutter/material.dart';

export 'app_colors.dart';

/// Application theme definition matching the React nodecast-catalog aesthetics.
class AppTheme {
  AppTheme._();

  // Core color palette matching React Tailwind styles
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12121A);
  static const Color card = Color(0xFF12121A);
  static const Color secondaryContainer = Color(0xFF181824);
  static const Color surfaceLight = Color(0xFF181824);
  static const Color surfaceElevated = Color(0xFF1E1E2D);
  static const Color border = Color(0xFF27272A);
  static const Color borderHover = Color(0xFF3F3F46);
  static const Color borderLight = Color(0xFF3F3F46);
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color primaryHover = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFF8B5CF6); // Purple
  static const Color accent = Color(0xFF8B5CF6);
  static const Color ratingGold = Color(0xFFF59E0B); // Amber/Gold
  static const Color amber = Color(0xFFFBBF24);
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color emerald = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444); // Red
  static const Color red = Color(0xFFEF4444);

  // Text colors
  static const Color textPrimary = Color(0xFFF1F1F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textLight = Color(0xFFD4D4D8);

  /// Modern text theme for dark backgrounds
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: textPrimary,
      letterSpacing: -0.5,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: textPrimary,
      letterSpacing: -0.5,
    ),
    headlineLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: textPrimary,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: textSecondary,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.normal,
      color: textPrimary,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textSecondary,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: textMuted,
      height: 1.3,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: textSecondary,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: textMuted,
      letterSpacing: 0.5,
    ),
  );

  /// Main dark theme configuration matching the React web app.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      canvasColor: background,
      cardColor: card,
      dividerColor: border,
      textTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF312E81),
        onPrimaryContainer: Color(0xFFE0E7FF),
        secondary: accent,
        onSecondary: Colors.white,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: Color(0xFFEDE9FE),
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
        outline: border,
        outlineVariant: borderHover,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondaryContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border, width: 1),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
