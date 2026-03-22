import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/inbox/inbox_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('InboxPage opens chat page with web scopes', (tester) async {
    final backend = CloudWebBackend(
      chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    final conversation = await backend.createConversation(key, 'Inbox thread');
    await backend.upsertTodo(
      key,
      id: 'todo:inbox-chat',
      title: 'Inbox task',
      dueAtMs: DateTime.now().toUtc().millisecondsSinceEpoch + 60000,
      status: 'open',
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_inbox_page'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey: key,
                            lock: () {},
                            child: const Scaffold(body: InboxPage()),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open inbox'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_inbox_page')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(ValueKey('conversation_${conversation.id}')),
    );

    await tester.tap(find.byKey(ValueKey('conversation_${conversation.id}')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(ChatPage));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_banner')),
    );
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
