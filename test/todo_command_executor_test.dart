import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/todo_command_executor.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';

void main() {
  group('TodoCommandExecutor', () {
    test('reschedules existing todo and records undo metadata', () async {
      final backend = _TodoCommandBackend(
        _todo(id: 'todo:1', title: 'Submit invoice', dueAtMs: 100),
      );
      final executor = TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List(32),
      );

      final result = await executor.execute(
        const SecretaryTodoCommand(
          id: 'cmd-1',
          kind: SecretaryTodoCommandKind.reschedule,
          route: SecretaryTodoCommandRoute.local,
          confidence: 0.93,
          sourceMessageId: 'msg:1',
          targetTodoId: 'todo:1',
          dueAtMs: 200,
        ),
      );

      expect(result.applied, isTrue);
      expect(result.updatedTodo?.dueAtMs, 200);
      expect(result.undo.previousDueAtMs, 100);
      expect(result.changedFields, contains('due_at_ms'));
      expect(backend.transitionTodoCalls, 1);
    });

    test('sets status through status API and preserves previous status',
        () async {
      final backend = _TodoCommandBackend(
        _todo(id: 'todo:1', title: 'Submit invoice', status: 'open'),
      );
      final executor = TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List(32),
      );

      final result = await executor.execute(
        const SecretaryTodoCommand(
          id: 'cmd-2',
          kind: SecretaryTodoCommandKind.setStatus,
          route: SecretaryTodoCommandRoute.local,
          confidence: 0.93,
          sourceMessageId: 'msg:1',
          targetTodoId: 'todo:1',
          newStatus: 'done',
        ),
      );

      expect(result.applied, isTrue);
      expect(result.updatedTodo?.status, 'done');
      expect(result.undo.previousStatus, 'open');
      expect(result.changedFields, contains('status'));
      expect(backend.setTodoStatusCalls, 1);
    });

    test('reprioritizes using manual nudge fields', () async {
      final backend = _TodoCommandBackend(
        _todo(
          id: 'todo:1',
          title: 'Submit invoice',
          manualImportanceNudgeScore: 0,
          manualUrgencyNudgeScore: 0,
        ),
      );
      final executor = TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List(32),
      );

      final result = await executor.execute(
        const SecretaryTodoCommand(
          id: 'cmd-3',
          kind: SecretaryTodoCommandKind.reprioritize,
          route: SecretaryTodoCommandRoute.local,
          confidence: 0.93,
          sourceMessageId: 'msg:1',
          targetTodoId: 'todo:1',
          manualImportanceNudgeScore: 1,
          manualUrgencyNudgeScore: 1,
        ),
      );

      expect(result.applied, isTrue);
      expect(result.updatedTodo?.manualImportanceNudgeScore, 1);
      expect(result.updatedTodo?.manualUrgencyNudgeScore, 1);
      expect(result.undo.previousManualImportanceNudgeScore, 0);
      expect(result.undo.previousManualUrgencyNudgeScore, 0);
      expect(result.changedFields, contains('manual_importance_nudge_score'));
      expect(result.changedFields, contains('manual_urgency_nudge_score'));
    });

    test('does not auto-apply dismiss without explicit confirmation', () async {
      final backend = _TodoCommandBackend(
        _todo(id: 'todo:1', title: 'Submit invoice'),
      );
      final executor = TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List(32),
      );

      final result = await executor.execute(
        const SecretaryTodoCommand(
          id: 'cmd-4',
          kind: SecretaryTodoCommandKind.dismiss,
          route: SecretaryTodoCommandRoute.local,
          confidence: 0.93,
          sourceMessageId: 'msg:1',
          targetTodoId: 'todo:1',
        ),
      );

      expect(result.applied, isFalse);
      expect(result.rejectionReason, 'confirmation_required');
      expect(backend.current.status, 'open');
      expect(backend.setTodoStatusCalls, 0);
    });

    test('applies review title change only after explicit confirmation',
        () async {
      final backend = _TodoCommandBackend(
        _todo(id: 'todo:1', title: 'Submit invoice'),
      );
      final executor = TodoCommandExecutor(
        backend: backend,
        sessionKey: Uint8List(32),
      );

      final result = await executor.execute(
        const SecretaryTodoCommand(
          id: 'cmd-5',
          kind: SecretaryTodoCommandKind.updateTitle,
          route: SecretaryTodoCommandRoute.local,
          confidence: 0.93,
          sourceMessageId: 'msg:1',
          targetTodoId: 'todo:1',
          newTitle: 'Submit Stripe invoice',
        ),
        confirmed: true,
      );

      expect(result.applied, isTrue);
      expect(result.updatedTodo?.title, 'Submit Stripe invoice');
      expect(result.undo.previousTitle, 'Submit invoice');
      expect(result.changedFields, contains('title'));
      expect(backend.upsertTodoCalls, 1);
    });
  });
}

Todo _todo({
  required String id,
  required String title,
  int? dueAtMs,
  String status = 'open',
  int? manualImportanceNudgeScore,
  int? manualUrgencyNudgeScore,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs,
    status: status,
    sourceEntryId: null,
    createdAtMs: 10,
    updatedAtMs: 10,
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
    manualImportanceNudgeScore: manualImportanceNudgeScore ?? 0,
    manualUrgencyNudgeScore: manualUrgencyNudgeScore ?? 0,
  );
}

final class _TodoCommandBackend extends TestAppBackend {
  _TodoCommandBackend(this.current);

  Todo current;
  var upsertTodoCalls = 0;
  var setTodoStatusCalls = 0;
  var transitionTodoCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => <Todo>[current];

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    return current.id == todoId ? current : null;
  }

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
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    upsertTodoCalls += 1;
    current = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: current.createdAtMs,
      updatedAtMs: current.updatedAtMs + 1,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ?? 0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ?? 0,
    );
    return current;
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    setTodoStatusCalls += 1;
    current = Todo(
      id: current.id,
      title: current.title,
      dueAtMs: current.dueAtMs,
      status: newStatus,
      sourceEntryId: current.sourceEntryId,
      createdAtMs: current.createdAtMs,
      updatedAtMs: current.updatedAtMs + 1,
      reviewStage: current.reviewStage,
      nextReviewAtMs: current.nextReviewAtMs,
      lastReviewAtMs: current.lastReviewAtMs,
      manualImportanceNudgeScore: current.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: current.manualUrgencyNudgeScore,
    );
    return current;
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    transitionTodoCalls += 1;
    return upsertTodo(
      key,
      id: current.id,
      title: current.title,
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? current.dueAtMs),
      status: newStatus ?? current.status,
      sourceEntryId: current.sourceEntryId,
      reviewStage:
          clearReviewStage ? null : (reviewStage ?? current.reviewStage),
      nextReviewAtMs: clearNextReviewAtMs
          ? null
          : (nextReviewAtMs ?? current.nextReviewAtMs),
      lastReviewAtMs: clearLastReviewAtMs
          ? null
          : (lastReviewAtMs ?? current.lastReviewAtMs),
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? 0
          : (manualImportanceNudgeScore ??
              current.manualImportanceNudgeScore ??
              0),
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? 0
          : (manualUrgencyNudgeScore ?? current.manualUrgencyNudgeScore ?? 0),
    );
  }
}
