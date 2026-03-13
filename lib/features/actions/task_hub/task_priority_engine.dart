import '../../../src/rust/db.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

bool _isSameLocalDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

TaskPrioritySnapshot buildTaskPrioritySnapshot(
  List<Todo> todos, {
  required DateTime nowLocal,
  TaskPriorityAiBatchResult? aiResult,
  TaskPriorityFeedbackState? feedbackState,
}) {
  final feedback = feedbackState ?? const TaskPriorityFeedbackState();
  final rawEntries = <TaskPriorityEntry>[];
  final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;

  for (final todo in todos) {
    if (todo.status == 'dismissed') continue;

    final dueLocal = todo.dueAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(todo.dueAtMs!, isUtc: true)
            .toLocal();
    final isOverdue = dueLocal != null && dueLocal.isBefore(nowLocal);
    final isDueToday =
        dueLocal != null && !isOverdue && _isSameLocalDate(dueLocal, nowLocal);
    final isFutureScheduled =
        dueLocal != null && !isOverdue && !_isSameLocalDate(dueLocal, nowLocal);
    final isInProgress = todo.status == 'in_progress';
    final isReviewDue = todo.reviewStage != null &&
        todo.nextReviewAtMs != null &&
        todo.nextReviewAtMs! <= nowUtcMs;
    final isSnoozed = todo.reviewStage != null &&
        todo.nextReviewAtMs != null &&
        todo.nextReviewAtMs! > nowUtcMs;

    late final TaskPriorityBand band;
    late final double ruleScore;
    late final TaskPrioritySuggestionKind suggestedAction;
    final reasons = <TaskPriorityReasonKind>[];

    if (todo.status == 'done') {
      band = TaskPriorityBand.done;
      ruleScore = 0;
      suggestedAction = TaskPrioritySuggestionKind.doNow;
      reasons.add(TaskPriorityReasonKind.done);
    } else if (isOverdue) {
      band = TaskPriorityBand.focus;
      ruleScore = 260;
      suggestedAction = TaskPrioritySuggestionKind.doNow;
      reasons.add(TaskPriorityReasonKind.overdue);
    } else if (isInProgress) {
      band = TaskPriorityBand.focus;
      ruleScore = 240;
      suggestedAction = TaskPrioritySuggestionKind.doNow;
      reasons.add(TaskPriorityReasonKind.inProgress);
    } else if (isDueToday) {
      band = TaskPriorityBand.focus;
      ruleScore = 220;
      suggestedAction = TaskPrioritySuggestionKind.doNow;
      reasons.add(TaskPriorityReasonKind.dueToday);
    } else if (isFutureScheduled) {
      band = TaskPriorityBand.scheduled;
      final daysUntil = dueLocal.difference(nowLocal).inHours / 24;
      ruleScore = 160 - daysUntil;
      suggestedAction = TaskPrioritySuggestionKind.schedule;
      reasons.add(TaskPriorityReasonKind.scheduledSoon);
    } else if (isReviewDue) {
      band = TaskPriorityBand.decide;
      ruleScore = 130;
      suggestedAction = TaskPrioritySuggestionKind.clarify;
      reasons.add(TaskPriorityReasonKind.reviewDue);
    } else {
      band = TaskPriorityBand.decide;
      ruleScore = isSnoozed ? 20 : 80;
      suggestedAction = isSnoozed
          ? TaskPrioritySuggestionKind.defer
          : TaskPrioritySuggestionKind.schedule;
      reasons.add(
        isSnoozed
            ? TaskPriorityReasonKind.snoozed
            : TaskPriorityReasonKind.unscheduled,
      );
    }

    rawEntries.add(
      TaskPriorityEntry(
        todo: todo,
        band: band,
        ruleScore: ruleScore,
        semanticScore: 0,
        reasons: reasons,
        suggestedAction: suggestedAction,
        isReviewDue: isReviewDue,
        isSnoozed: isSnoozed,
        isOverdue: isOverdue,
        isDueToday: isDueToday,
        isInProgress: isInProgress,
        isFutureScheduled: isFutureScheduled,
      ),
    );
  }

  var entries = rawEntries;
  if (aiResult != null) {
    entries = _applyAiResult(entries, aiResult);
  }
  entries = _applyFeedback(entries, feedback);

  final focus = <TaskPriorityEntry>[];
  final scheduled = <TaskPriorityEntry>[];
  final decide = <TaskPriorityEntry>[];
  final done = <TaskPriorityEntry>[];

  for (final entry in entries) {
    switch (entry.band) {
      case TaskPriorityBand.focus:
        focus.add(entry);
        break;
      case TaskPriorityBand.scheduled:
        scheduled.add(entry);
        break;
      case TaskPriorityBand.decide:
        decide.add(entry);
        break;
      case TaskPriorityBand.done:
        done.add(entry);
        break;
    }
  }

  focus.sort(_compareFocusEntries);
  scheduled.sort(_compareScheduledEntries);
  decide.sort(_compareDecideEntries);
  done.sort((a, b) => b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs));

  return TaskPrioritySnapshot(
    source: aiResult == null
        ? TaskPrioritySnapshotSource.rules
        : TaskPrioritySnapshotSource.hybrid,
    computedAtLocal: nowLocal,
    focus: List<TaskPriorityEntry>.unmodifiable(focus),
    scheduled: List<TaskPriorityEntry>.unmodifiable(scheduled),
    decide: List<TaskPriorityEntry>.unmodifiable(decide),
    done: List<TaskPriorityEntry>.unmodifiable(done),
  );
}

List<TaskPriorityEntry> _applyAiResult(
  List<TaskPriorityEntry> entries,
  TaskPriorityAiBatchResult aiResult,
) {
  final byId = <String, TaskPriorityAiEntry>{
    for (final entry in aiResult.entries)
      if (entry.todoId.trim().isNotEmpty) entry.todoId.trim(): entry,
  };
  return entries.map((entry) {
    final aiEntry = byId[entry.todo.id];
    if (aiEntry == null) return entry;

    var nextBand = entry.band;
    if (!entry.hasHardFocusGuard &&
        aiEntry.confidence != TaskPriorityAiConfidence.low) {
      switch (aiEntry.priorityBand) {
        case TaskPriorityAiBand.focus:
          nextBand = entry.band == TaskPriorityBand.done
              ? TaskPriorityBand.done
              : TaskPriorityBand.focus;
          break;
        case TaskPriorityAiBand.next:
          break;
        case TaskPriorityAiBand.later:
          if (entry.band == TaskPriorityBand.focus) {
            nextBand = TaskPriorityBand.decide;
          }
          break;
      }
    }

    final confidence = switch (aiEntry.confidence) {
      TaskPriorityAiConfidence.low => TaskPriorityConfidence.low,
      TaskPriorityAiConfidence.medium => TaskPriorityConfidence.medium,
      TaskPriorityAiConfidence.high => TaskPriorityConfidence.high,
    };

    return entry.copyWith(
      band: nextBand,
      semanticScore: aiEntry.semanticAdjustment,
      reasonText: aiEntry.reason.isEmpty ? null : aiEntry.reason,
      suggestedAction: aiEntry.suggestedAction,
      confidence: confidence,
      reasons: <TaskPriorityReasonKind>[
        ...entry.reasons,
        TaskPriorityReasonKind.aiSuggested,
      ],
    );
  }).toList(growable: false);
}

List<TaskPriorityEntry> _applyFeedback(
  List<TaskPriorityEntry> entries,
  TaskPriorityFeedbackState feedback,
) {
  return entries.map((entry) {
    var next = entry;
    final todoId = entry.todo.id;
    final suppressed = feedback.suppressedTodoIds.contains(todoId);
    final deprioritized = feedback.deprioritizedTodoIds.contains(todoId);
    if (!suppressed && !deprioritized) return entry;

    var nextBand = next.band;
    if (suppressed &&
        !next.hasHardFocusGuard &&
        next.band == TaskPriorityBand.focus) {
      nextBand = TaskPriorityBand.decide;
    }
    var semanticPenalty = next.semanticScore;
    if (suppressed) semanticPenalty -= 80;
    if (deprioritized) semanticPenalty -= 40;

    next = next.copyWith(
      band: nextBand,
      semanticScore: semanticPenalty,
      reasons: <TaskPriorityReasonKind>[
        ...next.reasons,
        TaskPriorityReasonKind.feedbackSuppressed,
      ],
    );
    return next;
  }).toList(growable: false);
}

int _compareFocusEntries(TaskPriorityEntry a, TaskPriorityEntry b) {
  final scoreCompare = b.totalScore.compareTo(a.totalScore);
  if (scoreCompare != 0) return scoreCompare;
  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
}

int _compareScheduledEntries(TaskPriorityEntry a, TaskPriorityEntry b) {
  final aDue = a.todo.dueAtMs ?? 9223372036854775807;
  final bDue = b.todo.dueAtMs ?? 9223372036854775807;
  if (aDue != bDue) return aDue.compareTo(bDue);
  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
}

int _compareDecideEntries(TaskPriorityEntry a, TaskPriorityEntry b) {
  if (a.isReviewDue != b.isReviewDue) {
    return a.isReviewDue ? -1 : 1;
  }
  final scoreCompare = b.totalScore.compareTo(a.totalScore);
  if (scoreCompare != 0) return scoreCompare;
  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
}
