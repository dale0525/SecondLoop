import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
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
  testWidgets('MessageViewerPage preserves scopes for nested message links',
      (tester) async {
    final backend = _MessageViewerBackend(
      messages: const <Message>[
        Message(
          id: 'm1',
          conversationId: 'c1',
          role: 'assistant',
          content: '[Open nested](secondloop://message/m2)',
          createdAtMs: 1,
          isMemory: false,
        ),
        Message(
          id: 'm2',
          conversationId: 'c1',
          role: 'assistant',
          content: 'Nested message content',
          createdAtMs: 2,
          isMemory: false,
        ),
      ],
    );
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_message_viewer_launcher'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey: key,
                            lock: () {},
                            child: Builder(
                              builder: (context) => Scaffold(
                                body: Center(
                                  child: ElevatedButton(
                                    key: const ValueKey('open_message_viewer'),
                                    onPressed: () => MessageViewerPage.openById(
                                      context,
                                      messageId: 'm1',
                                    ),
                                    child: const Text('Open message viewer'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open scoped launcher'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('open_message_viewer_launcher')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('open_message_viewer')),
    );

    await tester.tap(find.byKey(const ValueKey('open_message_viewer')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('message_viewer_page')),
    );
    await _pumpUntilFound(tester, find.text('Open nested'));

    await tester.tap(find.text('Open nested'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('Nested message content'));
  });
}

final class _MessageViewerBackend extends TestAppBackend {
  _MessageViewerBackend({required List<Message> messages})
      : _messagesById = {for (final message in messages) message.id: message};

  final Map<String, Message> _messagesById;

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    return _messagesById[messageId];
  }
}
