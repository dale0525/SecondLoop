part of 'native_backend.dart';

mixin _NativeAppBackendSyncManagedVault on _NativeAppBackendAccess {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncManagedVaultPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pushed.toInt();
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncManagedVaultPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pulled.toInt();
  }

  @override
  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncManagedVaultPullProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
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
    final appDir = await _getAppDir();
    await rust_core.syncManagedVaultDownloadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      sha256: sha256,
    );
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncManagedVaultPushOpsOnly(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pushed.toInt();
  }

  @override
  Stream<String> syncManagedVaultPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncManagedVaultPushOpsOnlyProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
  }

  @override
  Stream<String> syncManagedVaultPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncManagedVaultPushProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
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
    final appDir = await _getAppDir();
    return rust_core.syncManagedVaultUploadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      sha256: sha256,
    );
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateDeviceId(appDir: appDir);
  }

  @override
  Future<void> syncManagedVaultClearDevice({
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String deviceId,
  }) async {
    await rust_core.syncManagedVaultClearDevice(
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      deviceId: deviceId,
    );
  }

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    await rust_core.syncManagedVaultClearVault(
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
  }
}
