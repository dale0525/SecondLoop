part of 'media_enrichment_gate.dart';

final class _CompositeMediaEnrichmentClient implements MediaEnrichmentClient {
  const _CompositeMediaEnrichmentClient({
    required this.placeClient,
    required this.annotationClient,
  });

  final MediaEnrichmentClient placeClient;
  final MediaEnrichmentClient annotationClient;

  @override
  String get annotationModelName => annotationClient.annotationModelName;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) =>
      placeClient.reverseGeocode(lat: lat, lon: lon, lang: lang);

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) =>
      annotationClient.annotateImage(
        lang: lang,
        mimeType: mimeType,
        imageBytes: imageBytes,
      );
}

final class _ByokMediaEnrichmentClient implements MediaEnrichmentClient {
  const _ByokMediaEnrichmentClient({
    required Uint8List sessionKey,
    required this.profileId,
    required this.modelName,
    required this.appDirProvider,
  }) : _sessionKey = sessionKey;

  final Uint8List _sessionKey;
  final String profileId;
  final String modelName;
  final Future<String> Function() appDirProvider;

  @override
  String get annotationModelName => modelName;

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) {
    throw StateError('reverse_geocode_not_available_for_byok_annotation');
  }

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    final appDir = await appDirProvider();
    return rust_media_annotation.mediaAnnotationByokProfile(
      appDir: appDir,
      key: _sessionKey,
      profileId: profileId,
      localDay: _MediaEnrichmentGateState._formatLocalDayKey(DateTime.now()),
      lang: lang,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );
  }
}

final class _GatedMediaEnrichmentStore implements MediaEnrichmentStore {
  const _GatedMediaEnrichmentStore({
    required this.baseStore,
    required this.placesEnabled,
    required this.annotationEnabled,
  });

  final MediaEnrichmentStore baseStore;
  final bool placesEnabled;
  final bool annotationEnabled;

  @override
  Future<List<MediaEnrichmentPlaceItem>> listDuePlaces({
    required int nowMs,
    int limit = 5,
  }) {
    if (!placesEnabled) return Future.value(const <MediaEnrichmentPlaceItem>[]);
    return baseStore.listDuePlaces(nowMs: nowMs, limit: limit);
  }

  @override
  Future<List<MediaEnrichmentAnnotationItem>> listDueAnnotations({
    required int nowMs,
    int limit = 5,
  }) {
    if (!annotationEnabled) {
      return Future.value(const <MediaEnrichmentAnnotationItem>[]);
    }
    return baseStore.listDueAnnotations(nowMs: nowMs, limit: limit);
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata({
    required String attachmentSha256,
  }) =>
      baseStore.readAttachmentExifMetadata(attachmentSha256: attachmentSha256);

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) =>
      baseStore.readAttachmentBytes(attachmentSha256: attachmentSha256);

  @override
  Future<void> markPlaceOk({
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) =>
      baseStore.markPlaceOk(
        attachmentSha256: attachmentSha256,
        lang: lang,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markPlaceFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      baseStore.markPlaceFailed(
        attachmentSha256: attachmentSha256,
        error: error,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) =>
      baseStore.markAnnotationOk(
        attachmentSha256: attachmentSha256,
        lang: lang,
        modelName: modelName,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      baseStore.markAnnotationFailed(
        attachmentSha256: attachmentSha256,
        error: error,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        nowMs: nowMs,
      );
}

final class _BackendUrlEnrichmentStore implements UrlEnrichmentStore {
  _BackendUrlEnrichmentStore({
    required this.backend,
    required Uint8List sessionKey,
    AttachmentMetadataStore? metadataStore,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _metadataStore = metadataStore ?? const RustAttachmentMetadataStore();

  final NativeAppBackend backend;
  final Uint8List _sessionKey;
  final AttachmentMetadataStore _metadataStore;

  @override
  Future<List<UrlEnrichmentJob>> listDueUrlAnnotations({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await backend.listDueUrlManifestAttachmentAnnotations(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => UrlEnrichmentJob(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) =>
      backend.readAttachmentBytes(_sessionKey, sha256: attachmentSha256);

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) =>
      backend.markAttachmentAnnotationOkJson(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        modelName: modelName,
        payloadJson: payloadJson,
        nowMs: nowMs,
      );

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) =>
      backend.markAttachmentAnnotationFailed(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        attempts: attempts,
        nextRetryAtMs: nextRetryAtMs,
        lastError: error,
        nowMs: nowMs,
      );

  @override
  Future<void> upsertAttachmentTitle({
    required String attachmentSha256,
    required String title,
  }) =>
      _metadataStore.upsert(
        _sessionKey,
        attachmentSha256: attachmentSha256,
        title: title,
      );
}
