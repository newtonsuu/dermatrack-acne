import 'package:flutter/material.dart';

/// Central theme definition for DermaTrack.
///
/// Uses Material 3 with a calm teal/blue palette appropriate for a health app.
/// Exposes both [light] and [dark] ThemeData and context-aware color getters
/// for surface/text tokens that need to flip by brightness.
///
/// Brand colors ([primary], [primaryDark], [accent]) are stable across modes
/// — the teal stays teal in dark mode.
class AppTheme {
  AppTheme._();

  // ===== Brand colors (stable across light & dark) =====
  static const Color primary = Color(0xFF1F8A8A); // teal
  static const Color primaryDark = Color(0xFF0F5F5F);
  static const Color accent = Color(0xFFFF8A65); // warm coral for action accents

  // ===== Light-mode surface tokens =====
  static const Color _lightBackground = Color(0xFFF6F8FA);
  static const Color _lightSurface = Colors.white;
  static const Color _lightTextPrimary = Color(0xFF1A2B33);
  static const Color _lightTextSecondary = Color(0xFF6B7A82);
  static const Color _lightBorder = Color(0xFFE6EBEE);

  // ===== Dark-mode surface tokens =====
  // Tuned so the teal brand color still has good contrast against the
  // background, and so cards (`surface`) are slightly lighter than the
  // page background to keep the existing "card on canvas" layering.
  static const Color _darkBackground = Color(0xFF101316);
  static const Color _darkSurface = Color(0xFF1A1F24);
  static const Color _darkTextPrimary = Color(0xFFE9EDF0);
  static const Color _darkTextSecondary = Color(0xFFA3ADB4);
  static const Color _darkBorder = Color(0xFF2A3036);

  // ===== Context-aware getters =====
  // Use these inside build() methods so colors swap with theme mode.
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _darkBackground
          : _lightBackground;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _darkSurface
          : _lightSurface;

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _darkTextPrimary
          : _lightTextPrimary;

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _darkTextSecondary
          : _lightTextSecondary;

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _darkBorder
          : _lightBorder;

  // ===== ThemeData builders =====
  static ThemeData light() => _buildTheme(
        brightness: Brightness.light,
        background: _lightBackground,
        surface: _lightSurface,
        textPrimary: _lightTextPrimary,
        textSecondary: _lightTextSecondary,
        border: _lightBorder,
      );

  static ThemeData dark() => _buildTheme(
        brightness: Brightness.dark,
        background: _darkBackground,
        surface: _darkSurface,
        textPrimary: _darkTextPrimary,
        textSecondary: _darkTextSecondary,
        border: _darkBorder,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: textSecondary),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
      ),
    );
  }
}
