import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class ReviewReminderInAppFallbackPrefs {
  static const prefsKey = 'review_reminder.in_app_fallback_enabled_v1';
  static const bool defaultValue = true;

  static final ValueNotifier<bool> value = ValueNotifier<bool>(defaultValue);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value.value = prefs.getBool(prefsKey) ?? defaultValue;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, enabled);
    value.value = enabled;
  }
}
