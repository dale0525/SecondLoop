import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('Unscheduled semantic-parse todos enter the review queue', () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _Backend();
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await store.upsertTodoFromMessage(
      messageId: 'm1',
      title: '修电视机',
      status: 'inbox',
      dueAtMs: null,
    );

    final args = backend.lastUpsertTodo;
    expect(args, isNotNull);
    expect(args!.id, 'todo:m1');
    expect(args.status, 'inbox');
    expect(args.dueAtMs, isNull);
    expect(args.reviewStage, 0);
    expect(args.nextReviewAtMs, isNotNull);
  });

  test('Scheduled semantic-parse todos do not enter the review queue',
      () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _Backend();
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await store.upsertTodoFromMessage(
      messageId: 'm2',
      title: '预约师傅修电视机',
      status: 'inbox',
      dueAtMs: 1,
    );

    final args = backend.lastUpsertTodo;
    expect(args, isNotNull);
    expect(args!.id, 'todo:m2');
    expect(args.status, 'open');
    expect(args.dueAtMs, 1);
    expect(args.reviewStage, isNull);
    expect(args.nextReviewAtMs, isNull);
  });

  test('Semantic-parse create reuses existing source todo id', () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _Backend(
      todos: const [
        Todo(
          id: 'legacy:todo:42',
          title: '旧任务标题',
          status: 'open',
          sourceEntryId: 'm3',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await store.upsertTodoFromMessage(
      messageId: 'm3',
      title: '新任务标题',
      status: 'open',
      dueAtMs: 123,
    );

    final args = backend.lastUpsertTodo;
    expect(args, isNotNull);
    expect(args!.id, 'legacy:todo:42');
    expect(args.sourceEntryId, 'm3');
  });
}

final class _Backend extends TestAppBackend {
  _Backend({List<Todo>? todos}) : _todos = List<Todo>.from(todos ?? const []);

  final List<Todo> _todos;
  _UpsertTodoArgs? lastUpsertTodo;

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
    lastUpsertTodo = _UpsertTodoArgs(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );

    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: PlatformInt64Util.from(0),
      updatedAtMs: PlatformInt64Util.from(0),
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
    );

    _todos.removeWhere((item) => item.id == id);
    _todos.add(todo);
    return todo;
  }
}

final class _UpsertTodoArgs {
  const _UpsertTodoArgs({
    required this.id,
    required this.title,
    required this.dueAtMs,
    required this.status,
    required this.sourceEntryId,
    required this.reviewStage,
    required this.nextReviewAtMs,
    required this.lastReviewAtMs,
  });

  final String id;
  final String title;
  final int? dueAtMs;
  final String status;
  final String? sourceEntryId;
  final int? reviewStage;
  final int? nextReviewAtMs;
  final int? lastReviewAtMs;
}
