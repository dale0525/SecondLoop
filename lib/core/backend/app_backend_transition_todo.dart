part of 'app_backend.dart';

Future<Todo> _transitionTodoFallback(
  AppBackend backend,
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
  final todos = await backend.listTodos(key);
  Todo? existing;
  for (final todo in todos) {
    if (todo.id == todoId) {
      existing = todo;
      break;
    }
  }
  if (existing == null) {
    throw StateError('Unknown todo: $todoId');
  }

  final patchesStatus = newStatus != null && newStatus != existing.status;
  final staged = patchesStatus
      ? await backend.setTodoStatus(
          key,
          todoId: todoId,
          newStatus: newStatus,
          sourceMessageId: sourceMessageId,
        )
      : existing;

  final int? stagedDueAtMs = staged.dueAtMs?.toInt();
  final int? stagedReviewStage = staged.reviewStage?.toInt();
  final int? stagedNextReviewAtMs = staged.nextReviewAtMs?.toInt();
  final int? stagedLastReviewAtMs = staged.lastReviewAtMs?.toInt();
  final int stagedManualImportance =
      staged.manualImportanceNudgeScore?.toInt() ?? 0;
  final int stagedManualUrgency = staged.manualUrgencyNudgeScore?.toInt() ?? 0;

  final int? targetDueAtMs = clearDueAtMs ? null : (dueAtMs ?? stagedDueAtMs);
  final int? targetReviewStage =
      clearReviewStage ? null : (reviewStage ?? stagedReviewStage);
  final int? targetNextReviewAtMs =
      clearNextReviewAtMs ? null : (nextReviewAtMs ?? stagedNextReviewAtMs);
  final int? targetLastReviewAtMs =
      clearLastReviewAtMs ? null : (lastReviewAtMs ?? stagedLastReviewAtMs);
  final int? targetManualImportanceNudgeScore = clearManualImportanceNudgeScore
      ? null
      : (manualImportanceNudgeScore ??
          (stagedManualImportance == 0 ? null : stagedManualImportance));
  final int? targetManualUrgencyNudgeScore = clearManualUrgencyNudgeScore
      ? null
      : (manualUrgencyNudgeScore ??
          (stagedManualUrgency == 0 ? null : stagedManualUrgency));

  if (targetDueAtMs == stagedDueAtMs &&
      targetReviewStage == stagedReviewStage &&
      targetNextReviewAtMs == stagedNextReviewAtMs &&
      targetLastReviewAtMs == stagedLastReviewAtMs &&
      (targetManualImportanceNudgeScore ?? 0) == stagedManualImportance &&
      (targetManualUrgencyNudgeScore ?? 0) == stagedManualUrgency) {
    return staged;
  }

  return backend.upsertTodo(
    key,
    id: staged.id,
    title: staged.title,
    dueAtMs: targetDueAtMs,
    status: staged.status,
    sourceEntryId: staged.sourceEntryId,
    reviewStage: targetReviewStage,
    nextReviewAtMs: targetNextReviewAtMs,
    lastReviewAtMs: targetLastReviewAtMs,
    manualImportanceNudgeScore: targetManualImportanceNudgeScore,
    manualUrgencyNudgeScore: targetManualUrgencyNudgeScore,
  );
}
