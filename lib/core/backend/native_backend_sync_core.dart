part of 'native_backend.dart';

mixin _NativeAppBackendSyncCore on _NativeAppBackendAccess {
  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    return rust_core.syncDeriveKey(passphrase: passphrase);
  }

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async {
    return rust_core.syncCreateRecoveryEnvelope(
      syncKey: syncKey,
      passphrase: passphrase,
    );
  }

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    return rust_core.syncRecoverSyncKeyFromEnvelope(
      envelopeJson: envelopeJson,
      passphrase: passphrase,
    );
  }
}
