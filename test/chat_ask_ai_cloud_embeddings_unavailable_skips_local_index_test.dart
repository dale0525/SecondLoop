import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Ask AI skips local embeddings prep when cloud embeddings enabled but unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'embeddings_data_consent_v1': true,
    });

    final backend = _Backend();
    final cloudAuth = _FakeCloudAuthController(idToken: null);
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'gpt-test',
            ),
            child: SubscriptionScope(
              controller: subscriptions,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: AppBackendScope(
                  backend: backend,
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(backend.calls, isNot(contains('processPendingMessageEmbeddings')));
    expect(backend.calls, contains('askAiStream'));
    expect(backend.lastAskTopK, 0);
  });
}

final class _Backend extends TestAppBackend {
  final List<String> calls = <String>[];
  int? lastAskTopK;

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async {
    calls.add('processPendingMessageEmbeddings');
    return 0;
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    calls.add('askAiStream');
    lastAskTopK = topK;
    return const Stream<String>.empty();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({required String? idToken}) : _idToken = idToken;

  final String? _idToken;

  @override
  String? get uid => 'uid-test';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => _idToken;

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

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}
