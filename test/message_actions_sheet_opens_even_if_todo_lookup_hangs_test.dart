import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'Long press opens message actions even if todo lookup hangs',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      final backend = _SlowTodoLookupBackend(
        initialMessages: const [
          Message(
            id: 'm1',
            conversationId: 'main_stream',
            role: 'user',
            content: 'hello',
            createdAtMs: 0,
            isMemory: true,
          ),
        ],
      );

      const conversation = Conversation(
        id: 'main_stream',
        title: 'Main Stream',
        createdAtMs: 0,
        updatedAtMs: 0,
      );

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: wrapWithI18n(
              const MaterialApp(home: ChatPage(conversation: conversation)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('hello'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    },
  );
}

final class _SlowTodoLookupBackend extends TestAppBackend {
  _SlowTodoLookupBackend({super.initialMessages});

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    return Completer<List<TodoActivity>>().future;
  }
}
