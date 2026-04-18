import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SyncSecretStore {
  SyncSecretStore({String? scopeKey})
      : _scopeKey = _normalizeScopeKey(scopeKey);

  static const _kPrefsBlobKey = 'sync_secret_json_v1';

  static const kPrefsBlobKeyForTest = _kPrefsBlobKey;
  static const kWebdavPasswordB64 = 'sync_webdav_password_b64';
  static const kSyncKeyB64 = 'sync_webdav_sync_key_b64';
  static const kRecoveryEnvelopeJsonB64 = 'sync_recovery_envelope_json_b64';
  static const _kDeferredSessionKeyB64PrefsKey = 'deferred_session_key_b64_v1';
  static const _kEncryptedPrefix = 'enc1:';
  static const _kPlainPrefix = 'plain1:';
  static const _kNonceLength = 12;
  static const _kAad = 'sync-secret-store-v1';

  static final Cipher _cipher = AesGcm.with256bits();
  static Uint8List? _processSessionKey;

  final String? _scopeKey;
  Future<void> _tail = Future<void>.value();
  Future<SharedPreferences>? _prefsFuture;

  bool _loaded = false;
  String? _lastRaw;
  Map<String, String> _cache = <String, String>{};

  static void setProcessSessionKey(Uint8List? key) {
    if (key == null) {
      _processSessionKey = null;
      return;
    }
    if (key.length != 32) {
      throw ArgumentError('session key must be 32 bytes');
    }
    _processSessionKey = Uint8List.fromList(key);
  }

  static void setProcessSessionKeyForTest(Uint8List? key) {
    setProcessSessionKey(key);
  }

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
      final decoded = await _decodeSecret(_cache[kWebdavPasswordB64]);
      final bytes = decoded?.bytes;
      if (bytes == null || bytes.isEmpty) return null;
      try {
        final password = utf8.decode(bytes);
        if (password.isEmpty) return null;
        if (decoded != null) {
          await _maybeRewrapSecretIfNeeded(
            cacheKey: kWebdavPasswordB64,
            decoded: decoded,
          );
        }
        return password;
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

      final encoded = await _encodeSecretBytes(Uint8List.fromList(
        utf8.encode(password),
      ));
      if (_cache[kWebdavPasswordB64] == encoded) return;
      _cache[kWebdavPasswordB64] = encoded;
      await _persistCache();
    });
  }

  Future<Uint8List?> readSyncKey() async {
    return _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      final decoded = await _decodeSecret(_cache[kSyncKeyB64]);
      final bytes = decoded?.bytes;
      if (bytes == null || bytes.length != 32) return null;
      if (decoded != null) {
        await _maybeRewrapSecretIfNeeded(
          cacheKey: kSyncKeyB64,
          decoded: decoded,
        );
      }
      return Uint8List.fromList(bytes);
    });
  }

  Future<void> writeSyncKey(Uint8List key) async {
    await _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();

      if (key.length != 32) {
        throw ArgumentError('sync key must be 32 bytes');
      }
      final encoded = await _encodeSecretBytes(Uint8List.fromList(key));
      if (_cache[kSyncKeyB64] == encoded) return;

      _cache[kSyncKeyB64] = encoded;
      await _persistCache();
    });
  }

  Future<void> clearSyncKey() async {
    await _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      if (_cache.remove(kSyncKeyB64) == null) return;
      await _persistCache();
    });
  }

  Future<String?> readRecoveryEnvelopeJson() async {
    return _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();
      final decoded = await _decodeSecret(_cache[kRecoveryEnvelopeJsonB64]);
      final bytes = decoded?.bytes;
      if (bytes == null || bytes.isEmpty) return null;
      try {
        final envelopeJson = utf8.decode(bytes);
        if (envelopeJson.isEmpty) return null;
        if (decoded != null) {
          await _maybeRewrapSecretIfNeeded(
            cacheKey: kRecoveryEnvelopeJsonB64,
            decoded: decoded,
          );
        }
        return envelopeJson;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> writeRecoveryEnvelopeJson(String? envelopeJson) async {
    await _serial(() async {
      await _ensureLoaded();
      await _reloadIfChanged();

      final value = envelopeJson?.trim();
      if (value == null || value.isEmpty) {
        if (_cache.remove(kRecoveryEnvelopeJsonB64) != null) {
          await _persistCache();
        }
        return;
      }

      final encoded =
          await _encodeSecretBytes(Uint8List.fromList(utf8.encode(value)));
      if (_cache[kRecoveryEnvelopeJsonB64] == encoded) return;
      _cache[kRecoveryEnvelopeJsonB64] = encoded;
      await _persistCache();
    });
  }

  Future<_DecodedSecret?> _decodeSecret(String? encoded) async {
    if (encoded == null || encoded.isEmpty) return null;

    if (encoded.startsWith(_kEncryptedPrefix)) {
      final payloadB64 = encoded.substring(_kEncryptedPrefix.length);
      final payload = _decodeBase64(payloadB64);
      if (payload == null || payload.length <= _kNonceLength) return null;

      final key = await _resolveSessionKey();
      if (key == null || key.length != 32) return null;

      final nonce = payload.sublist(0, _kNonceLength);
      final macBytes = _cipher.macAlgorithm.macLength;
      if (payload.length < _kNonceLength + macBytes) return null;
      final cipherText = payload.sublist(
        _kNonceLength,
        payload.length - macBytes,
      );
      final mac = payload.sublist(payload.length - macBytes);

      try {
        final clear = await _cipher.decrypt(
          SecretBox(
            cipherText,
            nonce: nonce,
            mac: Mac(mac),
          ),
          secretKey: SecretKey(key),
          aad: utf8.encode(_kAad),
        );
        return _DecodedSecret(
          bytes: Uint8List.fromList(clear),
          format: _SecretFormat.encrypted,
        );
      } catch (_) {
        return null;
      }
    }

    if (encoded.startsWith(_kPlainPrefix)) {
      final payloadB64 = encoded.substring(_kPlainPrefix.length);
      final bytes = _decodeBase64(payloadB64);
      return bytes == null
          ? null
          : _DecodedSecret(
              bytes: Uint8List.fromList(bytes),
              format: _SecretFormat.plainPrefixed,
            );
    }

    final legacy = _decodeBase64(encoded);
    return legacy == null
        ? null
        : _DecodedSecret(
            bytes: Uint8List.fromList(legacy),
            format: _SecretFormat.legacyBase64,
          );
  }

  Future<String> _encodeSecretBytes(Uint8List bytes) async {
    final key = await _resolveSessionKey();
    if (key == null || key.length != 32) {
      return '$_kPlainPrefix${base64Encode(bytes)}';
    }
    return _encryptSecretBytes(bytes, key);
  }

  Future<String> _encryptSecretBytes(Uint8List bytes, Uint8List key) async {
    final nonce = _randomBytes(_kNonceLength);
    final box = await _cipher.encrypt(
      bytes,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode(_kAad),
    );
    final payload = Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    return '$_kEncryptedPrefix${base64Encode(payload)}';
  }

  Future<void> _maybeRewrapSecretIfNeeded({
    required String cacheKey,
    required _DecodedSecret decoded,
  }) async {
    if (decoded.format == _SecretFormat.encrypted) return;
    final key = await _resolveSessionKey();
    if (key == null || key.length != 32) return;

    final rewrapped = await _encryptSecretBytes(decoded.bytes, key);
    if (_cache[cacheKey] == rewrapped) return;
    _cache[cacheKey] = rewrapped;
    await _persistCache();
  }

  Future<Uint8List?> _resolveSessionKey() async {
    final process = _processSessionKey;
    if (process != null && process.length == 32) {
      return Uint8List.fromList(process);
    }

    final prefs = await _prefs();
    final deferredB64 = prefs.getString(_deferredSessionKeyPrefsKey);
    if (deferredB64 == null || deferredB64.isEmpty) return null;

    final decoded = _decodeBase64(deferredB64);
    if (decoded == null || decoded.length != 32) return null;
    return Uint8List.fromList(decoded);
  }

  Uint8List? _decodeBase64(String input) {
    try {
      return Uint8List.fromList(base64Decode(input));
    } catch (_) {
      return null;
    }
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<void> clearAll() async {
    await _serial(() async {
      final prefs = await _prefs();
      await prefs.remove(_prefsBlobKey);
      _loaded = true;
      _lastRaw = null;
      _cache = <String, String>{};
    });
  }

  Future<void> _reloadIfChanged() async {
    if (!_loaded) return;

    final prefs = await _prefs();
    final raw = prefs.getString(_prefsBlobKey);
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
    final raw = prefs.getString(_prefsBlobKey);
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
      await prefs.remove(_prefsBlobKey);
      _lastRaw = null;
      return;
    }
    final raw = jsonEncode(_cache);
    await prefs.setString(_prefsBlobKey, raw);
    _lastRaw = raw;
  }

  String get _prefsBlobKey => _scopedKey(_kPrefsBlobKey);

  String get _deferredSessionKeyPrefsKey =>
      _scopedKey(_kDeferredSessionKeyB64PrefsKey);

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
}

enum _SecretFormat {
  encrypted,
  plainPrefixed,
  legacyBase64,
}

final class _DecodedSecret {
  const _DecodedSecret({
    required this.bytes,
    required this.format,
  });

  final Uint8List bytes;
  final _SecretFormat format;
}
