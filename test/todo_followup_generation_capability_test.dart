import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/ai/todo_followup_generation_capability.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';

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
}
