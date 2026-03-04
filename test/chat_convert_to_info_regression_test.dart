import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/src/rust/db.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  testWidgets('convert linked note to info creates detached todo before move',
      (tester) async {
    final backend = _ConvertToInfoBackend(
      requireMoveTargetTodoExists: true,
      messages: const [
        Message(
          id: 'm2',
          conversationId: 'loop_home',
          role: 'user',
          content: 'note',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task A',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      activities: const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          sourceMessageId: 'm2',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('note'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('message_action_convert_to_info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(
      backend.movedActivityOps,
      contains((activityId: 'a1', toTodoId: 'todo:_detached_message_link:m2')),
    );
    expect(
      backend.upsertedTodos.any((todo) =>
          todo.id == 'todo:_detached_message_link:m2' &&
          todo.status == 'dismissed'),
      isTrue,
    );

    final activities = await backend.listTodoActivitiesInRange(
      Uint8List(0),
      startAtMsInclusive: 0,
      endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
    );
    expect(
      activities.any((a) => a.todoId == 't1' && a.sourceMessageId == 'm2'),
      isFalse,
    );
  });

  testWidgets('convert source-entry to info dismisses all source todos',
      (tester) async {
    final backend = _ConvertToInfoBackend(
      messages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'user',
          content: 'weekly planning',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Planning #1',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't2',
          title: 'Planning #2',
          status: 'inbox',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('weekly planning'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('message_action_convert_to_info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final t1 = backend.todos.firstWhere((todo) => todo.id == 't1');
    final t2 = backend.todos.firstWhere((todo) => todo.id == 't2');
    expect(t1.status, 'dismissed');
    expect(t2.status, 'dismissed');
    expect(t1.sourceEntryId, isNull);
    expect(t2.sourceEntryId, isNull);
  });

  testWidgets('desktop right click convert to info detaches linked note',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final backend = _ConvertToInfoBackend(
      requireMoveTargetTodoExists: true,
      messages: const [
        Message(
          id: 'm2',
          conversationId: 'loop_home',
          role: 'user',
          content: 'note',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task A',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      activities: const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          sourceMessageId: 'm2',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final pos = tester.getCenter(find.text('note'));
    final gesture = await tester.startGesture(
      pos,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message_context_convert_to_info')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('message_context_convert_to_info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(
      backend.movedActivityOps,
      contains((activityId: 'a1', toTodoId: 'todo:_detached_message_link:m2')),
    );

    debugDefaultTargetPlatformOverride = null;
  });
}

final class _ConvertToInfoBackend extends TestAppBackend {
  _ConvertToInfoBackend({
    required List<Message> messages,
    required List<Todo> todos,
    List<TodoActivity> activities = const <TodoActivity>[],
    this.requireMoveTargetTodoExists = false,
  })  : _todos = List<Todo>.from(todos),
        _activities = List<TodoActivity>.from(activities),
        super(initialMessages: messages);

  final bool requireMoveTargetTodoExists;
  final List<Todo> _todos;
  final List<TodoActivity> _activities;
  final List<Todo> upsertedTodos = <Todo>[];
  final List<({String activityId, String toTodoId})> movedActivityOps = [];

  List<Todo> get todos => List<Todo>.from(_todos);

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final existingIndex = _todos.indexWhere((todo) => todo.id == id);
    final createdAtMs =
        existingIndex >= 0 ? _todos[existingIndex].createdAtMs : nowMs;
    final updated = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: createdAtMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    if (existingIndex >= 0) {
      _todos[existingIndex] = updated;
    } else {
      _todos.add(updated);
    }
    upsertedTodos.add(updated);
    return updated;
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      _activities
          .where((activity) => activity.todoId == todoId)
          .toList(growable: false);

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      List<TodoActivity>.from(_activities);

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    if (requireMoveTargetTodoExists &&
        !_todos.any((todo) => todo.id == toTodoId)) {
      throw StateError('todo_not_found:$toTodoId');
    }
    final index =
        _activities.indexWhere((activity) => activity.id == activityId);
    if (index < 0) {
      throw StateError('activity_not_found:$activityId');
    }
    final existing = _activities[index];
    final moved = TodoActivity(
      id: existing.id,
      todoId: toTodoId,
      activityType: existing.activityType,
      fromStatus: existing.fromStatus,
      toStatus: existing.toStatus,
      content: existing.content,
      sourceMessageId: existing.sourceMessageId,
      createdAtMs: existing.createdAtMs,
    );
    _activities[index] = moved;
    movedActivityOps.add((activityId: activityId, toTodoId: toTodoId));
    return moved;
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async =>
      const <SemanticParseJob>[];

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {}
}
