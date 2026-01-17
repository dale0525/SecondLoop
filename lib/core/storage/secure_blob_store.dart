import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class SecureBlobStore {
  SecureBlobStore._(this._storage);

  factory SecureBlobStore({FlutterSecureStorage? storage}) {
    if (storage == null) return _defaultInstance;
    return SecureBlobStore._(storage);
  }

  static const kBlobKey = 'sync_config_blob_json_v1';

  static final SecureBlobStore _defaultInstance =
      SecureBlobStore._(_createDefaultSecureStorage());

  final FlutterSecureStorage _storage;

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
      await _safeDelete(kBlobKey);
      _cache = <String, String>{};
      _loaded = true;
    });
  }

  Future<void> deleteKey(String key) async {
    return _serial(() async {
      await _safeDelete(key);
      if (key == kBlobKey) {
        _cache = <String, String>{};
        _loaded = true;
      }
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final raw = await _safeRead(kBlobKey);
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
      await _safeDelete(kBlobKey);
      return;
    }
    await _safeWrite(kBlobKey, jsonEncode(_cache));
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
