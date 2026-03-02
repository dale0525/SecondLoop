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

    expect(
      find.byKey(const ValueKey('chat_open_markdown_editor')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat_configure_ai')), findsNothing);
    expect(find.byKey(const ValueKey('chat_ask_ai')), findsNothing);

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

    expect(sendSize.width, lessThanOrEqualTo(64));
    expect(hasConfigure || hasAsk, isTrue);
    if (hasConfigure || hasAsk) {
      final aiActionSize = hasConfigure
          ? tester.getSize(configureFinder)
          : tester.getSize(askFinder);
      expect(aiActionSize.width, lessThanOrEqualTo(64));
    }

    expect(tester.takeException(), isNull);
  });
}
