import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_secret_store.dart';

void main() {
  test('SyncConfigStore notices updates from other instances', () async {
    SharedPreferences.setMockInitialValues({});

    final staleReader = SyncConfigStore();
    expect(await staleReader.loadConfiguredSyncIfAutoEnabled(), isNull);

    final writer = SyncConfigStore();
    await writer.writeBackendType(SyncBackendType.webdav);
    await writer.writeAutoEnabled(true);
    await writer.writeRemoteRoot('SecondLoop');
    await writer.writeWebdavBaseUrl('https://example.com/dav');
    await writer.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final config = await staleReader.loadConfiguredSyncIfAutoEnabled();
    expect(config, isNotNull);
    expect(config!.baseUrl, 'https://example.com/dav');
    expect(config.remoteRoot, 'SecondLoop');
  });

  test('SyncConfigStore rollout flags default enabled and sync cross-instance',
      () async {
    SharedPreferences.setMockInitialValues({});

    final staleReader = SyncConfigStore();
    expect(await staleReader.readSyncRefreshV2Enabled(), isTrue);
    expect(await staleReader.readSyncBackgroundDiagV1Enabled(), isTrue);
    expect(await staleReader.readSyncBackoffV1Enabled(), isTrue);

    final writer = SyncConfigStore();
    await writer.writeSyncRefreshV2Enabled(false);
    await writer.writeSyncBackgroundDiagV1Enabled(false);
    await writer.writeSyncBackoffV1Enabled(false);

    expect(await staleReader.readSyncRefreshV2Enabled(), isFalse);
    expect(await staleReader.readSyncBackgroundDiagV1Enabled(), isFalse);
    expect(await staleReader.readSyncBackoffV1Enabled(), isFalse);
  });

  test('SyncConfigStore isolates scoped data between users', () async {
    SharedPreferences.setMockInitialValues({});

    final first = SyncConfigStore(scopeKey: 'web-native:uid-1');
    final second = SyncConfigStore(scopeKey: 'web-native:uid-2');

    await first.writeBackendType(SyncBackendType.managedVault);
    await first.writeRemoteRoot('uid-1');
    await first.writeManagedVaultBaseUrl('https://vault-1.example');
    await first.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await second.writeBackendType(SyncBackendType.managedVault);
    await second.writeRemoteRoot('uid-2');
    await second.writeManagedVaultBaseUrl('https://vault-2.example');
    await second.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 2)));

    expect(await first.readRemoteRoot(), 'uid-1');
    expect(await second.readRemoteRoot(), 'uid-2');
    expect(await first.resolveManagedVaultBaseUrl(), 'https://vault-1.example');
    expect(
      await second.resolveManagedVaultBaseUrl(),
      'https://vault-2.example',
    );
    expect(
        await first.readSyncKey(), Uint8List.fromList(List<int>.filled(32, 1)));
    expect(await second.readSyncKey(),
        Uint8List.fromList(List<int>.filled(32, 2)));
  });

  test('SyncConfigStore migrates legacy unscoped secure storage into a scope',
      () async {
    SharedPreferences.setMockInitialValues({});

    final storage = _InMemorySecureStorage({
      'sync_config_blob_json_v1':
          '{"sync_backend_type":"managedvault","sync_webdav_remote_root":"uid-1","sync_managed_vault_base_url":"https://vault-1.example"}',
    });
    final store = SyncConfigStore(
      storage: storage,
      scopeKey: 'web-native:uid-1',
      allowSecureStoreMigrationInTestEnvironment: true,
    );

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'uid-1');
    expect(await store.resolveManagedVaultBaseUrl(), 'https://vault-1.example');
    expect(storage.values['sync_config_blob_json_v1'], isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('sync_config_public_json_v2::web-native:uid-1'),
      isNotNull,
    );
    expect(
      jsonDecode(
          prefs.getString('sync_config_public_json_v2::web-native:uid-1')!),
      {
        'sync_backend_type': 'managedvault',
        'sync_webdav_remote_root': 'uid-1',
        'sync_managed_vault_base_url': 'https://vault-1.example',
      },
    );
  });

  test(
      'SyncConfigStore keeps legacy unscoped secure storage when scoped sync key migration fails',
      () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    addTearDown(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });

    final prefsStore = _FailingPrefsStore(
      failOnSetKeySuffix:
          '${SyncSecretStore.kPrefsBlobKeyForTest}::web-native:uid-1',
    );
    SharedPreferencesStorePlatform.instance = prefsStore;

    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    final storage = _InMemorySecureStorage({
      'sync_config_blob_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'managedvault',
        SyncConfigStore.kRemoteRoot: 'uid-1',
        SyncConfigStore.kManagedVaultBaseUrl: 'https://vault-1.example',
        SyncConfigStore.kSyncKeyB64: base64Encode(syncKey),
      }),
    });
    final store = SyncConfigStore(
      storage: storage,
      scopeKey: 'web-native:uid-1',
      allowSecureStoreMigrationInTestEnvironment: true,
    );

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(storage.values['sync_config_blob_json_v1'], isNotNull);

    final persisted = await prefsStore.getAll();
    expect(
      jsonDecode(
          persisted['flutter.sync_config_public_json_v2::web-native:uid-1']
              as String),
      {
        'sync_backend_type': 'managedvault',
        'sync_webdav_remote_root': 'uid-1',
        'sync_managed_vault_base_url': 'https://vault-1.example',
      },
    );
    expect(
      persisted.containsKey('flutter.sync_secret_json_v1::web-native:uid-1'),
      isFalse,
      reason: 'written keys: ${prefsStore.writtenKeys}',
    );
  });
}

final class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

final class _FailingPrefsStore extends InMemorySharedPreferencesStore {
  _FailingPrefsStore({required this.failOnSetKeySuffix}) : super.empty();

  final String failOnSetKeySuffix;
  final List<String> writtenKeys = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writtenKeys.add(key);
    if (key.endsWith(failOnSetKeySuffix)) {
      throw Exception('injected prefs write failure for $key');
    }
    return super.setValue(valueType, key, value);
  }
}
