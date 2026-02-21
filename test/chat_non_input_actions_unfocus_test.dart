import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opening settings from app bar keeps chat input unfocused',
      (tester) async {
    await tester.pumpWidget(_wrapChat(backend: TestAppBackend()));
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    TextField input() => tester.widget<TextField>(inputFinder);

    await tester.tap(inputFinder);
    await tester.pump();
    expect(input().focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('chat_open_settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(input().focusNode?.hasFocus, isFalse);
  });

  testWidgets('opening tag filter sheet keeps chat input unfocused',
      (tester) async {
    await tester.pumpWidget(_wrapChat(backend: TestAppBackend()));
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    TextField input() => tester.widget<TextField>(inputFinder);

    await tester.tap(inputFinder);
    await tester.pump();
    expect(input().focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('chat_tag_filter_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(input().focusNode?.hasFocus, isFalse);
  });
}

Widget _wrapChat({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const ChatPage(
            conversation: Conversation(
              id: 'chat_home',
              title: 'Chat',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    ),
  );
}
