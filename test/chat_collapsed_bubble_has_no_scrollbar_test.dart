import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Collapsed chat bubble disables scrollbars', (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final longText = List<String>.generate(20, (i) => 'Line $i').join('\n');

      final backend = TestAppBackend(
        initialMessages: [
          Message(
            id: 'm1',
            conversationId: 'chat_home',
            role: 'user',
            content: longText,
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              splashFactory: InkRipple.splashFactory,
            ),
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
        ),
      );

      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('message_bubble_m1'));
      expect(bubble, findsOneWidget);

      expect(
        find.byKey(const ValueKey('message_view_full_m1')),
        findsOneWidget,
      );

      final bubbleInkWell = find.descendant(
        of: bubble,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is InkWell &&
              widget.borderRadius == BorderRadius.circular(18),
        ),
      );
      expect(bubbleInkWell, findsOneWidget);

      final inkWellWidget = tester.widget<InkWell>(bubbleInkWell);
      expect(inkWellWidget.onTap, isNull);

      final innerScrollView = find.descendant(
        of: bubble,
        matching: find.byType(SingleChildScrollView),
      );
      expect(innerScrollView, findsWidgets);

      final innerContext = tester.element(innerScrollView.first);
      final behavior = ScrollConfiguration.of(innerContext);

      const dummy = SizedBox.shrink();
      final controller = ScrollController();
      addTearDown(controller.dispose);

      final built = behavior.buildScrollbar(
        innerContext,
        dummy,
        ScrollableDetails.vertical(controller: controller),
      );

      expect(identical(built, dummy), isTrue);

      expect(
        find.descendant(of: bubble, matching: find.byType(RawScrollbar)),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}
