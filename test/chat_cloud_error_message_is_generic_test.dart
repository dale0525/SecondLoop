import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

const _kAskAiErrorPrefix = '\u001eSL_ERROR\u001e';

void main() {
  testWidgets('Ask AI cloud errors stay generic in the chat bubble',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'embeddings_data_consent_v1': false,
    });

    final backend = _CloudErrorBackend();
    final cloudAuth = _FakeCloudAuthController(idToken: 'test-id-token');

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.test',
                modelName: 'gpt-test',
              ),
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
      ),
    );
    await tester.pumpAndSettle();

    const question = 'hello?';
    await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    final pendingBubble =
        find.byKey(const ValueKey('message_bubble_pending_assistant'));
    expect(pendingBubble, findsOneWidget);

    final pendingMarkdown = find.descendant(
      of: pendingBubble,
      matching: find.byType(MarkdownBody),
    );
    final pendingMarkdownData =
        tester.widget<MarkdownBody>(pendingMarkdown).data;
    expect(pendingMarkdownData, startsWith('Ask AI failed'));
    expect(pendingMarkdownData, isNot(contains('HTTP 502')));
    expect(pendingMarkdownData, isNot(contains('upstream_error')));
    expect(backend.lastTopK, 0);

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

final class _CloudErrorBackend extends TestAppBackend {
  int? lastTopK;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

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
  }) {
    lastTopK = topK;
    return Stream<String>.fromFuture(
      Future<String>.delayed(
        const Duration(milliseconds: 10),
        () =>
            '${_kAskAiErrorPrefix}cloud-gateway request failed: HTTP 502 {"error":"upstream_error"}',
      ),
    );
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({required this.idToken});

  final String idToken;

  @override
  Future<String?> getIdToken() async => idToken;

  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
