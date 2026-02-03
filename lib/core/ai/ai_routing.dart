import 'dart:convert';
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

/// Like [decideAskAiRoute], but for automation/background-ish flows where we
/// should **not** probe Cloud when entitlement is unknown.
///
/// This supports the product policy:
/// - Free users do not use LLM automatically.
/// - BYOK works when configured.
/// - Cloud is only used when explicitly entitled.
Future<AskAiRouteKind> decideAiAutomationRoute(
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

  final allowCloud = subscriptionStatus == SubscriptionStatus.entitled;
  if (hasCloud && allowCloud) return AskAiRouteKind.cloudGateway;
  if (hasByok) return AskAiRouteKind.byok;
  return AskAiRouteKind.needsSetup;
}

int? parseHttpStatusFromError(Object error) {
  final message = error.toString();
  final patterns = <RegExp>[
    RegExp(r'\bHTTP\s+(\d{3})\b', caseSensitive: false),
    RegExp(r'\bStatusCode\s*[:=]\s*(\d{3})\b', caseSensitive: false),
    RegExp(r'\bstatus(?:\s*code)?\s*[:=]\s*(\d{3})\b', caseSensitive: false),
    RegExp(r'\bstatus(?:\s*code)?\s+(\d{3})\b', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(message);
    if (match == null) continue;
    final status = int.tryParse(match.group(1) ?? '');
    if (status != null) return status;
  }
  return null;
}

String? parseCloudErrorCodeFromError(Object error) {
  final message = error.toString();
  final jsonStart = message.indexOf('{');
  final jsonEnd = message.lastIndexOf('}');
  if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
    final jsonText = message.substring(jsonStart, jsonEnd + 1);
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        final errorValue = decoded['error'];
        if (errorValue is String) return errorValue;
        if (errorValue is Map) {
          final codeValue =
              errorValue['code'] ?? errorValue['error'] ?? errorValue['type'];
          if (codeValue is String) return codeValue;
        }
        final codeValue = decoded['code'] ?? decoded['error_code'];
        if (codeValue is String) return codeValue;
      }
    } catch (_) {
      // Fall back to regex-based parsing below.
    }
  }

  final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message);
  if (match != null) return match.group(1);
  final nestedMatch = RegExp(
    r'"error"\s*:\s*\{[^}]*"code"\s*:\s*"([^"]+)"',
    dotAll: true,
  ).firstMatch(message);
  return nestedMatch?.group(1);
}

bool isCloudEmailNotVerifiedError(Object error) {
  final status = parseHttpStatusFromError(error);
  if (status != 403) return false;
  return parseCloudErrorCodeFromError(error) == 'email_not_verified';
}

bool isCloudFallbackableError(Object error) {
  final status = parseHttpStatusFromError(error);
  if (status == null) return false;
  return status == 401 || status == 402 || status == 429 || status >= 500;
}
