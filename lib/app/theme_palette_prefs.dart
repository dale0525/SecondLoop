import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePalette {
  studio('studio'),
  forest('forest'),
  ocean('ocean'),
  sunset('sunset'),
  monochrome('monochrome');

  const AppThemePalette(this.storageValue);

  final String storageValue;
}

final class AppThemePalettePrefs {
  static const prefsKey = 'app_theme_palette_v1';

  static final ValueNotifier<AppThemePalette> value =
      ValueNotifier<AppThemePalette>(AppThemePalette.studio);

  static Future<void>? _bootstrap;

  static Future<void> ensureInitialized() =>
      _bootstrap ??= _ensureInitialized();

  static void resetForTests() {
    _bootstrap = null;
    value.value = AppThemePalette.studio;
  }

  static Future<void> _ensureInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);

    final decoded = _decode(raw);
    if (decoded == null || raw != null) {
      await prefs.remove(prefsKey);
      value.value = AppThemePalette.studio;
      return;
    }

    value.value = decoded;
  }

  static AppThemePalette? _decode(String? raw) {
    final normalized = raw?.trim() ?? '';
    if (normalized.isEmpty) return AppThemePalette.studio;
    for (final palette in AppThemePalette.values) {
      if (palette.storageValue == normalized) {
        return palette;
      }
    }
    return null;
  }

  static Future<void> setPalette(AppThemePalette _) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    value.value = AppThemePalette.studio;
  }
}
