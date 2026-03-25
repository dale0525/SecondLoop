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

  test('matchesSessionKey only returns true for the active session key', () {
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 4));
    final staleKey = Uint8List.fromList(List<int>.filled(32, 5));

    SyncKeyManager.setSessionKey(sessionKey);

    expect(SyncKeyManager.matchesSessionKey(sessionKey), isTrue);
    expect(SyncKeyManager.matchesSessionKey(staleKey), isFalse);
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

  test('managed vault passphrase is namespaced by vault id', () {
    final passphrase = SyncKeyManager.managedVaultPassphraseForVaultId('uid_1');
    expect(passphrase, 'managed-vault-sync-v1::uid_1');
  });

  test('deriveManagedVaultSyncKey uses managed vault passphrase', () async {
    String? receivedPassphrase;
    final key = Uint8List.fromList(List<int>.filled(32, 7));

    final derived = await SyncKeyManager.deriveManagedVaultSyncKey(
      vaultId: 'uid_1',
      deriveSyncKey: (passphrase) async {
        receivedPassphrase = passphrase;
        return Uint8List.fromList(key);
      },
    );

    expect(receivedPassphrase, 'managed-vault-sync-v1::uid_1');
    expect(derived, key);
  });
}
