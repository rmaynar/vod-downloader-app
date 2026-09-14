import 'package:flutter/material.dart';

/// App color palette mirroring the nodecast-catalog dark design system.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0A0A0F);
  static const Color cardBackground = Color(0xFF12121A);
  static const Color surface = Color(0xFF181824);
  static const Color surfaceLight = Color(0xFF181824);
  static const Color surfaceElevated = Color(0xFF1E1E2D);
  static const Color inputBackground = Color(0xFF1A1A25);
  static const Color inputHover = Color(0xFF22222F);

  // Borders
  static const Color border = Color(0xFF27272A);
  static const Color borderHover = Color(0xFF3F3F46);
  static const Color borderLight = Color(0xFF3F3F46);

  // Primary Indigo & Accents
  static const Color indigo = Color(0xFF6366F1);
  static const Color indigoDark = Color(0xFF4F46E5);
  static const Color indigoDeeper = Color(0xFF4338CA);
  static const Color indigoLight = Color(0xFF818CF8);
  static const Color indigoLighter = Color(0xFFA5B4FC);
  static const Color purple = Color(0xFF9333EA);
  static const Color purpleLight = Color(0xFFA855F7);

  // Primary aliases
  static const Color primary = indigo;
  static const Color primaryHover = indigoDark;
  static const Color secondary = purple;
  static const Color amber = Color(0xFFFBBF24);
  static const Color emerald = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);

  // Typography
  static const Color textPrimary = Color(0xFFF1F1F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textDim = Color(0xFF52525B);
  static const Color textLight = Color(0xFFD4D4D8);

  // Feedback & Status
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFF34D399);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFF87171);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF38BDF8);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [indigo, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [indigoLight, indigoDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
