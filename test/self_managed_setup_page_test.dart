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
              capabilities: CloudRuntimeRequiredCapabilities.all,
              vaultBinding: 'CF_D1_PRIMARY_VAULT',
              providerCostOwner: 'you (local key)',
              skills: [
                CloudRuntimeSkillAvailability(
                  id: 'web-research',
                  status: 'ready',
                  provider: 'configured',
                ),
              ],
            ),
            authToken: 'runtime-token-1',
            capabilityManifestId: 'manifest-self-1',
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

    expect(find.text('Infrastructure Connection'), findsOneWidget);
    await _prepareManualCloudflareConnection(tester);
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
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_write_secrets')),
    );

    expect(find.text('https://user-runtime.example/'), findsOneWidget);
    expect(find.text('CF_D1_PRIMARY_VAULT'), findsOneWidget);
    expect(find.text('1/1 active'), findsOneWidget);
    expect(find.text('you (local key)'), findsOneWidget);
  });

  testWidgets('manual Cloudflare connection validates missing fields',
      (tester) async {
    await _pumpSelfManagedSetup(tester, SelfManagedSetupController());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_manual_toggle')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_verify_connection')),
    );

    expect(
      find.text(
          'Enter the Cloudflare account id before verifying manual setup.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('self_managed_cloudflare_account_id')),
      'acct-1',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_verify_connection')),
    );

    expect(
      find.text(
        'Enter a session-scoped Cloudflare API token before verifying manual setup.',
      ),
      findsOneWidget,
    );
    expect(find.text('Provider Secrets'), findsNothing);
  });

  testWidgets('OAuth action authorizes Cloudflare before provider secrets',
      (tester) async {
    var authorizationCalls = 0;
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        cloudflareAuthorizationRunner: (_, __) async {
          authorizationCalls += 1;
          return const SelfManagedCloudflareAuthorizationResult(
            cloudflareAccountId: 'acct-1',
            cloudflareAccountName: 'Personal Account',
            cloudflareUserEmail: 'user@example.test',
          );
        },
      ),
    );
    await _pumpSelfManagedSetup(tester, controller);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_cloudflare_oauth')),
    );

    expect(controller.state.step, SelfManagedSetupStep.cloudflareReady);
    expect(authorizationCalls, 1);
    expect(
      find.text(
        'Cloudflare authorization is ready. Fill Provider Secrets below, then write secrets to deploy and verify the runtime before metadata is saved.',
      ),
      findsOneWidget,
    );
    expect(find.text('Connect / Reconnect Cloudflare Account'), findsOneWidget);
    expect(find.text('Provider Secrets'), findsWidgets);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_verify_connection')),
    );

    expect(authorizationCalls, 1);
    expect(find.text('Provider Secrets'), findsWidgets);
  });

  testWidgets('side-effect verification failure blocks continue',
      (tester) async {
    final controller = SelfManagedSetupController(
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
            verification: _sideEffectDisciplineFailure,
          );
        },
      ),
    );

    await _pumpSelfManagedSetup(tester, controller);
    await _prepareManualCloudflareConnection(tester);
    await _fillRequiredProviderFields(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_write_secrets')),
    );

    expect(find.text('RETRY_REQUIRED'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('self_managed_capability_side_effect_discipline'),
      ),
      findsOneWidget,
    );
    expect(find.text('Provider Secrets'), findsWidgets);
  });

  testWidgets('ready runtime exposes confirmed uninstall action',
      (tester) async {
    var uninstallCalled = false;
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async => _readySetupResult,
        uninstallRunner: (request, onProgress) async {
          uninstallCalled = true;
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

    await _pumpSelfManagedSetup(tester, controller);
    await _prepareManualCloudflareConnection(tester);
    await _fillRequiredProviderFields(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_write_secrets')),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_uninstall_runtime')),
    );
    expect(
      find.byKey(const ValueKey('self_managed_confirm_uninstall_dialog')),
      findsOneWidget,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_confirm_uninstall')),
    );

    expect(uninstallCalled, isTrue);
    expect(controller.state.isUninstalled, isTrue);
    expect(
      find.text('Self-managed runtime connection removed.'),
      findsOneWidget,
    );
  });

  testWidgets('uninstall blocks missing manual Cloudflare token',
      (tester) async {
    var uninstallCalled = false;
    final controller = SelfManagedSetupController(
      helperProcess: LocalRuntimeHelperProcess(
        runner: (_, __) async => _readySetupResult,
        uninstallRunner: (_, __) async {
          uninstallCalled = true;
          throw const LocalRuntimeHelperException('unexpected', 'unexpected');
        },
      ),
    );

    await _pumpSelfManagedSetup(tester, controller);
    await _prepareManualCloudflareConnection(tester);
    await _fillRequiredProviderFields(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_write_secrets')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('self_managed_cloudflare_api_token')),
      '',
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_uninstall_runtime')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('self_managed_confirm_uninstall')),
    );

    expect(uninstallCalled, isFalse);
    expect(controller.state.errorCode, 'missing_cloudflare_api_token');
    expect(find.text('missing_cloudflare_api_token'), findsWidgets);
  });

  testWidgets(
      'screen layout renders across narrow, manifest, and desktop width',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(390, 900),
      Size(780, 1200),
      Size(1280, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpSelfManagedSetup(tester, SelfManagedSetupController());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('self_managed_setup_root')),
          findsOneWidget);
      expect(find.text('Infrastructure Connection'), findsOneWidget);
      expect(find.text('Cloudflare Integration Required'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('self_managed_cloudflare_oauth')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('self_managed_verify_connection')),
        findsOneWidget,
      );
    }
  });
}

Future<void> _pumpSelfManagedSetup(
  WidgetTester tester,
  SelfManagedSetupController controller,
) {
  return tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        home: SelfManagedSetupPage(controller: controller),
      ),
    ),
  );
}

Future<void> _fillRequiredProviderFields(WidgetTester tester) async {
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
}

Future<void> _prepareManualCloudflareConnection(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('self_managed_manual_toggle')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('self_managed_cloudflare_account_id')),
    'acct-1',
  );
  await tester.enterText(
    find.byKey(const ValueKey('self_managed_cloudflare_api_token')),
    'cf-session-token',
  );
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('self_managed_verify_connection')),
  );
  expect(find.text('Provider Secrets'), findsWidgets);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final center = tester.getCenter(finder);
  final rootSize = tester.binding.renderView.size;
  if (center.dx < 0 ||
      center.dy < 0 ||
      center.dx > rootSize.width ||
      center.dy > rootSize.height) {
    await tester.scrollUntilVisible(
      finder,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _sideEffectDisciplineFailure = ModelCapabilityVerificationResult(
  ok: false,
  checks: [
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.structuredOutput,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.secretaryMetadata,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.toolProposalDiscipline,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.multimodalUnderstanding,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.chineseIntentHandling,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.contextWindowLatency,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.clarificationBehavior,
      passed: true,
    ),
    ModelCapabilityCheckResult(
      code: ModelCapabilityRequiredChecks.sideEffectDiscipline,
      passed: false,
      failureCode: 'retry_required',
    ),
  ],
);

const _readySetupResult = SelfManagedSetupResult(
  manifest: CloudRuntimeManifest(
    manifestVersion: 1,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: CloudRuntimeRequiredCapabilities.all,
    vaultBinding: 'CF_D1_PRIMARY_VAULT',
    providerCostOwner: 'you (local key)',
    skills: [
      CloudRuntimeSkillAvailability(
        id: 'web-research',
        status: 'ready',
        provider: 'configured',
      ),
    ],
  ),
  authToken: 'runtime-token-1',
  capabilityManifestId: 'manifest-self-1',
  verification: ModelCapabilityVerificationResult.allRequiredPassed,
);
