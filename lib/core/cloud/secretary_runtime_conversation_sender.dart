import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'runtime_connection_store.dart';
import 'runtime_manifest.dart';
import 'runtime_profile.dart';
import 'runtime_api_client.dart';
import 'secretary_runtime_client.dart';
import 'secretary_runtime_conversation_models.dart';

abstract interface class ChatRuntimeConversationSender {
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  });
}

abstract interface class ChatRuntimeConversationAttachmentSender
    implements ChatRuntimeConversationSender {
  Future<SecretaryRuntimeConversationResult> sendWithAttachments({
    required String vaultId,
    required String conversationId,
    required String message,
    String? messageDisplayText,
    String? attachmentIntent,
    List<Map<String, Object?>> uploadAttachments =
        const <Map<String, Object?>>[],
    required List<Map<String, Object?>> messageAttachments,
  });
}

abstract interface class ChatRuntimeAttachmentContentFetcher {
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  });
}

abstract interface class ChatRuntimeApprovalSender {
  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals({
    required String vaultId,
  });

  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String approvalId,
    required String decision,
  });

  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  });
}

abstract interface class ChatRuntimeEntityFocusSender {
  Future<void> recordEntityFocus({
    required String vaultId,
    required String conversationId,
    required String entityType,
    required String entityId,
    required String title,
  });
}

final class SecretaryRuntimeConversationSender
    implements
        ChatRuntimeConversationSender,
        ChatRuntimeConversationAttachmentSender,
        ChatRuntimeAttachmentContentFetcher,
        ChatRuntimeApprovalSender,
        ChatRuntimeEntityFocusSender {
  SecretaryRuntimeConversationSender({
    SecretaryRuntimeClient? client,
  }) : _client = client ?? SecretaryRuntimeClient();

  factory SecretaryRuntimeConversationSender.hostedManagedPro({
    required String apiBaseUrl,
    required Future<String?> Function() hostedSessionTokenGetter,
    http.Client? httpClient,
  }) {
    final normalizedBaseUrl = apiBaseUrl.trim();
    return SecretaryRuntimeConversationSender(
      client: SecretaryRuntimeClient(
        apiClient: RuntimeApiClient(
          httpClient: httpClient,
          connectionLoader: () async {
            final token = (await hostedSessionTokenGetter())?.trim() ?? '';
            if (normalizedBaseUrl.isEmpty || token.isEmpty) {
              return null;
            }
            return CloudRuntimeConnection(
              profile: CloudRuntimeProfile(
                runtimeMode: CloudRuntimeMode.managedPro,
                apiBaseUrl: normalizedBaseUrl,
                authMode: CloudRuntimeAuthMode.hostedSession,
                authToken: token,
                capabilityManifestId: 'managed-pro-runtime',
                manifestVersion:
                    RuntimeConnectionStore.supportedManifestVersion,
              ),
              manifest: CloudRuntimeManifest(
                manifestVersion:
                    RuntimeConnectionStore.supportedManifestVersion,
                runtimeMode: CloudRuntimeMode.managedPro,
                apiBaseUrl: normalizedBaseUrl,
                authMode: CloudRuntimeAuthMode.hostedSession,
                capabilities: CloudRuntimeRequiredCapabilities.all,
                skills: CloudRuntimeKnownSkills.all,
              ),
            );
          },
        ),
      ),
    );
  }

  final SecretaryRuntimeClient _client;

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    return sendWithAttachments(
      vaultId: vaultId,
      conversationId: conversationId,
      message: message,
      uploadAttachments: const <Map<String, Object?>>[],
      messageAttachments: const <Map<String, Object?>>[],
    );
  }

  @override
  Future<SecretaryRuntimeConversationResult> sendWithAttachments({
    required String vaultId,
    required String conversationId,
    required String message,
    String? messageDisplayText,
    String? attachmentIntent,
    List<Map<String, Object?>> uploadAttachments =
        const <Map<String, Object?>>[],
    required List<Map<String, Object?>> messageAttachments,
  }) async {
    await _uploadVaultAttachments(
      vaultId: vaultId,
      attachments: uploadAttachments,
    );
    return _client.sendConversationMessage(
      vaultId,
      conversationId: conversationId,
      message: message,
      attachments: messageAttachments,
      messageDisplayText: messageDisplayText,
      attachmentIntent: attachmentIntent,
    );
  }

  Future<void> _uploadVaultAttachments({
    required String vaultId,
    required List<Map<String, Object?>> attachments,
  }) async {
    for (final attachment in attachments) {
      final attachmentId = _attachmentString(
        attachment,
        const ['attachment_id', 'id', 'sha256', 'blob_id'],
      );
      final encoded = _attachmentString(
        attachment,
        const ['content_base64', 'bytes_base64'],
      );
      if (attachmentId.isEmpty || encoded.isEmpty) continue;
      final bytes = base64Decode(encoded);
      await _client.uploadVaultAttachment(
        vaultId,
        attachmentId: attachmentId,
        filename: _attachmentString(
          attachment,
          const ['filename', 'display_name', 'name'],
          fallback: attachmentId,
        ),
        mimeType: _attachmentString(
          attachment,
          const ['mime_type', 'content_type'],
          fallback: 'application/octet-stream',
        ),
        mediaType: _attachmentString(
          attachment,
          const ['media_type', 'type'],
          fallback: 'file',
        ),
        bytes: bytes,
      );
    }
  }

  @override
  Future<Uint8List?> fetchAttachmentBytes({
    required String vaultId,
    required String attachmentId,
  }) {
    return _client.fetchVaultAttachmentBytes(
      vaultId,
      attachmentId: attachmentId,
    );
  }

  @override
  Future<List<SecretaryRuntimeApprovalItem>> fetchApprovals({
    required String vaultId,
  }) {
    return _client.fetchApprovals(vaultId);
  }

  @override
  Future<SecretaryRuntimeConversationResult?> submitApprovalDecision({
    required String vaultId,
    required String approvalId,
    required String decision,
  }) {
    return _client.submitApprovalDecision(
      vaultId,
      approvalId: approvalId,
      decision: decision,
    );
  }

  @override
  Future<SecretaryRuntimeApprovalItem> patchApprovalItem({
    required String vaultId,
    required String approvalId,
    required int baseVersion,
    required Map<String, Object?> changes,
  }) {
    return _client.patchApprovalItem(
      vaultId,
      approvalId: approvalId,
      baseVersion: baseVersion,
      changes: changes,
    );
  }

  @override
  Future<void> recordEntityFocus({
    required String vaultId,
    required String conversationId,
    required String entityType,
    required String entityId,
    required String title,
  }) {
    return _client.recordEntityFocus(
      vaultId,
      conversationId: conversationId,
      entityType: entityType,
      entityId: entityId,
      title: title,
    );
  }
}

String _attachmentString(
  Map<String, Object?> attachment,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = '${attachment[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != 'null') return value;
  }
  return fallback;
}
