import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/desktop/desktop_quick_capture_hotkey_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopQuickCaptureHotkeyPrefs.value.value = null;
  });

  test('load returns null when unset', () async {
    await DesktopQuickCaptureHotkeyPrefs.load();
    expect(DesktopQuickCaptureHotkeyPrefs.value.value, isNull);
  });

  test('setHotKey persists JSON and updates notifier', () async {
    final hotKey = HotKey(
      identifier: DesktopQuickCaptureHotkeyPrefs.hotKeyIdentifier,
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    await DesktopQuickCaptureHotkeyPrefs.setHotKey(hotKey);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DesktopQuickCaptureHotkeyPrefs.prefsKey);
    expect(raw, isNotNull);
    expect(jsonDecode(raw!), hotKey.toJson());
    expect(
        DesktopQuickCaptureHotkeyPrefs.value.value?.toJson(), hotKey.toJson());
  });

  test('clear removes preference and sets notifier to null', () async {
    final hotKey = HotKey(
      identifier: DesktopQuickCaptureHotkeyPrefs.hotKeyIdentifier,
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    await DesktopQuickCaptureHotkeyPrefs.setHotKey(hotKey);
    await DesktopQuickCaptureHotkeyPrefs.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(DesktopQuickCaptureHotkeyPrefs.prefsKey), isFalse);
    expect(DesktopQuickCaptureHotkeyPrefs.value.value, isNull);
  });
}
