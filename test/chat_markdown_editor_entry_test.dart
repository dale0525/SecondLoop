import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_icon_button.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Chat composer opens markdown editor and sends on save',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = TestAppBackend();

    await tester.pumpWidget(_wrapChat(backend: backend));
    await tester.pumpAndSettle();

    const inputKey = ValueKey('chat_input');
    const editorOpenKey = ValueKey('chat_open_markdown_editor');
    const editorPageKey = ValueKey('chat_markdown_editor_page');
    const editorInputKey = ValueKey('chat_markdown_editor_input');
    const editorPreviewKey = ValueKey('chat_markdown_editor_preview');
    const editorSaveKey = ValueKey('chat_markdown_editor_save');

    expect(find.byKey(editorOpenKey), findsNothing);

    await tester.tap(find.byKey(inputKey));
    await tester.pumpAndSettle();

    expect(find.byKey(editorOpenKey), findsOneWidget);
    expect(tester.widget<SlIconButton>(find.byKey(editorOpenKey)), isNotNull);

    await tester.tap(find.byKey(editorOpenKey));
    await tester.pumpAndSettle();

    expect(find.byKey(editorPageKey), findsOneWidget);
    expect(find.byKey(editorInputKey), findsOneWidget);
    expect(find.byKey(editorPreviewKey), findsOneWidget);

    await tester.enterText(find.byKey(editorInputKey), '## Updated\n\n- item');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(editorSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(editorPageKey), findsNothing);

    final input = tester.widget<TextField>(find.byKey(inputKey));
    expect(input.controller?.text, isEmpty);

    final sentMessages = await backend.listMessages(
      Uint8List.fromList(List<int>.filled(32, 1)),
      'chat_home',
    );
    expect(sentMessages, hasLength(1));
    expect(sentMessages.single.content, '## Updated\n\n- item');
  });

  testWidgets('Desktop composer also exposes markdown editor entry',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});

    try {
      await tester.pumpWidget(_wrapChat(backend: TestAppBackend()));
      await tester.pumpAndSettle();

      final inputKey = find.byKey(const ValueKey('chat_input'));
      expect(find.byKey(const ValueKey('chat_open_markdown_editor')),
          findsNothing);

      await tester.tap(inputKey);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat_open_markdown_editor')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
