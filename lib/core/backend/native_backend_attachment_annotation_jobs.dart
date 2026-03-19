part of 'native_backend.dart';

mixin _NativeAppBackendAttachmentAnnotationJobs on _NativeAppBackendAccess {
  Future<void> enqueueAttachmentPlace(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueAttachmentPlace(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueAttachmentAnnotation(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  Future<List<AttachmentPlaceJob>> listDueAttachmentPlaces(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueAttachmentPlaces(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  Future<List<AttachmentAnnotationJob>> listDueAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  Future<List<AttachmentAnnotationJob>> listDueImageAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbListDueImageAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  Future<List<AttachmentAnnotationJob>> listDueUrlManifestAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbListDueUrlManifestAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  Future<int> processPendingDocumentExtractions(
    Uint8List key, {
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbProcessPendingDocumentExtractions(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  Future<void> markAttachmentPlaceFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentPlaceFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  Future<void> markAttachmentAnnotationFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentAnnotationFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  Future<void> markAttachmentPlaceOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentPlaceOkJson(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      payloadJson: payloadJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markAttachmentAnnotationOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentAnnotationOkJson(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      modelName: modelName,
      payloadJson: payloadJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  Future<String> geoReverseCloudGateway({
    required String gatewayBaseUrl,
    required String idToken,
    required double lat,
    required double lon,
    required String lang,
  }) async {
    return rust_core.geoReverseCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      lat: lat,
      lon: lon,
      lang: lang,
    );
  }

  Future<String> mediaAnnotationCloudGateway({
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    return rust_core.mediaAnnotationCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      lang: lang,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );
  }
}
