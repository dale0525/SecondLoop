import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/dynamic_app_harness.dart';
import '../../integration_test/support/dynamic_test_backend.dart';
import '../../test_helpers/test_semantics_ids.dart';

void main() {
  testWidgets('runtime mode selection scenario exposes both runtime modes',
      (tester) async {
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: DynamicTestBackend(),
    );

    await harness.openSettings();
    await harness.openRuntimeModeSettings();

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModePageRoot)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeSelfManaged)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeManagedPro)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeStatusTitle)),
      findsOneWidget,
    );
  });
}
