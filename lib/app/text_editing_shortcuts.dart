import 'package:flutter/services.dart';

enum TextEditingShortcut {
  selectAll,
  copy,
  paste,
  cut,
  undo,
  redo,
}

final Set<LogicalKeyboardKey> _modifierOnlyKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.altGraph,
};

TextEditingShortcut? resolveTextEditingShortcut({
  required LogicalKeyboardKey key,
  required String keyLabel,
  required String? character,
  required bool metaPressed,
  required bool controlPressed,
  required bool shiftPressed,
  required Set<TextEditingShortcut> supportedShortcuts,
}) {
  if (_modifierOnlyKeys.contains(key)) {
    return null;
  }

  final hasPrimaryModifier = metaPressed || controlPressed;
  final shortcutCharacter = _resolveShortcutCharacter(
    key: key,
    keyLabel: keyLabel,
    character: character,
    supportedShortcuts: supportedShortcuts,
  );

  if (supportedShortcuts.contains(TextEditingShortcut.paste) &&
      (key == LogicalKeyboardKey.paste ||
          ((shortcutCharacter == 'v' || key == LogicalKeyboardKey.keyV) &&
              hasPrimaryModifier))) {
    return TextEditingShortcut.paste;
  }

  if (supportedShortcuts.contains(TextEditingShortcut.selectAll) &&
      hasPrimaryModifier &&
      (shortcutCharacter == 'a' ||
          (shortcutCharacter == null && key == LogicalKeyboardKey.keyA))) {
    return TextEditingShortcut.selectAll;
  }

  if (supportedShortcuts.contains(TextEditingShortcut.copy) &&
      (key == LogicalKeyboardKey.copy ||
          ((shortcutCharacter == 'c' || key == LogicalKeyboardKey.keyC) &&
              hasPrimaryModifier))) {
    return TextEditingShortcut.copy;
  }

  if (supportedShortcuts.contains(TextEditingShortcut.cut) &&
      (key == LogicalKeyboardKey.cut ||
          ((shortcutCharacter == 'x' || key == LogicalKeyboardKey.keyX) &&
              hasPrimaryModifier))) {
    return TextEditingShortcut.cut;
  }

  if (supportedShortcuts.contains(TextEditingShortcut.undo) &&
      hasPrimaryModifier &&
      !shiftPressed &&
      (shortcutCharacter == 'z' || key == LogicalKeyboardKey.keyZ)) {
    return TextEditingShortcut.undo;
  }

  if (supportedShortcuts.contains(TextEditingShortcut.redo) &&
      hasPrimaryModifier &&
      ((shortcutCharacter == 'y' || key == LogicalKeyboardKey.keyY) ||
          (shiftPressed &&
              (shortcutCharacter == 'z' || key == LogicalKeyboardKey.keyZ)))) {
    return TextEditingShortcut.redo;
  }

  return null;
}

String? _resolveShortcutCharacter({
  required LogicalKeyboardKey key,
  required String keyLabel,
  required String? character,
  required Set<TextEditingShortcut> supportedShortcuts,
}) {
  if (_modifierOnlyKeys.contains(key)) {
    return null;
  }

  final supportedCharacters = <String>{
    if (supportedShortcuts.contains(TextEditingShortcut.selectAll)) 'a',
    if (supportedShortcuts.contains(TextEditingShortcut.copy)) 'c',
    if (supportedShortcuts.contains(TextEditingShortcut.paste)) 'v',
    if (supportedShortcuts.contains(TextEditingShortcut.cut)) 'x',
    if (supportedShortcuts.contains(TextEditingShortcut.undo) ||
        supportedShortcuts.contains(TextEditingShortcut.redo))
      'z',
    if (supportedShortcuts.contains(TextEditingShortcut.redo)) 'y',
  };

  String? normalize(String? value) {
    if (value == null || value.length != 1) {
      return null;
    }

    final lowered = value.toLowerCase();
    return supportedCharacters.contains(lowered) ? lowered : null;
  }

  return normalize(keyLabel) ?? normalize(character);
}

bool shouldIgnoreTextEditingShortcutEvent(RawKeyEvent event) {
  return isMacOsCommandModifierKeyDown(event);
}

bool isMacOsCommandModifierKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) {
    return false;
  }

  return switch (event.logicalKey) {
    LogicalKeyboardKey.meta ||
    LogicalKeyboardKey.metaLeft ||
    LogicalKeyboardKey.metaRight =>
      true,
    _ => false,
  };
}

bool isMacOsCommandModifierKeyDown(RawKeyEvent event) {
  if (event is! RawKeyDownEvent) {
    return false;
  }

  final data = event.data;
  if (data is! RawKeyEventDataMacOs) {
    return false;
  }

  return data.keyCode == 54 || data.keyCode == 55;
}
