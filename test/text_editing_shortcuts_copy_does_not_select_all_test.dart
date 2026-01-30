// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Desktop: Cmd/Ctrl+C does not trigger select-all due to key mapping',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = TextEditingController(text: 'hello world');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TextEditingShortcutsFallback(
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pumpAndSettle();

      final before = controller.selection;

      // Simulate the observed bug: on some layouts/platforms, Cmd/Ctrl+C can be
      // reported with a logical key of `keyA` while the typed character is `c`.
      //
      // The app should treat this as copy (and keep selection unchanged), not
      // select-all.
      final focusWidgets = find
          .ancestor(of: find.byType(TextField), matching: find.byType(Focus))
          .evaluate()
          .map((e) => e.widget)
          .whereType<Focus>();
      final onKey = focusWidgets.firstWhere((w) => w.onKey != null).onKey!;

      RawKeyDownEvent buildMacOsEvent({
        required int modifiers,
        required String keyLabel,
      }) {
        return RawKeyDownEvent(
          data: RawKeyEventDataMacOs(
            characters: keyLabel,
            charactersIgnoringModifiers: keyLabel,
            keyCode: 0,
            modifiers: modifiers,
            specifiedLogicalKey: LogicalKeyboardKey.keyA.keyId,
          ),
          character: keyLabel,
        );
      }

      final focusNode = FocusNode();
      try {
        onKey(
          focusNode,
          buildMacOsEvent(
            modifiers: RawKeyEventDataMacOs.modifierCommand,
            keyLabel: 'c',
          ),
        );
      } finally {
        focusNode.dispose();
      }
      await tester.pump();

      expect(controller.selection, before);

      final focusNode2 = FocusNode();
      try {
        onKey(
          focusNode2,
          buildMacOsEvent(
            modifiers: RawKeyEventDataMacOs.modifierControl,
            keyLabel: 'c',
          ),
        );
      } finally {
        focusNode2.dispose();
      }
      await tester.pump();

      expect(controller.selection, before);

      // Ensure Select All still works (Cmd/Ctrl+A).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      );

      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _TextEditingShortcutsFallback extends StatelessWidget {
  const _TextEditingShortcutsFallback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKey: (node, event) {
        if (event is! RawKeyDownEvent) {
          return KeyEventResult.ignored;
        }

        if (event.repeat) {
          return KeyEventResult.ignored;
        }

        final metaPressed = event.isMetaPressed;
        final controlPressed = event.isControlPressed;
        final shiftPressed = event.isShiftPressed;
        final hasModifier = metaPressed || controlPressed;
        if (!hasModifier) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;
        bool isTextEditingShortcutChar(String char) =>
            char == 'a' ||
            char == 'c' ||
            char == 'v' ||
            char == 'x' ||
            char == 'z' ||
            char == 'y';

        String? keyChar;
        final keyLabel = event.data.keyLabel;
        if (keyLabel.length == 1) {
          final lowered = keyLabel.toLowerCase();
          if (isTextEditingShortcutChar(lowered)) {
            keyChar = lowered;
          }
        }
        if (keyChar == null) {
          final rawChar = event.character;
          if (rawChar != null && rawChar.length == 1) {
            final lowered = rawChar.toLowerCase();
            if (isTextEditingShortcutChar(lowered)) {
              keyChar = lowered;
            }
          }
        }

        Intent? intent;
        switch (keyChar) {
          case 'a':
            intent = const SelectAllTextIntent(
              SelectionChangedCause.keyboard,
            );
            break;
          case 'c':
            intent = CopySelectionTextIntent.copy;
            break;
          case 'x':
            intent = const CopySelectionTextIntent.cut(
              SelectionChangedCause.keyboard,
            );
            break;
          case 'v':
            intent = const PasteTextIntent(
              SelectionChangedCause.keyboard,
            );
            break;
          case 'z':
            intent = shiftPressed
                ? const RedoTextIntent(SelectionChangedCause.keyboard)
                : const UndoTextIntent(SelectionChangedCause.keyboard);
            break;
          case 'y':
            intent = const RedoTextIntent(SelectionChangedCause.keyboard);
            break;
        }

        if (intent == null) {
          if (key == LogicalKeyboardKey.keyA) {
            intent = const SelectAllTextIntent(
              SelectionChangedCause.keyboard,
            );
          } else if (key == LogicalKeyboardKey.keyC ||
              key == LogicalKeyboardKey.copy) {
            intent = CopySelectionTextIntent.copy;
          } else if (key == LogicalKeyboardKey.keyX ||
              key == LogicalKeyboardKey.cut) {
            intent = const CopySelectionTextIntent.cut(
              SelectionChangedCause.keyboard,
            );
          } else if (key == LogicalKeyboardKey.keyV ||
              key == LogicalKeyboardKey.paste) {
            intent = const PasteTextIntent(
              SelectionChangedCause.keyboard,
            );
          } else if (key == LogicalKeyboardKey.keyZ && !shiftPressed) {
            intent = const UndoTextIntent(
              SelectionChangedCause.keyboard,
            );
          } else if (key == LogicalKeyboardKey.keyY ||
              (key == LogicalKeyboardKey.keyZ && shiftPressed)) {
            intent = const RedoTextIntent(
              SelectionChangedCause.keyboard,
            );
          }
        }

        if (intent == null) {
          return KeyEventResult.ignored;
        }

        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext == null) {
          return KeyEventResult.ignored;
        }

        final action = Actions.maybeFind<Intent>(
          focusContext,
          intent: intent,
        );
        if (action == null || !action.isEnabled(intent)) {
          return KeyEventResult.ignored;
        }

        Actions.invoke(focusContext, intent);
        return KeyEventResult.handled;
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          CharacterActivator('c', control: true): CopySelectionTextIntent.copy,
          CharacterActivator('c', meta: true): CopySelectionTextIntent.copy,
          SingleActivator(LogicalKeyboardKey.keyC, control: true):
              CopySelectionTextIntent.copy,
          SingleActivator(LogicalKeyboardKey.keyC, meta: true):
              CopySelectionTextIntent.copy,
          SingleActivator(LogicalKeyboardKey.copy):
              CopySelectionTextIntent.copy,
          CharacterActivator('v', control: true):
              PasteTextIntent(SelectionChangedCause.keyboard),
          CharacterActivator('v', meta: true):
              PasteTextIntent(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.keyV, control: true):
              PasteTextIntent(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              PasteTextIntent(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.paste):
              PasteTextIntent(SelectionChangedCause.keyboard),
          CharacterActivator('x', control: true):
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          CharacterActivator('x', meta: true):
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.keyX, control: true):
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.keyX, meta: true):
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          SingleActivator(LogicalKeyboardKey.cut):
              CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          CharacterActivator('a', control: true):
              SelectAllTextIntent(SelectionChangedCause.keyboard),
          CharacterActivator('a', meta: true):
              SelectAllTextIntent(SelectionChangedCause.keyboard),
        },
        child: child,
      ),
    );
  }
}
