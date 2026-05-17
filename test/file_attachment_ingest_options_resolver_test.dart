import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/features/attachments/attachment_ingest_options_resolver.dart';
import 'package:secondloop/features/attachments/attachment_ingest_pipeline.dart';
import 'package:secondloop/features/media_backup/audio_transcode_policy.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  group('resolveFileAttachmentIngestOptions', () {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

    test('uses content config for video attachments', () async {
      final oldPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final store = _FakeContentEnrichmentConfigStore(
          _contentConfig(
            videoProxyEnabled: false,
            videoProxyMaxDurationMs: 321000,
            videoProxyMaxBytes: 654000,
          ),
        );

        final options = await resolveFileAttachmentIngestOptions(
          sessionKey: sessionKey,
          mimeType: 'video/mp4',
          subscriptionStatus: SubscriptionStatus.entitled,
          contentConfigStore: store,
        );

        expect(store.readCalls, 1);
        expect(
          options.useLocalAudioTranscode,
          shouldUseLocalAudioTranscode(
            subscriptionStatus: SubscriptionStatus.entitled,
          ),
        );
        expect(options.videoProxyEnabled, isFalse);
        expect(options.videoProxyMaxDurationMs, 321000);
        expect(options.videoProxyMaxBytes, 654000);
      } finally {
        debugDefaultTargetPlatformOverride = oldPlatform;
      }
    });

    test('does not read content config for non-video attachments', () async {
      final store = _FakeContentEnrichmentConfigStore(_contentConfig());

      final options = await resolveFileAttachmentIngestOptions(
        sessionKey: sessionKey,
        mimeType: 'application/pdf',
        subscriptionStatus: SubscriptionStatus.unknown,
        contentConfigStore: store,
      );

      expect(store.readCalls, 0);
      expect(options.videoProxyEnabled, isTrue);
      expect(
        options.videoProxyMaxDurationMs,
        kAttachmentVideoProxyMaxDurationMs,
      );
      expect(options.videoProxyMaxBytes, kAttachmentVideoProxyMaxBytes);
    });

    test('falls back to defaults when config read fails', () async {
      final store = _FakeContentEnrichmentConfigStore(
        _contentConfig(),
        throwOnRead: true,
      );

      final options = await resolveFileAttachmentIngestOptions(
        sessionKey: sessionKey,
        mimeType: 'video/quicktime',
        subscriptionStatus: SubscriptionStatus.unknown,
        contentConfigStore: store,
      );

      expect(store.readCalls, 1);
      expect(options.videoProxyEnabled, isTrue);
      expect(
        options.videoProxyMaxDurationMs,
        kAttachmentVideoProxyMaxDurationMs,
      );
      expect(options.videoProxyMaxBytes, kAttachmentVideoProxyMaxBytes);
    });
  });
}

final class _FakeContentEnrichmentConfigStore
    implements ContentEnrichmentConfigStore {
  _FakeContentEnrichmentConfigStore(this._config, {this.throwOnRead = false});

  ContentEnrichmentConfig _config;
  final bool throwOnRead;
  int readCalls = 0;

  @override
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key) async {
    readCalls += 1;
    if (throwOnRead) {
      throw StateError('read_failed');
    }
    return _config;
  }

  @override
  Future<void> writeContentEnrichment(
    Uint8List key,
    ContentEnrichmentConfig config,
  ) async {
    _config = config;
  }

  @override
  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key) async {
    return const StoragePolicyConfig(
      autoPurgeEnabled: false,
      autoPurgeKeepRecentDays: 30,
      autoPurgeMaxCacheBytes: 0,
      autoPurgeMinCandidateBytes: 0,
      autoPurgeIncludeImages: true,
    );
  }

  @override
  Future<void> writeStoragePolicy(
    Uint8List key,
    StoragePolicyConfig config,
  ) async {}
}

ContentEnrichmentConfig _contentConfig({
  bool videoProxyEnabled = true,
  int videoProxyMaxDurationMs = 600000,
  int videoProxyMaxBytes = 209715200,
}) {
  return ContentEnrichmentConfig(
    urlFetchEnabled: true,
    documentExtractEnabled: true,
    documentKeepOriginalMaxBytes: 104857600,
    audioTranscribeEnabled: true,
    audioTranscribeEngine: 'whisper',
    videoExtractEnabled: true,
    videoProxyEnabled: videoProxyEnabled,
    videoProxyMaxDurationMs: videoProxyMaxDurationMs,
    videoProxyMaxBytes: videoProxyMaxBytes,
    ocrEnabled: true,
    ocrEngineMode: 'auto',
    ocrLanguageHints: '',
    ocrPdfDpi: 200,
    ocrPdfAutoMaxPages: 20,
    ocrPdfMaxPages: 100,
    mobileBackgroundEnabled: true,
    mobileBackgroundRequiresWifi: true,
    mobileBackgroundRequiresCharging: false,
  );
}
