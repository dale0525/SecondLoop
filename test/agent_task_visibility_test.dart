import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'conversation does not duplicate task cards at the top of the chat',
    (tester) async {
      final backend = _TaskVisibilityBackend([
        _todo(id: 'task_weekly', title: '完成周报'),
      ]);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_top_priorities_card')),
          findsNothing);
      expect(find.byKey(const ValueKey('agent_see_all_tasks')), findsNothing);
      expect(find.text('完成周报'), findsWidgets);
    },
  );

  testWidgets(
    'conversation shows a runtime-created task card below the assistant reply',
    (tester) async {
      final backend = _TaskVisibilityBackend(
        [
          _todo(
            id: 'task_weekly',
            title: '完成周报',
            sourceEntryId: 'm-user-1',
          ),
        ],
        initialMessages: [
          _message(
            id: 'm-user-1',
            role: 'user',
            content: '帮我创建一个任务：完成周报。',
            createdAtMs: 1,
          ),
          _message(
            id: 'm-assistant-1',
            role: 'assistant',
            content: '好的，已为您创建任务：完成周报。',
            createdAtMs: 2,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final assistantMarkdown =
          find.byKey(const ValueKey('agent_assistant_markdown_m-assistant-1'));
      final createdTaskCard =
          find.byKey(const ValueKey('agent_created_task_card_task_weekly'));

      expect(assistantMarkdown, findsOneWidget);
      expect(createdTaskCard, findsOneWidget);
      expect(
        tester.getTopLeft(createdTaskCard).dy,
        greaterThan(tester.getBottomLeft(assistantMarkdown).dy),
      );
    },
  );

  testWidgets(
    'created task card opens an agent task detail sheet',
    (tester) async {
      final backend = _TaskVisibilityBackend(
        [
          _todo(
            id: 'task_weekly',
            title: '完成周报',
            sourceEntryId: 'm-user-1',
          ),
        ],
        initialMessages: [
          _message(
            id: 'm-user-1',
            role: 'user',
            content: '帮我创建一个任务：完成周报。',
            createdAtMs: 1,
          ),
          _message(
            id: 'm-assistant-1',
            role: 'assistant',
            content: '好的，已为您创建任务：完成周报。',
            createdAtMs: 2,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('agent_open_task_task_weekly')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_task_detail_sheet')),
          findsOneWidget);
      expect(find.text('完成周报'), findsWidgets);
    },
  );

  testWidgets(
    'conversation glance opens the all tasks sheet',
    (tester) async {
      final backend = _TaskVisibilityBackend([
        _todo(id: 'task_weekly', title: '完成周报'),
      ]);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('agent_context_open_tasks')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_tasks_sheet')), findsOneWidget);
      expect(find.text('完成周报'), findsWidgets);
    },
  );

  testWidgets(
    'task list items open the agent task detail sheet',
    (tester) async {
      final backend = _TaskVisibilityBackend([
        _todo(id: 'task_weekly', title: '完成周报'),
      ]);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AgentConversationPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                  isTabActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('agent_context_open_tasks')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('agent_task_list_item_task_weekly')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_task_detail_sheet')),
          findsOneWidget);
      expect(find.text('完成周报'), findsWidgets);
    },
  );
}

Todo _todo({
  required String id,
  required String title,
  String status = 'open',
  int? dueAtMs,
  String? sourceEntryId,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs == null ? null : platformIntFromInt(dueAtMs),
    status: status,
    sourceEntryId: sourceEntryId,
    createdAtMs: platformIntFromInt(1000),
    updatedAtMs: platformIntFromInt(1000),
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
  );
}

Message _message({
  required String id,
  required String role,
  required String content,
  required int createdAtMs,
}) {
  return Message(
    id: id,
    conversationId: 'loop_home',
    role: role,
    content: content,
    createdAtMs: platformIntFromInt(createdAtMs),
    isMemory: true,
  );
}

final class _TaskVisibilityBackend extends TestAppBackend {
  _TaskVisibilityBackend(
    this.todos, {
    List<Message> initialMessages = const <Message>[],
  }) : super(initialMessages: initialMessages);

  final List<Todo> todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(todos);
}
