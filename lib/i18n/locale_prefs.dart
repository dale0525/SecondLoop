import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'strings.g.dart';

const kAppLocaleOverridePrefsKey = 'app_locale_override_v1';

class AppLocaleBootstrap {
  static Future<void>? _bootstrap;

  static Future<void> ensureInitialized() =>
      _bootstrap ??= _ensureInitialized();

  static void resetForTests() {
    _bootstrap = null;
  }

  static Future<void> _ensureInitialized() async {
    LocaleSettings.useDeviceLocale();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAppLocaleOverridePrefsKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      LocaleSettings.setLocaleRaw(raw);
    } catch (_) {
      await prefs.remove(kAppLocaleOverridePrefsKey);
      LocaleSettings.useDeviceLocale();
    }
  }
}

Future<AppLocale?> readLocaleOverride() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kAppLocaleOverridePrefsKey);
  if (raw == null || raw.trim().isEmpty) return null;

  try {
    return AppLocaleUtils.parse(raw);
  } catch (_) {
    return null;
  }
}

Future<void> setLocaleOverride(AppLocale? override) async {
  final prefs = await SharedPreferences.getInstance();

  if (override == null) {
    LocaleSettings.useDeviceLocale();
    await prefs.remove(kAppLocaleOverridePrefsKey);
    return;
  }

  LocaleSettings.setLocale(override);
  await prefs.setString(
    kAppLocaleOverridePrefsKey,
    override.flutterLocale.toLanguageTag(),
  );
}
