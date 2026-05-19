part of 'native_backend.dart';

mixin _NativeAppBackendAttachmentAnnotationJobs on _NativeAppBackendAccess {
  Future<void> enqueueAttachmentPlace(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  }

  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  }

  Future<List<AttachmentPlaceJob>> listDueAttachmentPlaces(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
    return const <AttachmentPlaceJob>[];
  }

  Future<List<AttachmentAnnotationJob>> listDueAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
    return const <AttachmentAnnotationJob>[];
  }

  Future<List<AttachmentAnnotationJob>> listDueImageAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
    return const <AttachmentAnnotationJob>[];
  }

  Future<List<AttachmentAnnotationJob>> listDueUrlManifestAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
    return const <AttachmentAnnotationJob>[];
  }

  Future<int> processPendingDocumentExtractions(
    Uint8List key, {
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
    return 0;
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
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
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
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  }

  Future<void> markAttachmentPlaceOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
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
    await _dartDbMarkAttachmentAnnotationOkJson(
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
    throw _retiredNativeRuntimeFeature('geoReverseCloudGateway');
  }

  Future<String> mediaAnnotationCloudGateway({
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    throw _retiredNativeRuntimeFeature('mediaAnnotationCloudGateway');
  }
}
