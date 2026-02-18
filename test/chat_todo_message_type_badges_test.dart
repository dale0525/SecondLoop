import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'chat_todo_message_type_badges_test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
  });

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

  testWidgets('create todo message bubble tap opens todo detail',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm_bubble_open',
          conversationId: 'main_stream',
          role: 'user',
          content: '晚上收快递',
          createdAtMs: 10,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't_bubble_open',
          title: '收快递',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
          sourceEntryId: 'm_bubble_open',
        ),
      ],
      jobsByMessageId: <String, SemanticParseJob>{
        'm_bubble_open': _job(
          messageId: 'm_bubble_open',
          actionKind: 'create',
          todoId: 't_bubble_open',
          todoTitle: '收快递',
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

    await tester
        .tap(find.byKey(const ValueKey('message_bubble_m_bubble_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets(
    'returning from todo detail via badge keeps chat input unfocused',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm_focus_badge',
            conversationId: 'main_stream',
            role: 'user',
            content: '查看事项详情',
            createdAtMs: 11,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't_focus_badge',
            title: '查看事项详情',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
            sourceEntryId: 'm_focus_badge',
          ),
        ],
        jobsByMessageId: <String, SemanticParseJob>{
          'm_focus_badge': _job(
            messageId: 'm_focus_badge',
            actionKind: 'create',
            todoId: 't_focus_badge',
            todoTitle: '查看事项详情',
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

      final inputFinder = find.byKey(const ValueKey('chat_input'));
      TextField input() => tester.widget<TextField>(inputFinder);

      await tester.tap(inputFinder);
      await tester.pump();
      expect(input().focusNode?.hasFocus, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('message_todo_type_badge_m_focus_badge')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_detail_header')), findsNothing);
      expect(input().focusNode?.hasFocus, isFalse);
    },
  );

  testWidgets(
    'returning from todo detail via message action keeps input unfocused',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm_focus_action',
            conversationId: 'main_stream',
            role: 'user',
            content: '打开事项详情',
            createdAtMs: 12,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't_focus_action',
            title: '打开事项详情',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
            sourceEntryId: 'm_focus_action',
          ),
        ],
        jobsByMessageId: const <String, SemanticParseJob>{},
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

      final inputFinder = find.byKey(const ValueKey('chat_input'));
      TextField input() => tester.widget<TextField>(inputFinder);

      await tester.tap(inputFinder);
      await tester.pump();
      expect(input().focusNode?.hasFocus, isTrue);

      await tester.longPress(
        find.byKey(const ValueKey('message_bubble_m_focus_action')),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('message_action_open_todo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo_detail_header')), findsNothing);
      expect(input().focusNode?.hasFocus, isFalse);
    },
  );

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
    'linked related todo badge wins over stale semantic create job',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm9',
            conversationId: 'main_stream',
            role: 'user',
            content: '更新了任务内容',
            createdAtMs: 9,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't9_old',
            title: '旧任务',
            status: 'dismissed',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
          Todo(
            id: 't9_new',
            title: '新任务',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
        jobsByMessageId: <String, SemanticParseJob>{
          'm9': _job(
            messageId: 'm9',
            actionKind: 'create',
            todoId: 't9_old',
            todoTitle: '旧任务',
          ),
        },
        todoActivities: const [
          TodoActivity(
            id: 'a9',
            todoId: 't9_new',
            activityType: 'note',
            content: '更新了任务内容',
            sourceMessageId: 'm9',
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

      expect(find.byKey(const ValueKey('message_todo_type_badge_m9')),
          findsOneWidget);
      expect(find.text('Related task'), findsOneWidget);
      expect(find.text('Task'), findsNothing);
      expect(find.byKey(const ValueKey('message_related_todo_root_m9')),
          findsOneWidget);
      expect(find.text('「新任务」'), findsOneWidget);
    },
  );

  testWidgets(
    'convert todo to info clears marker even with semantic create history',
    (tester) async {
      final backend = _Backend(
        initialMessages: const [
          Message(
            id: 'm10',
            conversationId: 'main_stream',
            role: 'user',
            content: 'Call supplier',
            createdAtMs: 10,
            isMemory: true,
          ),
        ],
        todos: const [
          Todo(
            id: 't10',
            title: 'Call supplier',
            status: 'open',
            createdAtMs: 0,
            updatedAtMs: 0,
            sourceEntryId: 'm10',
          ),
        ],
        jobsByMessageId: <String, SemanticParseJob>{
          'm10': _job(
            messageId: 'm10',
            actionKind: 'create',
            todoId: 't10',
            todoTitle: 'Call supplier',
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

      expect(find.byKey(const ValueKey('message_todo_type_badge_m10')),
          findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('message_bubble_m10')));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('message_action_convert_to_info')));
      await tester.pumpAndSettle();

      expect(find.text('Convert to note?'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('message_todo_type_badge_m10')),
        findsNothing,
      );
      expect(
        backend.undoneSemanticJobMessageIds,
        contains('m10'),
      );
    },
  );

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

typedef _Backend = ChatTodoMessageTypeBadgesTestBackend;
