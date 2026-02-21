import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Scroll up shows jump-to-latest button', (tester) async {
    final messages = List.generate(
      80,
      (i) => Message(
        id: 'm${i + 1}',
        conversationId: 'chat_home',
        role: 'user',
        content: 'm${i + 1}',
        createdAtMs: i + 1,
        isMemory: true,
      ),
    );
    final backend = TestAppBackend(initialMessages: messages);

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

    final buttonFinder = find.byKey(const ValueKey('chat_jump_to_latest'));
    expect(buttonFinder, findsNothing);

    final listFinder = find.byKey(const ValueKey('chat_message_list'));
    await tester.drag(listFinder, const Offset(0, 800));
    await tester.pumpAndSettle();

    expect(buttonFinder, findsOneWidget);

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(buttonFinder, findsNothing);
  });
}
