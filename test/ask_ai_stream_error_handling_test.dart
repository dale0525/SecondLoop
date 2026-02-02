import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Ask AI stream error does not crash and resets state',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});

    final backend = _Backend();

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

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.textContaining('removed in 3 seconds'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_stop')), findsNothing);
    expect(backend.askCalls, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_user')),
        findsNothing);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
    expect(field.controller?.text, 'hello?');
    expect(find.byKey(const ValueKey('chat_ask_ai')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _Backend extends TestAppBackend {
  int _llmProfilesCalls = 0;
  int askCalls = 0;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    _llmProfilesCalls += 1;
    if (_llmProfilesCalls >= 2) {
      throw StateError('list_llm_profiles_failed');
    }
    return const <LlmProfile>[
      LlmProfile(
        id: 'p1',
        name: 'OpenAI',
        providerType: 'openai-compatible',
        baseUrl: 'https://api.openai.com/v1',
        modelName: 'gpt-4o-mini',
        isActive: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    ];
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    askCalls += 1;
    return Stream<String>.error(StateError('HTTP 500'));
  }
}
