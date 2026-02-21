import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  testWidgets('Ask AI retries cloud without embeddings when embeddings fail',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'embeddings_data_consent_v1': true,
    });

    final backend = _Backend();
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      equals(<String>[
        'askAiStreamCloudGatewayWithEmbeddings',
        'askAiStreamCloudGateway',
      ]),
    );
    expect(backend.plainCloudTopK, 0);
    expect(find.textContaining('Ask AI failed'), findsNothing);
  });
}

final class _Backend extends TestAppBackend {
  final List<String> calls = <String>[];
  int? plainCloudTopK;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) {
    calls.add('askAiStreamCloudGatewayWithEmbeddings');
    return Stream<String>.fromIterable(const [
      '${_kAskAiErrorPrefix}cloud-gateway embedding model_id mismatch: expected a, got b',
    ]);
  }

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
    calls.add('askAiStreamCloudGateway');
    plainCloudTopK = topK;
    return Stream<String>.fromIterable(const ['ok']);
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
