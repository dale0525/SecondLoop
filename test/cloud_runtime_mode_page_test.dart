import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
import 'package:secondloop/features/settings/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('selecting self-managed opens the setup flow', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: CloudRuntimeModePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPageShell), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('runtime_mode_self_managed')));
    await tester.pumpAndSettle();

    expect(find.byType(SelfManagedSetupPage), findsOneWidget);
  });

  testWidgets('managed pro connection surfaces user-facing account status only',
      (tester) async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(
      const CloudRuntimeConnection(
        profile: CloudRuntimeProfile(
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://hosted-runtime.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          authToken: 'hosted-session-1',
          capabilityManifestId: 'manifest-managed-1',
          manifestVersion: 1,
        ),
        manifest: CloudRuntimeManifest(
          manifestVersion: 1,
          runtimeMode: CloudRuntimeMode.managedPro,
          apiBaseUrl: 'https://hosted-runtime.example/',
          authMode: CloudRuntimeAuthMode.hostedSession,
          capabilities: [CloudRuntimeCapability('chat')],
        ),
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudRuntimeModePage(connectionStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Managed Pro runtime connected'), findsOneWidget);
    expect(
        find.text('Use the hosted runtime without Cloudflare setup or BYOK.'),
        findsOneWidget);
    expect(find.text('https://hosted-runtime.example/'), findsNothing);
    expect(find.text('hosted_session'), findsNothing);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('runtime_mode_managed_pro')));
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPage), findsOneWidget);
  });

  testWidgets('self-managed connection opens setup with runtime management',
      (tester) async {
    final store = RuntimeConnectionStore();
    await store.saveConnection(_selfManagedConnection);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudRuntimeModePage(connectionStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Self-managed runtime connected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('runtime_mode_self_managed')));
    await tester.pumpAndSettle();

    expect(find.byType(SelfManagedSetupPage), findsOneWidget);
    expect(find.text('https://user-runtime.example/'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('self_managed_uninstall_runtime')),
      findsOneWidget,
    );
  });

  testWidgets('signed-in managed pro session is shown as connected',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: CloudAuthScope(
            controller: _FakeCloudAuthController(uid: 'managed-user-1'),
            gatewayConfig: CloudGatewayConfig(
              baseUrl: 'https://gateway.example/root/',
              modelName: 'cloud',
            ),
            child: CloudRuntimeModePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Managed Pro runtime connected'), findsOneWidget);
    expect(find.text('Managed Pro'), findsWidgets);
    expect(
        find.text('Use the hosted runtime without Cloudflare setup or BYOK.'),
        findsOneWidget);
    expect(find.text('Managed session'), findsNothing);
    expect(find.text('https://gateway.example/root/'), findsNothing);
    expect(find.text('hosted_session'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.text('Not configured'), findsNothing);
  });
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController({required this.uid});

  @override
  final String? uid;

  @override
  String? get email => 'qa@example.test';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'hosted-id-token-1';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
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
