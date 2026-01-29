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
  testWidgets('Chat inserts date dividers between day groups', (tester) async {
    final jan27 = DateTime(2026, 1, 27, 10, 0).millisecondsSinceEpoch;
    final jan28 = DateTime(2026, 1, 28, 10, 0).millisecondsSinceEpoch;

    final backend = _Backend(
      initialMessages: [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'Old',
          createdAtMs: jan27,
          isMemory: true,
        ),
        Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'user',
          content: 'New',
          createdAtMs: jan28,
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

    expect(
        find.byKey(const ValueKey('message_date_divider_m1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('message_date_divider_m2')), findsOneWidget);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Message> initialMessages})
      : super(initialMessages: initialMessages);

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    final messages = await listMessages(key, conversationId);
    final newestFirst = messages.reversed.toList(growable: false);
    if (beforeId == null) {
      return newestFirst.take(limit).toList(growable: false);
    }

    final cursorIndex = newestFirst.indexWhere((m) => m.id == beforeId);
    if (cursorIndex < 0) return const <Message>[];
    final start = cursorIndex + 1;
    if (start >= newestFirst.length) return const <Message>[];
    return newestFirst.skip(start).take(limit).toList(growable: false);
  }
}
