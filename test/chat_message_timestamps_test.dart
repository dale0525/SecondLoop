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
  testWidgets('Chat message bubbles do not render timestamp text',
      (tester) async {
    final backend = _Backend(
      initialMessages: [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'Hello',
          createdAtMs: DateTime(2026, 1, 27, 10, 0).millisecondsSinceEpoch,
          isMemory: true,
        ),
      ],
    );

    await _pumpChat(tester, backend);

    expect(
      find.byKey(const ValueKey('message_timestamp_m1')),
      findsNothing,
    );
  });

  testWidgets('Chat skips extra time divider for short message intervals',
      (tester) async {
    final base = DateTime(2026, 1, 27, 10, 0);
    final backend = _Backend(
      initialMessages: [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'First',
          createdAtMs: base.millisecondsSinceEpoch,
          isMemory: true,
        ),
        Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'assistant',
          content: 'Second',
          createdAtMs:
              base.add(const Duration(minutes: 3)).millisecondsSinceEpoch,
          isMemory: true,
        ),
      ],
    );

    await _pumpChat(tester, backend);

    expect(
      find.byKey(const ValueKey('message_time_divider_m2')),
      findsNothing,
    );
  });

  testWidgets('Chat shows interleaved time divider for long message intervals',
      (tester) async {
    final base = DateTime(2026, 1, 27, 10, 0);
    final backend = _Backend(
      initialMessages: [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'First',
          createdAtMs: base.millisecondsSinceEpoch,
          isMemory: true,
        ),
        Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'assistant',
          content: 'Second',
          createdAtMs:
              base.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
          isMemory: true,
        ),
      ],
    );

    await _pumpChat(tester, backend);

    expect(
      find.byKey(const ValueKey('message_time_divider_m2')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpChat(WidgetTester tester, AppBackend backend) async {
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
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Message> initialMessages})
      : super(initialMessages: initialMessages);
}
