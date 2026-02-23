import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Chat input: Cmd/Ctrl+C does not trigger select-all due to key mapping',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = TestAppBackend(initialMessages: const <Message>[]);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'main_stream',
                    title: 'Main Stream',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('chat_input'));
      expect(inputFinder, findsOneWidget);

      await tester.tap(inputFinder);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(inputFinder);
      final controller = textField.controller!;

      controller.text = 'hello world';
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pumpAndSettle();

      final before = controller.selection;

      // Simulate the observed bug: on some layouts/platforms, Cmd/Ctrl+C can be
      // reported with a logical key of `keyA` while the typed character is `c`.
      //
      // Chat input should treat this as copy (and keep selection unchanged),
      // not select-all.
      //
      // NOTE: We invoke the chat input's `Focus.onKey` handler directly to
      // ensure we exercise its own shortcut logic (instead of the default text
      // editing shortcuts handling the event earlier in the focus chain).
      final focusWidgets = find
          .ancestor(of: inputFinder, matching: find.byType(Focus))
          .evaluate()
          .map((e) => e.widget)
          .whereType<Focus>();
      // ignore: deprecated_member_use
      final onKey = focusWidgets.firstWhere((w) => w.onKey != null).onKey!;

      final focusNode = FocusNode();
      try {
        HardwareKeyboard.instance.handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.metaLeft,
            logicalKey: LogicalKeyboardKey.metaLeft,
            timeStamp: Duration.zero,
          ),
        );

        // ignore: deprecated_member_use
        final event = RawKeyDownEvent(
          // ignore: deprecated_member_use
          data: RawKeyEventDataMacOs(
            characters: 'c',
            charactersIgnoringModifiers: 'c',
            keyCode: 0,
            modifiers: 0,
            specifiedLogicalKey: LogicalKeyboardKey.keyA.keyId,
          ),
          character: 'c',
        );

        // ignore: deprecated_member_use
        onKey(focusNode, event);
      } finally {
        HardwareKeyboard.instance.handleKeyEvent(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.metaLeft,
            logicalKey: LogicalKeyboardKey.metaLeft,
            timeStamp: Duration.zero,
          ),
        );
        focusNode.dispose();
      }

      expect(controller.selection, before);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
