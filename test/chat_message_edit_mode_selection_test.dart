import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/src/rust/db.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  testWidgets('Editing long chat message defaults to markdown mode',
      (tester) async {
    final longContent = List<String>.filled(
      8,
      'LONG_DEFAULT_MARKDOWN content that should prefer markdown editor mode.',
    ).join('\n');
    final backend = TestAppBackend(
      initialMessages: [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: longContent,
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_preview')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_switch_plain')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_switch_markdown')),
        findsNothing);
  });
}
