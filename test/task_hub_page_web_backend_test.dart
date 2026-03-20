import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';

import 'test_i18n.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) async {
  for (var i = 0; i < 120; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const ValueKey('task_hub_page')).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  expect(find.byKey(const ValueKey('task_hub_page')), findsOneWidget);
}

void main() {
  testWidgets('TaskHubPage opens detail page with backend scopes on web',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:task-hub-web',
      title: 'TaskHub web task',
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
              child: const TaskHubPage(),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilTaskHubReady(tester);
    expect(find.byKey(const ValueKey('task_hub_page_item_todo:task-hub-web')),
        findsOneWidget);

    await tester.tap(find.text('TaskHub web task'));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('todo_detail_input')),
    );

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_input')),
      'task hub web note',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('task hub web note'));

    final activities =
        await backend.listTodoActivities(key, 'todo:task-hub-web');
    expect(activities, hasLength(1));
    expect(activities.single.activityType, 'note');
    expect(activities.single.content, 'task hub web note');
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
