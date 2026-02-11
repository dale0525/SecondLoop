import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/embeddings_index_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets('Embeddings BYOK preference falls back to local on BYOK error',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_source_preference_v1': 'byok',
      'embeddings_data_consent_v1': false,
    });

    final backend = _FakeEmbeddingsNativeBackend(
      embeddingProfiles: const <EmbeddingProfile>[
        EmbeddingProfile(
          id: 'embed_1',
          name: 'Active',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'text-embedding-3-small',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      throwOnByok: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const EmbeddingsIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(backend.calls, isEmpty);

    await tester.pump(const Duration(seconds: 3));

    expect(backend.calls, contains('byok'));
    expect(backend.calls, contains('local'));
  });

  testWidgets(
      'Embeddings cloud preference falls back to BYOK when not entitled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_source_preference_v1': 'cloud',
      'embeddings_data_consent_v1': true,
    });

    final backend = _FakeEmbeddingsNativeBackend(
      embeddingProfiles: const <EmbeddingProfile>[
        EmbeddingProfile(
          id: 'embed_1',
          name: 'Active',
          providerType: 'openai-compatible',
          baseUrl: 'https://api.openai.com/v1',
          modelName: 'text-embedding-3-small',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudAuthScope(
          controller: _FakeCloudAuthController(),
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'gpt-test',
          ),
          child: SubscriptionScope(
            controller: _FakeSubscriptionStatusController(
                SubscriptionStatus.notEntitled),
            child: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const EmbeddingsIndexGate(child: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(backend.calls, contains('byok'));
    expect(backend.calls, isNot(contains('cloud')));
  });
}

final class _FakeEmbeddingsNativeBackend extends NativeAppBackend {
  _FakeEmbeddingsNativeBackend({
    required this.embeddingProfiles,
    this.throwOnByok = false,
  }) : super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<EmbeddingProfile> embeddingProfiles;
  final bool throwOnByok;
  final List<String> calls = <String>[];

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    return embeddingProfiles;
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsCloudGateway(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    calls.add('cloud');
    return 0;
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    calls.add('byok');
    if (throwOnByok) {
      throw StateError('byok-failed');
    }
    return 0;
  }

  @override
  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    calls.add('local');
    return 0;
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'token';

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
