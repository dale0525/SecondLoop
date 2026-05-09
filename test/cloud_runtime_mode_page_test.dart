import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';
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

    await tester.tap(find.byKey(const ValueKey('runtime_mode_self_managed')));
    await tester.pumpAndSettle();

    expect(find.byType(SelfManagedSetupPage), findsOneWidget);
  });

  testWidgets(
      'selecting managed pro surfaces hosted account and session details',
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

    expect(find.text('https://hosted-runtime.example/'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('runtime_mode_managed_pro')));
    await tester.pumpAndSettle();

    expect(find.byType(CloudAccountPage), findsOneWidget);
  });
}
