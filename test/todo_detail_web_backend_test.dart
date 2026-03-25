import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage sends a plain note on web backend',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List(0);
    final todo = await backend.upsertTodo(
      key,
      id: 'todo:web-note',
      title: 'Web note task',
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
              child: TodoDetailPage(initialTodo: todo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_input')),
      'web note',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
    await tester.pumpAndSettle();

    final activities = await backend.listTodoActivities(key, todo.id);
    expect(activities, hasLength(1));
    expect(activities.single.activityType, 'note');
    expect(activities.single.content, 'web note');
    expect(find.textContaining('native_backend_required'), findsNothing);
    expect(find.text('web note'), findsOneWidget);
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
