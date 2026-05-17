import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/content_enrichment/content_enrichment_config_store.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  group('DartContentEnrichmentConfigStore', () {
    late DartContentEnrichmentConfigStore store;
    late Uint8List key;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = const DartContentEnrichmentConfigStore();
      key = Uint8List.fromList(List<int>.filled(32, 3));
    });

    test('persists content enrichment config in Dart storage', () async {
      const config = ContentEnrichmentConfig(
        urlFetchEnabled: false,
        documentExtractEnabled: false,
        documentKeepOriginalMaxBytes: 123,
        audioTranscribeEnabled: false,
        audioTranscribeEngine: 'none',
        videoExtractEnabled: false,
        videoProxyEnabled: false,
        videoProxyMaxDurationMs: 456,
        videoProxyMaxBytes: 789,
        ocrEnabled: false,
        ocrEngineMode: 'off',
        ocrLanguageHints: 'en',
        ocrPdfDpi: 144,
        ocrPdfAutoMaxPages: 2,
        ocrPdfMaxPages: 4,
        mobileBackgroundEnabled: false,
        mobileBackgroundRequiresWifi: false,
        mobileBackgroundRequiresCharging: true,
      );

      await store.writeContentEnrichment(key, config);
      final restored = await store.readContentEnrichment(key);

      expect(restored.documentKeepOriginalMaxBytes, 123);
      expect(restored.videoProxyEnabled, isFalse);
      expect(restored.videoProxyMaxDurationMs, 456);
      expect(restored.ocrLanguageHints, 'en');
      expect(restored.mobileBackgroundRequiresCharging, isTrue);
    });

    test('persists storage policy config in Dart storage', () async {
      const config = StoragePolicyConfig(
        autoPurgeEnabled: true,
        autoPurgeKeepRecentDays: 7,
        autoPurgeMaxCacheBytes: 1000,
        autoPurgeMinCandidateBytes: 200,
        autoPurgeIncludeImages: false,
      );

      await store.writeStoragePolicy(key, config);
      final restored = await store.readStoragePolicy(key);

      expect(restored.autoPurgeEnabled, isTrue);
      expect(restored.autoPurgeKeepRecentDays, 7);
      expect(restored.autoPurgeMaxCacheBytes, 1000);
      expect(restored.autoPurgeMinCandidateBytes, 200);
      expect(restored.autoPurgeIncludeImages, isFalse);
    });
  });
}
