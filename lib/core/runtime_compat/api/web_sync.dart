Future<String> syncManagedVaultReadWebPullState(
        {required String appDir,
        required String baseUrl,
        required String vaultId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultReadWebPullState');

Future<String> syncManagedVaultApplyWebPullPage(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String responseJson}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultApplyWebPullPage');

Future<String> syncManagedVaultRecoverWebPullState(
        {required String appDir,
        required List<int> key,
        required String baseUrl,
        required String vaultId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultRecoverWebPullState');

Future<bool> syncManagedVaultFinalizeWebPull(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken,
        required BigInt appliedOps}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultFinalizeWebPull');

Future<String> syncManagedVaultPrepareWebPushBatch(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultPrepareWebPushBatch');

Future<String> syncManagedVaultApplyWebPushResponse(
        {required String appDir,
        required String baseUrl,
        required String vaultId,
        required String batchJson,
        required String responseJson}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultApplyWebPushResponse');

Future<String> syncManagedVaultPrepareWebPushMediaUpload(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String actionJson}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultPrepareWebPushMediaUpload');

Future<bool> syncManagedVaultRecordWebPushMediaResult(
        {required String appDir,
        required String baseUrl,
        required String vaultId,
        required String actionJson,
        required bool success,
        String? errorMessage}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultRecordWebPushMediaResult');

Future<bool> syncManagedVaultCompleteWebPushMediaBatch(
        {required String appDir,
        required List<int> key,
        required String baseUrl,
        required String vaultId,
        required String batchJson}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultCompleteWebPushMediaBatch');
