import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('Managed vault config uses default base URL when override is missing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.managedVault);
    expect(configured.baseUrl, 'https://vault.default.example');
    expect(configured.remoteRoot, 'uid_1');
  });

  test('Managed vault config prefers stored base URL override', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeManagedVaultBaseUrl('https://vault.override.example');

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.managedVault);
    expect(configured.baseUrl, 'https://vault.override.example');
  });
}
