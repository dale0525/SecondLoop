import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';

void main() {
  test('manifest parses skill availability report entries', () {
    final manifest = CloudRuntimeManifest.fromJson(const <String, dynamic>{
      'manifest_version': 1,
      'runtime_mode': 'managed_pro',
      'api_base_url': 'https://runtime.example/',
      'auth_mode': 'hosted_session',
      'capabilities': <String>['chat'],
      'vault_binding': 'CF_D1_PRIMARY_VAULT',
      'provider_cost_owner': 'you (local key)',
      'skills': [
        {
          'id': 'web-research',
          'status': 'ready',
          'provider': 'configured',
        },
      ],
    });

    expect(manifest.skills.single.id, 'web-research');
    expect(manifest.skills.single.status, 'ready');
    expect(manifest.skills.single.provider, 'configured');
    expect(manifest.vaultBinding, 'CF_D1_PRIMARY_VAULT');
    expect(manifest.providerCostOwner, 'you (local key)');
    expect(manifest.toJson()['skills'], const [
      {
        'id': 'web-research',
        'status': 'ready',
        'provider': 'configured',
      },
    ]);
    expect(manifest.toJson()['vault_binding'], 'CF_D1_PRIMARY_VAULT');
    expect(manifest.toJson()['provider_cost_owner'], 'you (local key)');
  });
}
