import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/src/rust/db.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Long press message actions do not focus chat input on mobile',
      (tester) async {
    final backend = TestAppBackend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final bubbleInkWellFinder = find.descendant(
      of: find.byKey(const ValueKey('message_bubble_m1')),
      matching: find.byType(InkWell),
    );
    expect(bubbleInkWellFinder, findsOneWidget);
    expect(
        tester.widget<InkWell>(bubbleInkWellFinder).canRequestFocus, isFalse);

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    TextField input() => tester.widget<TextField>(inputFinder);

    expect(input().focusNode?.hasFocus, isFalse);

    await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(input().focusNode?.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('message_action_copy')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsNothing);
    expect(input().focusNode?.hasFocus, isFalse);
  });
}
