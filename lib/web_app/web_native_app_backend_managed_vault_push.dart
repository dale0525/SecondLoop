part of 'web_native_app_backend.dart';

const int _kManagedVaultPushBatchWatchdogLimit = 1024;

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

mixin _WebNativeManagedVaultPushBridge on NativeAppBackend {
  Future<String> _resolveAppDir();

  Future<ManagedVaultV2PushBatch> prepareManagedVaultV2PushBatch(
    Uint8List key,
    Uint8List syncKey, {
    required String appDir,
    required String baseUrl,
    required String vaultId,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultPrepareWebPushBatch',
    );
  }

  Future<ManagedVaultV2PushApplyResult> applyManagedVaultV2PushResponse({
    required String appDir,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
    required Map<String, Object?> response,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultApplyWebPushResponse',
    );
  }

  Future<ManagedVaultV2PushMediaUpload> prepareManagedVaultV2PushMediaUpload({
    required String appDir,
    required Uint8List key,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushMediaAction action,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultPrepareWebPushMediaUpload',
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
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultRecordWebPushMediaResult',
    );
  }

  Future<void> completeManagedVaultV2PushMediaBatch({
    required String appDir,
    required Uint8List key,
    required String baseUrl,
    required String vaultId,
    required ManagedVaultV2PushBatch batch,
  }) async {
    throw _retiredWebNativeRuntimeFeature(
      'syncManagedVaultCompleteWebPushMediaBatch',
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
    for (var iteration = 0;
        iteration < _kManagedVaultPushBatchWatchdogLimit;
        iteration += 1) {
      final batch = await prepareManagedVaultV2PushBatch(
        key,
        syncKey,
        appDir: appDir,
        baseUrl: baseUrl,
        vaultId: vaultId,
      );
      if (!batch.hasOps) {
        if (batch.mediaActions.isEmpty) {
          return totalAccepted;
        }
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
        continue;
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
    throw StateError('managed_vault_push_iteration_limit_exceeded');
  }
}
