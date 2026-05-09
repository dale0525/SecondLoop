import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/settings/cloud_runtime_mode_page.dart';
import 'package:secondloop/features/settings/self_managed_setup_page.dart';

import '../../test_i18n.dart';
import '../../../test_helpers/test_semantics_ids.dart';

void main() {
  testWidgets('runtime mode page keeps stable automation ids', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: CloudRuntimeModePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModePageRoot)),
        findsOneWidget);
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

    await tester.tap(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.runtimeModeSelfManaged)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelfManagedSetupPage), findsOneWidget);
  });
}
