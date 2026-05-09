import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
