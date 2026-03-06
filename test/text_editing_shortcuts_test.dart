import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/text_editing_shortcuts.dart';

void main() {
  test('modifier-only key does not resolve to select all', () {
    final shortcut = resolveTextEditingShortcut(
      key: LogicalKeyboardKey.metaLeft,
      keyLabel: 'a',
      character: 'a',
      metaPressed: true,
      controlPressed: false,
      shiftPressed: false,
      supportedShortcuts: const {
        TextEditingShortcut.selectAll,
        TextEditingShortcut.copy,
        TextEditingShortcut.paste,
        TextEditingShortcut.cut,
      },
    );

    expect(shortcut, isNull);
  });

  test('meta+v still resolves to paste', () {
    final shortcut = resolveTextEditingShortcut(
      key: LogicalKeyboardKey.keyV,
      keyLabel: 'v',
      character: 'v',
      metaPressed: true,
      controlPressed: false,
      shiftPressed: false,
      supportedShortcuts: const {
        TextEditingShortcut.selectAll,
        TextEditingShortcut.copy,
        TextEditingShortcut.paste,
        TextEditingShortcut.cut,
      },
    );

    expect(shortcut, TextEditingShortcut.paste);
  });

  test('macOS command modifier keydown is detected', () {
    final isCommandOnly = isMacOsCommandModifierKeyDown(
      const RawKeyDownEvent(
        data: RawKeyEventDataMacOs(
          keyCode: 55,
          modifiers: RawKeyEventDataMacOs.modifierCommand |
              RawKeyEventDataMacOs.modifierLeftCommand,
        ),
      ),
    );

    expect(isCommandOnly, isTrue);
  });

  test('macOS command+a is not treated as command-only modifier event', () {
    final isCommandOnly = isMacOsCommandModifierKeyDown(
      const RawKeyDownEvent(
        data: RawKeyEventDataMacOs(
          characters: 'a',
          charactersIgnoringModifiers: 'a',
          keyCode: 0,
          modifiers: RawKeyEventDataMacOs.modifierCommand |
              RawKeyEventDataMacOs.modifierLeftCommand,
        ),
      ),
    );

    expect(isCommandOnly, isFalse);
  });

  test('text editing shortcut dispatch ignores macOS command-only keydown', () {
    final shouldIgnore = shouldIgnoreTextEditingShortcutEvent(
      const RawKeyDownEvent(
        data: RawKeyEventDataMacOs(
          keyCode: 55,
          modifiers: RawKeyEventDataMacOs.modifierCommand |
              RawKeyEventDataMacOs.modifierLeftCommand,
        ),
      ),
    );

    expect(shouldIgnore, isTrue);
  });
}
