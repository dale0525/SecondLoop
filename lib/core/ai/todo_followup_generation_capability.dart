import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import 'ai_routing.dart';

enum ForegroundAiRoutePolicy {
  askAi,
  automation,
}

enum ForegroundAiWarmupPolicy {
  never,
  cloudOnly,
  always,
}

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

final class ForegroundAiPreparedRoute {
  const ForegroundAiPreparedRoute({
    required this.route,
    required this.idToken,
  });

  final AskAiRouteKind route;
  final String? idToken;
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

Future<ForegroundAiPreparedRoute> prepareForegroundAiRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required ForegroundAiRoutePolicy routePolicy,
  required CloudAuthController? cloudAuthController,
  required CloudGatewayConfig gatewayConfig,
  required SubscriptionStatus subscriptionStatus,
  CloudCapabilityAuthMode authMode = CloudCapabilityAuthMode.interactive,
  ForegroundAiWarmupPolicy warmupPolicy = ForegroundAiWarmupPolicy.never,
  bool fallbackToNeedsSetupOnRouteError = false,
}) async {
  final idToken = await readCloudCapabilityIdToken(
    cloudAuthController,
    mode: authMode,
  );
  final route = await _decideForegroundAiRoute(
    backend,
    sessionKey,
    routePolicy: routePolicy,
    cloudIdToken: idToken,
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
    fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
  );

  if (_shouldWarmForegroundAiRoute(route, warmupPolicy)) {
    await bestEffortWarmCloudCapabilityAuth(cloudAuthController);
  }

  return ForegroundAiPreparedRoute(
    route: route,
    idToken: idToken,
  );
}

Future<AskAiRouteKind> _decideForegroundAiRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required ForegroundAiRoutePolicy routePolicy,
  required String? cloudIdToken,
  required CloudGatewayConfig gatewayConfig,
  required SubscriptionStatus subscriptionStatus,
  required bool fallbackToNeedsSetupOnRouteError,
}) async {
  try {
    switch (routePolicy) {
      case ForegroundAiRoutePolicy.askAi:
        return await decideAskAiRoute(
          backend,
          sessionKey,
          cloudIdToken: cloudIdToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
      case ForegroundAiRoutePolicy.automation:
        return await decideAiAutomationRoute(
          backend,
          sessionKey,
          cloudIdToken: cloudIdToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
    }
  } catch (_) {
    if (fallbackToNeedsSetupOnRouteError) {
      return AskAiRouteKind.needsSetup;
    }
    rethrow;
  }
}

bool _shouldWarmForegroundAiRoute(
  AskAiRouteKind route,
  ForegroundAiWarmupPolicy warmupPolicy,
) {
  switch (warmupPolicy) {
    case ForegroundAiWarmupPolicy.never:
      return false;
    case ForegroundAiWarmupPolicy.cloudOnly:
      return route == AskAiRouteKind.cloudGateway;
    case ForegroundAiWarmupPolicy.always:
      return route != AskAiRouteKind.needsSetup;
  }
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
