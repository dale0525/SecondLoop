import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';

void main() {
  test(
      'self-managed profile persists user-owned base url and capability manifest id',
      () {
    const profile = CloudRuntimeProfile(
      runtimeMode: CloudRuntimeMode.selfManaged,
      apiBaseUrl: 'https://user-runtime.example/',
      authMode: CloudRuntimeAuthMode.runtimeToken,
      authToken: 'runtime-token-1',
      capabilityManifestId: 'manifest-self-1',
      manifestVersion: 1,
    );

    expect(profile.toJson(), <String, Object?>{
      'runtime_mode': 'self_managed',
      'api_base_url': 'https://user-runtime.example/',
      'auth_mode': 'runtime_token',
      'auth_token': 'runtime-token-1',
      'capability_manifest_id': 'manifest-self-1',
      'manifest_version': 1,
    });

    expect(
      CloudRuntimeProfile.fromJson(profile.toJson()),
      profile,
    );
  });

  test('managed pro profile persists hosted base url and hosted auth mode', () {
    const profile = CloudRuntimeProfile(
      runtimeMode: CloudRuntimeMode.managedPro,
      apiBaseUrl: 'https://hosted-runtime.example/',
      authMode: CloudRuntimeAuthMode.hostedSession,
      authToken: 'hosted-session-1',
      capabilityManifestId: 'manifest-managed-1',
      manifestVersion: 1,
    );

    expect(profile.toJson()['runtime_mode'], 'managed_pro');
    expect(profile.toJson()['auth_mode'], 'hosted_session');
    expect(
      CloudRuntimeProfile.fromJson(profile.toJson()),
      profile,
    );
  });

  test('manifest uses snake_case wire fields and typed capabilities', () {
    const manifest = CloudRuntimeManifest(
      manifestVersion: 1,
      runtimeMode: CloudRuntimeMode.selfManaged,
      apiBaseUrl: 'https://user-runtime.example/',
      authMode: CloudRuntimeAuthMode.runtimeToken,
      capabilities: [
        CloudRuntimeCapability('chat'),
        CloudRuntimeCapability('working_set'),
      ],
    );

    expect(manifest.toJson(), <String, Object?>{
      'manifest_version': 1,
      'runtime_mode': 'self_managed',
      'api_base_url': 'https://user-runtime.example/',
      'auth_mode': 'runtime_token',
      'capabilities': ['chat', 'working_set'],
    });

    expect(
      CloudRuntimeManifest.fromJson(manifest.toJson()),
      manifest,
    );
  });
}
