import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/self_managed_setup_controller.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('selecting deploy runs setup and surfaces ready state',
      (tester) async {
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, onProgress) async {
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
            verification: ModelCapabilityVerificationResult(
              ok: true,
              checks: [
                ModelCapabilityCheckResult(
                  code: 'structured_output',
                  passed: true,
                ),
              ],
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SelfManagedSetupPage(controller: controller),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('self_managed_cloudflare_account')),
      'acct-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_api_key')),
      'sk-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_embedding_api_key')),
      'emb-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_multimodal_api_key')),
      'mm-test',
    );
    await tester.tap(find.byKey(const ValueKey('self_managed_deploy')));
    await tester.pumpAndSettle();

    expect(find.text('https://user-runtime.example/'), findsOneWidget);
  });
}
