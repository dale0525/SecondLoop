import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/ask_ai_source_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/cloud/runtime_secretary_app_service.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../core/subscription/subscription_scope.dart';

const agentAskAiErrorPrefix = '\u001eSL_ERROR\u001e';
const agentAskAiMetaPrefix = '\u001eSL_META\u001e';
const agentAskAiReasoningPrefix = '\u001eSL_REASONING\u001e';
const agentAskAiControlPrefix = '\u001eSL_';

final class AgentConversationSendException implements Exception {
  AgentConversationSendException(
    this.error, {
    required this.userMessageCommitted,
  });

  final Object error;
  final bool userMessageCommitted;

  @override
  String toString() => 'AgentConversationSendException($error)';
}

final class AgentConversationSendResult {
  const AgentConversationSendResult({
    required this.routeKind,
    required this.userMessageCommitted,
    required this.sawVisibleDelta,
    required this.approvalItems,
    this.streamError,
  });

  final AskAiRouteKind routeKind;
  final bool userMessageCommitted;
  final bool sawVisibleDelta;
  final String? streamError;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
}

Future<AgentConversationSendResult> sendAgentConversationMessage({
  required BuildContext context,
  required AppBackend backend,
  required Uint8List sessionKey,
  required String conversationId,
  required String message,
  ChatRuntimeConversationSender? runtimeConversationSender,
  void Function(String delta)? onAnswerDelta,
  void Function(String delta)? onReasoningDelta,
  int topK = 10,
}) async {
  var userMessageCommitted = false;
  try {
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final route = await resolveAgentConversationRoute(
      context: context,
      backend: backend,
      sessionKey: sessionKey,
    );

    if (route.route == AskAiRouteKind.cloudGateway) {
      final vaultId = cloudAuthScope?.controller.uid?.trim() ?? '';
      if (cloudAuthScope == null || vaultId.isEmpty) {
        throw StateError('managed_pro_vault_id_required');
      }
      final userMessage = await backend.insertMessage(
        sessionKey,
        conversationId,
        role: 'user',
        content: message,
      );
      userMessageCommitted = true;

      final sender = runtimeConversationSender ??
          SecretaryRuntimeConversationSender.hostedManagedPro(
            apiBaseUrl: route.cloudGatewayConfig.baseUrl,
            hostedSessionTokenGetter: cloudAuthScope.controller.getIdToken,
          );
      final service = RuntimeSecretaryAppService(
        sender: sender,
        backend: backend,
        sessionKey: sessionKey,
      );
      final result = await service.sendAndApply(
        vaultId: vaultId,
        conversationId: conversationId,
        message: message,
        sourceMessageId: userMessage.id,
      );
      var approvalItems = result.metadata.approvalItems;
      if (approvalItems.isEmpty && result.metadata.approvalRequired) {
        approvalItems = await service.fetchApprovalItems(vaultId: vaultId);
      }
      return AgentConversationSendResult(
        routeKind: route.route,
        userMessageCommitted: userMessageCommitted,
        sawVisibleDelta: result.assistantContent.trim().isNotEmpty,
        approvalItems: _validApprovalItems(approvalItems),
      );
    }

    final stream = openAgentAskAiStream(
      backend: backend,
      sessionKey: sessionKey,
      conversationId: conversationId,
      question: message,
      route: route,
      topK: topK,
    );
    final streamResult = await consumeAgentAskAiStream(
      stream,
      onAnswerDelta: onAnswerDelta,
      onReasoningDelta: onReasoningDelta,
    );
    return AgentConversationSendResult(
      routeKind: route.route,
      userMessageCommitted: false,
      sawVisibleDelta: streamResult.sawVisibleDelta,
      streamError: streamResult.streamError,
      approvalItems: const <SecretaryRuntimeApprovalItem>[],
    );
  } catch (error) {
    throw AgentConversationSendException(
      error,
      userMessageCommitted: userMessageCommitted,
    );
  }
}

Future<
    ({
      AskAiRouteKind route,
      String? cloudIdToken,
      CloudGatewayConfig cloudGatewayConfig,
    })> resolveAgentConversationRoute({
  required BuildContext context,
  required AppBackend backend,
  required Uint8List sessionKey,
}) async {
  final cloudAuthScope = CloudAuthScope.maybeOf(context);
  final cloudGatewayConfig =
      cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
  final subscriptionStatus =
      SubscriptionScope.maybeOf(context)?.status ?? SubscriptionStatus.unknown;

  AskAiSourcePreference preference;
  try {
    preference = await AskAiSourcePrefs.read();
  } catch (_) {
    preference = AskAiSourcePreference.auto;
  }

  if (preference == AskAiSourcePreference.byok) {
    var hasByok = false;
    try {
      hasByok = await hasActiveLlmProfile(backend, sessionKey);
    } catch (_) {
      hasByok = false;
    }
    if (hasByok) {
      return (
        route: AskAiRouteKind.byok,
        cloudIdToken: null,
        cloudGatewayConfig: cloudGatewayConfig,
      );
    }
  }

  final cloudIdToken = await readCloudCapabilityIdToken(
    cloudAuthScope?.controller,
    mode: CloudCapabilityAuthMode.interactive,
  );

  final defaultRoute = await decideAskAiRoute(
    backend,
    sessionKey,
    cloudIdToken: cloudIdToken,
    cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
    subscriptionStatus: subscriptionStatus,
  );

  var hasByokWhenCloudRoute = false;
  if (preference == AskAiSourcePreference.byok &&
      defaultRoute == AskAiRouteKind.cloudGateway) {
    try {
      hasByokWhenCloudRoute = await hasActiveLlmProfile(backend, sessionKey);
    } catch (_) {
      hasByokWhenCloudRoute = false;
    }
  }

  final route = applyAskAiSourcePreference(
    defaultRoute,
    preference,
    hasByokWhenCloudRoute: hasByokWhenCloudRoute,
  );

  return (
    route: route,
    cloudIdToken: cloudIdToken,
    cloudGatewayConfig: cloudGatewayConfig,
  );
}

Stream<String> openAgentAskAiStream({
  required AppBackend backend,
  required Uint8List sessionKey,
  required String conversationId,
  required String question,
  required int topK,
  required ({
    AskAiRouteKind route,
    String? cloudIdToken,
    CloudGatewayConfig cloudGatewayConfig,
  }) route,
}) {
  switch (route.route) {
    case AskAiRouteKind.cloudGateway:
      final idToken = route.cloudIdToken?.trim() ?? '';
      if (idToken.isEmpty) {
        throw StateError('cloud_id_token_required');
      }
      return backend.askAiStreamCloudGateway(
        sessionKey,
        conversationId,
        question: question,
        topK: topK,
        gatewayBaseUrl: route.cloudGatewayConfig.baseUrl,
        idToken: idToken,
        modelName: route.cloudGatewayConfig.modelName,
      );
    case AskAiRouteKind.byok:
      return backend.askAiStream(
        sessionKey,
        conversationId,
        question: question,
        topK: topK,
      );
    case AskAiRouteKind.needsSetup:
      throw StateError('ask_ai_route_needs_setup');
  }
}

Future<({bool sawVisibleDelta, String? streamError})> consumeAgentAskAiStream(
  Stream<String> stream, {
  void Function(String delta)? onAnswerDelta,
  void Function(String delta)? onReasoningDelta,
}) async {
  var sawVisibleDelta = false;
  String? streamError;

  await for (final delta in stream) {
    if (delta.isEmpty) continue;
    if (delta.startsWith(agentAskAiMetaPrefix)) {
      continue;
    }
    if (delta.startsWith(agentAskAiErrorPrefix)) {
      streamError = delta.substring(agentAskAiErrorPrefix.length).trim();
      break;
    }
    if (delta.startsWith(agentAskAiReasoningPrefix)) {
      final text = _extractReasoningDeltaText(
        delta.substring(agentAskAiReasoningPrefix.length),
      );
      if (text.isNotEmpty) onReasoningDelta?.call(text);
      continue;
    }
    if (delta.startsWith(agentAskAiControlPrefix)) {
      continue;
    }
    sawVisibleDelta = true;
    onAnswerDelta?.call(delta);
  }

  return (
    sawVisibleDelta: sawVisibleDelta,
    streamError: streamError,
  );
}

bool isAgentEmbeddingsQuotaStreamError(String? error) {
  final normalized = error?.trim() ?? '';
  if (normalized.isEmpty) return false;
  return normalized.contains('embeddings_token_quota_exceeded') ||
      normalized.contains('embeddings_input_token_quota_exceeded');
}

String _extractReasoningDeltaText(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (!trimmed.startsWith('{')) return raw;
  final textMatch = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(trimmed);
  return textMatch?.group(1) ?? raw;
}

List<SecretaryRuntimeApprovalItem> _validApprovalItems(
  List<SecretaryRuntimeApprovalItem> items,
) {
  return items
      .where((item) => item.id.trim().isNotEmpty)
      .toList(growable: false);
}
