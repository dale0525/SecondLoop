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
  testWidgets('Chat page shifts with keyboard instead of extra composer lift',
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
      wrapWithI18n(
        MaterialApp(
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                viewInsets: const EdgeInsets.only(bottom: 320),
              ),
              child: child!,
            );
          },
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(conversation: conversation),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.resizeToAvoidBottomInset, isTrue);

    final composerPaddingFinder = find.ancestor(
      of: find.byKey(const ValueKey('chat_input_ring')),
      matching: find.byType(AnimatedPadding),
    );
    expect(composerPaddingFinder, findsOneWidget);
    final composerPadding =
        tester.widget<AnimatedPadding>(composerPaddingFinder);
    expect(composerPadding.padding, const EdgeInsets.only(bottom: 0));
  });
}
