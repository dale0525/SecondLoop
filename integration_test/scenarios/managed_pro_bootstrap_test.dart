import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/test_semantics_ids.dart';
import '../support/dynamic_app_harness.dart';
import '../support/dynamic_test_backend.dart';

void main() {
  testWidgets(
      'managed pro bootstrap scenario opens hosted runtime account surface',
      (tester) async {
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: DynamicTestBackend(),
      cloudUid: 'managed-user-1',
      cloudEmail: 'managed@example.com',
      cloudIdToken: 'managed-test-token',
      cloudGatewayBaseUrl: 'https://cloud.test',
      subscriptionEntitled: true,
      canManageSubscription: true,
    );

    await harness.openSettings();
    await harness.openRuntimeModeSettings();
    await tester.tap(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeManagedPro)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.cloudAccountPageRoot)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cloud_account_value_props')),
        findsOneWidget);
  });
}
