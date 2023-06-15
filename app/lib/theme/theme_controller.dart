import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app-wide ThemeMode (light / dark / system) and persists the user's
/// preference between launches via shared_preferences.
///
/// Mirrors the singleton-with-ChangeNotifier pattern used by [AuthService],
/// so MaterialApp can listen and rebuild whenever the user toggles a mode.
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  static const String _prefsKey = 'dermatrack.theme_mode';

  ThemeMode _mode = ThemeMode.system;
  bool _initialized = false;

  ThemeMode get mode => _mode;
  bool get isInitialized => _initialized;

  /// Loads the saved mode (if any) from shared_preferences. Safe to call
  /// multiple times — second and later calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _mode = _decode(saved);
      }
    } catch (_) {
      // If shared_preferences blows up for any reason, fall back to the
      // default system mode silently. Theme persistence isn't critical.
    }
    _initialized = true;
    notifyListeners();
  }

  /// Updates the mode and persists it. No-op if [newMode] equals the
  /// current mode, to avoid unnecessary rebuilds.
  Future<void> setMode(ThemeMode newMode) async {
    if (newMode == _mode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(newMode));
    } catch (_) {
      // Persistence is best-effort; the in-memory value still flipped.
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
