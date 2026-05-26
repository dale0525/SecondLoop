import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';

void main() {
  test('app bridge launches helper with structured input and progress events',
      () async {
    SelfManagedSetupRequest? capturedRequest;
    final events = <SelfManagedSetupProgress>[];
    final process = LocalRuntimeHelperProcess(
      runner: (request, onProgress) async {
        capturedRequest = request;
        const event = SelfManagedSetupProgress(
          step: SelfManagedSetupStep.deploying,
          message: 'deploying',
        );
        events.add(event);
        onProgress(event);
        return const SelfManagedSetupResult(
          manifest: CloudRuntimeManifest(
            manifestVersion: 1,
            runtimeMode: CloudRuntimeMode.selfManaged,
            apiBaseUrl: 'https://user-runtime.example/',
            authMode: CloudRuntimeAuthMode.runtimeToken,
            capabilities: [CloudRuntimeCapability('chat')],
          ),
          authToken: 'runtime-token-1',
          capabilityManifestId: 'manifest-self-1',
          verification: ModelCapabilityVerificationResult.allRequiredPassed,
        );
      },
    );

    final result = await process.runSetup(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
      onProgress: events.add,
    );

    expect(capturedRequest?.cloudflareAccountLabel, 'acct-1');
    expect(events.last.step, SelfManagedSetupStep.deploying);
    expect(result.manifest.apiBaseUrl, 'https://user-runtime.example/');
  });

  test('app bridge launches uninstall helper with structured input', () async {
    SelfManagedRuntimeUninstallRequest? capturedRequest;
    final events = <SelfManagedSetupProgress>[];
    final process = LocalRuntimeHelperProcess(
      uninstallRunner: (request, onProgress) async {
        capturedRequest = request;
        const event = SelfManagedSetupProgress(
          step: SelfManagedSetupStep.uninstalling,
          message: 'uninstalling',
        );
        events.add(event);
        onProgress(event);
        return const SelfManagedRuntimeUninstallResult(
          ok: true,
          runtimeMode: 'self_managed',
          cloudflareAccountId: 'acct-1',
          removedWorkers: ['secretary-runtime'],
          removedBindings: ['D1'],
          removedSecrets: ['LLM_API_KEY'],
        );
      },
    );

    final result = await process.runUninstall(
      const SelfManagedRuntimeUninstallRequest(
        cloudflareAccountLabel: 'acct-1',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-1',
        cloudflareApiToken: 'cf-session-token',
      ),
      onProgress: events.add,
    );

    expect(capturedRequest?.cloudflareDeploymentAccountId, 'acct-1');
    expect(events.last.step, SelfManagedSetupStep.uninstalling);
    expect(result.removedWorkers, ['secretary-runtime']);
    expect(result.toJson().toString().contains('cf-session-token'), isFalse);
  });

  test('default app bridge invokes local helper process on IO platforms',
      () async {
    final events = <SelfManagedSetupProgress>[];
    final process = LocalRuntimeHelperProcess();

    await expectLater(
      () => process.runUninstall(
        const SelfManagedRuntimeUninstallRequest(
          cloudflareAccountLabel: 'acct-1',
          cloudflareAuthorizationMethod:
              SelfManagedCloudflareAuthorizationMethod.manual,
        ),
        onProgress: events.add,
      ),
      throwsA(
        isA<LocalRuntimeHelperException>().having(
          (error) => error.code,
          'code',
          'missing_cloudflare_account_id',
        ),
      ),
    );
    expect(events, isEmpty);
  });
}
