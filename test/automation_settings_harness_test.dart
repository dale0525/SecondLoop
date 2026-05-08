import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/dynamic_app_harness.dart';
import '../integration_test/support/dynamic_test_backend.dart';

void main() {
  testWidgets('signed in pro harness opens AI settings without setup warning',
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
    await harness.openAiSettings();

    expect(
      find.byKey(const ValueKey('ai_settings_ask_ai_setup_hint')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ai_settings_smart_organization_recommended_button'),
      ),
      findsOneWidget,
    );
  });
}
