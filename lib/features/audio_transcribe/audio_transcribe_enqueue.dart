import 'dart:typed_data';

import '../../core/backend/native_backend.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';

bool isAudioTranscribeCandidateMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('audio/') || normalized.startsWith('video/');
}

Future<void> maybeEnqueueAudioTranscribe({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String attachmentSha256,
  required String mimeType,
  String lang = 'und',
  bool respectFeatureToggle = true,
  int? nowMs,
  Future<void> Function()? beforeEnqueue,
}) async {
  final normalizedSha = attachmentSha256.trim();
  if (normalizedSha.isEmpty) return;
  if (!isAudioTranscribeCandidateMimeType(mimeType)) return;

  if (respectFeatureToggle) {
    Object? contentConfig;
    try {
      contentConfig =
          await const DartContentEnrichmentConfigStore().readContentEnrichment(
        sessionKey,
      );
    } catch (_) {
      contentConfig = null;
    }
    final dynamic dynamicConfig = contentConfig;
    final enabled = dynamicConfig?.audioTranscribeEnabled == true;
    if (!enabled) {
      return;
    }
  }

  if (beforeEnqueue != null) {
    try {
      await beforeEnqueue();
    } catch (_) {}
  }

  await backend.enqueueAttachmentAnnotation(
    sessionKey,
    attachmentSha256: normalizedSha,
    lang: lang.trim().isEmpty ? 'und' : lang.trim(),
    nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}
