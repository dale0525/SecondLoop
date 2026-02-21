import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Tapping send keeps chat input focused on mobile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = TestAppBackend();
    const conversation = Conversation(
      id: 'loop_home',
      title: 'Loop',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: ChatPage(conversation: conversation)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    await tester.tap(inputFinder);
    await tester.pump();

    await tester.enterText(inputFinder, 'Hello');
    await tester.pump();

    TextField input() => tester.widget<TextField>(inputFinder);
    expect(input().focusNode?.hasFocus, isTrue);

    final sendInkWellFinder = find.descendant(
      of: find.byKey(const ValueKey('chat_send')),
      matching: find.byType(InkWell),
    );
    expect(sendInkWellFinder, findsOneWidget);
    expect(tester.widget<InkWell>(sendInkWellFinder).canRequestFocus, isFalse);

    final askInkWellFinder = find.descendant(
      of: find.byKey(const ValueKey('chat_ask_ai')),
      matching: find.byType(InkWell),
    );
    expect(askInkWellFinder, findsOneWidget);
    expect(tester.widget<InkWell>(askInkWellFinder).canRequestFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pumpAndSettle();

    expect(input().focusNode?.hasFocus, isTrue);
  });
}
