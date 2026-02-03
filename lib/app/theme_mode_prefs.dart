import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AppThemeModePrefs {
  static const prefsKey = 'app_theme_mode_v1';

  static final ValueNotifier<ThemeMode> value =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void>? _bootstrap;

  static Future<void> ensureInitialized() =>
      _bootstrap ??= _ensureInitialized();

  static void resetForTests() {
    _bootstrap = null;
    value.value = ThemeMode.system;
  }

  static Future<void> _ensureInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);

    final decoded = _decode(raw);
    if (decoded == null) {
      await prefs.remove(prefsKey);
      value.value = ThemeMode.system;
      return;
    }

    value.value = decoded;
  }

  static ThemeMode? _decode(String? raw) {
    final v = raw?.trim() ?? '';
    return switch (v) {
      '' || 'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();

    switch (mode) {
      case ThemeMode.system:
        await prefs.remove(prefsKey);
        break;
      case ThemeMode.light:
        await prefs.setString(prefsKey, 'light');
        break;
      case ThemeMode.dark:
        await prefs.setString(prefsKey, 'dark');
        break;
    }

    value.value = mode;
  }
}
