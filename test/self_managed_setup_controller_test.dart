import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/self_managed_setup_controller.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setup starts in idle', () {
    final controller = SelfManagedSetupController();

    expect(controller.state.step, SelfManagedSetupStep.idle);
  });

  test('entering Cloudflare auth moves to authorizing', () {
    final controller = SelfManagedSetupController();

    controller.beginCloudflareAuthorization();

    expect(controller.state.step, SelfManagedSetupStep.authorizing);
  });

  test('OAuth handoff unavailable is explicit degraded state', () {
    final controller = SelfManagedSetupController();

    controller.reportCloudflareOAuthUnavailable();

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'tool_unavailable:cloudflare_oauth');
  });

  test('OAuth handoff authorizes Cloudflare through helper', () async {
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        cloudflareAuthorizationRunner: (accountLabel, onProgress) async {
          expect(accountLabel, 'personal-vault');
          onProgress(
            const SelfManagedSetupProgress(
              step: SelfManagedSetupStep.authorizing,
              message: 'authorizing_cloudflare_oauth',
            ),
          );
          return const SelfManagedCloudflareAuthorizationResult(
            cloudflareAccountId: 'acct-1',
            cloudflareAccountName: 'Personal Account',
            cloudflareUserEmail: 'user@example.test',
          );
        },
      ),
    );

    final result = await controller.authorizeCloudflareOAuth(
      accountLabel: 'personal-vault',
    );

    expect(result?.cloudflareAccountId, 'acct-1');
    expect(controller.state.step, SelfManagedSetupStep.cloudflareReady);
    expect(controller.state.errorCode, isNull);
  });

  test('manual Cloudflare authorization requires account id and API token', () {
    final controller = SelfManagedSetupController();

    expect(
      controller.prepareManualCloudflareAuthorization(
        accountId: '',
        apiToken: '',
      ),
      isFalse,
    );
    expect(controller.state.errorCode, 'missing_cloudflare_account_id');

    expect(
      controller.prepareManualCloudflareAuthorization(
        accountId: 'acct-1',
        apiToken: '',
      ),
      isFalse,
    );
    expect(controller.state.errorCode, 'missing_cloudflare_api_token');

    expect(
      controller.prepareManualCloudflareAuthorization(
        accountId: 'acct-1',
        apiToken: 'cf-session-token',
      ),
      isTrue,
    );
    expect(controller.state.step, SelfManagedSetupStep.cloudflareReady);
    expect(controller.state.isCloudflareReady, isTrue);
  });

  test('successful manifest write moves to ready', () async {
    final store = RuntimeConnectionStore();
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        runner: (request, onProgress) async {
          onProgress(
            const SelfManagedSetupProgress(
              step: SelfManagedSetupStep.deploying,
              message: 'deploying',
            ),
          );
          return const SelfManagedSetupResult(
            manifest: CloudRuntimeManifest(
              manifestVersion: 1,
              runtimeMode: CloudRuntimeMode.selfManaged,
              apiBaseUrl: 'https://user-runtime.example/',
              authMode: CloudRuntimeAuthMode.runtimeToken,
              capabilities: CloudRuntimeRequiredCapabilities.all,
            ),
            authToken: 'runtime-token-1',
            capabilityManifestId: 'manifest-self-1',
            verification: ModelCapabilityVerificationResult.allRequiredPassed,
          );
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.ready);
    expect(controller.state.verification?.ok, isTrue);
    final connection = await store.loadConnection();
    expect(connection?.profile.authToken, 'runtime-token-1');
    expect(connection?.profile.authToken.contains('sk-test'), isFalse);
    expect(connection?.manifest.capabilities,
        contains(CloudRuntimeRequiredCapabilities.workingSet));
  });

  test('helper failure yields a user-displayable error state with retry',
      () async {
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async {
          throw const LocalRuntimeHelperException(
            'cloudflare_auth_failed',
            'Authorization failed.',
          );
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'cloudflare_auth_failed');
  });

  test('missing manual Cloudflare token does not call helper or save runtime',
      () async {
    final store = RuntimeConnectionStore();
    var helperCalled = false;
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async {
          helperCalled = true;
          throw const LocalRuntimeHelperException('unexpected', 'unexpected');
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-1',
      ),
    );

    expect(helperCalled, isFalse);
    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'missing_cloudflare_api_token');
    expect(await store.loadConnection(), isNull);
  });

  test('verification failure does not save runtime connection', () async {
    final store = RuntimeConnectionStore();
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async {
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
            verification: ModelCapabilityVerificationResult(
              ok: false,
              checks: [
                ModelCapabilityCheckResult(
                  code: 'structured_output',
                  passed: false,
                  failureCode: 'invalid_structured_output',
                ),
              ],
            ),
          );
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'invalid_structured_output');
    expect(controller.state.verification?.ok, isFalse);
    expect(await store.loadConnection(), isNull);
  });

  test('missing required verification check does not save runtime connection',
      () async {
    final store = RuntimeConnectionStore();
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async {
          return const SelfManagedSetupResult(
            manifest: CloudRuntimeManifest(
              manifestVersion: 1,
              runtimeMode: CloudRuntimeMode.selfManaged,
              apiBaseUrl: 'https://user-runtime.example/',
              authMode: CloudRuntimeAuthMode.runtimeToken,
              capabilities: CloudRuntimeRequiredCapabilities.all,
            ),
            authToken: 'runtime-token-1',
            capabilityManifestId: 'manifest-self-1',
            verification: ModelCapabilityVerificationResult(
              ok: true,
              checks: [
                ModelCapabilityCheckResult(
                  code: ModelCapabilityRequiredChecks.structuredOutput,
                  passed: true,
                ),
              ],
            ),
          );
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(
      controller.state.errorCode,
      'missing_model_capability_check:secretary_metadata',
    );
    expect(await store.loadConnection(), isNull);
  });

  test('missing required runtime capability does not save runtime connection',
      () async {
    final store = RuntimeConnectionStore();
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async {
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
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
        embeddingApiKey: 'emb-test',
        multimodalApiKey: 'mm-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'missing_runtime_capability');
    expect(await store.loadConnection(), isNull);
  });

  test('successful uninstall calls helper and clears runtime connection',
      () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(_selfManagedConnection);
    var helperCalled = false;
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        uninstallRunner: (request, onProgress) async {
          helperCalled = true;
          expect(request.cloudflareDeploymentAccountId, 'acct-1');
          expect(request.cloudflareApiToken, 'cf-session-token');
          onProgress(
            const SelfManagedSetupProgress(
              step: SelfManagedSetupStep.uninstalling,
              message: 'uninstalling',
            ),
          );
          return const SelfManagedRuntimeUninstallResult(
            ok: true,
            runtimeMode: 'self_managed',
            cloudflareAccountId: 'acct-1',
            removedWorkers: ['secretary-runtime'],
            removedBindings: ['D1'],
            removedSecrets: ['LLM_API_KEY'],
          );
        },
      ),
    );

    await controller.uninstall(
      const SelfManagedRuntimeUninstallRequest(
        cloudflareAccountLabel: 'acct-1',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-1',
        cloudflareApiToken: 'cf-session-token',
      ),
    );

    expect(helperCalled, isTrue);
    expect(controller.state.step, SelfManagedSetupStep.uninstalled);
    expect(controller.state.manifest, isNull);
    expect(await store.loadConnection(), isNull);
  });

  test('missing uninstall manual token does not call helper or clear runtime',
      () async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(_selfManagedConnection);
    var helperCalled = false;
    final controller = SelfManagedSetupController(
      connectionStore: store,
      helperProcess: LocalRuntimeHelperProcess(
        uninstallRunner: (_, __) async {
          helperCalled = true;
          throw const LocalRuntimeHelperException('unexpected', 'unexpected');
        },
      ),
    );

    await controller.uninstall(
      const SelfManagedRuntimeUninstallRequest(
        cloudflareAccountLabel: 'acct-1',
        cloudflareAuthorizationMethod:
            SelfManagedCloudflareAuthorizationMethod.manual,
        cloudflareAccountId: 'acct-1',
      ),
    );

    expect(helperCalled, isFalse);
    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'missing_cloudflare_api_token');
    expect(await store.loadConnection(), _selfManagedConnection);
  });
}

const _selfManagedConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: CloudRuntimeRequiredCapabilities.all,
    vaultBinding: 'CF_D1_PRIMARY_VAULT',
    providerCostOwner: 'you (local key)',
  ),
);
