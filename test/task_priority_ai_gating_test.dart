import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_ai.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('no Cloud or BYOK disables priority reranking', () async {
    final route = await resolveTaskPriorityAiRoute(
      _NoAiBackend(),
      Uint8List(32),
      cloudIdToken: null,
      cloudGatewayBaseUrl: '',
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );

    expect(route, AskAiRouteKind.needsSetup);
  });

  test('BYOK enables priority reranking without Cloud entitlement', () async {
    final route = await resolveTaskPriorityAiRoute(
      TestAppBackend(),
      Uint8List(32),
      cloudIdToken: null,
      cloudGatewayBaseUrl: '',
      subscriptionStatus: SubscriptionStatus.notEntitled,
    );

    expect(route, AskAiRouteKind.byok);
  });

  test('entitled Cloud wins when token and gateway are present', () async {
    final route = await resolveTaskPriorityAiRoute(
      TestAppBackend(),
      Uint8List(32),
      cloudIdToken: 'token-123',
      cloudGatewayBaseUrl: 'https://cloud.secondloop.ai',
      subscriptionStatus: SubscriptionStatus.entitled,
    );

    expect(route, AskAiRouteKind.cloudGateway);
  });
}

final class _NoAiBackend extends TestAppBackend {
  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];
}
