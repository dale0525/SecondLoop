import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import 'ai_routing.dart';

Future<String?> prepareTodoFollowupGenerationIdToken(
  CloudAuthController? controller, {
  required SubscriptionStatus subscriptionStatus,
  required String gatewayBaseUrl,
  bool forceWarm = false,
}) async {
  final normalizedGatewayBaseUrl = gatewayBaseUrl.trim();
  final shouldWarm = normalizedGatewayBaseUrl.isNotEmpty &&
      (subscriptionStatus == SubscriptionStatus.entitled || forceWarm);
  if (shouldWarm) {
    await bestEffortWarmCloudCapabilityAuth(controller);
  }

  return readCloudCapabilityIdToken(
    controller,
    mode: CloudCapabilityAuthMode.background,
  );
}

final class TodoFollowupGenerationPreparedRoute {
  const TodoFollowupGenerationPreparedRoute({
    required this.route,
    required this.idToken,
  });

  final AskAiRouteKind route;
  final String? idToken;
}

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

Future<TodoFollowupGenerationPreparedRoute> prepareTodoFollowupGenerationRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required bool hasManualRegenerateDueJob,
  required CloudAuthController? cloudAuthController,
  required CloudGatewayConfig gatewayConfig,
  required SubscriptionStatus subscriptionStatus,
}) async {
  final idToken = await prepareTodoFollowupGenerationIdToken(
    cloudAuthController,
    subscriptionStatus: subscriptionStatus,
    gatewayBaseUrl: gatewayConfig.baseUrl,
    forceWarm: hasManualRegenerateDueJob,
  );
  final route = await decideTodoFollowupGenerationRoute(
    backend,
    sessionKey,
    hasManualRegenerateDueJob: hasManualRegenerateDueJob,
    cloudIdToken: idToken,
    cloudGatewayBaseUrl: gatewayConfig.baseUrl,
    subscriptionStatus: subscriptionStatus,
  );
  return TodoFollowupGenerationPreparedRoute(
    route: route,
    idToken: idToken,
  );
}
