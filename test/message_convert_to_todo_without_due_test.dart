import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/ui/sl_button.dart';

import 'message_actions_test_helpers.dart';
import 'test_backend.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Message can convert to todo without due as inbox',
      (tester) async {
    final backend = _Backend(
      messages: const [
        Message(
          id: 'm1',
          conversationId: 'chat_home',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_convert_todo')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message_convert_todo_no_due_m1')),
      findsOneWidget,
    );

    final noDueButton = tester.widget<SlButton>(
      find.byKey(const ValueKey('message_convert_todo_no_due_m1')),
    );
    expect(noDueButton.onPressed, isNotNull);
    noDueButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(backend.upsertedTodos, hasLength(1));
    final created = backend.upsertedTodos.single;
    expect(created.id, 'todo:m1');
    expect(created.status, 'inbox');
    expect(created.dueAtMs, isNull);
    expect(created.reviewStage, 0);
    expect(created.nextReviewAtMs, isNotNull);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Message> messages})
      : super(initialMessages: messages);

  final List<Todo> _todos = <Todo>[];
  final List<Todo> upsertedTodos = <Todo>[];

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
    final existing = _todos.where((t) => t.id == id).cast<Todo?>().firstOrNull;
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos.removeWhere((t) => t.id == id);
    _todos.add(todo);
    upsertedTodos.add(todo);
    return todo;
  }

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      const <TodoActivity>[];
}

extension<E> on Iterable<E> {
  E? get firstOrNull => this.isEmpty ? null : first;
}
