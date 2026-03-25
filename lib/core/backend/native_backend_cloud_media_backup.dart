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
    final appDir = await _getAppDir();
    return rust_core.dbUpsertAttachmentVariant(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      variant: variant,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<Uint8List> readAttachmentVariantBytes(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentVariantBytes(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      variant: variant,
    );
  }

  @override
  Future<void> enqueueCloudMediaBackup(
    Uint8List key, {
    required String attachmentSha256,
    required String desiredVariant,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueCloudMediaBackup(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      desiredVariant: desiredVariant,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    final affected = await rust_core.dbBackfillCloudMediaBackupImages(
      appDir: appDir,
      key: key,
      desiredVariant: desiredVariant,
      nowMs: PlatformInt64Util.from(nowMs),
    );
    return affected.toInt();
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueCloudMediaBackups(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkCloudMediaBackupFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkCloudMediaBackupUploaded(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbCloudMediaBackupSummary(appDir: appDir, key: key);
  }
}
