part of 'native_backend.dart';

mixin _NativeAppBackendVaultRollback on _NativeAppBackendAccess {
  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    throw _retiredNativeRuntimeFeature('vaultRollbackCreateSnapshot');
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    throw _retiredNativeRuntimeFeature('vaultRollbackRestoreSnapshot');
  }

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {
    throw _retiredNativeRuntimeFeature('vaultRollbackRemoveSnapshot');
  }
}
