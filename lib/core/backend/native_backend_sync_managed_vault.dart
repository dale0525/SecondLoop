part of 'native_backend.dart';

@visibleForTesting
int parseManagedVaultBlobRepairQueueDepthForTest(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException(
      'Managed-vault diagnostics payload must be a JSON object.',
    );
  }
  final depth = decoded['blob_repair_queue_depth'];
  if (depth is! num) {
    throw const FormatException(
      'Managed-vault diagnostics payload missing blob_repair_queue_depth.',
    );
  }
  final normalizedDepth = depth.toInt();
  return normalizedDepth < 0 ? 0 : normalizedDepth;
}

mixin _NativeAppBackendSyncManagedVault on _NativeAppBackendAccess {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultPush');
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultPull');
  }

  @override
  Future<int> syncManagedVaultBlobRepairQueueDepth({
    required String baseUrl,
    required String vaultId,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultCursorDiagnostics');
  }

  @override
  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncManagedVaultPullProgress'),
    );
  }

  @override
  Future<void> syncManagedVaultDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    throw _retiredNativeRuntimeFeature(
        'syncManagedVaultDownloadAttachmentBytes');
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultPushOpsOnly');
  }

  @override
  Stream<String> syncManagedVaultPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncManagedVaultPushOpsOnlyProgress'),
    );
  }

  @override
  Stream<String> syncManagedVaultPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncManagedVaultPushProgress'),
    );
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultUploadAttachmentBytes');
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    final appDir = await _getAppDir();
    return 'dart_device_${appDir.hashCode.toUnsigned(32).toRadixString(16)}';
  }

  @override
  Future<void> syncManagedVaultClearDevice({
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String deviceId,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultClearDevice');
  }

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    throw _retiredNativeRuntimeFeature('syncManagedVaultClearVault');
  }
}
