import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../cloud/cloud_auth_scope.dart';
import 'ai_routing.dart';

bool supportsTodoFollowupWebSearch({
  required AskAiRouteKind route,
  required CloudGatewayConfig gatewayConfig,
}) {
  if (route != AskAiRouteKind.cloudGateway) return false;
  return gatewayConfig.supportsWebSearch;
}

Future<AskAiRouteKind> decideTodoFollowupGenerationRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required bool hasManualRegenerateDueJob,
  required String? cloudIdToken,
  required String cloudGatewayBaseUrl,
  required SubscriptionStatus subscriptionStatus,
}) {
  if (hasManualRegenerateDueJob) {
    return decideAskAiRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayBaseUrl,
      subscriptionStatus: subscriptionStatus,
    );
  }

  return decideAiAutomationRoute(
    backend,
    sessionKey,
    cloudIdToken: cloudIdToken,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    subscriptionStatus: subscriptionStatus,
  );
}
