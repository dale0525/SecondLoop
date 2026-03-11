import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('message viewer secondloop message link opens referenced message',
      (tester) async {
    final backend = TestAppBackend(
      initialMessages: const [
        Message(
          id: 'history-2',
          conversationId: 'loop_home',
          role: 'user',
          content: 'Budget review happened last Monday.',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: '[Open prior note](secondloop://message/history-2)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open prior note', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('message_viewer_page')), findsNWidgets(2));
    expect(
      find.text('Budget review happened last Monday.', findRichText: true),
      findsOneWidget,
    );
  });
}
