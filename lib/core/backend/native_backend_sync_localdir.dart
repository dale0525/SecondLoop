part of 'native_backend.dart';

mixin _NativeAppBackendSyncLocaldir on _NativeAppBackendAccess {
  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncLocaldirTestConnection');
  }

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncLocaldirClearRemoteRoot');
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncLocaldirPush');
  }

  @override
  Stream<String> syncLocaldirPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncLocaldirPushProgress'),
    );
  }

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    throw _retiredNativeRuntimeFeature('syncLocaldirPull');
  }

  @override
  Stream<String> syncLocaldirPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) {
    return Stream<String>.error(
      _retiredNativeRuntimeFeature('syncLocaldirPullProgress'),
    );
  }

  @override
  Future<void> syncLocaldirDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
    required String sha256,
  }) async {
    throw _retiredNativeRuntimeFeature('syncLocaldirDownloadAttachmentBytes');
  }
}
