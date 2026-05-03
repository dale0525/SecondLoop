import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import '../backend/app_backend.dart';
import 'todo_command_models.dart';
import 'todo_command_risk_policy.dart';

final class SecretaryTodoCommandUndoSnapshot {
  const SecretaryTodoCommandUndoSnapshot({
    this.previousTitle,
    this.previousStatus,
    this.previousDueAtMs,
    this.previousManualImportanceNudgeScore,
    this.previousManualUrgencyNudgeScore,
  });

  factory SecretaryTodoCommandUndoSnapshot.fromTodo(Todo todo) {
    return SecretaryTodoCommandUndoSnapshot(
      previousTitle: todo.title,
      previousStatus: todo.status,
      previousDueAtMs: platformIntToNullableInt(todo.dueAtMs),
      previousManualImportanceNudgeScore:
          platformIntToNullableInt(todo.manualImportanceNudgeScore) ?? 0,
      previousManualUrgencyNudgeScore:
          platformIntToNullableInt(todo.manualUrgencyNudgeScore) ?? 0,
    );
  }

  final String? previousTitle;
  final String? previousStatus;
  final int? previousDueAtMs;
  final int? previousManualImportanceNudgeScore;
  final int? previousManualUrgencyNudgeScore;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'previous_title': previousTitle,
      'previous_status': previousStatus,
      'previous_due_at_ms': previousDueAtMs,
      'previous_manual_importance_nudge_score':
          previousManualImportanceNudgeScore,
      'previous_manual_urgency_nudge_score': previousManualUrgencyNudgeScore,
    };
  }
}

final class SecretaryTodoCommandExecutionResult {
  const SecretaryTodoCommandExecutionResult({
    required this.command,
    required this.applied,
    required this.changedFields,
    required this.undo,
    this.updatedTodo,
    this.rejectionReason,
  });

  factory SecretaryTodoCommandExecutionResult.rejected({
    required SecretaryTodoCommand command,
    required String reason,
    SecretaryTodoCommandUndoSnapshot undo =
        const SecretaryTodoCommandUndoSnapshot(),
  }) {
    return SecretaryTodoCommandExecutionResult(
      command: command,
      applied: false,
      changedFields: const <String>[],
      undo: undo,
      rejectionReason: reason,
    );
  }

  final SecretaryTodoCommand command;
  final bool applied;
  final List<String> changedFields;
  final SecretaryTodoCommandUndoSnapshot undo;
  final Todo? updatedTodo;
  final String? rejectionReason;

  String get appliedActionKind => applied
      ? 'todo_command:${todoCommandKindWireValue(command.kind)}'
      : 'none';

  String toAuditOutputJson() {
    return jsonEncode(<String, Object?>{
      'applied': applied,
      'applied_action_kind': appliedActionKind,
      'todo_id': command.targetTodoId,
      'updated_title': updatedTodo?.title,
      'updated_status': updatedTodo?.status,
      'updated_due_at_ms': platformIntToNullableInt(updatedTodo?.dueAtMs),
      'updated_manual_importance_nudge_score':
          platformIntToNullableInt(updatedTodo?.manualImportanceNudgeScore),
      'updated_manual_urgency_nudge_score':
          platformIntToNullableInt(updatedTodo?.manualUrgencyNudgeScore),
      'changed_fields': changedFields,
      'undo': undo.toJson(),
      'rejection_reason': rejectionReason,
    });
  }
}

final class TodoCommandExecutor {
  const TodoCommandExecutor({
    required AppBackend backend,
    required Uint8List sessionKey,
    SecretaryTodoCommandRiskPolicy riskPolicy =
        const SecretaryTodoCommandRiskPolicy(),
  })  : _backend = backend,
        _sessionKey = sessionKey,
        _riskPolicy = riskPolicy;

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final SecretaryTodoCommandRiskPolicy _riskPolicy;

  Future<SecretaryTodoCommandExecutionResult> execute(
    SecretaryTodoCommand command, {
    bool confirmed = false,
  }) async {
    final risk = _riskPolicy.classify(command);
    if (risk == SecretaryTodoCommandRisk.reject) {
      return SecretaryTodoCommandExecutionResult.rejected(
        command: command,
        reason: 'rejected',
      );
    }
    if (!confirmed &&
        (risk == SecretaryTodoCommandRisk.review ||
            risk == SecretaryTodoCommandRisk.confirm)) {
      return SecretaryTodoCommandExecutionResult.rejected(
        command: command,
        reason: 'confirmation_required',
      );
    }

    final targetTodoId = command.targetTodoId?.trim();
    if (targetTodoId == null || targetTodoId.isEmpty) {
      return SecretaryTodoCommandExecutionResult.rejected(
        command: command,
        reason: 'target_required',
      );
    }

    final existing = await _backend.getTodoById(_sessionKey, targetTodoId);
    if (existing == null) {
      return SecretaryTodoCommandExecutionResult.rejected(
        command: command,
        reason: 'target_not_found',
      );
    }

    final undo = SecretaryTodoCommandUndoSnapshot.fromTodo(existing);
    return switch (command.kind) {
      SecretaryTodoCommandKind.updateTitle =>
        _executeUpdateTitle(command, existing, undo),
      SecretaryTodoCommandKind.reschedule =>
        _executeReschedule(command, existing, undo),
      SecretaryTodoCommandKind.setStatus =>
        _executeSetStatus(command, existing, undo),
      SecretaryTodoCommandKind.dismiss =>
        _executeDismiss(command, existing, undo),
      SecretaryTodoCommandKind.reprioritize =>
        _executeReprioritize(command, existing, undo),
      SecretaryTodoCommandKind.create ||
      SecretaryTodoCommandKind.batchUpdate ||
      SecretaryTodoCommandKind.none =>
        SecretaryTodoCommandExecutionResult.rejected(
          command: command,
          reason: 'unsupported_kind',
          undo: undo,
        ),
    };
  }

  Future<SecretaryTodoCommandExecutionResult> _executeUpdateTitle(
    SecretaryTodoCommand command,
    Todo existing,
    SecretaryTodoCommandUndoSnapshot undo,
  ) async {
    final newTitle = command.newTitle?.trim();
    if (newTitle == null || newTitle.isEmpty || newTitle == existing.title) {
      return _noChange(command, undo, existing);
    }
    final updated = await _backend.upsertTodo(
      _sessionKey,
      id: existing.id,
      title: newTitle,
      dueAtMs: platformIntToNullableInt(existing.dueAtMs),
      status: existing.status,
      sourceEntryId: existing.sourceEntryId,
      reviewStage: platformIntToNullableInt(existing.reviewStage),
      nextReviewAtMs: platformIntToNullableInt(existing.nextReviewAtMs),
      lastReviewAtMs: platformIntToNullableInt(existing.lastReviewAtMs),
      manualImportanceNudgeScore:
          platformIntToNullableInt(existing.manualImportanceNudgeScore) ?? 0,
      manualUrgencyNudgeScore:
          platformIntToNullableInt(existing.manualUrgencyNudgeScore) ?? 0,
    );
    return _applied(command, undo, updated, const <String>['title']);
  }

  Future<SecretaryTodoCommandExecutionResult> _executeReschedule(
    SecretaryTodoCommand command,
    Todo existing,
    SecretaryTodoCommandUndoSnapshot undo,
  ) async {
    final dueAtMs = command.dueAtMs;
    if (dueAtMs == null ||
        dueAtMs == platformIntToNullableInt(existing.dueAtMs)) {
      return _noChange(command, undo, existing);
    }
    final updated = await _backend.transitionTodo(
      _sessionKey,
      todoId: existing.id,
      dueAtMs: dueAtMs,
      sourceMessageId: command.sourceMessageId,
    );
    return _applied(command, undo, updated, const <String>['due_at_ms']);
  }

  Future<SecretaryTodoCommandExecutionResult> _executeSetStatus(
    SecretaryTodoCommand command,
    Todo existing,
    SecretaryTodoCommandUndoSnapshot undo,
  ) async {
    final newStatus = command.newStatus?.trim();
    if (newStatus == null ||
        newStatus.isEmpty ||
        newStatus == existing.status) {
      return _noChange(command, undo, existing);
    }
    final updated = await _backend.setTodoStatus(
      _sessionKey,
      todoId: existing.id,
      newStatus: newStatus,
      sourceMessageId: command.sourceMessageId,
    );
    return _applied(command, undo, updated, const <String>['status']);
  }

  Future<SecretaryTodoCommandExecutionResult> _executeDismiss(
    SecretaryTodoCommand command,
    Todo existing,
    SecretaryTodoCommandUndoSnapshot undo,
  ) async {
    if (existing.status == 'dismissed') {
      return _noChange(command, undo, existing);
    }
    final updated = await _backend.transitionTodo(
      _sessionKey,
      todoId: existing.id,
      newStatus: 'dismissed',
      clearManualImportanceNudgeScore: true,
      clearManualUrgencyNudgeScore: true,
      sourceMessageId: command.sourceMessageId,
    );
    return _applied(command, undo, updated, const <String>['status']);
  }

  Future<SecretaryTodoCommandExecutionResult> _executeReprioritize(
    SecretaryTodoCommand command,
    Todo existing,
    SecretaryTodoCommandUndoSnapshot undo,
  ) async {
    final nextImportance = command.manualImportanceNudgeScore;
    final nextUrgency = command.manualUrgencyNudgeScore;
    final currentImportance =
        platformIntToNullableInt(existing.manualImportanceNudgeScore) ?? 0;
    final currentUrgency =
        platformIntToNullableInt(existing.manualUrgencyNudgeScore) ?? 0;
    if ((nextImportance == null || nextImportance == currentImportance) &&
        (nextUrgency == null || nextUrgency == currentUrgency)) {
      return _noChange(command, undo, existing);
    }

    final changedFields = <String>[
      if (nextImportance != null && nextImportance != currentImportance)
        'manual_importance_nudge_score',
      if (nextUrgency != null && nextUrgency != currentUrgency)
        'manual_urgency_nudge_score',
    ];
    final updated = await _backend.transitionTodo(
      _sessionKey,
      todoId: existing.id,
      manualImportanceNudgeScore: nextImportance,
      manualUrgencyNudgeScore: nextUrgency,
      sourceMessageId: command.sourceMessageId,
    );
    return _applied(command, undo, updated, changedFields);
  }

  SecretaryTodoCommandExecutionResult _applied(
    SecretaryTodoCommand command,
    SecretaryTodoCommandUndoSnapshot undo,
    Todo updated,
    List<String> changedFields,
  ) {
    return SecretaryTodoCommandExecutionResult(
      command: command,
      applied: changedFields.isNotEmpty,
      changedFields: changedFields,
      undo: undo,
      updatedTodo: updated,
      rejectionReason: changedFields.isEmpty ? 'no_change' : null,
    );
  }

  SecretaryTodoCommandExecutionResult _noChange(
    SecretaryTodoCommand command,
    SecretaryTodoCommandUndoSnapshot undo,
    Todo existing,
  ) {
    return SecretaryTodoCommandExecutionResult(
      command: command,
      applied: false,
      changedFields: const <String>[],
      undo: undo,
      updatedTodo: existing,
      rejectionReason: 'no_change',
    );
  }
}

String todoCommandKindWireValue(SecretaryTodoCommandKind kind) {
  return switch (kind) {
    SecretaryTodoCommandKind.create => 'create',
    SecretaryTodoCommandKind.updateTitle => 'update_title',
    SecretaryTodoCommandKind.reschedule => 'reschedule',
    SecretaryTodoCommandKind.setStatus => 'set_status',
    SecretaryTodoCommandKind.dismiss => 'dismiss',
    SecretaryTodoCommandKind.reprioritize => 'reprioritize',
    SecretaryTodoCommandKind.batchUpdate => 'batch_update',
    SecretaryTodoCommandKind.none => 'none',
  };
}

String secretaryToolNameForTodoCommand(SecretaryTodoCommandKind kind) {
  return switch (kind) {
    SecretaryTodoCommandKind.create => 'todo.create',
    SecretaryTodoCommandKind.updateTitle ||
    SecretaryTodoCommandKind.reschedule =>
      'todo.update',
    SecretaryTodoCommandKind.setStatus => 'todo.status.set',
    SecretaryTodoCommandKind.dismiss => 'todo.dismiss',
    SecretaryTodoCommandKind.reprioritize => 'todo.priority.set',
    SecretaryTodoCommandKind.batchUpdate ||
    SecretaryTodoCommandKind.none =>
      'todo.update',
  };
}
