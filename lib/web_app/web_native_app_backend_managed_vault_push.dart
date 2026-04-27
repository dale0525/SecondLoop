part of 'web_native_app_backend.dart';

enum ManagedVaultV2PushMediaActionKind {
  attachmentUpload,
  attachmentDelete,
  artifactUpload,
}

enum ManagedVaultV2PushMediaPhase {
  none,
  batch,
  repairs,
  freshDevice,
}

class ManagedVaultV2PushMediaAction {
  const ManagedVaultV2PushMediaAction({
    required this.kind,
    required this.remoteId,
    this.sha256,
    this.blobRef,
    this.mimeType,
    this.createdAtMs,
  });

  final ManagedVaultV2PushMediaActionKind kind;
  final String remoteId;
  final String? sha256;
  final String? blobRef;
  final String? mimeType;
  final int? createdAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _managedVaultMediaActionKindToJson(kind),
        'remote_id': remoteId,
        if (sha256 != null) 'sha256': sha256,
        if (blobRef != null) 'blob_ref': blobRef,
        if (mimeType != null) 'mime_type': mimeType,
        if (createdAtMs != null) 'created_at_ms': createdAtMs,
      };
}

class ManagedVaultV2PushMediaUpload {
  const ManagedVaultV2PushMediaUpload({
    required this.hasBody,
    required this.remoteId,
    required this.mimeType,
    required this.createdAtMs,
    required this.bytes,
    this.headers = const <String, String>{},
    this.retryable = false,
    this.errorMessage,
  });

  final bool hasBody;
  final String remoteId;
  final String mimeType;
  final int createdAtMs;
  final Uint8List bytes;
  final Map<String, String> headers;
  final bool retryable;
  final String? errorMessage;
}

String _managedVaultMediaActionKindToJson(
  ManagedVaultV2PushMediaActionKind kind,
) {
  switch (kind) {
    case ManagedVaultV2PushMediaActionKind.attachmentUpload:
      return 'attachment_upload';
    case ManagedVaultV2PushMediaActionKind.attachmentDelete:
      return 'attachment_delete';
    case ManagedVaultV2PushMediaActionKind.artifactUpload:
      return 'artifact_upload';
  }
}

ManagedVaultV2PushMediaActionKind _parseManagedVaultMediaActionKind(
  Object? value,
) {
  switch ('${value ?? ''}'.trim()) {
    case 'attachment_upload':
      return ManagedVaultV2PushMediaActionKind.attachmentUpload;
    case 'attachment_delete':
      return ManagedVaultV2PushMediaActionKind.attachmentDelete;
    case 'artifact_upload':
      return ManagedVaultV2PushMediaActionKind.artifactUpload;
    default:
      throw const FormatException('invalid_managed_vault_push_media_kind');
  }
}

String _managedVaultMediaPhaseToJson(ManagedVaultV2PushMediaPhase phase) {
  switch (phase) {
    case ManagedVaultV2PushMediaPhase.none:
      return 'none';
    case ManagedVaultV2PushMediaPhase.batch:
      return 'batch';
    case ManagedVaultV2PushMediaPhase.repairs:
      return 'repairs';
    case ManagedVaultV2PushMediaPhase.freshDevice:
      return 'fresh_device';
  }
}

ManagedVaultV2PushMediaPhase _parseManagedVaultMediaPhase(Object? value) {
  switch ('${value ?? ''}'.trim()) {
    case '':
    case 'none':
      return ManagedVaultV2PushMediaPhase.none;
    case 'batch':
      return ManagedVaultV2PushMediaPhase.batch;
    case 'repairs':
      return ManagedVaultV2PushMediaPhase.repairs;
    case 'fresh_device':
      return ManagedVaultV2PushMediaPhase.freshDevice;
    default:
      throw const FormatException('invalid_managed_vault_push_media_phase');
  }
}

mixin _WebNativeManagedVaultPushBridge on NativeAppBackend {
  Future<String> _resolveAppDir();

  Map<String, Object?> _decodeObjectMap(
    Object? value,
    String errorName,
  );

  String? _decodeOptionalNonEmptyString(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }

  List<ManagedVaultV2PushMediaAction> _decodeManagedVaultPushMediaActions(
    Object? value,
  ) {
    if (value == null) return const <ManagedVaultV2PushMediaAction>[];
    if (value is! List) {
      throw const FormatException('invalid_managed_vault_push_media_actions');
    }
    return value.map((item) {
      final decoded = _decodeObjectMap(
        item,
        'invalid_managed_vault_push_media_action',
      );
      final remoteId = _decodeOptionalNonEmptyString(decoded['remote_id']);
      if (remoteId == null) {
        throw const FormatException('invalid_managed_vault_push_media_remote');
      }
      return ManagedVaultV2PushMediaAction(
        kind: _parseManagedVaultMediaActionKind(decoded['kind']),
        remoteId: remoteId,
        sha256: _decodeOptionalNonEmptyString(decoded['sha256']),
        blobRef: _decodeOptionalNonEmptyString(decoded['blob_ref']),
        mimeType: _decodeOptionalNonEmptyString(decoded['mime_type']),
        createdAtMs: (decoded['created_at_ms'] as num?)?.toInt(),
      );
    }).toList(growable: false);
  }

  Map<String, String> _decodeStringMap(Object? value) {
    if (value == null) return const <String, String>{};
    if (value is! Map) {
      throw const FormatException('invalid_managed_vault_push_media_headers');
    }
    return value.map((key, value) => MapEntry('$key', '$value'));
  }

  Future<ManagedVaultV2PushBatch> prepareManagedVaultV2PushBatch(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    final batchJson = await rust_web_sync.syncManagedVaultPrepareWebPushBatch(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
    );
    final decoded = _decodeObjectMap(
      jsonDecode(batchJson),
      'invalid_managed_vault_push_batch',
    );
    final hasOps = decoded['has_ops'] == true;
    final requestValue = decoded['request'];
    return ManagedVaultV2PushBatch(
      hasOps: hasOps,
      opCount: (decoded['op_count'] as num?)?.toInt() ?? 0,
      request: requestValue == null
          ? null
          : _decodeObjectMap(
              requestValue,
              'invalid_managed_vault_push_request',
            ),
      mediaActions: _decodeManagedVaultPushMediaActions(
        decoded['media_actions'],
      ),
      mediaPhase: _parseManagedVaultMediaPhase(decoded['media_phase']),
      batchJson: batchJson,
    );
  }

  Future<ManagedVaultV2PushApplyResult> applyManagedVaultV2PushResponse({
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
    required Map<String, Object?> response,
  }) async {
    final decoded = _decodeObjectMap(
      jsonDecode(
        await rust_web_sync.syncManagedVaultApplyWebPushResponse(
          appDir: appDir,
          baseUrl: baseUrl,
          vaultId: vaultId,
          batchJson: batch.batchJson,
          responseJson: jsonEncode(response),
        ),
      ),
      'invalid_managed_vault_push_apply_result',
    );
    return ManagedVaultV2PushApplyResult(
      accepted: (decoded['accepted'] as num?)?.toInt() ?? 0,
      generationId: '${decoded['generation_id'] ?? ''}',
      remoteLatestGlobalSeq:
          (decoded['remote_latest_global_seq'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ManagedVaultV2PushMediaUpload> prepareManagedVaultV2PushMediaUpload({
    required String appDir,
    required Uint8List key,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushMediaAction action,
    required ManagedVaultV2PushMediaPhase mediaPhase,
  }) async {
    final decoded = _decodeObjectMap(
      jsonDecode(
        await rust_web_sync.syncManagedVaultPrepareWebPushMediaUpload(
          appDir: appDir,
          key: key,
          syncKey: syncKey,
          baseUrl: baseUrl,
          vaultId: vaultId,
          actionJson: jsonEncode(action.toJson()),
          mediaPhase: _managedVaultMediaPhaseToJson(mediaPhase),
        ),
      ),
      'invalid_managed_vault_push_media_upload',
    );
    final hasBody = decoded['has_body'] == true;
    final ciphertextB64 = '${decoded['ciphertext_b64'] ?? ''}'.trim();
    return ManagedVaultV2PushMediaUpload(
      hasBody: hasBody,
      remoteId: _decodeOptionalNonEmptyString(decoded['remote_id']) ??
          action.remoteId,
      mimeType: _decodeOptionalNonEmptyString(decoded['mime_type']) ??
          'application/octet-stream',
      createdAtMs: (decoded['created_at_ms'] as num?)?.toInt() ?? 0,
      bytes: hasBody && ciphertextB64.isNotEmpty
          ? base64Decode(ciphertextB64)
          : Uint8List(0),
      headers: _decodeStringMap(decoded['headers']),
      retryable: decoded['retryable'] == true,
      errorMessage: _decodeOptionalNonEmptyString(decoded['error_message']),
    );
  }

  Future<void> recordManagedVaultV2PushMediaResult({
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushMediaAction action,
    required bool success,
    String? errorMessage,
  }) async {
    await rust_web_sync.syncManagedVaultRecordWebPushMediaResult(
      appDir: appDir,
      baseUrl: baseUrl,
      vaultId: vaultId,
      actionJson: jsonEncode(action.toJson()),
      success: success,
      errorMessage: errorMessage,
    );
  }

  Future<void> completeManagedVaultV2PushMediaBatch({
    required String appDir,
    required Uint8List key,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
  }) async {
    await rust_web_sync.syncManagedVaultCompleteWebPushMediaBatch(
      appDir: appDir,
      key: key,
      baseUrl: baseUrl,
      vaultId: vaultId,
      batchJson: batch.batchJson,
    );
  }

  Future<bool> _runManagedVaultPushMediaActions(
    WebAppService webAppService,
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required ManagedVaultV2PushBatch batch,
  }) async {
    var allSucceeded = true;
    for (final action in batch.mediaActions) {
      try {
        switch (action.kind) {
          case ManagedVaultV2PushMediaActionKind.attachmentUpload:
          case ManagedVaultV2PushMediaActionKind.artifactUpload:
            final upload = await prepareManagedVaultV2PushMediaUpload(
              appDir: appDir,
              key: key,
              syncKey: syncKey,
              baseUrl: baseUrl,
              vaultId: vaultId,
              action: action,
              mediaPhase: batch.mediaPhase,
            );
            if (upload.hasBody) {
              await webAppService.uploadManagedVaultMedia(
                idToken: idToken,
                vaultId: vaultId,
                remoteId: upload.remoteId,
                mimeType: upload.mimeType,
                createdAtMs: upload.createdAtMs,
                bytes: upload.bytes,
                headers: upload.headers,
              );
              await recordManagedVaultV2PushMediaResult(
                appDir: appDir,
                baseUrl: baseUrl,
                vaultId: vaultId,
                action: action,
                success: true,
              );
            } else {
              final success = !upload.retryable;
              allSucceeded = allSucceeded && success;
              await recordManagedVaultV2PushMediaResult(
                appDir: appDir,
                baseUrl: baseUrl,
                vaultId: vaultId,
                action: action,
                success: success,
                errorMessage: upload.errorMessage,
              );
            }
            break;
          case ManagedVaultV2PushMediaActionKind.attachmentDelete:
            await webAppService.deleteManagedVaultMedia(
              idToken: idToken,
              vaultId: vaultId,
              remoteId: action.remoteId,
            );
            await recordManagedVaultV2PushMediaResult(
              appDir: appDir,
              baseUrl: baseUrl,
              vaultId: vaultId,
              action: action,
              success: true,
            );
            break;
        }
      } catch (error) {
        allSucceeded = false;
        await recordManagedVaultV2PushMediaResult(
          appDir: appDir,
          baseUrl: baseUrl,
          vaultId: vaultId,
          action: action,
          success: false,
          errorMessage: error.toString(),
        );
      }
    }

    if (allSucceeded) {
      await completeManagedVaultV2PushMediaBatch(
        appDir: appDir,
        key: key,
        baseUrl: baseUrl,
        vaultId: vaultId,
        batch: batch,
      );
    }
    return allSucceeded;
  }

  Future<int> _syncManagedVaultPushThroughWebAppService(
    WebAppService webAppService,
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _resolveAppDir();
    var totalAccepted = 0;
    while (true) {
      final batch = await prepareManagedVaultV2PushBatch(
        key,
        syncKey,
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
      );
      if (!batch.hasOps) {
        if (batch.mediaActions.isNotEmpty) {
          await _runManagedVaultPushMediaActions(
            webAppService,
            key,
            syncKey,
            appDir: appDir,
            baseUrl: baseUrl,
            vaultId: vaultId,
            idToken: idToken,
            batch: batch,
          );
        }
        return totalAccepted;
      }
      final request = batch.request;
      if (request == null) {
        throw StateError('managed_vault_push_missing_request');
      }
      final response = await webAppService.pushManagedVaultBatch(
        idToken: idToken,
        vaultId: vaultId,
        request: request,
      );
      final result = await applyManagedVaultV2PushResponse(
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
        batch: batch,
        response: response,
      );
      totalAccepted += result.accepted;
      if (batch.mediaActions.isNotEmpty) {
        final mediaSucceeded = await _runManagedVaultPushMediaActions(
          webAppService,
          key,
          syncKey,
          appDir: appDir,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
          batch: batch,
        );
        if (!mediaSucceeded) {
          return totalAccepted;
        }
      }
    }
  }
}
