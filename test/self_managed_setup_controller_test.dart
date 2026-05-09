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
              capabilities: [CloudRuntimeCapability('chat')],
            ),
            authToken: 'runtime-token-1',
            capabilityManifestId: 'manifest-self-1',
          );
        },
      ),
    );

    await controller.deploy(
      const SelfManagedSetupRequest(
        cloudflareAccountLabel: 'acct-1',
        provider: 'openai',
        apiKey: 'sk-test',
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.ready);
    expect(
        (await store.loadConnection())?.profile.authToken, 'runtime-token-1');
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
      ),
    );

    expect(controller.state.step, SelfManagedSetupStep.failed);
    expect(controller.state.errorCode, 'cloudflare_auth_failed');
  });
}
