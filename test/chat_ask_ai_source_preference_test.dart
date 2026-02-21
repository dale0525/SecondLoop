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
      'Ask AI preference BYOK forces BYOK stream when cloud is available',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'ask_ai_source_preference_v1': 'byok',
    });

    final backend = _AskAiPreferenceBackend(hasByokProfile: true);

    await tester.pumpWidget(
      _buildChatHarness(
        backend: backend,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_ask_ai')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('askAiStream'));
    expect(backend.calls, isNot(contains('askAiStreamCloudGateway')));
  });

  testWidgets(
      'Ask AI preference BYOK shows configure entry when no BYOK profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': true,
      'ask_ai_source_preference_v1': 'byok',
    });

    final backend = _AskAiPreferenceBackend(hasByokProfile: false);

    await tester.pumpWidget(
      _buildChatHarness(
        backend: backend,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello?');
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_configure_ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_ask_ai')), findsNothing);
  });
}

Widget _buildChatHarness({required AppBackend backend}) {
  final subscriptionController =
      _FakeSubscriptionStatusController(SubscriptionStatus.entitled);
  final cloudAuthController = _FakeCloudAuthController();

  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: CloudAuthScope(
          controller: cloudAuthController,
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'gpt-test',
          ),
          child: SubscriptionScope(
            controller: subscriptionController,
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
}

final class _AskAiPreferenceBackend extends TestAppBackend {
  _AskAiPreferenceBackend({required this.hasByokProfile});

  final bool hasByokProfile;
  final List<String> calls = <String>[];

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    if (!hasByokProfile) {
      return const <LlmProfile>[];
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
    calls.add('askAiStream');
    return Stream<String>.fromIterable(const ['ok']);
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
    return Stream<String>.fromIterable(const ['cloud']);
  }
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

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
