import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/src/rust/db.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  testWidgets('Long-press actions show edit for AI answers', (tester) async {
    final backend = _AiAnswerEditableBackend(
      initialMessages: const [
        Message(
          id: 'm_ai',
          conversationId: 'loop_home',
          role: 'assistant',
          content: 'AI answer',
          createdAtMs: 1,
          isMemory: false,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('AI answer'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_action_edit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('edit_message_content')),
      'AI answer updated',
    );
    await tester.tap(find.byKey(const ValueKey('edit_message_save')));
    await tester.pumpAndSettle();

    expect(find.text('AI answer updated'), findsOneWidget);
    expect(backend.editedMessageIds, contains('m_ai'));
  });

  testWidgets('Desktop hover actions show edit for AI answers', (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _AiAnswerEditableBackend(
        initialMessages: const [
          Message(
            id: 'm_ai',
            conversationId: 'loop_home',
            role: 'assistant',
            content: 'AI answer',
            createdAtMs: 1,
            isMemory: false,
          ),
        ],
      );

      await tester.pumpWidget(wrapChatForTests(backend: backend));
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('message_bubble_m_ai'));
      expect(bubble, findsOneWidget);
      expect(find.byKey(const ValueKey('message_edit_m_ai')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(bubble));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('message_edit_m_ai')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Desktop context menu shows edit for AI answers', (tester) async {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _AiAnswerEditableBackend(
        initialMessages: const [
          Message(
            id: 'm_ai',
            conversationId: 'loop_home',
            role: 'assistant',
            content: 'AI answer',
            createdAtMs: 1,
            isMemory: false,
          ),
        ],
      );

      await tester.pumpWidget(wrapChatForTests(backend: backend));
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('message_bubble_m_ai'));
      final gesture = await tester.startGesture(
        tester.getCenter(bubble),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_context_edit')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });
}

final class _AiAnswerEditableBackend extends TestAppBackend {
  _AiAnswerEditableBackend({required super.initialMessages});

  final List<String> editedMessageIds = <String>[];

  @override
  Future<void> editMessage(
    Uint8List key,
    String messageId,
    String content,
  ) async {
    editedMessageIds.add(messageId);
    await super.editMessage(key, messageId, content);
  }
}
