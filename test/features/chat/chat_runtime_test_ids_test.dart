import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/dynamic_app_harness.dart';
import '../../../integration_test/support/dynamic_test_backend.dart';
import '../../../test_helpers/test_semantics_ids.dart';

void main() {
  testWidgets('chat runtime automation keeps stable composer ids',
      (tester) async {
    final backend = DynamicTestBackend();
    await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerInput)),
      findsOneWidget,
    );
    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerSend)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerSend)),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerInput)),
      'trigger send button',
    );
    await tester.pump();

    expect(
      find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerSend)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(TestSemanticsIds.key(TestSemanticsIds.chatComposerSend)),
          )
          .onPressed,
      isNotNull,
    );
  });
}
