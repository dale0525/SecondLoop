import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class UpdateBadgePrefs {
  static const prefsKey = 'update_badge_latest_tag_v1';

  static final ValueNotifier<String?> value = ValueNotifier<String?>(null);

  static Future<void>? _bootstrap;

  static Future<void> ensureInitialized() => _bootstrap ??= _load();

  static bool get hasAvailableUpdate {
    final latestTag = value.value;
    return latestTag != null && latestTag.trim().isNotEmpty;
  }

  static Future<void> setAvailableVersion(String version) async {
    final normalized = version.trim();
    if (normalized.isEmpty) {
      await clear();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, normalized);
    value.value = normalized;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    value.value = null;
  }

  static void resetForTests() {
    _bootstrap = null;
    value.value = null;
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey)?.trim();
    if (raw == null || raw.isEmpty) {
      await prefs.remove(prefsKey);
      value.value = null;
      return;
    }

    value.value = raw;
  }
}
