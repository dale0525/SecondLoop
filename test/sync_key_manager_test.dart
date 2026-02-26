import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_key_manager.dart';

void main() {
  setUp(() {
    SyncKeyManager.resetForTest();
  });

  tearDown(() {
    SyncKeyManager.resetForTest();
  });

  test('loadOrCreate caches sync key during unlocked session', () async {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 9));
    SyncKeyManager.setSessionKey(sessionKey);

    Uint8List? persisted;

    Future<Uint8List?> read() async {
      final current = persisted;
      if (current == null) return null;
      return Uint8List.fromList(current);
    }

    Future<void> write(Uint8List key) async {
      persisted = Uint8List.fromList(key);
    }

    final created = await SyncKeyManager.loadOrCreate(read: read, write: write);
    expect(created.length, 32);
    expect(persisted, isNotNull);

    persisted = null;
    final loaded = await SyncKeyManager.load(read: read);
    expect(loaded, created);
  });

  test('does not keep sync key cache without session key', () async {
    final key = Uint8List.fromList(List<int>.filled(32, 5));
    Uint8List? persisted = Uint8List.fromList(key);

    Future<Uint8List?> read() async {
      final current = persisted;
      if (current == null) return null;
      return Uint8List.fromList(current);
    }

    final first = await SyncKeyManager.load(read: read);
    expect(first, key);

    persisted = null;
    final second = await SyncKeyManager.load(read: read);
    expect(second, isNull);
  });

  test('clears cached sync key when session is cleared', () async {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 2));
    final syncKey = Uint8List.fromList(List<int>.filled(32, 3));

    SyncKeyManager.setSessionKey(sessionKey);
    SyncKeyManager.cacheSyncKey(syncKey);
    expect(SyncKeyManager.readCachedSyncKey(), syncKey);

    SyncKeyManager.setSessionKey(null);
    expect(SyncKeyManager.readCachedSyncKey(), isNull);
  });
}
