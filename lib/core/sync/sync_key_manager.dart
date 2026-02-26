import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sync_secret_store.dart';

typedef SyncKeyReader = Future<Uint8List?> Function();
typedef SyncKeyWriter = Future<void> Function(Uint8List key);

final class SyncKeyManager {
  SyncKeyManager._();

  static Uint8List? _sessionKey;
  static Uint8List? _cachedSyncKey;

  static bool get hasSessionKey => _sessionKey != null;

  static void setSessionKey(Uint8List? key) {
    if (key == null) {
      _sessionKey = null;
      _cachedSyncKey = null;
      SyncSecretStore.setProcessSessionKey(null);
      return;
    }
    if (key.length != 32) {
      throw ArgumentError('session key must be 32 bytes');
    }
    final next = Uint8List.fromList(key);
    final current = _sessionKey;
    final changed = current == null || !_bytesEqual(current, next);
    _sessionKey = next;
    if (changed) {
      _cachedSyncKey = null;
    }
    SyncSecretStore.setProcessSessionKey(next);
  }

  static Uint8List? readCachedSyncKey() {
    final cached = _cachedSyncKey;
    if (cached == null || cached.length != 32) return null;
    return Uint8List.fromList(cached);
  }

  static void cacheSyncKey(Uint8List? key) {
    if (!hasSessionKey || key == null || key.length != 32) {
      _cachedSyncKey = null;
      return;
    }
    _cachedSyncKey = Uint8List.fromList(key);
  }

  static void clearSyncKeyCache() {
    _cachedSyncKey = null;
  }

  static Future<Uint8List?> load({
    required SyncKeyReader read,
  }) async {
    final cached = readCachedSyncKey();
    if (cached != null) return cached;

    final loaded = await read();
    if (loaded == null || loaded.length != 32) {
      if (hasSessionKey) {
        _cachedSyncKey = null;
      }
      return null;
    }
    cacheSyncKey(loaded);
    return Uint8List.fromList(loaded);
  }

  static Future<void> save({
    required SyncKeyWriter write,
    required Uint8List key,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('sync key must be 32 bytes');
    }
    final next = Uint8List.fromList(key);
    await write(next);
    cacheSyncKey(next);
  }

  static Future<Uint8List> loadOrCreate({
    required SyncKeyReader read,
    required SyncKeyWriter write,
  }) async {
    final existing = await load(read: read);
    if (existing != null && existing.length == 32) {
      return Uint8List.fromList(existing);
    }

    final generated = _createSyncKey();
    await save(write: write, key: generated);
    return Uint8List.fromList(generated);
  }

  static Uint8List _createSyncKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    _sessionKey = null;
    _cachedSyncKey = null;
    SyncSecretStore.setProcessSessionKey(null);
  }
}
