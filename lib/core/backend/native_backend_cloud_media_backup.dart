part of 'native_backend.dart';

mixin _NativeAppBackendCloudMediaBackup on _NativeAppBackendAccess {
  @override
  Future<AttachmentVariant> upsertAttachmentVariant(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    throw _retiredNativeRuntimeFeature('dbUpsertAttachmentVariant');
  }

  @override
  Future<Uint8List> readAttachmentVariantBytes(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
  }) async {
    throw _retiredNativeRuntimeFeature('dbReadAttachmentVariantBytes');
  }

  @override
  Future<void> enqueueCloudMediaBackup(
    Uint8List key, {
    required String attachmentSha256,
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbEnqueueCloudMediaBackup');
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbBackfillCloudMediaBackupImages');
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbListDueCloudMediaBackups');
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkCloudMediaBackupFailed');
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbMarkCloudMediaBackupUploaded');
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    throw _retiredNativeRuntimeFeature('dbCloudMediaBackupSummary');
  }
}
