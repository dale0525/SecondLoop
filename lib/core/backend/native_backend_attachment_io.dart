part of 'native_backend.dart';

mixin _NativeAppBackendAttachmentIo on _NativeAppBackendAccess {
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final appDir = await _getAppDir();
    return _dbInsertAttachment(
      appDir: appDir,
      key: key,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  Future<void> upsertAttachmentDerivation(
    Uint8List key, {
    required String rootSha256,
    required String childSha256,
    required String role,
    required int createdAtMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertAttachmentDerivation(
      appDir: appDir,
      key: key,
      rootSha256: rootSha256,
      childSha256: childSha256,
      role: role,
      createdAtMs: PlatformInt64Util.from(createdAtMs),
    );
  }

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListRecentAttachments(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbLinkAttachmentToMessage(
      appDir: appDir,
      key: key,
      messageId: messageId,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
      Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessageAttachments(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentBytes(
      appDir: appDir,
      key: key,
      sha256: sha256,
    );
  }

  Future<void> upsertAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
    int? capturedAtMs,
    double? latitude,
    double? longitude,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertAttachmentExifMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
      capturedAtMs:
          capturedAtMs == null ? null : PlatformInt64Util.from(capturedAtMs),
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentExifMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentPlaceDisplayName(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentAnnotationCaptionLong(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbReadAttachmentAnnotationPayloadJson(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {
    final appDir = await _getAppDir();
    await rust_core.dbEditMessage(
      appDir: appDir,
      key: key,
      messageId: messageId,
      content: content,
    );
  }

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {
    final appDir = await _getAppDir();
    await rust_core.dbSetMessageDeleted(
      appDir: appDir,
      key: key,
      messageId: messageId,
      isDeleted: isDeleted,
    );
  }

  @override
  Future<void> purgeMessageAttachments(Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    await rust_core.dbPurgeMessageAttachments(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.dbResetVaultDataPreservingLlmProfiles(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> clearLocalAttachmentCache(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.dbClearLocalAttachmentCache(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    final appDir = await _getAppDir();
    return rust_attachments.dbReadAttachmentBySha256(
      appDir: appDir,
      attachmentSha256: attachmentSha256,
    );
  }
}
