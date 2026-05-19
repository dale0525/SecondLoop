part of 'native_backend.dart';

mixin _NativeAppBackendSyncCore on _NativeAppBackendAccess {
  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    throw _retiredNativeRuntimeFeature('syncDeriveKey');
  }

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async {
    throw _retiredNativeRuntimeFeature('syncCreateRecoveryEnvelope');
  }

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    throw _retiredNativeRuntimeFeature('syncRecoverSyncKeyFromEnvelope');
  }
}
