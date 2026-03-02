import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Compact mobile composer keeps usable input width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final backend = TestAppBackend();

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    await tester.tap(inputFinder);
    await tester.pump();

    await tester.enterText(inputFinder, 'hello from compact composer');
    await tester.pumpAndSettle();

    final inputSize = tester.getSize(inputFinder);
    expect(inputSize.width, greaterThanOrEqualTo(150));

    expect(
      find.byKey(const ValueKey('chat_open_markdown_editor')),
      findsOneWidget,
    );

    final sendSize = tester.getSize(find.byKey(const ValueKey('chat_send')));
    final configureFinder = find.byKey(const ValueKey('chat_configure_ai'));
    final askFinder = find.byKey(const ValueKey('chat_ask_ai'));
    final hasConfigure = configureFinder.evaluate().isNotEmpty;
    final hasAsk = askFinder.evaluate().isNotEmpty;
    final sendInkWellFinder = find.descendant(
      of: find.byKey(const ValueKey('chat_send')),
      matching: find.byType(InkWell),
    );

    expect(sendSize.width, lessThanOrEqualTo(64));
    expect(sendInkWellFinder, findsOneWidget);
    if (hasConfigure || hasAsk) {
      final aiActionSize = hasConfigure
          ? tester.getSize(configureFinder)
          : tester.getSize(askFinder);
      expect(aiActionSize.width, lessThanOrEqualTo(64));
      expect(tester.widget<InkWell>(sendInkWellFinder).onLongPress, isNull);
    } else {
      expect(
        tester.widget<InkWell>(sendInkWellFinder).onLongPress,
        isNotNull,
      );
    }

    expect(tester.takeException(), isNull);
  });
}
