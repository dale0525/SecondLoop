import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RuntimeConnectionStore.resetCacheForTests();
  });

  test('store can write and read the active runtime profile', () async {
    final store = RuntimeConnectionStore();
    const connection = CloudRuntimeConnection(
      profile: CloudRuntimeProfile(
        runtimeMode: CloudRuntimeMode.selfManaged,
        apiBaseUrl: 'https://user-runtime.example/',
        authMode: CloudRuntimeAuthMode.runtimeToken,
        authToken: 'runtime-token-1',
        capabilityManifestId: 'manifest-self-1',
        manifestVersion: 1,
      ),
      manifest: CloudRuntimeManifest(
        manifestVersion: 1,
        runtimeMode: CloudRuntimeMode.selfManaged,
        apiBaseUrl: 'https://user-runtime.example/',
        authMode: CloudRuntimeAuthMode.runtimeToken,
        capabilities: [
          CloudRuntimeCapability('chat'),
          CloudRuntimeCapability('working_set'),
        ],
      ),
    );

    await store.saveConnection(connection);

    expect(await store.loadConnection(), connection);
  });

  test('store can clear the active runtime profile', () async {
    final store = RuntimeConnectionStore();
    const connection = CloudRuntimeConnection(
      profile: CloudRuntimeProfile(
        runtimeMode: CloudRuntimeMode.managedPro,
        apiBaseUrl: 'https://hosted-runtime.example/',
        authMode: CloudRuntimeAuthMode.hostedSession,
        authToken: 'hosted-session-1',
        capabilityManifestId: 'manifest-managed-1',
        manifestVersion: 1,
      ),
      manifest: CloudRuntimeManifest(
        manifestVersion: 1,
        runtimeMode: CloudRuntimeMode.managedPro,
        apiBaseUrl: 'https://hosted-runtime.example/',
        authMode: CloudRuntimeAuthMode.hostedSession,
        capabilities: [
          CloudRuntimeCapability('chat'),
        ],
      ),
    );

    await store.saveConnection(connection);
    await store.clearConnection();

    expect(await store.loadConnection(), isNull);
  });

  test('legacy self-managed connection migrates vault id from manifest binding',
      () async {
    final store = RuntimeConnectionStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      RuntimeConnectionStore.connectionPrefsKey,
      '''
      {
        "profile": {
          "runtime_mode": "self_managed",
          "api_base_url": "https://user-runtime.example/",
          "auth_mode": "runtime_token",
          "auth_token": "runtime-token-1",
          "capability_manifest_id": "manifest-self-1",
          "manifest_version": 1
        },
        "manifest": {
          "manifest_version": 1,
          "runtime_mode": "self_managed",
          "api_base_url": "https://user-runtime.example/",
          "auth_mode": "runtime_token",
          "capabilities": ["chat"],
          "vault_binding": "CF_D1_PRIMARY_VAULT"
        }
      }
      ''',
    );

    final connection = await store.loadConnection();

    expect(connection?.profile.vaultId, 'CF_D1_PRIMARY_VAULT');
    expect(
      prefs.getString(RuntimeConnectionStore.connectionPrefsKey),
      contains('"vault_id":"CF_D1_PRIMARY_VAULT"'),
    );
  });

  test('legacy managed pro connection does not infer a vault id', () async {
    final store = RuntimeConnectionStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      RuntimeConnectionStore.connectionPrefsKey,
      '''
      {
        "profile": {
          "runtime_mode": "managed_pro",
          "api_base_url": "https://hosted-runtime.example/",
          "auth_mode": "hosted_session",
          "auth_token": "hosted-session-1",
          "capability_manifest_id": "manifest-managed-1",
          "manifest_version": 1
        },
        "manifest": {
          "manifest_version": 1,
          "runtime_mode": "managed_pro",
          "api_base_url": "https://hosted-runtime.example/",
          "auth_mode": "hosted_session",
          "capabilities": ["chat"],
          "vault_binding": "managed-vault-binding"
        }
      }
      ''',
    );

    final connection = await store.loadConnection();

    expect(connection?.profile.vaultId, isEmpty);
  });

  test('unknown manifest versions are rejected', () async {
    final store = RuntimeConnectionStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      RuntimeConnectionStore.connectionPrefsKey,
      '''
      {
        "profile": {
          "runtime_mode": "self_managed",
          "api_base_url": "https://user-runtime.example/",
          "auth_mode": "runtime_token",
          "auth_token": "runtime-token-1",
          "capability_manifest_id": "manifest-self-1",
          "manifest_version": 999
        },
        "manifest": {
          "manifest_version": 999,
          "runtime_mode": "self_managed",
          "api_base_url": "https://user-runtime.example/",
          "auth_mode": "runtime_token",
          "capabilities": ["chat"]
        }
      }
      ''',
    );

    expect(
      store.loadConnection,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('manifest_version'),
        ),
      ),
    );
  });
}
