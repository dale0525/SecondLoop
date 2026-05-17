import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/models/app_models.dart';

import '../ai/required_ai_capability_policy.dart';

abstract class MediaAnnotationConfigStore {
  Future<MediaAnnotationConfig> read(Uint8List key);
  Future<void> write(Uint8List key, MediaAnnotationConfig config);
}

final class DartMediaAnnotationConfigStore
    implements MediaAnnotationConfigStore {
  const DartMediaAnnotationConfigStore();

  static final Map<String, String> _memoryStore = <String, String>{};

  @override
  Future<MediaAnnotationConfig> read(Uint8List key) async {
    final encoded = await _read(_preferenceKey(key));
    final config = encoded == null
        ? _defaultMediaAnnotationConfig
        : _fromJson(_decodeMap(encoded));
    return RequiredAiCapabilityPolicy.requireMediaAnnotationConfig(config);
  }

  @override
  Future<void> write(Uint8List key, MediaAnnotationConfig config) async {
    await _write(
      _preferenceKey(key),
      jsonEncode(
        _toJson(
            RequiredAiCapabilityPolicy.requireMediaAnnotationConfig(config)),
      ),
    );
  }

  static String _preferenceKey(Uint8List key) {
    final session = base64Url.encode(key.take(12).toList());
    return 'secondloop.media_annotation.config.$session';
  }

  static Map<String, Object?> _decodeMap(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value as Object?));
    }
    return const <String, Object?>{};
  }

  static MediaAnnotationConfig _fromJson(Map<String, Object?> json) {
    return MediaAnnotationConfig(
      annotateEnabled: json['annotate_enabled'] == true,
      searchEnabled: json['search_enabled'] == true,
      allowCellular: json['allow_cellular'] == true,
      providerMode: (json['provider_mode'] as String?) ??
          _defaultMediaAnnotationConfig.providerMode,
      byokProfileId: json['byok_profile_id'] as String?,
      cloudModelName: json['cloud_model_name'] as String?,
    );
  }

  static Map<String, Object?> _toJson(MediaAnnotationConfig config) {
    return <String, Object?>{
      'annotate_enabled': config.annotateEnabled,
      'search_enabled': config.searchEnabled,
      'allow_cellular': config.allowCellular,
      'provider_mode': config.providerMode,
      'byok_profile_id': config.byokProfileId,
      'cloud_model_name': config.cloudModelName,
    };
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

const _defaultMediaAnnotationConfig = MediaAnnotationConfig(
  annotateEnabled: true,
  searchEnabled: true,
  allowCellular: false,
  providerMode: 'follow_ask_ai',
);
