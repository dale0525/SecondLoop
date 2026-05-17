Stream<String> syncWebdavPullProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavPullProgress');

Stream<String> syncWebdavPushOpsOnlyProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncWebdavPushOpsOnlyProgress');

Stream<String> syncLocaldirPullProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirPullProgress');

Stream<String> syncLocaldirPushProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirPushProgress');

Stream<String> syncManagedVaultPullProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String idToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultPullProgress');

Stream<String> syncManagedVaultPushOpsOnlyProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String idToken}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultPushOpsOnlyProgress');

Stream<String> syncManagedVaultPushProgress(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String idToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultPushProgress');
