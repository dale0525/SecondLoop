import 'dart:async';
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
  testWidgets('Ask AI shows animation while waiting for first token',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});

    final streamController = StreamController<String>();
    addTearDown(streamController.close);
    final backend = _Backend(streamController: streamController);

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
                  id: 'loop_home',
                  title: 'Loop',
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

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('ask_ai_waiting_indicator')), findsOneWidget);
  });

  testWidgets('Ask AI shows typing indicator while streaming text',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});

    final streamController = StreamController<String>();
    addTearDown(streamController.close);
    final backend = _Backend(streamController: streamController);

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
                  id: 'loop_home',
                  title: 'Loop',
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

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();

    streamController.add('Hi');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsOneWidget);
    expect(find.textContaining('Hi'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ask_ai_typing_indicator')), findsOneWidget);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required this.streamController});

  final StreamController<String> streamController;

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      streamController.stream;

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      streamController.stream;
}
