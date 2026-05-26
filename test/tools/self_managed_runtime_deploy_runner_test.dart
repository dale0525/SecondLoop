import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

import '../../tools/self_managed_runtime_lib/cloudflare_auth.dart';
import '../../tools/self_managed_runtime_lib/cloudflare_runtime_resources.dart';
import '../../tools/self_managed_runtime_lib/deploy_runner.dart';
import '../../tools/self_managed_runtime_lib/resource_plan.dart';
import '../../tools/self_managed_runtime_lib/uninstall_runner.dart';

void main() {
  test('deploy runner returns manifest after auth, deploy, and health check',
      () async {
    final events = <SelfManagedSetupProgress>[];
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async =>
            SelfManagedCloudflareAuthorization.placeholder(
          accessToken: 'cf-token-$accountLabel',
          accountLabel: accountLabel,
        ),
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
    expect(result.manifest.skills.single.id, 'web-research');
    expect(result.manifest.skills.single.status, 'ready');
    expect(result.verification?.ok, isTrue);
  });

  test('manual Cloudflare token is session input and bypasses OAuth helper',
      () async {
    var oauthCalled = false;
    String? capturedCloudflareToken;
    SelfManagedSetupRequest? capturedRequest;
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (_) async {
          oauthCalled = true;
          return SelfManagedCloudflareAuthorization.placeholder(
            accessToken: 'unexpected-oauth-token',
            accountLabel: 'unexpected',
          );
        },
      ),
      deployResources: (request, cloudflareAuthorization, _) async {
        capturedRequest = request;
        capturedCloudflareToken = cloudflareAuthorization.accessToken;
        return 'https://manual-runtime.example/';
      },
      runHealthCheck: (_) async {},
      verifyModelCapabilities: (_, __) async => _successfulVerificationResult,
    );

    final result = await runner.run(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'legacy-label',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-manual',
        cloudflareApiToken: 'cf-session-token',
      ),
      onProgress: (_) {},
    );

    expect(oauthCalled, isFalse);
    expect(capturedCloudflareToken, 'cf-session-token');
    expect(capturedRequest?.cloudflareDeploymentAccountId, 'acct-manual');
    expect(result.manifest.apiBaseUrl, 'https://manual-runtime.example/');
    expect(result.manifest.toJson().toString().contains('cf-session-token'),
        isFalse);
    expect(result.authToken.contains('cf-session-token'), isFalse);
  });

  test('deploy runner rejects failed model capability verification', () async {
    final runner = SelfManagedRuntimeDeployRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (accountLabel) async =>
            SelfManagedCloudflareAuthorization.placeholder(
          accessToken: 'cf-token-$accountLabel',
          accountLabel: accountLabel,
        ),
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
        authorize: (accountLabel) async =>
            SelfManagedCloudflareAuthorization.placeholder(
          accessToken: 'cf-token-$accountLabel',
          accountLabel: accountLabel,
        ),
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
        authorize: (accountLabel) async =>
            SelfManagedCloudflareAuthorization.placeholder(
          accessToken: 'cf-token-$accountLabel',
          accountLabel: accountLabel,
        ),
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

  test('uninstall runner validates manual Cloudflare credentials before delete',
      () async {
    var uninstallCalled = false;
    final runner = SelfManagedRuntimeUninstallRunner(
      uninstallResources: (_, __, ___) async {
        uninstallCalled = true;
        return const SelfManagedRuntimeUninstallResult(
          ok: true,
          runtimeMode: 'self_managed',
          cloudflareAccountId: 'acct-1',
          removedWorkers: [],
          removedBindings: [],
          removedSecrets: [],
        );
      },
    );

    await expectLater(
      () => runner.run(
        const SelfManagedRuntimeUninstallRequest(
          cloudflareAccountLabel: 'acct-1',
          cloudflareAuthorizationMethod:
              SelfManagedCloudflareAuthorizationMethod.manual,
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<LocalRuntimeHelperException>().having(
          (error) => error.code,
          'code',
          'missing_cloudflare_account_id',
        ),
      ),
    );

    await expectLater(
      () => runner.run(
        const SelfManagedRuntimeUninstallRequest(
          cloudflareAccountLabel: 'acct-1',
          cloudflareAuthorizationMethod:
              SelfManagedCloudflareAuthorizationMethod.manual,
          cloudflareAccountId: 'acct-1',
        ),
        onProgress: (_) {},
      ),
      throwsA(
        isA<LocalRuntimeHelperException>().having(
          (error) => error.code,
          'code',
          'missing_cloudflare_api_token',
        ),
      ),
    );
    expect(uninstallCalled, isFalse);
  });

  test('uninstall runner passes manual token without leaking it in output',
      () async {
    var oauthCalled = false;
    String? capturedCloudflareToken;
    final events = <SelfManagedSetupProgress>[];
    final runner = SelfManagedRuntimeUninstallRunner(
      cloudflareAuth: SelfManagedCloudflareAuth(
        authorize: (_) async {
          oauthCalled = true;
          return SelfManagedCloudflareAuthorization.placeholder(
            accessToken: 'unexpected-oauth-token',
            accountLabel: 'unexpected',
          );
        },
      ),
      uninstallResources: (request, cloudflareAuthorization, plan) async {
        capturedCloudflareToken = cloudflareAuthorization.accessToken;
        return SelfManagedRuntimeUninstallResult(
          ok: true,
          runtimeMode: 'self_managed',
          cloudflareAccountId: request.cloudflareDeploymentAccountId,
          removedWorkers: plan.workerNames,
          removedBindings: plan.bindings,
          removedSecrets: plan.secrets,
        );
      },
    );

    final result = await runner.run(
      const SelfManagedRuntimeUninstallRequest(
        cloudflareAccountLabel: 'legacy-label',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-manual',
        cloudflareApiToken: 'cf-session-token',
      ),
      onProgress: events.add,
    );

    expect(oauthCalled, isFalse);
    expect(capturedCloudflareToken, 'cf-session-token');
    expect(
      events.map((event) => event.step),
      [
        SelfManagedSetupStep.authorizing,
        SelfManagedSetupStep.uninstalling,
        SelfManagedSetupStep.uninstalled,
      ],
    );
    expect(result.cloudflareAccountId, 'acct-manual');
    expect(result.removedWorkers, contains('secretary-runtime'));
    expect(result.toJson().toString().contains('cf-session-token'), isFalse);
  });

  test('Cloudflare local QA resource names are deterministic and scoped', () {
    final plan = buildSelfManagedRuntimeResourcePlan();

    final names = buildCloudflareRuntimeResourceNames(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'ignored',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: '9A7806061C88ADA191ED06F989CC3DAC',
        cloudflareApiToken: 'cf-session-token',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
      plan,
    );

    expect(names.prefix, 'secondloop-9a7806061c88');
    expect(
        names.workerNames.first, 'secondloop-9a7806061c88-secretary-runtime');
    expect(names.d1DatabaseName, 'secondloop-9a7806061c88-d1');
    expect(names.kvNamespaceTitle, 'secondloop-9a7806061c88-kv');
    expect(names.r2BucketName, 'secondloop-9a7806061c88-r2');
  });
}

const _successfulVerificationResult =
    ModelCapabilityVerificationResult.allRequiredPassed;
