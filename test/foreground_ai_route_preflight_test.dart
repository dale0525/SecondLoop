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
  test('prepared foreground route requires token only for cloud', () {
    expect(
      canRunPreparedForegroundAiRoute(
        const ForegroundAiPreparedRoute(
          route: AskAiRouteKind.byok,
          idToken: null,
        ),
      ),
      isTrue,
    );

    expect(
      canRunPreparedForegroundAiRoute(
        const ForegroundAiPreparedRoute(
          route: AskAiRouteKind.cloudGateway,
          idToken: null,
        ),
      ),
      isFalse,
    );

    expect(
      canRunPreparedForegroundAiRoute(
        const ForegroundAiPreparedRoute(
          route: AskAiRouteKind.cloudGateway,
          idToken: 'token_1',
        ),
      ),
      isTrue,
    );
  });

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

  test(
      'Product intent: manual regenerate can use cloud when entitlement is still unknown',
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

  test(
      'Product intent: automatic followup still blocks cloud when entitlement is unknown',
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

  test(
      'Product intent: manual regenerate intentionally stays cloud-routable before entitlement is resolved',
      () async {
    final manualRoute = await decideTodoFollowupGenerationRoute(
      _FakeBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: true,
      cloudIdToken: 'token_1',
      cloudGatewayBaseUrl: 'https://example.com',
      subscriptionStatus: SubscriptionStatus.unknown,
    );
    final automaticRoute = await decideTodoFollowupGenerationRoute(
      _FakeBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: false,
      cloudIdToken: 'token_1',
      cloudGatewayBaseUrl: 'https://example.com',
      subscriptionStatus: SubscriptionStatus.unknown,
    );

    expect(manualRoute, AskAiRouteKind.cloudGateway);
    expect(automaticRoute, AskAiRouteKind.needsSetup);
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
      _SetupLikeRouteBackend(),
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

  test(
      'interactive automation preflight rethrows non-setup route errors even when fallback requested',
      () async {
    await expectLater(
      () => prepareForegroundAiRoute(
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
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'interactive automation preflight rethrows payment-required route errors',
      () async {
    await expectLater(
      () => prepareForegroundAiRoute(
        _PaymentRequiredRouteBackend(),
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
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('payment_required'),
        ),
      ),
    );
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

  test('followup preflight falls back to needsSetup on route errors', () async {
    final prepared = await prepareTodoFollowupGenerationRoute(
      _SetupLikeRouteBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: true,
      cloudAuthController: null,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.entitled,
      fallbackToNeedsSetupOnRouteError: true,
    );

    expect(prepared.route, AskAiRouteKind.needsSetup);
    expect(prepared.idToken, isNull);
  });

  test(
      'followup preflight rethrows non-setup route errors even when fallback requested',
      () async {
    await expectLater(
      () => prepareTodoFollowupGenerationRoute(
        _ThrowingRouteBackend(),
        _sessionKey,
        hasManualRegenerateDueJob: true,
        cloudAuthController: null,
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://example.com',
          modelName: 'cloud',
        ),
        subscriptionStatus: SubscriptionStatus.entitled,
        fallbackToNeedsSetupOnRouteError: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('followup preflight rethrows email-verification route errors', () async {
    await expectLater(
      () => prepareTodoFollowupGenerationRoute(
        _EmailNotVerifiedRouteBackend(),
        _sessionKey,
        hasManualRegenerateDueJob: true,
        cloudAuthController: null,
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://example.com',
          modelName: 'cloud',
        ),
        subscriptionStatus: SubscriptionStatus.entitled,
        fallbackToNeedsSetupOnRouteError: true,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('email_not_verified'),
        ),
      ),
    );
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

  test('followup preflight keeps auto byok local without reading cloud token',
      () async {
    final controller = _CountingCloudAuthController();

    final prepared = await prepareTodoFollowupGenerationRoute(
      _ByokBackend(),
      _sessionKey,
      hasManualRegenerateDueJob: false,
      cloudAuthController: controller,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.entitled,
    );

    expect(prepared.route, AskAiRouteKind.byok);
    expect(prepared.idToken, isNull);
    expect(controller.readCount, 0);
  });

  test('automation preflight keeps byok local without reading cloud token',
      () async {
    final controller = _CountingCloudAuthController();

    final prepared = await prepareForegroundAiRoute(
      _ByokBackend(),
      _sessionKey,
      routePolicy: ForegroundAiRoutePolicy.automation,
      cloudAuthController: controller,
      gatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://example.com',
        modelName: 'cloud',
      ),
      subscriptionStatus: SubscriptionStatus.entitled,
      warmupPolicy: ForegroundAiWarmupPolicy.never,
    );

    expect(prepared.route, AskAiRouteKind.byok);
    expect(prepared.idToken, isNull);
    expect(controller.readCount, 0);
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

final class _SetupLikeRouteBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw UnsupportedError('master password setup required');
  }
}

final class _PaymentRequiredRouteBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError(
      'cloud-gateway request failed: HTTP 402 {"error":"payment_required"}',
    );
  }
}

final class _EmailNotVerifiedRouteBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    throw StateError(
      'cloud-gateway request failed: HTTP 403 {"error":"email_not_verified"}',
    );
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

final class _CountingCloudAuthController implements CloudAuthController {
  int readCount = 0;

  @override
  String? get email => 'demo@example.com';

  @override
  bool? get emailVerified => true;

  @override
  String? get uid => 'uid_1';

  @override
  Future<String?> getIdToken() async {
    readCount += 1;
    return 'token_1';
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
