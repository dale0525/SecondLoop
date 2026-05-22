import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/test_semantics_ids.dart';
import 'support/dynamic_app_harness.dart';
import 'support/dynamic_test_backend.dart';

void main() {
  testWidgets(
      'cloud runtime automation smoke keeps critical selectors reachable',
      (tester) async {
    final backend = DynamicTestBackend();
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
      cloudUid: 'runtime-user-1',
      cloudEmail: 'runtime@test.dev',
      cloudIdToken: 'runtime-test-token',
      cloudGatewayBaseUrl: 'https://cloud.test',
      subscriptionEntitled: true,
    );

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerInput)),
      findsOneWidget,
    );

    await harness.openSettings();
    await harness.openRuntimeModeSettings();

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeSelfManaged)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeManagedPro)),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeSelfManaged)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.selfManagedSetupRoot)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.selfManagedAuthorize)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.selfManagedDeploy)),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeManagedPro)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud_manage_subscription')),
        findsOneWidget);
  });
}
