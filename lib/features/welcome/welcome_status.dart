import 'package:flutter/widgets.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';

typedef WelcomeGuideStatusLoader = Future<WelcomeGuideStatus> Function(
  BuildContext context,
);

class WelcomeGuideStatus {
  const WelcomeGuideStatus({
    required this.aiReady,
    required this.syncReady,
  });

  final bool aiReady;
  final bool syncReady;
}

Future<WelcomeGuideStatus> loadWelcomeGuideStatus(BuildContext context) async {
  final aiReady = await _resolveAiReady(context);
  final syncReady = await _resolveSyncReady();
  return WelcomeGuideStatus(aiReady: aiReady, syncReady: syncReady);
}

Future<bool> _resolveAiReady(BuildContext context) async {
  final backend = AppBackendScope.maybeOf(context);
  final sessionScope = SessionScope.maybeOf(context);
  if (backend == null || sessionScope == null) {
    return false;
  }

  final cloudAuthScope = CloudAuthScope.maybeOf(context);
  final cloudGatewayConfig =
      cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
  final subscriptionStatus =
      SubscriptionScope.maybeOf(context)?.status ?? SubscriptionStatus.unknown;

  final cloudIdToken = await readCloudCapabilityIdToken(
    cloudAuthScope?.controller,
    mode: CloudCapabilityAuthMode.interactive,
  );

  try {
    final route = await decideAskAiRoute(
      backend,
      sessionScope.sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      subscriptionStatus: subscriptionStatus,
    );
    return route != AskAiRouteKind.needsSetup;
  } catch (_) {
    return false;
  }
}

Future<bool> _resolveSyncReady() async {
  final store = SyncConfigStore();
  try {
    final configured = await store.loadConfiguredSync();
    return configured != null;
  } catch (_) {
    return false;
  }
}
