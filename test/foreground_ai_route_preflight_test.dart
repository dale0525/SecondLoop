import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/foreground_ai_route_preflight.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_store.dart';
import 'package:secondloop/core/cloud/firebase_identity_toolkit.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('prepared followup route requires token only for cloud', () {
    expect(
      canRunPreparedTodoFollowupGenerationRoute(
        const TodoFollowupGenerationPreparedRoute(
          route: AskAiRouteKind.byok,
          idToken: null,
        ),
      ),
      isTrue,
    );

    expect(
      canRunPreparedTodoFollowupGenerationRoute(
        const TodoFollowupGenerationPreparedRoute(
          route: AskAiRouteKind.cloudGateway,
          idToken: null,
        ),
      ),
      isFalse,
    );

    expect(
      canRunPreparedTodoFollowupGenerationRoute(
        const TodoFollowupGenerationPreparedRoute(
          route: AskAiRouteKind.cloudGateway,
          idToken: 'token_1',
        ),
      ),
      isTrue,
    );
  });

  test('cloud route can opt into web search explicitly', () {
    expect(
      supportsTodoFollowupWebSearch(
        route: AskAiRouteKind.cloudGateway,
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://example.com',
          modelName: 'cloud',
          supportsWebSearch: true,
        ),
      ),
      isTrue,
    );
  });

  test('byok stays model-knowledge only by default', () {
    expect(
      supportsTodoFollowupWebSearch(
        route: AskAiRouteKind.byok,
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://example.com',
          modelName: 'cloud',
          supportsWebSearch: true,
        ),
      ),
      isFalse,
    );
  });

  test('manual regenerate can use cloud when entitlement is still unknown',
      () async {
    final route = await decideTodoFollowupGenerationRoute(
      _FakeBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: true,
      cloudIdToken: 'token_1',
      cloudGatewayBaseUrl: 'https://example.com',
      subscriptionStatus: SubscriptionStatus.unknown,
    );

    expect(route, AskAiRouteKind.cloudGateway);
  });

  test('automatic followup still blocks cloud when entitlement is unknown',
      () async {
    final route = await decideTodoFollowupGenerationRoute(
      _FakeBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: false,
      cloudIdToken: 'token_1',
      cloudGatewayBaseUrl: 'https://example.com',
      subscriptionStatus: SubscriptionStatus.unknown,
    );

    expect(route, AskAiRouteKind.needsSetup);
  });

  test('interactive ask-ai preflight warms cloud only after cloud route',
      () async {
    final toolkit = _RefreshingIdentityToolkit();
    final store = _InMemoryCloudAuthStore(
      const CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'refresh_1'),
    );
    final controller = CloudAuthControllerImpl(
      identityToolkit: toolkit,
      store: store,
      nowMs: () => 1000,
    );

    final prepared = await prepareForegroundAiRoute(
      _FakeBackend(),
      _sessionKey,
      routePolicy: ForegroundAiRoutePolicy.askAi,
      cloudAuthController: controller,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.unknown,
      warmupPolicy: ForegroundAiWarmupPolicy.cloudOnly,
    );

    expect(prepared.route, AskAiRouteKind.cloudGateway);
    expect(prepared.idToken, 'id_token_1');
    expect(store.loadCalls, 1);
    expect(toolkit.refreshCalls, 1);
  });

  test('interactive automation preflight falls back to needsSetup on errors',
      () async {
    final prepared = await prepareForegroundAiRoute(
      _ThrowingRouteBackend(),
      _sessionKey,
      routePolicy: ForegroundAiRoutePolicy.automation,
      cloudAuthController: null,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.entitled,
      warmupPolicy: ForegroundAiWarmupPolicy.always,
      fallbackToNeedsSetupOnRouteError: true,
    );

    expect(prepared.route, AskAiRouteKind.needsSetup);
    expect(prepared.idToken, isNull);
  });

  test('shared followup preflight reuses background auth + manual route',
      () async {
    final toolkit = _RefreshingIdentityToolkit();
    final store = _InMemoryCloudAuthStore(
      const CloudAuthStoredSession(uid: 'uid_1', refreshToken: 'refresh_1'),
    );
    final controller = CloudAuthControllerImpl(
      identityToolkit: toolkit,
      store: store,
      nowMs: () => 1000,
    );

    final prepared = await prepareTodoFollowupGenerationRoute(
      _FakeBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: true,
      cloudAuthController: controller,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.unknown,
    );

    expect(prepared.route, AskAiRouteKind.cloudGateway);
    expect(prepared.idToken, 'id_token_1');
    expect(store.loadCalls, 1);
    expect(toolkit.refreshCalls, 1);
  });

  test('interactive preflight warms before first token read when needed',
      () async {
    final prepared = await prepareForegroundAiRoute(
      _FakeBackend(),
      _sessionKey,
      routePolicy: ForegroundAiRoutePolicy.askAi,
      cloudAuthController: _WarmupRequiredCloudAuthController(),
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.unknown,
      warmupPolicy: ForegroundAiWarmupPolicy.cloudOnly,
    );

    expect(prepared.route, AskAiRouteKind.cloudGateway);
    expect(prepared.idToken, 'token_after_warm');
  });

  test('late warmup refreshes returned token before handing route back',
      () async {
    final prepared = await prepareForegroundAiRoute(
      _ByokBackend(),
      _sessionKey,
      routePolicy: ForegroundAiRoutePolicy.askAi,
      cloudAuthController: _WarmupRequiredCloudAuthController(),
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: '',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.unknown,
      warmupPolicy: ForegroundAiWarmupPolicy.always,
    );

    expect(prepared.route, AskAiRouteKind.byok);
    expect(prepared.idToken, 'token_after_warm');
  });
}

final Uint8List _sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

final class _FakeBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];
}

final class _ThrowingRouteBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError('boom');
  }
}

final class _ByokBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[
        LlmProfile(
          id: 'p1',
          name: 'BYOK',
          providerType: 'openai',
          modelName: 'gpt-4o-mini',
          isActive: true,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];
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

final class _RefreshingIdentityToolkit implements FirebaseIdentityToolkit {
  int refreshCalls = 0;

  @override
  Future<FirebaseAuthTokens> refreshIdToken(
      {required String refreshToken}) async {
    refreshCalls += 1;
    return const FirebaseAuthTokens(
      idToken: 'id_token_1',
      refreshToken: 'refresh_1',
      uid: 'uid_1',
      expiresAtMs: 1 << 30,
    );
  }

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
  Future<FirebaseUserInfo> lookup({required String idToken}) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendOobCode({
    required String requestType,
    String? idToken,
    String? email,
  }) {
    throw UnimplementedError();
  }
}

final class _WarmupRequiredCloudAuthController implements CloudAuthController {
  var _reads = 0;

  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async {
    _reads += 1;
    return _reads >= 2 ? 'token_after_warm' : null;
  }

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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
