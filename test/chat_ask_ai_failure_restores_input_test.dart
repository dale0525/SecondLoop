import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Ask AI failure shows a temporary message and restores input after 3 seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _FailingAskBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
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

    const question = 'hello?';
    await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsOneWidget);
    expect(find.textContaining('removed in 3 seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsNothing);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
    expect(field.controller?.text, question);
  });

  testWidgets(
      'Ask AI empty stream is treated as failure and restores input after 3 seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = TestAppBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
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

    const question = 'hello?';
    await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsOneWidget);
    expect(find.textContaining('removed in 3 seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsNothing);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
    expect(field.controller?.text, question);
  });
}

final class _FailingAskBackend extends TestAppBackend {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    return Stream<String>.fromFuture(
      Future<String>.error(StateError('HTTP 500')),
    );
  }
}
