import 'dart:typed_data';

import '../backend/app_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../cloud/firebase_identity_toolkit.dart';
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
  CloudCapabilityAuthMode authMode = CloudCapabilityAuthMode.background,
  bool forceWarm = false,
}) async {
  final normalizedGatewayBaseUrl = gatewayBaseUrl.trim();
  if (normalizedGatewayBaseUrl.isEmpty) {
    return null;
  }

  final shouldWarm = normalizedGatewayBaseUrl.isNotEmpty &&
      (subscriptionStatus == SubscriptionStatus.entitled || forceWarm);
  if (shouldWarm) {
    await bestEffortWarmCloudCapabilityAuth(controller);
  }

  return readCloudCapabilityIdToken(
    controller,
    mode: authMode,
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

bool canRunPreparedForegroundAiRoute(
  ForegroundAiPreparedRoute prepared,
) {
  if (prepared.route == AskAiRouteKind.needsSetup) {
    return false;
  }
  if (prepared.route != AskAiRouteKind.cloudGateway) {
    return true;
  }
  return prepared.idToken?.trim().isNotEmpty ?? false;
}

bool canRunPreparedTodoFollowupGenerationRoute(
  TodoFollowupGenerationPreparedRoute prepared,
) {
  if (prepared.route == AskAiRouteKind.needsSetup) {
    return false;
  }
  if (prepared.route != AskAiRouteKind.cloudGateway) {
    return true;
  }
  return prepared.idToken?.trim().isNotEmpty ?? false;
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
  final preliminaryRoute = await _decideForegroundAiRoute(
    backend,
    sessionKey,
    routePolicy: routePolicy,
    cloudIdToken: null,
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
    fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
  );
  final canAttemptCloud = _canAttemptForegroundAiCloudRoute(
    routePolicy: routePolicy,
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
  );
  if (!canAttemptCloud ||
      (routePolicy == ForegroundAiRoutePolicy.automation &&
          preliminaryRoute == AskAiRouteKind.byok)) {
    return ForegroundAiPreparedRoute(
      route: preliminaryRoute,
      idToken: null,
    );
  }

  final didWarmBeforeRead = _shouldWarmForegroundAiTokenRead(
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
    warmupPolicy: warmupPolicy,
  );
  if (didWarmBeforeRead) {
    await bestEffortWarmCloudCapabilityAuth(cloudAuthController);
  }

  var idToken = await readCloudCapabilityIdToken(
    cloudAuthController,
    mode: authMode,
  );
  var route = await _decideForegroundAiRoute(
    backend,
    sessionKey,
    routePolicy: routePolicy,
    cloudIdToken: idToken,
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
    fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
  );

  if (!didWarmBeforeRead && _shouldWarmForegroundAiRoute(route, warmupPolicy)) {
    await bestEffortWarmCloudCapabilityAuth(cloudAuthController);
    idToken = await readCloudCapabilityIdToken(
      cloudAuthController,
      mode: authMode,
    );
    route = await _decideForegroundAiRoute(
      backend,
      sessionKey,
      routePolicy: routePolicy,
      cloudIdToken: idToken,
      gatewayConfig: gatewayConfig,
      subscriptionStatus: subscriptionStatus,
      fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
    );
  }

  return ForegroundAiPreparedRoute(
    route: route,
    idToken: idToken,
  );
}

bool _shouldWarmForegroundAiTokenRead({
  required CloudGatewayConfig gatewayConfig,
  required SubscriptionStatus subscriptionStatus,
  required ForegroundAiWarmupPolicy warmupPolicy,
}) {
  if (gatewayConfig.baseUrl.trim().isEmpty) return false;

  switch (warmupPolicy) {
    case ForegroundAiWarmupPolicy.never:
      return false;
    case ForegroundAiWarmupPolicy.always:
      return true;
    case ForegroundAiWarmupPolicy.cloudOnly:
      return subscriptionStatus != SubscriptionStatus.notEntitled;
  }
}

bool _canAttemptForegroundAiCloudRoute({
  required ForegroundAiRoutePolicy routePolicy,
  required CloudGatewayConfig gatewayConfig,
  required SubscriptionStatus subscriptionStatus,
}) {
  if (gatewayConfig.baseUrl.trim().isEmpty) return false;

  return switch (routePolicy) {
    ForegroundAiRoutePolicy.askAi =>
      subscriptionStatus != SubscriptionStatus.notEntitled,
    ForegroundAiRoutePolicy.automation =>
      subscriptionStatus == SubscriptionStatus.entitled,
  };
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
  } catch (error) {
    if (fallbackToNeedsSetupOnRouteError &&
        _shouldFallbackToNeedsSetupOnRouteError(error)) {
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
    // Product decision: a user-triggered regenerate stays on the interactive
    // Ask AI route, so cloud follow-up generation can run as soon as auth is
    // available even before entitlement settles. Automatic follow-up jobs keep
    // the stricter automation gating below.
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
  bool fallbackToNeedsSetupOnRouteError = false,
}) async {
  final routePolicy = hasManualRegenerateDueJob
      ? ForegroundAiRoutePolicy.askAi
      : ForegroundAiRoutePolicy.automation;
  final preliminaryRoute = await _decideTodoFollowupGenerationRoute(
    backend,
    sessionKey,
    hasManualRegenerateDueJob: hasManualRegenerateDueJob,
    cloudIdToken: null,
    cloudGatewayBaseUrl: gatewayConfig.baseUrl,
    subscriptionStatus: subscriptionStatus,
    fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
  );
  final canAttemptCloud = _canAttemptForegroundAiCloudRoute(
    routePolicy: routePolicy,
    gatewayConfig: gatewayConfig,
    subscriptionStatus: subscriptionStatus,
  );
  if (!canAttemptCloud ||
      (!hasManualRegenerateDueJob && preliminaryRoute == AskAiRouteKind.byok)) {
    return TodoFollowupGenerationPreparedRoute(
      route: preliminaryRoute,
      idToken: null,
    );
  }

  final idToken = await prepareTodoFollowupGenerationIdToken(
    cloudAuthController,
    subscriptionStatus: subscriptionStatus,
    gatewayBaseUrl: gatewayConfig.baseUrl,
    authMode: hasManualRegenerateDueJob
        ? CloudCapabilityAuthMode.interactive
        : CloudCapabilityAuthMode.background,
    forceWarm: hasManualRegenerateDueJob,
  );
  final route = await _decideTodoFollowupGenerationRoute(
    backend,
    sessionKey,
    hasManualRegenerateDueJob: hasManualRegenerateDueJob,
    cloudIdToken: idToken,
    cloudGatewayBaseUrl: gatewayConfig.baseUrl,
    subscriptionStatus: subscriptionStatus,
    fallbackToNeedsSetupOnRouteError: fallbackToNeedsSetupOnRouteError,
  );
  return TodoFollowupGenerationPreparedRoute(
    route: route,
    idToken: idToken,
  );
}

Future<AskAiRouteKind> _decideTodoFollowupGenerationRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required bool hasManualRegenerateDueJob,
  required String? cloudIdToken,
  required String cloudGatewayBaseUrl,
  required SubscriptionStatus subscriptionStatus,
  required bool fallbackToNeedsSetupOnRouteError,
}) async {
  try {
    return await decideTodoFollowupGenerationRoute(
      backend,
      sessionKey,
      hasManualRegenerateDueJob: hasManualRegenerateDueJob,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayBaseUrl,
      subscriptionStatus: subscriptionStatus,
    );
  } catch (error) {
    if (fallbackToNeedsSetupOnRouteError &&
        _shouldFallbackToNeedsSetupOnRouteError(error)) {
      return AskAiRouteKind.needsSetup;
    }
    rethrow;
  }
}

bool _shouldFallbackToNeedsSetupOnRouteError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'missing_web_api_key':
      case 'missing_wwb_api_key':
      case 'missing_user':
      case 'missing_id_token':
      case 'missing_refresh_token':
      case 'missing_local_id':
        return true;
    }
  }

  final message = error.toString().toLowerCase();
  if (message.contains('missing_web_api_key') ||
      message.contains('missing_wwb_api_key') ||
      message.contains('missing_user') ||
      message.contains('missing_id_token') ||
      message.contains('missing_refresh_token') ||
      message.contains('missing_local_id')) {
    return true;
  }
  if (message.contains('master password') && message.contains('setup')) {
    return true;
  }
  if (message.contains('setup required') ||
      message.contains('not initialized')) {
    return true;
  }
  return false;
}
