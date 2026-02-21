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
  testWidgets('Ask AI messages show a visual badge', (tester) async {
    final backend = TestAppBackend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'user',
          content: 'capture',
          createdAtMs: 1,
          isMemory: true,
        ),
        Message(
          id: 'm2',
          conversationId: 'loop_home',
          role: 'user',
          content: 'ask ai question',
          createdAtMs: 2,
          isMemory: false,
        ),
      ],
    );

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
                  id: 'loop_home',
                  title: 'Loop',
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

    expect(find.byKey(const ValueKey('message_ask_ai_badge_m1')), findsNothing);
    expect(
        find.byKey(const ValueKey('message_ask_ai_badge_m2')), findsOneWidget);
  });
}
