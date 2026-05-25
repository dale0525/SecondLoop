import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/local_runtime_helper_process.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/self_managed_setup_controller.dart';
import 'package:secondloop/core/cloud/self_managed_setup_models.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_i18n.dart';
import '../../test_helpers/test_semantics_ids.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'self-managed setup scenario runs deploy and surfaces ready manifest',
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
              apiBaseUrl: 'https://self-managed-runtime.example/',
              authMode: CloudRuntimeAuthMode.runtimeToken,
              capabilities: [
                ...CloudRuntimeRequiredCapabilities.all,
                CloudRuntimeCapability('runtime_test_api'),
              ],
            ),
            authToken: 'runtime-test-token',
            capabilityManifestId: 'manifest-self-managed',
            verification: ModelCapabilityVerificationResult.allRequiredPassed,
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

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.selfManagedSetupRoot)),
      findsOneWidget,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_manual_toggle')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_cloudflare_account_id')),
      'acct-runtime-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_cloudflare_api_token')),
      'cf-runtime-session-token',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_verify_connection')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_api_key')),
      'sk-runtime-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_embedding_api_key')),
      'emb-runtime-test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_multimodal_api_key')),
      'mm-runtime-test',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_write_secrets')),
    );

    expect(find.text('https://self-managed-runtime.example/'), findsOneWidget);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
