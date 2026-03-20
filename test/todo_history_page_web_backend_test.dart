import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_history_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'TodoHistoryPage shows done summary from web backend activity log',
      (tester) async {
    var nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      nowMs: () => nowMs,
    );
    final key = Uint8List(0);

    await backend.upsertTodo(
      key,
      id: 'todo:history',
      title: 'History task',
      status: 'open',
    );
    nowMs += 1;
    await backend.setTodoStatus(
      key,
      todoId: 'todo:history',
      newStatus: 'done',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: const TodoHistoryPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_history_this_week')));
    await tester.pumpAndSettle();

    final summary = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data?.contains('Done (1)') ?? false) &&
          (widget.data?.contains('- History task') ?? false),
    );
    expect(summary, findsOneWidget);
  });
}

final class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({required this.responseText});

  final String responseText;

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    return responseText;
  }
}
