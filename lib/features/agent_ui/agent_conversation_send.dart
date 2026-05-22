import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/cloud/runtime_secretary_app_service.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../../core/cloud/secretary_runtime_conversation_sender.dart';
import '../../core/subscription/subscription_scope.dart';

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
    required this.assistantContent,
    required this.mediaResults,
    required this.turnId,
    this.streamError,
  });

  final AskAiRouteKind routeKind;
  final bool userMessageCommitted;
  final bool sawVisibleDelta;
  final String? streamError;
  final List<SecretaryRuntimeApprovalItem> approvalItems;
  final String assistantContent;
  final List<Map<String, Object?>> mediaResults;
  final String turnId;
}

Future<AgentConversationSendResult> sendAgentConversationMessage({
  required BuildContext context,
  required AppBackend backend,
  required Uint8List sessionKey,
  required String conversationId,
  required String message,
  List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
  List<Map<String, Object?>> uploadAttachments = const <Map<String, Object?>>[],
  String? messageDisplayText,
  String? attachmentIntent,
  ChatRuntimeConversationSender? runtimeConversationSender,
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
        attachments: attachments,
        uploadAttachments: uploadAttachments,
        messageDisplayText: messageDisplayText,
        attachmentIntent: attachmentIntent,
      );
      userMessageCommitted = true;
      var approvalItems = result.metadata.approvalItems;
      if (approvalItems.isEmpty && result.metadata.approvalRequired) {
        approvalItems = await service.fetchApprovalItems(vaultId: vaultId);
      }
      return AgentConversationSendResult(
        routeKind: route.route,
        userMessageCommitted: userMessageCommitted,
        sawVisibleDelta: result.assistantContent.trim().isNotEmpty,
        approvalItems: _validApprovalItems(approvalItems),
        assistantContent: result.assistantContent,
        mediaResults: result.metadata.mediaResults,
        turnId: result.metadata.turnId,
      );
    }

    throw StateError('agent_runtime_route_required');
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

  return (
    route: defaultRoute,
    cloudIdToken: cloudIdToken,
    cloudGatewayConfig: cloudGatewayConfig,
  );
}

List<SecretaryRuntimeApprovalItem> _validApprovalItems(
  List<SecretaryRuntimeApprovalItem> items,
) {
  return items
      .where((item) => item.id.trim().isNotEmpty)
      .toList(growable: false);
}
