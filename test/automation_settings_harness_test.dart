import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/dynamic_app_harness.dart';
import '../integration_test/support/dynamic_test_backend.dart';

void main() {
  testWidgets('signed in pro harness opens runtime mode without AI setup entry',
      (tester) async {
    final backend = DynamicTestBackend();
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
      cloudUid: 'gd9s9Jc2n1PdN7o46An57KlXNnt1',
      cloudEmail: '812388447@qq.com',
      cloudIdToken: 'test-id-token',
      cloudGatewayBaseUrl: 'https://cloud.test',
      subscriptionEntitled: true,
    );

    await harness.openSettings();
    await harness.openRuntimeModeSettings();

    expect(
      find.byKey(const ValueKey('settings_ai_source')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('runtime_mode_managed_pro')),
      findsOneWidget,
    );
  });

  testWidgets('signed in pro harness opens cloud account manage subscription',
      (tester) async {
    final backend = DynamicTestBackend();
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
      cloudUid: 'gd9s9Jc2n1PdN7o46An57KlXNnt1',
      cloudEmail: '812388447@qq.com',
      cloudIdToken: 'test-id-token',
      cloudGatewayBaseUrl: 'https://cloud.test',
      subscriptionEntitled: true,
      canManageSubscription: true,
    );

    await harness.openSettings();
    await harness.openManagedProAccount();

    expect(find.byKey(const ValueKey('cloud_manage_subscription')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_subscribe')), findsNothing);
  });

  testWidgets('default harness opens runtime mode settings', (tester) async {
    final backend = DynamicTestBackend();
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    await harness.openSettings();
    await harness.openSelfManagedSetup();

    expect(
      find.byKey(const ValueKey('self_managed_deploy')),
      findsOneWidget,
    );
  });
}
