import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Desktop: Enter-to-send keeps input focused', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final backend = TestAppBackend();

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('chat_input'));
      await tester.tap(inputFinder);
      await tester.pumpAndSettle();

      var input = tester.widget<TextField>(inputFinder);
      expect(input.focusNode?.hasFocus, isTrue);

      await tester.enterText(inputFinder, 'hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      input = tester.widget<TextField>(inputFinder);
      expect(input.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
