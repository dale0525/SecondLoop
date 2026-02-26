import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

final class SyncSecretStore {
  SyncSecretStore();

  static const _kPrefsBlobKey = 'sync_secret_json_v1';

  static const kPrefsBlobKeyForTest = _kPrefsBlobKey;
  static const kWebdavPasswordB64 = 'sync_webdav_password_b64';
  static const kSyncKeyB64 = 'sync_webdav_sync_key_b64';

  Future<void> _tail = Future<void>.value();
  Future<SharedPreferences>? _prefsFuture;

  bool _loaded = false;
  String? _lastRaw;
  Map<String, String> _cache = <String, String>{};

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}).catchError((_) {});
    return next;
  }

  Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  Future<String?> readWebdavPassword() async {
    return _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      final encoded = _cache[kWebdavPasswordB64];
      if (encoded == null || encoded.isEmpty) return null;
      try {
        final decoded = utf8.decode(base64Decode(encoded));
        return decoded.isEmpty ? null : decoded;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> writeWebdavPassword(String? password) async {
    await _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();

      if (password == null || password.isEmpty) {
        if (_cache.remove(kWebdavPasswordB64) != null) {
          await _persistCache();
        }
        return;
      }

      final encoded = base64Encode(utf8.encode(password));
      if (_cache[kWebdavPasswordB64] == encoded) return;
      _cache[kWebdavPasswordB64] = encoded;
      await _persistCache();
    });
  }

  Future<Uint8List?> readSyncKey() async {
    return _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      final b64 = _cache[kSyncKeyB64];
      if (b64 == null || b64.isEmpty) return null;
      try {
        final bytes = base64Decode(b64);
        if (bytes.length != 32) return null;
        return Uint8List.fromList(bytes);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();

      final encoded = base64Encode(key);
      if (_cache[kSyncKeyB64] == encoded) return;

      _cache[kSyncKeyB64] = encoded;
      await _persistCache();
    });
  }

  Future<void> clearAll() async {
    await _serial(() async {
      final prefs = await _prefs();
      await prefs.remove(_kPrefsBlobKey);
      _loaded = true;
      _lastRaw = null;
      _cache = <String, String>{};
    });
  }

  Future<void> _reloadIfChanged() async {
    if (!_loaded) return;

    final prefs = await _prefs();
    final raw = prefs.getString(_kPrefsBlobKey);
    if (raw == _lastRaw) return;

    if (raw == null || raw.trim().isEmpty) {
      _lastRaw = null;
      _cache = <String, String>{};
      return;
    }

    _lastRaw = raw;
    _cache = _decodeRawMap(raw);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final prefs = await _prefs();
    final raw = prefs.getString(_kPrefsBlobKey);
    if (raw == null || raw.trim().isEmpty) {
      _lastRaw = null;
      _cache = <String, String>{};
      _loaded = true;
      return;
    }

    _lastRaw = raw;
    _cache = _decodeRawMap(raw);
    _loaded = true;
  }

  Map<String, String> _decodeRawMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, String>{};

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
      return result;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _persistCache() async {
    final prefs = await _prefs();
    if (_cache.isEmpty) {
      await prefs.remove(_kPrefsBlobKey);
      _lastRaw = null;
      return;
    }
    final raw = jsonEncode(_cache);
    await prefs.setString(_kPrefsBlobKey, raw);
    _lastRaw = raw;
  }
}
