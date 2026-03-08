import 'dart:typed_data';

import '../../core/backend/native_backend.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../src/rust/db.dart';
import '../audio_transcribe/audio_transcribe_enqueue.dart';
import 'attachment_draft_send_contract.dart';

Future<void> maybeEnqueueAttachmentPlaceEnrichment({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String attachmentSha256,
  required String lang,
  int? nowMs,
}) async {
  await backend.enqueueAttachmentPlace(
    sessionKey,
    attachmentSha256: attachmentSha256,
    lang: lang,
    nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

Future<void> maybeEnqueueAttachmentAnnotationEnrichment({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String attachmentSha256,
  required String lang,
  MediaAnnotationConfigStore mediaAnnotationConfigStore =
      const RustMediaAnnotationConfigStore(),
  Future<void> Function()? beforeEnqueue,
  int? nowMs,
}) async {
  MediaAnnotationConfig? config;
  try {
    config = await mediaAnnotationConfigStore.read(sessionKey);
  } catch (_) {
    config = null;
  }
  if (config == null || !config.annotateEnabled) return;

  if (beforeEnqueue != null) {
    try {
      await beforeEnqueue();
    } catch (_) {}
  }

  await backend.enqueueAttachmentAnnotation(
    sessionKey,
    attachmentSha256: attachmentSha256,
    lang: lang,
    nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

Future<void> runDraftAttachmentPostLinkEnrichment({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String attachmentSha256,
  required AttachmentDraftPayload draft,
  required String lang,
  MediaAnnotationConfigStore mediaAnnotationConfigStore =
      const RustMediaAnnotationConfigStore(),
  Future<void> Function()? beforeEnqueueImageAnnotation,
  Future<void> Function()? beforeEnqueueAudioTranscribe,
}) async {
  await runAttachmentPostLinkEnrichmentForMimeType(
    backend: backend,
    sessionKey: sessionKey,
    attachmentSha256: attachmentSha256,
    mimeType: draft.normalizedMimeType,
    lang: lang,
    mediaAnnotationConfigStore: mediaAnnotationConfigStore,
    beforeEnqueueImageAnnotation: beforeEnqueueImageAnnotation,
    beforeEnqueueAudioTranscribe: beforeEnqueueAudioTranscribe,
  );
}

Future<void> runAttachmentPostLinkEnrichmentForMimeType({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String attachmentSha256,
  required String mimeType,
  required String lang,
  MediaAnnotationConfigStore mediaAnnotationConfigStore =
      const RustMediaAnnotationConfigStore(),
  Future<void> Function()? beforeEnqueueImageAnnotation,
  Future<void> Function()? beforeEnqueueAudioTranscribe,
}) async {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  if (normalizedMimeType.isEmpty) return;

  if (normalizedMimeType.startsWith('image/')) {
    try {
      await maybeEnqueueAttachmentAnnotationEnrichment(
        backend: backend,
        sessionKey: sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        mediaAnnotationConfigStore: mediaAnnotationConfigStore,
        beforeEnqueue: beforeEnqueueImageAnnotation,
      );
    } catch (_) {}

    try {
      final exif = await backend.readAttachmentExifMetadata(
        sessionKey,
        sha256: attachmentSha256,
      );
      final lat = exif?.latitude;
      final lon = exif?.longitude;
      final hasValidLocation = lat != null &&
          lon != null &&
          !(lat == 0.0 && lon == 0.0) &&
          !lat.isNaN &&
          !lon.isNaN;
      if (!hasValidLocation) return;

      await maybeEnqueueAttachmentPlaceEnrichment(
        backend: backend,
        sessionKey: sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
      );
    } catch (_) {}
    return;
  }

  if (isAudioTranscribeCandidateMimeType(normalizedMimeType)) {
    try {
      await maybeEnqueueAudioTranscribe(
        backend: backend,
        sessionKey: sessionKey,
        attachmentSha256: attachmentSha256,
        mimeType: normalizedMimeType,
        lang: 'und',
        beforeEnqueue: beforeEnqueueAudioTranscribe,
      );
    } catch (_) {}
  }
}
