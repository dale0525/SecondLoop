// ignore_for_file: deprecated_member_use

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
  testWidgets('Chat input: Shift+Enter from key modifiers inserts newline',
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
                    id: 'chat_home',
                    title: 'Chat',
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
      await tester.enterText(inputFinder, 'hello');

      final focusWidgets = find
          .ancestor(of: inputFinder, matching: find.byType(Focus))
          .evaluate()
          .map((e) => e.widget)
          .whereType<Focus>()
          .where((w) => w.onKey != null && w.child is TextField)
          .toList();
      expect(focusWidgets.length, 1);

      final onKey = focusWidgets.single.onKey!;
      final focusNode = FocusNode();
      try {
        final event = RawKeyDownEvent(
          data: RawKeyEventDataMacOs(
            keyCode: 0x24,
            characters: '\n',
            charactersIgnoringModifiers: '\n',
            modifiers: RawKeyEventDataMacOs.modifierShift,
            specifiedLogicalKey: LogicalKeyboardKey.enter.keyId,
          ),
          character: '\n',
        );
        final result = onKey(focusNode, event);
        expect(result, KeyEventResult.handled);
      } finally {
        focusNode.dispose();
      }

      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(inputFinder);
      expect(field.controller!.text, 'hello\n');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
