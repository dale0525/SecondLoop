import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_secret_store.dart';

void main() {
  setUp(() {
    SyncSecretStore.setProcessSessionKeyForTest(null);
  });

  tearDown(() {
    SyncSecretStore.setProcessSessionKeyForTest(null);
  });

  test('encrypts secret payload when process session key is present', () async {
    SharedPreferences.setMockInitialValues({});
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 9));
    final expectedSyncKey = Uint8List.fromList(List<int>.filled(32, 7));

    SyncSecretStore.setProcessSessionKeyForTest(sessionKey);

    final store = SyncSecretStore();
    await store.writeWebdavPassword('plain-password');
    await store.writeSyncKey(expectedSyncKey);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SyncSecretStore.kPrefsBlobKeyForTest);
    expect(raw, isNotNull);
    expect(raw, isNot(contains('plain-password')));
    expect(raw, isNot(contains(base64Encode(expectedSyncKey))));
    expect(raw, contains('enc1:'));

    expect(await store.readWebdavPassword(), 'plain-password');
    expect(await store.readSyncKey(), expectedSyncKey);
  });

  test('can decrypt with deferred session key from preferences', () async {
    final deferredKey =
        Uint8List.fromList(List<int>.generate(32, (i) => i + 3));
    SharedPreferences.setMockInitialValues({
      'deferred_session_key_b64_v1': base64Encode(deferredKey),
    });

    final store = SyncSecretStore();
    await store.writeWebdavPassword('deferred-password');

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SyncSecretStore.kPrefsBlobKeyForTest);
    expect(raw, isNotNull);
    expect(raw, contains('enc1:'));

    SyncSecretStore.setProcessSessionKeyForTest(null);
    expect(await store.readWebdavPassword(), 'deferred-password');
  });

  test('keeps compatibility for existing unencrypted secret payload', () async {
    SharedPreferences.setMockInitialValues({
      SyncSecretStore.kPrefsBlobKeyForTest: jsonEncode({
        SyncSecretStore.kWebdavPasswordB64:
            base64Encode(utf8.encode('legacy-password')),
      }),
    });

    final store = SyncSecretStore();
    expect(await store.readWebdavPassword(), 'legacy-password');
  });
}
