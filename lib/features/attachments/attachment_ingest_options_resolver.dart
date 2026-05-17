import 'dart:typed_data';

import '../../core/ai/ai_routing.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import 'attachment_ingest_pipeline.dart';
import '../media_backup/audio_transcode_policy.dart';

Future<FileAttachmentIngestOptions> resolveFileAttachmentIngestOptions({
  required Uint8List sessionKey,
  required String mimeType,
  required SubscriptionStatus subscriptionStatus,
  ContentEnrichmentConfigStore contentConfigStore =
      const DartContentEnrichmentConfigStore(),
}) async {
  final useLocalAudioTranscode = shouldUseLocalAudioTranscode(
    subscriptionStatus: subscriptionStatus,
  );

  var videoProxyEnabled = true;
  var videoProxyMaxDurationMs = kAttachmentVideoProxyMaxDurationMs;
  var videoProxyMaxBytes = kAttachmentVideoProxyMaxBytes;

  if (mimeType.trim().toLowerCase().startsWith('video/')) {
    try {
      final contentConfig = await contentConfigStore.readContentEnrichment(
        sessionKey,
      );
      videoProxyEnabled = contentConfig.videoProxyEnabled;
      videoProxyMaxDurationMs = sanitizeAttachmentIngestLimit(
        contentConfig.videoProxyMaxDurationMs.toInt(),
        kAttachmentVideoProxyMaxDurationMs,
      );
      videoProxyMaxBytes = sanitizeAttachmentIngestLimit(
        contentConfig.videoProxyMaxBytes.toInt(),
        kAttachmentVideoProxyMaxBytes,
      );
    } catch (_) {
      videoProxyEnabled = true;
      videoProxyMaxDurationMs = kAttachmentVideoProxyMaxDurationMs;
      videoProxyMaxBytes = kAttachmentVideoProxyMaxBytes;
    }
  }

  return FileAttachmentIngestOptions(
    useLocalAudioTranscode: useLocalAudioTranscode,
    videoProxyEnabled: videoProxyEnabled,
    videoProxyMaxDurationMs: videoProxyMaxDurationMs,
    videoProxyMaxBytes: videoProxyMaxBytes,
  );
}
