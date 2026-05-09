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
      verifyModelCapabilities: (_, __) async => _successfulVerificationResult,
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
      SelfManagedSetupStep.verifying,
    ]);
    expect(result.manifest.apiBaseUrl, 'https://acct-1.runtime.example/');
    expect(result.verification?.ok, isTrue);
  });

  test('deploy runner rejects failed model capability verification', () async {
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async => 'cf-token-$accountLabel',
      ),
      verifyModelCapabilities: (_, __) async =>
          const ModelCapabilityVerificationResult(
        ok: false,
        checks: [
          ModelCapabilityCheckResult(
            code: 'multimodal_understanding',
            passed: false,
            failureCode: 'multimodal_model_required',
          ),
        ],
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
          'multimodal_model_required',
        ),
      ),
    );
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

  test('deploy runner default verifier posts to runtime capability route',
      () async {
    Uri? capturedUri;
    Map<String, Object?>? capturedBody;

    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async => 'cf-token-$accountLabel',
      ),
      deployResources: (_, __, ___) async => 'https://runtime.example/base/',
      runHealthCheck: (_) async {},
      postVerificationJson: (uri, body) async {
        capturedUri = uri;
        capturedBody = body;
        return _successfulVerificationResult.toJson();
      },
    );

    final result = await runner.run(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
      onProgress: (_) {},
    );

    expect(result.verification?.ok, isTrue);
    expect(
      capturedUri.toString(),
      'https://runtime.example/base/v1/runtime/model/verify-capabilities',
    );
    expect(capturedBody?['runtime_mode'], 'self_managed');
    expect(capturedBody?['provider'], 'openai');
    expect(capturedBody?['vault_id'], 'acct-1');
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

const _successfulVerificationResult = ModelCapabilityVerificationResult(
  ok: true,
  checks: [
    ModelCapabilityCheckResult(
      code: 'structured_output',
      passed: true,
    ),
  ],
);
