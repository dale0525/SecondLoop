import 'embeddings_source_prefs.dart';
import 'media_source_prefs.dart';
import '../../src/rust/db.dart';

final class RequiredAiCapabilityPolicy {
  const RequiredAiCapabilityPolicy._();

  static bool get enabled => true;

  static EmbeddingsSourcePreference normalizeEmbeddingsSourcePreference(
    EmbeddingsSourcePreference preference,
  ) {
    return switch (preference) {
      EmbeddingsSourcePreference.local => EmbeddingsSourcePreference.auto,
      _ => preference,
    };
  }

  static MediaSourcePreference normalizeMediaSourcePreference(
    MediaSourcePreference preference,
  ) {
    return switch (preference) {
      MediaSourcePreference.local => MediaSourcePreference.auto,
      _ => preference,
    };
  }

  static MediaAnnotationConfig requireMediaAnnotationConfig(
    MediaAnnotationConfig config,
  ) {
    if (config.annotateEnabled && config.searchEnabled) return config;
    return MediaAnnotationConfig(
      annotateEnabled: true,
      searchEnabled: true,
      allowCellular: config.allowCellular,
      providerMode: config.providerMode,
      byokProfileId: config.byokProfileId,
      cloudModelName: config.cloudModelName,
    );
  }

  static ContentEnrichmentConfig requireContentEnrichmentConfig(
    ContentEnrichmentConfig config,
  ) {
    if (config.urlFetchEnabled &&
        config.documentExtractEnabled &&
        config.audioTranscribeEnabled &&
        config.ocrEnabled) {
      return config;
    }

    return ContentEnrichmentConfig(
      urlFetchEnabled: true,
      documentExtractEnabled: true,
      documentKeepOriginalMaxBytes: config.documentKeepOriginalMaxBytes,
      audioTranscribeEnabled: true,
      audioTranscribeEngine: config.audioTranscribeEngine,
      videoExtractEnabled: config.videoExtractEnabled,
      videoProxyEnabled: config.videoProxyEnabled,
      videoProxyMaxDurationMs: config.videoProxyMaxDurationMs,
      videoProxyMaxBytes: config.videoProxyMaxBytes,
      ocrEnabled: true,
      ocrEngineMode: config.ocrEngineMode,
      ocrLanguageHints: config.ocrLanguageHints,
      ocrPdfDpi: config.ocrPdfDpi,
      ocrPdfAutoMaxPages: config.ocrPdfAutoMaxPages,
      ocrPdfMaxPages: config.ocrPdfMaxPages,
      mobileBackgroundEnabled: config.mobileBackgroundEnabled,
      mobileBackgroundRequiresWifi: config.mobileBackgroundRequiresWifi,
      mobileBackgroundRequiresCharging: config.mobileBackgroundRequiresCharging,
    );
  }
}
