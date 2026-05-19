part of 'native_backend.dart';

mixin _NativeAppBackendSyncWebdav on _NativeAppBackendAccess {
  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavTestConnection');
  }

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavClearRemoteRoot');
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavPush');
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavPushOpsOnly');
  }

  @override
  Stream<String> syncWebdavPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncWebdavPushOpsOnlyProgress'),
    );
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavPull');
  }

  @override
  Stream<String> syncWebdavPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncWebdavPullProgress'),
    );
  }

  @override
  Future<void> syncWebdavDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavDownloadAttachmentBytes');
  }

  @override
  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    throw _retiredNativeRuntimeFeature('syncWebdavUploadAttachmentBytes');
  }
}
