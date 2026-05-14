part of 'native_backend.dart';

mixin _NativeAppBackendVaultRollback on _NativeAppBackendAccess {
  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_vault_rollback.vaultRollbackCreateSnapshot(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    final appDir = await _getAppDir();
    await rust_vault_rollback.vaultRollbackRestoreSnapshot(
      appDir: appDir,
      key: key,
      snapshotPath: snapshotPath,
    );
  }

  @override
  Future<void> deleteVaultRollbackSnapshot(
      {required String snapshotPath}) async {
    await rust_vault_rollback.vaultRollbackRemoveSnapshot(
      snapshotPath: snapshotPath,
    );
  }
}
