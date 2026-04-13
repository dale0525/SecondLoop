import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

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

Widget _buildLauncher(
    {required CloudWebBackend backend, required Uint8List key}) {
  return wrapWithI18n(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open_chat_page'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppBackendScope(
                      backend: backend,
                      child: SessionScope(
                        sessionKey: key,
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
                );
              },
              child: const Text('Open chat'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Chat task hub banner opens todo detail with web scopes',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:chat-web',
      title: 'Chat web task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(_buildLauncher(backend: backend, key: key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_chat_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    await tester.tap(find.byKey(const ValueKey('chat_open_task_center')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(TaskHubPage));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_item_todo:chat-web')),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('task_hub_page_item_todo:chat-web')),
        matching: find.text('Chat web task'),
      ),
    );
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('todo_detail_input')),
    );

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_input')),
      'chat scope note',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('todo_detail_send')));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('chat scope note'));

    final activities = await backend.listTodoActivities(key, 'todo:chat-web');
    expect(activities, hasLength(1));
    expect(activities.single.activityType, 'note');
  });

  testWidgets('Chat task hub banner opens task hub page with web scopes',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:chat-hub',
      title: 'Chat hub task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(_buildLauncher(backend: backend, key: key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_chat_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    await tester.tap(find.byKey(const ValueKey('chat_open_task_center')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(TaskHubPage));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_item_todo:chat-hub')),
    );
  });

  testWidgets('Chat page header exposes a stable task center entry',
      (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    await backend.upsertTodo(
      key,
      id: 'todo:chat-header',
      title: 'Chat header task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(_buildLauncher(backend: backend, key: key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_chat_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );

    await tester.tap(find.byKey(const ValueKey('chat_open_task_center')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(TaskHubPage));
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
