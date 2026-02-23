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
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/cloud_subscription_controller.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('startup subscription refresh keeps keychain untouched before unlock',
      () async {
    final store = _InMemoryCloudAuthStore();
    final auth = CloudAuthControllerImpl(
      identityToolkit: _NeverCalledIdentityToolkit(),
      store: store,
      nowMs: () => 1000,
    );

    final subscriptions = CloudSubscriptionController(
      idTokenGetter: () => readCloudIdTokenForBackground(auth),
      cloudGatewayBaseUrl: 'https://gateway.secondloop.test',
    );
    addTearDown(subscriptions.dispose);

    await subscriptions.refresh();

    expect(subscriptions.status, SubscriptionStatus.unknown);
    expect(store.loadCalls, 0);
  });

  testWidgets(
      'embeddings gate avoids loading stored cloud session on cold start',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_source_preference_v1': 'cloud',
      'embeddings_data_consent_v1': true,
    });

    final backend = _FakeEmbeddingsNativeBackend();
    final store = _InMemoryCloudAuthStore(
      const CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'refresh_1'),
    );
    final cloudAuth = CloudAuthControllerImpl(
      identityToolkit: _NeverCalledIdentityToolkit(),
      store: store,
      nowMs: () => 1000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudAuthScope(
          controller: cloudAuth,
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: 'https://gateway.test',
            modelName: 'gpt-test',
          ),
          child: SubscriptionScope(
            controller: _FakeSubscriptionStatusController(
              SubscriptionStatus.entitled,
            ),
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

    expect(backend.calls, contains('local'));
    expect(backend.calls, isNot(contains('cloud')));
    expect(store.loadCalls, 0);
  });
}

final class _InMemoryCloudAuthStore implements CloudAuthStore {
  _InMemoryCloudAuthStore([this._session]);

  CloudAuthStoredSession? _session;
  int loadCalls = 0;

  @override
  Future<CloudAuthStoredSession?> load() async {
    loadCalls += 1;
    return _session;
  }

  @override
  Future<void> save(CloudAuthStoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

final class _NeverCalledIdentityToolkit implements FirebaseIdentityToolkit {
  @override
  Future<FirebaseAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseAuthTokens> signUpWithPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseAuthTokens> refreshIdToken({required String refreshToken}) {
    throw UnimplementedError();
  }

  @override
  Future<FirebaseUserInfo> lookup({required String idToken}) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendOobCode({
    required String requestType,
    required String idToken,
  }) {
    throw UnimplementedError();
  }
}

final class _FakeEmbeddingsNativeBackend extends NativeAppBackend {
  _FakeEmbeddingsNativeBackend()
      : super(appDirProvider: () async => '/tmp/secondloop-test');

  final List<String> calls = <String>[];

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    return const <EmbeddingProfile>[];
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

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}
