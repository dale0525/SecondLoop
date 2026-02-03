import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:secondloop/core/desktop/system_hotkey_conflicts.dart';

void main() {
  test('macOS: ⌘ + Space conflicts with Spotlight', () {
    final hotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

    expect(
      systemHotkeyConflict(hotKey: hotKey, platform: TargetPlatform.macOS),
      SystemHotkeyConflict.macosSpotlight,
    );
  });

  test('macOS: ⌘⇧K has no known system conflict', () {
    final hotKey = HotKey(
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    expect(
      systemHotkeyConflict(hotKey: hotKey, platform: TargetPlatform.macOS),
      isNull,
    );
  });

  test('Windows: Win + L conflicts with Lock screen', () {
    final hotKey = HotKey(
      key: PhysicalKeyboardKey.keyL,
      modifiers: [HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

    expect(
      systemHotkeyConflict(hotKey: hotKey, platform: TargetPlatform.windows),
      SystemHotkeyConflict.windowsLock,
    );
  });
}
