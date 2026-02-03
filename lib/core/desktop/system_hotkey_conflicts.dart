import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

enum SystemHotkeyConflict {
  // macOS
  macosSpotlight,
  macosFinderSearch,
  macosInputSourceSwitch,
  macosEmojiPicker,
  macosScreenshot,
  macosAppSwitcher,
  macosForceQuit,
  macosLockScreen,

  // Windows
  windowsLock,
  windowsShowDesktop,
  windowsFileExplorer,
  windowsRun,
  windowsSearch,
  windowsSettings,
  windowsTaskView,
  windowsLanguageSwitch,
  windowsAppSwitcher,
}

Set<HotKeyModifier> _mods(HotKey hotKey) => {...?hotKey.modifiers};

bool _matches(
  HotKey hotKey, {
  required PhysicalKeyboardKey key,
  required Set<HotKeyModifier> modifiers,
}) {
  final mods = _mods(hotKey);
  return hotKey.physicalKey == key &&
      mods.length == modifiers.length &&
      mods.containsAll(modifiers);
}

SystemHotkeyConflict? systemHotkeyConflict({
  required HotKey hotKey,
  required TargetPlatform platform,
}) {
  switch (platform) {
    case TargetPlatform.macOS:
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.space,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.macosSpotlight;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.space,
        modifiers: {HotKeyModifier.meta, HotKeyModifier.alt},
      )) {
        return SystemHotkeyConflict.macosFinderSearch;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.space,
        modifiers: {HotKeyModifier.control},
      )) {
        return SystemHotkeyConflict.macosInputSourceSwitch;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.space,
        modifiers: {HotKeyModifier.meta, HotKeyModifier.control},
      )) {
        return SystemHotkeyConflict.macosEmojiPicker;
      }
      if (_matches(
            hotKey,
            key: PhysicalKeyboardKey.digit3,
            modifiers: {HotKeyModifier.meta, HotKeyModifier.shift},
          ) ||
          _matches(
            hotKey,
            key: PhysicalKeyboardKey.digit4,
            modifiers: {HotKeyModifier.meta, HotKeyModifier.shift},
          ) ||
          _matches(
            hotKey,
            key: PhysicalKeyboardKey.digit5,
            modifiers: {HotKeyModifier.meta, HotKeyModifier.shift},
          ) ||
          _matches(
            hotKey,
            key: PhysicalKeyboardKey.digit6,
            modifiers: {HotKeyModifier.meta, HotKeyModifier.shift},
          )) {
        return SystemHotkeyConflict.macosScreenshot;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.tab,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.macosAppSwitcher;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.escape,
        modifiers: {HotKeyModifier.meta, HotKeyModifier.alt},
      )) {
        return SystemHotkeyConflict.macosForceQuit;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyQ,
        modifiers: {HotKeyModifier.meta, HotKeyModifier.control},
      )) {
        return SystemHotkeyConflict.macosLockScreen;
      }
      return null;
    case TargetPlatform.windows:
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyL,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsLock;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyD,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsShowDesktop;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyE,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsFileExplorer;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyR,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsRun;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyS,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsSearch;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.keyI,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsSettings;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.tab,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsTaskView;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.space,
        modifiers: {HotKeyModifier.meta},
      )) {
        return SystemHotkeyConflict.windowsLanguageSwitch;
      }
      if (_matches(
        hotKey,
        key: PhysicalKeyboardKey.tab,
        modifiers: {HotKeyModifier.alt},
      )) {
        return SystemHotkeyConflict.windowsAppSwitcher;
      }
      return null;
    default:
      return null;
  }
}
