import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../core/ai/ai_routing.dart';
import '../../../core/backend/app_backend.dart';
import '../../../core/cloud/cloud_auth_scope.dart';
import '../../../core/cloud/cloud_capability_auth.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/subscription/subscription_scope.dart';
import 'task_priority_ai.dart';

Future<BackendTaskPriorityAiSharedAssessmentsClient?>
    resolveTaskPrioritySharedAssessmentsClient(
  BuildContext context, {
  required String cacheScopeKey,
}) async {
  final normalizedScopeKey = cacheScopeKey.trim();
  if (normalizedScopeKey.isEmpty) return null;

  final backend = AppBackendScope.maybeOf(context);
  final sessionScope = SessionScope.maybeOf(context);
  if (backend == null || sessionScope == null) return null;

  final subscriptionStatus =
      SubscriptionScope.maybeOf(context)?.status ?? SubscriptionStatus.unknown;
  if (subscriptionStatus != SubscriptionStatus.entitled) {
    return null;
  }

  final cloudAuthScope = CloudAuthScope.maybeOf(context);
  final gatewayConfig =
      cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
  final cloudUid = (cloudAuthScope?.controller.uid ?? '').trim();
  final localeTag =
      Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en-US';
  final sessionKey = Uint8List.fromList(sessionScope.sessionKey);
  if (cloudUid.isEmpty || gatewayConfig.baseUrl.trim().isEmpty) {
    return null;
  }

  final expectedScopeKey = await resolveTaskPriorityAiCacheScopeKey(
    backend,
    sessionKey,
    route: AskAiRouteKind.cloudGateway,
    gatewayBaseUrl: gatewayConfig.baseUrl,
    modelName: gatewayConfig.modelName,
    localeTag: localeTag,
    cloudUid: cloudUid,
  );
  if ((expectedScopeKey ?? '').trim() != normalizedScopeKey) {
    return null;
  }

  final idToken = await readCloudCapabilityIdToken(
    cloudAuthScope?.controller,
    mode: CloudCapabilityAuthMode.background,
  );
  final normalizedIdToken = (idToken ?? '').trim();
  if (normalizedIdToken.isEmpty) {
    return null;
  }

  return BackendTaskPriorityAiSharedAssessmentsClient(
    backend: backend,
    sessionKey: sessionKey,
    gatewayBaseUrl: gatewayConfig.baseUrl,
    idToken: normalizedIdToken,
    modelName: gatewayConfig.modelName,
    localeTag: localeTag,
    cacheScopeKey: normalizedScopeKey,
  );
}
