import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

final class ChatTodoMessageTypeBadgesTestBackend extends TestAppBackend {
  ChatTodoMessageTypeBadgesTestBackend({
    required super.initialMessages,
    required Map<String, SemanticParseJob> jobsByMessageId,
    required List<Todo> todos,
    List<TodoActivity> todoActivities = const <TodoActivity>[],
  })  : _jobsByMessageId = Map<String, SemanticParseJob>.from(jobsByMessageId),
        _todos = List<Todo>.from(todos),
        _todoActivities = List<TodoActivity>.from(todoActivities);

  final Map<String, SemanticParseJob> _jobsByMessageId;
  final List<Todo> _todos;
  final List<TodoActivity> _todoActivities;
  final List<String> undoneSemanticJobMessageIds = <String>[];

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    final jobs = <SemanticParseJob>[];
    for (final id in messageIds) {
      final job = _jobsByMessageId[id];
      if (job != null) jobs.add(job);
    }
    return jobs;
  }

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
    Todo? existing;
    for (final todo in _todos) {
      if (todo.id == id) {
        existing = todo;
        break;
      }
    }
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
    _todos.removeWhere((item) => item.id == id);
    _todos.add(todo);
    return todo;
  }

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final existing = _jobsByMessageId[messageId];
    if (existing == null) return;
    _jobsByMessageId[messageId] = SemanticParseJob(
      messageId: existing.messageId,
      status: existing.status,
      attempts: existing.attempts,
      nextRetryAtMs: existing.nextRetryAtMs,
      lastError: existing.lastError,
      appliedActionKind: existing.appliedActionKind,
      appliedTodoId: existing.appliedTodoId,
      appliedTodoTitle: existing.appliedTodoTitle,
      appliedPrevTodoStatus: existing.appliedPrevTodoStatus,
      undoneAtMs: PlatformInt64Util.from(nowMs),
      createdAtMs: existing.createdAtMs,
      updatedAtMs: PlatformInt64Util.from(nowMs),
    );
    undoneSemanticJobMessageIds.add(messageId);
  }

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      List<TodoActivity>.from(_todoActivities);
}
