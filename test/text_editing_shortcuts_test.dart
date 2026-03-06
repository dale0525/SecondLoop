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
}
