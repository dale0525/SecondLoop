import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

Future<void> confirmChatMessageDelete(WidgetTester tester) async {
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('chat_delete_message_confirm')));
  await tester.pumpAndSettle();
}

Future<void> confirmChatTodoDelete(WidgetTester tester) async {
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('chat_delete_todo_confirm')));
  await tester.pumpAndSettle();
}

Widget wrapChatForTests({required AppBackend backend, SyncEngine? syncEngine}) {
  return wrapWithI18n(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
      ),
      home: SyncEngineScope(
        engine: syncEngine,
        child: AppBackendScope(
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
}
