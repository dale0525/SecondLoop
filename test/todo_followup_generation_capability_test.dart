import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/todo_followup_generation_capability.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
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
}

final Uint8List _sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

final class _FakeBackend extends AppBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];
}
