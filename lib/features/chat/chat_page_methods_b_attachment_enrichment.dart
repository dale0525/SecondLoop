part of 'chat_page.dart';

extension _ChatPageStateMethodsBAttachmentEnrichment on _ChatPageState {
  Future<void> _maybeEnqueueAttachmentPlaceEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    try {
      await backend.enqueueAttachmentPlace(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _maybeEnqueueAttachmentAnnotationEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    final cloudAuthController = CloudAuthScope.maybeOf(context)?.controller;

    MediaAnnotationConfig? config;
    try {
      config = await const RustMediaAnnotationConfigStore().read(sessionKey);
    } catch (_) {
      config = null;
    }
    if (config == null || !config.annotateEnabled) return;

    try {
      await bestEffortWarmCloudCapabilityAuth(cloudAuthController);
      await backend.enqueueAttachmentAnnotation(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) {
        _setState(() {});
      }
    } catch (_) {
      return;
    }
  }

  Future<_AttachmentEnrichment> _loadAttachmentEnrichment(
    AttachmentsBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    final placeFuture = backend
        .readAttachmentPlaceDisplayName(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    final captionFuture = backend
        .readAttachmentAnnotationCaptionLong(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    return _AttachmentEnrichment(
      placeDisplayName: await placeFuture,
      captionLong: await captionFuture,
    );
  }
}
