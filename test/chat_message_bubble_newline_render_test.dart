import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Chat bubble markdown keeps newline rendering', (tester) async {
    final backend = TestAppBackend(
      initialMessages: const <Message>[
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'line 1\nline 2',
          createdAtMs: 1,
          isMemory: true,
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

    final bubble = find.byKey(const ValueKey('message_bubble_m1'));
    expect(bubble, findsOneWidget);

    final markdownFinder = find.descendant(
      of: bubble,
      matching: find.byType(MarkdownBody),
    );
    expect(markdownFinder, findsOneWidget);

    final markdown = tester.widget<MarkdownBody>(markdownFinder);
    expect(markdown.data, contains('\n'));
    expect(markdown.softLineBreak, isTrue);
  });
}
