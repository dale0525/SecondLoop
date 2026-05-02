import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/secretary/memory_proposal_detector.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/secretary/chat_secretary_cards.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('pending memory proposal renders as assistant-side chat card',
      (tester) async {
    await tester.pumpWidget(
      _wrapWithBackend(
        TestAppBackend(
          initialMessages: const [
            Message(
              id: 'm1',
              conversationId: 'loop_home',
              role: 'user',
              content: 'Remember that I prefer morning meetings.',
              createdAtMs: 1,
              isMemory: true,
            ),
          ],
        ),
        const ChatPage(
          conversation: Conversation(
            id: 'loop_home',
            title: 'Loop',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(
        find.byKey(const ValueKey('secretary_memory_card_m1')), findsOneWidget);
    expect(find.text('Memory suggestion'), findsOneWidget);
    expect(find.byKey(const ValueKey('secretary_memory_accept_m1')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('secretary_memory_edit_m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('secretary_memory_ignore_m1')),
        findsOneWidget);
  });

  testWidgets('duplicate memory proposals show one concrete suggestion',
      (tester) async {
    await tester.pumpWidget(
      _wrapWithBackend(
        TestAppBackend(
          initialMessages: const [
            Message(
              id: 'm1',
              conversationId: 'loop_home',
              role: 'user',
              content: '我更喜欢上午处理重要任务。',
              createdAtMs: 1,
              isMemory: true,
            ),
            Message(
              id: 'm2',
              conversationId: 'loop_home',
              role: 'user',
              content: '我更喜欢上午处理重要任务。',
              createdAtMs: 2,
              isMemory: true,
            ),
            Message(
              id: 'm3',
              conversationId: 'loop_home',
              role: 'user',
              content: '我更喜欢上午处理重要任务。',
              createdAtMs: 3,
              isMemory: true,
            ),
          ],
        ),
        const ChatPage(
          conversation: Conversation(
            id: 'loop_home',
            title: 'Loop',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('secretary_memory_card_m3')), findsOneWidget);
    expect(find.text('我更喜欢上午处理重要任务'), findsWidgets);
    expect(find.textContaining('memory suggestions'), findsNothing);
  });

  testWidgets('single memory card can be accepted or ignored', (tester) async {
    final proposal = const MemoryProposalDetector().detect(
      messageId: 'm1',
      text: 'Remember that I prefer morning meetings.',
      createdAtMs: 1,
    )!;
    var accepted = false;
    var ignored = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryMemoryCard(
              proposal: proposal,
              onAccept: () => accepted = true,
              onEdit: () {},
              onIgnore: () => ignored = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('secretary_memory_accept_m1')));
    expect(accepted, isTrue);

    await tester.tap(find.byKey(const ValueKey('secretary_memory_ignore_m1')));
    expect(ignored, isTrue);
  });

  testWidgets('memory card localizes visible labels in zh-CN', (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
    final proposal = const MemoryProposalDetector().detect(
      messageId: 'm1',
      text: '我更喜欢上午处理重要任务。',
      createdAtMs: 1,
    )!;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: Scaffold(
            body: ChatSecretaryMemoryCard(
              proposal: proposal,
              onAccept: () {},
              onEdit: () {},
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('记忆建议'), findsOneWidget);
    expect(find.text('建议记住'), findsOneWidget);
    expect(find.text('接受'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('忽略'), findsOneWidget);
  });
}

Widget _wrapWithBackend(AppBackend backend, Widget child) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: child,
        ),
      ),
    ),
  );
}
