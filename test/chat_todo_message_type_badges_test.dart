import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('create todo message shows marker and opens todo detail',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: '下午买牛奶',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: '买牛奶',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
          sourceEntryId: 'm1',
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm1': _job(
          messageId: 'm1',
          actionKind: 'create',
          todoId: 't1',
          todoTitle: '买牛奶',
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('message_todo_type_badge_m1')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('message_related_todo_root_m1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('message_todo_type_badge_m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets('followup todo message shows root quote and opens todo detail',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'user',
          content: '已经联系供应商了',
          createdAtMs: 2,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't2',
          title: '采购流程推进',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm2': _job(
          messageId: 'm2',
          actionKind: 'followup',
          todoId: 't2',
          todoTitle: '采购流程推进',
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('message_todo_type_badge_m2')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('message_related_todo_root_m2')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('message_related_todo_root_m2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets('todo badge does not block message long-press actions',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm3',
          conversationId: 'main_stream',
          role: 'user',
          content: '跟进采购进度',
          createdAtMs: 3,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't3',
          title: '采购流程推进',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
          sourceEntryId: 'm3',
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm3': _job(
          messageId: 'm3',
          actionKind: 'create',
          todoId: 't3',
          todoTitle: '采购流程推进',
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('message_todo_type_badge_m3')),
        findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('message_bubble_m3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('message_action_open_todo')),
      findsOneWidget,
    );
  });

  testWidgets('todo markers remain visible and clickable in dark theme',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm4',
          conversationId: 'main_stream',
          role: 'user',
          content: '已经联系供应商了',
          createdAtMs: 4,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't4',
          title: '采购流程推进',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm4': _job(
          messageId: 'm4',
          actionKind: 'followup',
          todoId: 't4',
          todoTitle: '采购流程推进',
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          locale: const Locale('zh', 'CN'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('message_todo_type_badge_m4')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('message_related_todo_root_m4')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message_todo_type_badge_m4')),
        matching: find.byType(Text),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message_related_todo_root_m4')),
        matching: find.byType(Text),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('message_todo_type_badge_m4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('message_related_todo_root_m4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets('english locale uses english todo marker labels', (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm5',
          conversationId: 'main_stream',
          role: 'user',
          content: 'buy milk',
          createdAtMs: 5,
          isMemory: true,
        ),
        Message(
          id: 'm6',
          conversationId: 'main_stream',
          role: 'user',
          content: 'vendor replied, continue this thread',
          createdAtMs: 6,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't5',
          title: 'Buy milk',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
          sourceEntryId: 'm5',
        ),
        Todo(
          id: 't6',
          title: 'Procurement follow-up',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm5': _job(
          messageId: 'm5',
          actionKind: 'create',
          todoId: 't5',
          todoTitle: 'Buy milk',
        ),
        'm6': _job(
          messageId: 'm6',
          actionKind: 'followup',
          todoId: 't6',
          todoTitle: 'Procurement follow-up',
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('en'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('message_todo_type_badge_m5')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('message_todo_type_badge_m6')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('message_related_todo_root_m6')),
      findsOneWidget,
    );
    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Related task'), findsOneWidget);
    expect(find.text('「Procurement follow-up」'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_todo_type_badge_m5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('message_related_todo_root_m6')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets(
    'linked todo messages still show markers without semantic jobs',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm7',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Submit invoice',
            createdAtMs: 7,
            isMemory: true,
          ),
          Message(
            id: 'm8',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Vendor confirmed delivery slot',
            createdAtMs: 8,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't7',
            title: 'Submit invoice',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
            sourceEntryId: 'm7',
          ),
          Todo(
            id: 't8',
            title: 'Vendor follow-up',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
        jobsByMessageId: const <String, SemanticParseJob>{},
        todoActivities: const [
          TodoActivity(
            id: 'a8',
            todoId: 't8',
            activityType: 'note',
            content: 'Vendor confirmed delivery slot',
            sourceMessageId: 'm8',
            createdAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            locale: const Locale('en'),
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'main_stream',
                    title: 'Main Stream',
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

      expect(find.byKey(const ValueKey('message_todo_type_badge_m7')),
          findsOneWidget);
      expect(find.text('Task'), findsOneWidget);

      expect(find.byKey(const ValueKey('message_todo_type_badge_m8')),
          findsOneWidget);
      expect(find.text('Related task'), findsOneWidget);
      expect(find.byKey(const ValueKey('message_related_todo_root_m8')),
          findsOneWidget);
      expect(find.text('「Vendor follow-up」'), findsOneWidget);
    },
  );
}

SemanticParseJob _job({
  required String messageId,
  required String actionKind,
  required String todoId,
  required String todoTitle,
}) {
  return SemanticParseJob(
    messageId: messageId,
    status: 'succeeded',
    attempts: PlatformInt64Util.from(1),
    nextRetryAtMs: null,
    lastError: null,
    appliedActionKind: actionKind,
    appliedTodoId: todoId,
    appliedTodoTitle: todoTitle,
    appliedPrevTodoStatus: null,
    undoneAtMs: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

final class _Backend extends TestAppBackend {
  _Backend({
    required super.initialMessages,
    required this.jobsByMessageId,
    required this.todos,
    this.todoActivities = const <TodoActivity>[],
  });

  final Map<String, SemanticParseJob> jobsByMessageId;
  final List<Todo> todos;
  final List<TodoActivity> todoActivities;

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    final jobs = <SemanticParseJob>[];
    for (final id in messageIds) {
      final job = jobsByMessageId[id];
      if (job != null) jobs.add(job);
    }
    return jobs;
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(todos);

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      List<TodoActivity>.from(todoActivities);
}
