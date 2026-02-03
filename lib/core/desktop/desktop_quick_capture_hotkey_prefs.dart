import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class DesktopQuickCaptureHotkeyPrefs {
  static const prefsKey = 'desktop.quick_capture_hotkey_v1';

  static const hotKeyIdentifier = 'desktop.quick_capture_hotkey';

  static final ValueNotifier<HotKey?> value = ValueNotifier<HotKey?>(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      value.value = null;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        value.value = HotKey.fromJson(decoded.cast<String, dynamic>());
      } else {
        value.value = null;
      }
    } catch (_) {
      value.value = null;
    }
  }

  static Future<void> setHotKey(HotKey hotKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(hotKey.toJson()));
    value.value = hotKey;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    value.value = null;
  }
}
