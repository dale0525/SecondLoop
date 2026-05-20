import 'dart:typed_data';

import '../backend/app_backend.dart';
import 'secretary_runtime_client.dart';
import 'secretary_runtime_conversation_models.dart';
import 'secretary_runtime_conversation_sender.dart';

part 'runtime_secretary_app_service_memory.dart';

final class RuntimeSecretaryAppService {
  const RuntimeSecretaryAppService({
    required ChatRuntimeConversationSender sender,
    required AppBackend backend,
    required Uint8List sessionKey,
  }) : _sender = sender;

  final ChatRuntimeConversationSender _sender;

  Future<SecretaryRuntimeConversationResult> sendAndApply({
    required String vaultId,
    required String conversationId,
    required String message,
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
    String? sourceMessageId,
  }) async {
    final sender = _sender;
    final result = attachments.isNotEmpty &&
            sender is ChatRuntimeConversationAttachmentSender
        ? await sender.sendWithAttachments(
            vaultId: vaultId,
            conversationId: conversationId,
            message: message,
            attachments: attachments,
          )
        : await sender.send(
            vaultId: vaultId,
            conversationId: conversationId,
            message: message,
          );
    await applyResult(
      result,
      conversationId: conversationId,
      sourceMessageId: sourceMessageId,
    );
    return result;
  }

  Future<void> applyResult(
    SecretaryRuntimeConversationResult result, {
    required String conversationId,
    String? sourceMessageId,
  }) async {}

  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String conversationId,
    required String approvalId,
    required String decision,
    String? sourceMessageId,
  }) async {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    final result = await approvalSender.submitApprovalDecision(
      vaultId: vaultId,
      approvalId: approvalId,
      decision: decision,
    );
    if (result != null) {
      await applyResult(
        result,
        conversationId: conversationId,
        sourceMessageId: sourceMessageId,
      );
    }
    return result;
  }

  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovalItems({
    required String vaultId,
  }) {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    return approvalSender.fetchApprovals(vaultId: vaultId);
  }

  Future<SecretaryRuntimeApprovalItem> patchApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required Map<String, Object?> changes,
  }) {
    final sender = _sender;
    if (sender is! ChatRuntimeApprovalSender) {
      throw StateError('runtime_approval_sender_required');
    }
    final approvalSender = sender as ChatRuntimeApprovalSender;
    return approvalSender.patchApprovalItem(
      vaultId: vaultId,
      approvalId: item.id,
      baseVersion: item.version,
      changes: changes,
    );
  }

  Future<SecretaryRuntimeConversationResult?> approveApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required String conversationId,
    String? sourceMessageId,
  }) {
    return submitApprovalDecision(
      vaultId: vaultId,
      conversationId: conversationId,
      approvalId: item.id,
      decision: 'approve',
      sourceMessageId: sourceMessageId,
    );
  }

  Future<void> rejectApprovalItem(
    SecretaryRuntimeApprovalItem item, {
    required String vaultId,
    required String conversationId,
    String? sourceMessageId,
  }) {
    return submitApprovalDecision(
      vaultId: vaultId,
      conversationId: conversationId,
      approvalId: item.id,
      decision: 'reject',
      sourceMessageId: sourceMessageId,
    );
  }

  Future<void> applyApprovedTaskMutation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {}

  Future<void> applyApprovedMemoryConfirmation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {}

  Future<void> applyApprovedRecurringReminderConfirmation(
    SecretaryRuntimeApprovalItem item, {
    String? sourceMessageId,
  }) async {}
}

Future<void> applyRuntimeTaskMutations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {}

Future<void> applyRuntimeTaskCreations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) {
  return applyRuntimeTaskMutations(
    result,
    backend: backend,
    sessionKey: sessionKey,
    sourceMessageId: sourceMessageId,
  );
}

Future<void> applyRuntimeRecurringReminderMutations(
  SecretaryRuntimeConversationResult result, {
  required AppBackend backend,
  required Uint8List sessionKey,
  required String? sourceMessageId,
}) async {}
