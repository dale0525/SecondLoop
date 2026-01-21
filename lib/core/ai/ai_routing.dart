import 'dart:typed_data';

import '../backend/app_backend.dart';

enum AskAiRouteKind {
  cloudGateway,
  byok,
  needsSetup,
}

enum SubscriptionStatus {
  unknown,
  entitled,
  notEntitled,
}

Future<bool> hasActiveLlmProfile(
  AppBackend backend,
  Uint8List sessionKey,
) async {
  final profiles = await backend.listLlmProfiles(sessionKey);
  return profiles.any((p) => p.isActive);
}

Future<AskAiRouteKind> decideAskAiRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required String? cloudIdToken,
  required String cloudGatewayBaseUrl,
  SubscriptionStatus subscriptionStatus = SubscriptionStatus.unknown,
}) async {
  final hasByok = await hasActiveLlmProfile(backend, sessionKey);
  final hasCloud = cloudIdToken != null &&
      cloudIdToken.trim().isNotEmpty &&
      cloudGatewayBaseUrl.trim().isNotEmpty;

  final allowCloud = subscriptionStatus != SubscriptionStatus.notEntitled;
  if (hasCloud && allowCloud) return AskAiRouteKind.cloudGateway;
  if (hasByok) return AskAiRouteKind.byok;
  return AskAiRouteKind.needsSetup;
}

int? parseHttpStatusFromError(Object error) {
  final message = error.toString();
  final match = RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

String? parseCloudErrorCodeFromError(Object error) {
  final message = error.toString();
  final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message);
  return match?.group(1);
}

bool isCloudEmailNotVerifiedError(Object error) {
  final status = parseHttpStatusFromError(error);
  if (status != 403) return false;
  return parseCloudErrorCodeFromError(error) == 'email_not_verified';
}

bool isCloudFallbackableError(Object error) {
  final status = parseHttpStatusFromError(error);
  return status == 401 || status == 402 || status == 429;
}
