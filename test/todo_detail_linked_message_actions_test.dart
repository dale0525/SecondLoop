import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage long press linked message shows actions + edit',
      (tester) async {
    final backend = _Backend();

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
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.text('before', findRichText: true), findsOneWidget);

    await tester.longPress(find.text('before', findRichText: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('message_action_link_todo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.byKey(const ValueKey('chat_markdown_editor_page')), findsNothing);
    expect(find.byKey(const ValueKey('chat_markdown_editor_switch_markdown')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('chat_markdown_editor_switch_markdown')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_preview')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('chat_markdown_editor_switch_plain')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.byKey(const ValueKey('chat_markdown_editor_page')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('edit_message_content')),
      'after',
    );
    await tester.tap(find.byKey(const ValueKey('edit_message_save')));
    await tester.pumpAndSettle();

    expect(find.text('after'), findsOneWidget);
    expect(find.text('before', findRichText: true), findsNothing);
    expect(backend.editedMessageIds, contains('m1'));
  });

  testWidgets('TodoDetailPage long message edit defaults to markdown mode',
      (tester) async {
    final longContent = List<String>.filled(
      8,
      'TODO_LONG_MARKER content that should default to markdown editor mode.',
    ).join('\n');
    final backend = _Backend(messageContent: longContent);

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
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.longPress(
      find.textContaining('TODO_LONG_MARKER', findRichText: true).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_preview')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_switch_plain')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_markdown_editor_switch_markdown')),
        findsNothing);
  });

  testWidgets('TodoDetailPage can relink linked message to another todo',
      (tester) async {
    final backend = _Backend();

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
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.longPress(find.text('before'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    expect(backend.movedTodoActivityIds, contains('a1'));
    expect(backend.movedTodoActivityToTodoIds, contains('t2'));
    expect(backend.appendedTodoNoteTodoIds, isEmpty);
  });

  testWidgets(
      'TodoDetailPage relink moves activity between todos without duplicates',
      (tester) async {
    final backend = _RelinkBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

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
              sessionKey: key,
              lock: () {},
              child: const TodoDetailPage(
                key: ValueKey('todo_detail_t1'),
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.text('before', findRichText: true), findsOneWidget);

    await tester.longPress(find.text('before', findRichText: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    expect(find.text('before', findRichText: true), findsNothing);
    final movedActivities = await backend.listTodoActivities(key, 't2');
    expect(movedActivities, hasLength(1));
    expect(movedActivities.single.sourceMessageId, 'm1');
    expect(movedActivities.single.content, 'before');

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
              sessionKey: key,
              lock: () {},
              child: const TodoDetailPage(
                key: ValueKey('todo_detail_t2'),
                initialTodo: Todo(
                  id: 't2',
                  title: 'Other',
                  status: 'open',
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

    expect(find.text('before', findRichText: true), findsOneWidget);

    await tester.longPress(find.text('before', findRichText: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('todo_note_link_sheet')),
            matching: find.text('Task'),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('before', findRichText: true), findsNothing);

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
              sessionKey: key,
              lock: () {},
              child: const TodoDetailPage(
                key: ValueKey('todo_detail_t1_again'),
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.text('before', findRichText: true), findsOneWidget);
  });

  testWidgets('TodoDetailPage right click linked message opens context menu',
      (tester) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      final backend = _Backend();

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
                child: const TodoDetailPage(
                  initialTodo: Todo(
                    id: 't1',
                    title: 'Task',
                    status: 'open',
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

      final pos = tester.getCenter(find.text('before'));
      final gesture = await tester.startGesture(
        pos,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_context_copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_context_link_todo')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('message_context_delete')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  });

  testWidgets(
      'TodoDetailPage deleting a linked item does not delete the root todo',
      (tester) async {
    final backend = _DeleteLinkedMessageBackend();

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
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.text('before'), findsOneWidget);

    await tester.longPress(find.text('before'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_delete')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('todo_detail_delete_message_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('before'), findsNothing);
    expect(backend.deletedMessageIds, contains('m1'));
    expect(backend.deletedTodoIds, isEmpty);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({String messageContent = 'before'})
      : super(
          initialMessages: [
            Message(
              id: 'm1',
              conversationId: 'main_stream',
              role: 'user',
              content: messageContent,
              createdAtMs: 0,
              isMemory: true,
            ),
          ],
        );

  final List<String> editedMessageIds = [];
  final List<String> appendedTodoNoteTodoIds = [];
  final List<String?> appendedTodoNoteSourceMessageIds = [];
  final List<String> movedTodoActivityIds = [];
  final List<String> movedTodoActivityToTodoIds = [];

  @override
  Future<void> editMessage(
    Uint8List key,
    String messageId,
    String content,
  ) async {
    editedMessageIds.add(messageId);
    return super.editMessage(key, messageId, content);
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't2',
          title: 'Other',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    appendedTodoNoteTodoIds.add(todoId);
    appendedTodoNoteSourceMessageIds.add(sourceMessageId);
    return TodoActivity(
      id: 'a_new',
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: sourceMessageId,
      createdAtMs: 0,
    );
  }

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    movedTodoActivityIds.add(activityId);
    movedTodoActivityToTodoIds.add(toTodoId);
    return TodoActivity(
      id: activityId,
      todoId: toTodoId,
      activityType: 'note',
      content: 'before',
      sourceMessageId: 'm1',
      createdAtMs: 0,
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          content: 'before',
          sourceMessageId: 'm1',
          createdAtMs: 0,
        ),
      ];

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      listTodoActivities(key, 't1');

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];
}

final class _RelinkBackend extends TestAppBackend {
  _RelinkBackend()
      : super(
          initialMessages: const [
            Message(
              id: 'm1',
              conversationId: 'main_stream',
              role: 'user',
              content: 'before',
              createdAtMs: 0,
              isMemory: true,
            ),
          ],
        );

  int _nextActivityIndex = 2;
  final Map<String, List<TodoActivity>> _activitiesByTodoId = {
    't1': [
      const TodoActivity(
        id: 'a1',
        todoId: 't1',
        activityType: 'note',
        content: 'before',
        sourceMessageId: 'm1',
        createdAtMs: 0,
      ),
    ],
    't2': <TodoActivity>[],
  };

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't2',
          title: 'Other',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoActivity>.from(_activitiesByTodoId[todoId] ?? const []);

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    final merged = <TodoActivity>[];
    for (final list in _activitiesByTodoId.values) {
      merged.addAll(list);
    }
    return merged;
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    final nextId = 'a${_nextActivityIndex++}';
    final activity = TodoActivity(
      id: nextId,
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: sourceMessageId,
      createdAtMs: 0,
    );
    final updated = List<TodoActivity>.from(_activitiesByTodoId[todoId] ?? []);
    updated.add(activity);
    _activitiesByTodoId[todoId] = updated;
    return activity;
  }

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    TodoActivity? existing;
    for (final entry in _activitiesByTodoId.entries) {
      final list = entry.value;
      final index = list.indexWhere((a) => a.id == activityId);
      if (index == -1) continue;
      existing = list.removeAt(index);
      break;
    }

    final moved = TodoActivity(
      id: activityId,
      todoId: toTodoId,
      activityType: existing?.activityType ?? 'note',
      content: existing?.content,
      sourceMessageId: existing?.sourceMessageId,
      createdAtMs: existing?.createdAtMs ?? 0,
    );
    _activitiesByTodoId
        .putIfAbsent(toTodoId, () => <TodoActivity>[])
        .add(moved);
    return moved;
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];
}

final class _DeleteLinkedMessageBackend extends TestAppBackend {
  _DeleteLinkedMessageBackend()
      : super(
          initialMessages: const [
            Message(
              id: 'm1',
              conversationId: 'main_stream',
              role: 'user',
              content: 'before',
              createdAtMs: 0,
              isMemory: true,
            ),
          ],
        );

  final List<String> deletedTodoIds = [];
  final List<String> deletedMessageIds = [];
  final Set<String> _deletedMessages = {};

  final List<TodoActivity> _activities = [
    const TodoActivity(
      id: 'a1',
      todoId: 't1',
      activityType: 'note',
      content: 'before',
      sourceMessageId: 'm1',
      createdAtMs: 0,
    ),
  ];

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ];

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    deletedTodoIds.add(todoId);
  }

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async {
    if (isDeleted) {
      deletedMessageIds.add(messageId);
      _deletedMessages.add(messageId);
    }
    return super.setMessageDeleted(key, messageId, isDeleted);
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      _activities
          .where((a) =>
              a.todoId == todoId &&
              (a.sourceMessageId == null ||
                  !_deletedMessages.contains(a.sourceMessageId)))
          .toList(growable: false);

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      listTodoActivities(key, 't1');

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];
}
