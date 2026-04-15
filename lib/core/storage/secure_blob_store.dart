import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class SecureBlobStore {
  SecureBlobStore._(this._storage, this._scopeKey);

  factory SecureBlobStore({
    FlutterSecureStorage? storage,
    String? scopeKey,
  }) {
    final normalizedScopeKey = _normalizeScopeKey(scopeKey);
    if (storage == null && normalizedScopeKey == null) return _defaultInstance;
    return SecureBlobStore._(
      storage ?? _createDefaultSecureStorage(),
      normalizedScopeKey,
    );
  }

  static const kBlobKey = 'sync_config_blob_json_v1';

  static final SecureBlobStore _defaultInstance =
      SecureBlobStore._(_createDefaultSecureStorage(), null);

  final FlutterSecureStorage _storage;
  final String? _scopeKey;

  Future<void> _tail = Future<void>.value();
  bool _loaded = false;
  Map<String, String> _cache = <String, String>{};

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}).catchError((_) {});
    return next;
  }

  Future<Map<String, String>> readAll() async {
    return _serial(() async {
      await _ensureLoaded();
      return Map<String, String>.from(_cache);
    });
  }

  bool get isLoaded => _loaded;

  Future<String?> readValue(String key) async {
    return _serial(() async {
      await _ensureLoaded();
      return _cache[key];
    });
  }

  Future<String?> readKey(String key) async {
    return _serial(() async {
      return _safeRead(key);
    });
  }

  Future<void> update(Map<String, String?> updates) async {
    return _serial(() async {
      await _ensureLoaded();

      var changed = false;
      for (final entry in updates.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value == null || value.isEmpty) {
          changed = _cache.remove(key) != null || changed;
          continue;
        }
        if (_cache[key] != value) {
          _cache[key] = value;
          changed = true;
        }
      }

      if (!changed) return;
      await _persistCache();
    });
  }

  Future<void> clear() async {
    return _serial(() async {
      await _safeDelete(_scopedKey(kBlobKey));
      _cache = <String, String>{};
      _loaded = true;
    });
  }

  Future<void> deleteKey(String key) async {
    return _serial(() async {
      final scopedKey = _scopedKey(key);
      await _safeDelete(scopedKey);
      if (scopedKey == _scopedKey(kBlobKey)) {
        _cache = <String, String>{};
        _loaded = true;
      }
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final raw = await _safeRead(_scopedKey(kBlobKey));
    if (raw == null || raw.trim().isEmpty) {
      _cache = <String, String>{};
      _loaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _cache = <String, String>{};
        _loaded = true;
        return;
      }

      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is String) {
          result[key] = value;
          continue;
        }
        if (value == null) continue;
        result[key] = value.toString();
      }
      _cache = result;
    } catch (_) {
      _cache = <String, String>{};
    }

    _loaded = true;
  }

  Future<void> _persistCache() async {
    if (_cache.isEmpty) {
      await _safeDelete(_scopedKey(kBlobKey));
      return;
    }
    await _safeWrite(_scopedKey(kBlobKey), jsonEncode(_cache));
  }

  String _scopedKey(String key) {
    final scopeKey = _scopeKey;
    if (scopeKey == null) return key;
    return '$key::$scopeKey';
  }

  static String? _normalizeScopeKey(String? scopeKey) {
    final normalized = scopeKey?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static FlutterSecureStorage _createDefaultSecureStorage() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(),
      );
    }
    return const FlutterSecureStorage();
  }

  Future<String?> _safeRead(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null || defaultTargetPlatform != TargetPlatform.macOS) return v;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return null;

    try {
      final legacy = await _storage.read(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
      if (legacy == null) return null;

      try {
        await _storage.write(key: key, value: legacy);
        await _storage.delete(
          key: key,
          mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
        );
      } catch (_) {
        // Best-effort migration.
      }

      return legacy;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _storage.delete(
          key: key,
          mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
        );
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _storage.write(
        key: key,
        value: value,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      // Fall through and try legacy storage below.
    }

    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _storage.delete(
        key: key,
        mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
      );
    } catch (_) {
      return;
    }
  }
}
