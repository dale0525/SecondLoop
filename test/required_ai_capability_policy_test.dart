import 'package:secondloop/core/models/platform_int.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/embeddings_data_consent_prefs.dart';
import 'package:secondloop/core/ai/embeddings_source_prefs.dart';
import 'package:secondloop/core/ai/media_source_prefs.dart';
import 'package:secondloop/core/ai/required_ai_capability_policy.dart';
import 'package:secondloop/core/ai/semantic_parse_data_consent_prefs.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  test('legacy AI opt-out preferences are ignored for required capabilities',
      () async {
    SharedPreferences.setMockInitialValues({
      SemanticParseDataConsentPrefs.prefsKey: false,
      EmbeddingsDataConsentPrefs.prefsKey: false,
    });

    final prefs = await SharedPreferences.getInstance();

    expect(SemanticParseDataConsentPrefs.readEffectiveEnabled(prefs), isTrue);
    expect(EmbeddingsDataConsentPrefs.readEffectiveEnabled(prefs), isTrue);

    await SemanticParseDataConsentPrefs.setEnabled(prefs, false);
    await EmbeddingsDataConsentPrefs.setEnabled(prefs, false);

    expect(prefs.getBool(SemanticParseDataConsentPrefs.prefsKey), isTrue);
    expect(prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey), isTrue);
  });

  test('legacy local source preferences collapse to runtime auto selection',
      () {
    expect(
      RequiredAiCapabilityPolicy.normalizeEmbeddingsSourcePreference(
        EmbeddingsSourcePreference.local,
      ),
      EmbeddingsSourcePreference.auto,
    );
    expect(
      RequiredAiCapabilityPolicy.normalizeMediaSourcePreference(
        MediaSourcePreference.local,
      ),
      MediaSourcePreference.auto,
    );
  });

  test('legacy media opt-out configs are normalized to required enabled', () {
    final mediaConfig = RequiredAiCapabilityPolicy.requireMediaAnnotationConfig(
      const MediaAnnotationConfig(
        annotateEnabled: false,
        searchEnabled: false,
        allowCellular: false,
        providerMode: 'follow_ask_ai',
      ),
    );

    expect(mediaConfig.annotateEnabled, isTrue);
    expect(mediaConfig.searchEnabled, isTrue);
    expect(mediaConfig.allowCellular, isFalse);

    final contentConfig =
        RequiredAiCapabilityPolicy.requireContentEnrichmentConfig(
      ContentEnrichmentConfig(
        urlFetchEnabled: false,
        documentExtractEnabled: false,
        documentKeepOriginalMaxBytes: PlatformInt64Util.from(0),
        audioTranscribeEnabled: false,
        audioTranscribeEngine: 'whisper',
        videoExtractEnabled: false,
        videoProxyEnabled: true,
        videoProxyMaxDurationMs: PlatformInt64Util.from(0),
        videoProxyMaxBytes: PlatformInt64Util.from(0),
        ocrEnabled: false,
        ocrEngineMode: 'multimodal_llm',
        ocrLanguageHints: 'device_plus_en',
        ocrPdfDpi: PlatformInt64Util.from(180),
        ocrPdfAutoMaxPages: PlatformInt64Util.from(0),
        ocrPdfMaxPages: PlatformInt64Util.from(0),
        mobileBackgroundEnabled: true,
        mobileBackgroundRequiresWifi: true,
        mobileBackgroundRequiresCharging: true,
      ),
    );

    expect(contentConfig.urlFetchEnabled, isTrue);
    expect(contentConfig.documentExtractEnabled, isTrue);
    expect(contentConfig.audioTranscribeEnabled, isTrue);
    expect(contentConfig.ocrEnabled, isTrue);
    expect(contentConfig.videoExtractEnabled, isFalse);
  });

  test('runtime capabilities include required AI surfaces', () {
    const capabilities = CloudRuntimeRequiredCapabilities.all;

    expect(capabilities, contains(const CloudRuntimeCapability('chat')));
    expect(capabilities, contains(const CloudRuntimeCapability('working_set')));
    expect(capabilities, contains(const CloudRuntimeCapability('llm')));
    expect(capabilities, contains(const CloudRuntimeCapability('embedding')));
    expect(
        capabilities, contains(const CloudRuntimeCapability('semantic_parse')));
    expect(
      capabilities,
      contains(const CloudRuntimeCapability('media_understanding')),
    );
    expect(
      capabilities,
      contains(const CloudRuntimeCapability('multimodal_llm')),
    );
  });
}
