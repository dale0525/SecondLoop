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
}
