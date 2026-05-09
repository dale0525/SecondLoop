import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import '../../tools/self_managed_runtime_lib/cloudflare_auth.dart';
import '../../tools/self_managed_runtime_lib/deploy_runner.dart';

void main() {
  test('deploy runner returns manifest after auth, deploy, and health check',
      () async {
    final events = <SelfManagedSetupProgress>[];
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async => 'cf-token-$accountLabel',
      ),
    );

    final result = await runner.run(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
      onProgress: events.add,
    );

    expect(events.map((event) => event.step), [
      SelfManagedSetupStep.authorizing,
      SelfManagedSetupStep.deploying,
    ]);
    expect(result.manifest.apiBaseUrl, 'https://acct-1.runtime.example/');
  });

  test('deploy runner preserves actionable failure codes', () async {
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (_) async => throw StateError('cloudflare_auth_failed'),
      ),
    );

    await expectLater(
      () => runner.run(
        const SelfManagedSetupRequest(
          cloudflareAccountLabel: 'acct-1',
          provider: 'openai',
          apiKey: 'sk-test',
          embeddingApiKey: 'emb-test',
          multimodalApiKey: 'mm-test',
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<LocalRuntimeHelperException>().having(
          (error) => error.code,
          'code',
          'cloudflare_auth_failed',
        ),
      ),
    );
  });

  test('deploy runner rejects missing required AI provider config', () async {
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async => 'cf-token-$accountLabel',
      ),
    );

    await expectLater(
      () => runner.run(
        const SelfManagedSetupRequest(
          cloudflareAccountLabel: 'acct-1',
          provider: 'openai',
          apiKey: 'sk-test',
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<LocalRuntimeHelperException>().having(
          (error) => error.code,
          'code',
          'missing_ai_provider_config',
        ),
      ),
    );
  });
}
