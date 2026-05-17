import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/models/app_models.dart';

import '../ai/required_ai_capability_policy.dart';

abstract class ContentEnrichmentConfigStore {
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key);
  Future<void> writeContentEnrichment(
      Uint8List key, ContentEnrichmentConfig config);

  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key);
  Future<void> writeStoragePolicy(Uint8List key, StoragePolicyConfig config);
}

final class DartContentEnrichmentConfigStore
    implements ContentEnrichmentConfigStore {
  const DartContentEnrichmentConfigStore();

  static final Map<String, String> _memoryStore = <String, String>{};

  @override
  Future<ContentEnrichmentConfig> readContentEnrichment(Uint8List key) async {
    final encoded = await _read(_preferenceKey(key, 'content'));
    if (encoded == null) {
      return RequiredAiCapabilityPolicy.requireContentEnrichmentConfig(
        _defaultContentEnrichmentConfig,
      );
    }
    return RequiredAiCapabilityPolicy.requireContentEnrichmentConfig(
      _contentConfigFromJson(_decodeMap(encoded)),
    );
  }

  @override
  Future<void> writeContentEnrichment(
    Uint8List key,
    ContentEnrichmentConfig config,
  ) async {
    await _write(
      _preferenceKey(key, 'content'),
      jsonEncode(
        _contentConfigToJson(
          RequiredAiCapabilityPolicy.requireContentEnrichmentConfig(config),
        ),
      ),
    );
  }

  @override
  Future<StoragePolicyConfig> readStoragePolicy(Uint8List key) async {
    final encoded = await _read(_preferenceKey(key, 'storage'));
    if (encoded == null) return _defaultStoragePolicyConfig;
    return _storagePolicyFromJson(_decodeMap(encoded));
  }

  @override
  Future<void> writeStoragePolicy(
    Uint8List key,
    StoragePolicyConfig config,
  ) async {
    await _write(
      _preferenceKey(key, 'storage'),
      jsonEncode(_storagePolicyToJson(config)),
    );
  }

  static String _preferenceKey(Uint8List key, String kind) {
    final session = base64Url.encode(key.take(12).toList());
    return 'secondloop.$kind.config.$session';
  }

  static Map<String, Object?> _decodeMap(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value as Object?));
    }
    return const <String, Object?>{};
  }

  static Future<String?> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return _memoryStore[key];
    }
  }

  static Future<void> _write(String key, String value) async {
    _memoryStore[key] = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}

const _defaultContentEnrichmentConfig = ContentEnrichmentConfig(
  urlFetchEnabled: true,
  documentExtractEnabled: true,
  documentKeepOriginalMaxBytes: 104857600,
  audioTranscribeEnabled: true,
  audioTranscribeEngine: 'whisper',
  videoExtractEnabled: true,
  videoProxyEnabled: true,
  videoProxyMaxDurationMs: 600000,
  videoProxyMaxBytes: 209715200,
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

const _defaultStoragePolicyConfig = StoragePolicyConfig(
  autoPurgeEnabled: false,
  autoPurgeKeepRecentDays: 30,
  autoPurgeMaxCacheBytes: 0,
  autoPurgeMinCandidateBytes: 0,
  autoPurgeIncludeImages: true,
);

ContentEnrichmentConfig _contentConfigFromJson(Map<String, Object?> json) {
  return ContentEnrichmentConfig(
    urlFetchEnabled: json['url_fetch_enabled'] == true,
    documentExtractEnabled: json['document_extract_enabled'] == true,
    documentKeepOriginalMaxBytes:
        (json['document_keep_original_max_bytes'] as num?)?.toInt() ??
            _defaultContentEnrichmentConfig.documentKeepOriginalMaxBytes,
    audioTranscribeEnabled: json['audio_transcribe_enabled'] == true,
    audioTranscribeEngine: (json['audio_transcribe_engine'] as String?) ??
        _defaultContentEnrichmentConfig.audioTranscribeEngine,
    videoExtractEnabled: json['video_extract_enabled'] == true,
    videoProxyEnabled: json['video_proxy_enabled'] == true,
    videoProxyMaxDurationMs:
        (json['video_proxy_max_duration_ms'] as num?)?.toInt() ??
            _defaultContentEnrichmentConfig.videoProxyMaxDurationMs,
    videoProxyMaxBytes: (json['video_proxy_max_bytes'] as num?)?.toInt() ??
        _defaultContentEnrichmentConfig.videoProxyMaxBytes,
    ocrEnabled: json['ocr_enabled'] == true,
    ocrEngineMode: (json['ocr_engine_mode'] as String?) ??
        _defaultContentEnrichmentConfig.ocrEngineMode,
    ocrLanguageHints: (json['ocr_language_hints'] as String?) ??
        _defaultContentEnrichmentConfig.ocrLanguageHints,
    ocrPdfDpi: (json['ocr_pdf_dpi'] as num?)?.toInt() ??
        _defaultContentEnrichmentConfig.ocrPdfDpi,
    ocrPdfAutoMaxPages: (json['ocr_pdf_auto_max_pages'] as num?)?.toInt() ??
        _defaultContentEnrichmentConfig.ocrPdfAutoMaxPages,
    ocrPdfMaxPages: (json['ocr_pdf_max_pages'] as num?)?.toInt() ??
        _defaultContentEnrichmentConfig.ocrPdfMaxPages,
    mobileBackgroundEnabled: json['mobile_background_enabled'] == true,
    mobileBackgroundRequiresWifi:
        json['mobile_background_requires_wifi'] == true,
    mobileBackgroundRequiresCharging:
        json['mobile_background_requires_charging'] == true,
  );
}

Map<String, Object?> _contentConfigToJson(ContentEnrichmentConfig config) {
  return <String, Object?>{
    'url_fetch_enabled': config.urlFetchEnabled,
    'document_extract_enabled': config.documentExtractEnabled,
    'document_keep_original_max_bytes': config.documentKeepOriginalMaxBytes,
    'audio_transcribe_enabled': config.audioTranscribeEnabled,
    'audio_transcribe_engine': config.audioTranscribeEngine,
    'video_extract_enabled': config.videoExtractEnabled,
    'video_proxy_enabled': config.videoProxyEnabled,
    'video_proxy_max_duration_ms': config.videoProxyMaxDurationMs,
    'video_proxy_max_bytes': config.videoProxyMaxBytes,
    'ocr_enabled': config.ocrEnabled,
    'ocr_engine_mode': config.ocrEngineMode,
    'ocr_language_hints': config.ocrLanguageHints,
    'ocr_pdf_dpi': config.ocrPdfDpi,
    'ocr_pdf_auto_max_pages': config.ocrPdfAutoMaxPages,
    'ocr_pdf_max_pages': config.ocrPdfMaxPages,
    'mobile_background_enabled': config.mobileBackgroundEnabled,
    'mobile_background_requires_wifi': config.mobileBackgroundRequiresWifi,
    'mobile_background_requires_charging':
        config.mobileBackgroundRequiresCharging,
  };
}

StoragePolicyConfig _storagePolicyFromJson(Map<String, Object?> json) {
  return StoragePolicyConfig(
    autoPurgeEnabled: json['auto_purge_enabled'] == true,
    autoPurgeKeepRecentDays:
        (json['auto_purge_keep_recent_days'] as num?)?.toInt() ??
            _defaultStoragePolicyConfig.autoPurgeKeepRecentDays,
    autoPurgeMaxCacheBytes:
        (json['auto_purge_max_cache_bytes'] as num?)?.toInt() ??
            _defaultStoragePolicyConfig.autoPurgeMaxCacheBytes,
    autoPurgeMinCandidateBytes:
        (json['auto_purge_min_candidate_bytes'] as num?)?.toInt() ??
            _defaultStoragePolicyConfig.autoPurgeMinCandidateBytes,
    autoPurgeIncludeImages: json['auto_purge_include_images'] != false,
  );
}

Map<String, Object?> _storagePolicyToJson(StoragePolicyConfig config) {
  return <String, Object?>{
    'auto_purge_enabled': config.autoPurgeEnabled,
    'auto_purge_keep_recent_days': config.autoPurgeKeepRecentDays,
    'auto_purge_max_cache_bytes': config.autoPurgeMaxCacheBytes,
    'auto_purge_min_candidate_bytes': config.autoPurgeMinCandidateBytes,
    'auto_purge_include_images': config.autoPurgeIncludeImages,
  };
}
