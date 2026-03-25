import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoAgendaPage updates todo status on web backend',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List(0);
    await backend.upsertTodo(
      key,
      id: 't1',
      title: 'Agenda web task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: const TodoAgendaPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_agenda_item_t1')), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('todo_agenda_set_status_t1_done')));
    await tester.pumpAndSettle();

    final updated =
        (await backend.listTodos(key)).singleWhere((todo) => todo.id == 't1');
    expect(updated.status, 'done');

    final activities = await backend.listTodoActivities(key, 't1');
    expect(
        activities.any((item) =>
            item.activityType == 'status_change' && item.toStatus == 'done'),
        isTrue);
  });

  testWidgets('TodoAgendaPage opens history page backed by web task history',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List(0);
    await backend.upsertTodo(
      key,
      id: 't1',
      title: 'Agenda history task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );
    await backend.setTodoStatus(
      key,
      todoId: 't1',
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
              child: const TodoAgendaPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_history_this_week')));
    await tester.pumpAndSettle();

    final summary = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data?.contains('Done (1)') ?? false) &&
          (widget.data?.contains('- Agenda history task') ?? false),
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
