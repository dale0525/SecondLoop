import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'chat_todo_message_type_badges_test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
  });

  testWidgets(
    'convert todo to info also clears related linked messages',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm11',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Book hotel for trip',
            createdAtMs: 11,
            isMemory: true,
          ),
          Message(
            id: 'm12',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Done, booked it and sent confirmation',
            createdAtMs: 12,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't11',
            title: 'Book hotel for trip',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
            sourceEntryId: 'm11',
          ),
        ],
        jobsByMessageId: <String, SemanticParseJob>{
          'm11': _job(
            messageId: 'm11',
            actionKind: 'create',
            todoId: 't11',
            todoTitle: 'Book hotel for trip',
          ),
          'm12': _job(
            messageId: 'm12',
            actionKind: 'followup',
            todoId: 't11',
            todoTitle: 'Book hotel for trip',
          ),
        },
        todoActivities: const [
          TodoActivity(
            id: 'a11',
            todoId: 't11',
            activityType: 'note',
            content: 'Done, booked it and sent confirmation',
            sourceMessageId: 'm12',
            createdAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            locale: const Locale('en'),
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

      await tester.longPress(find.byKey(const ValueKey('message_bubble_m11')));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('message_action_convert_to_info')));
      await tester.pumpAndSettle();

      expect(find.text('Convert to note?'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        backend.undoneSemanticJobMessageIds.toSet(),
        containsAll(<String>{'m11', 'm12'}),
      );
    },
    skip: true,
  );
}

SemanticParseJob _job({
  required String messageId,
  required String actionKind,
  required String todoId,
  required String todoTitle,
}) {
  return SemanticParseJob(
    messageId: messageId,
    status: 'succeeded',
    attempts: PlatformInt64Util.from(1),
    nextRetryAtMs: null,
    lastError: null,
    appliedActionKind: actionKind,
    appliedTodoId: todoId,
    appliedTodoTitle: todoTitle,
    appliedPrevTodoStatus: null,
    undoneAtMs: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

typedef _Backend = ChatTodoMessageTypeBadgesTestBackend;
