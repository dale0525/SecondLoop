Future<String?> vaultRollbackCreateSnapshot(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:vaultRollbackCreateSnapshot');

Future<void> vaultRollbackRestoreSnapshot(
        {required String appDir,
        required List<int> key,
        required String snapshotPath}) =>
    throw UnsupportedError('rust_runtime_removed:vaultRollbackRestoreSnapshot');

Future<void> vaultRollbackRemoveSnapshot({required String snapshotPath}) =>
    throw UnsupportedError('rust_runtime_removed:vaultRollbackRemoveSnapshot');
