import '../../../src/rust/db.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';
import 'task_priority_signal_store.dart';

bool _isSameLocalDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _dueDerivedUrgencyScoreFor(
  Todo todo, {
  required DateTime nowLocal,
  DateTime? dueLocal,
}) {
  if (todo.status == 'done') return 0;
  if (dueLocal == null) return 0;
  if (dueLocal.isBefore(nowLocal)) return 4;
  if (_isSameLocalDate(dueLocal, nowLocal)) return 3;

  final tomorrow = DateTime(
    nowLocal.year,
    nowLocal.month,
    nowLocal.day,
  ).add(const Duration(days: 1));
  if (_isSameLocalDate(dueLocal, tomorrow)) return 2;
  return 1;
}

TaskPrioritySnapshot buildTaskPrioritySnapshot(
  List<Todo> todos, {
  required DateTime nowLocal,
  TaskPriorityAiBatchResult? aiResult,
  TaskPriorityFeedbackState? feedbackState,
  TaskPriorityManualSignalState? signalState,
}) {
  final feedback = feedbackState ?? const TaskPriorityFeedbackState();
  final manualSignals = signalState ?? const TaskPriorityManualSignalState();
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

    if (isInProgress && todo.status != 'done') {
      reasons.add(TaskPriorityReasonKind.inProgress);
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
        importanceScore: 0,
        urgencyScore: 0,
        dueDerivedUrgencyScore: _dueDerivedUrgencyScoreFor(
          todo,
          nowLocal: nowLocal,
          dueLocal: dueLocal,
        ),
      ),
    );
  }

  var entries = rawEntries;
  if (aiResult != null) {
    entries = _applyAiResult(entries, aiResult);
  }
  entries = _applyFeedback(entries, feedback);
  entries = _applyManualSignals(entries, manualSignals);

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

  final orderedActive = <TaskPriorityEntry>[
    ...focus,
    ...scheduled,
    ...decide,
  ]..sort(_compareOverallPriority);

  return TaskPrioritySnapshot(
    source: aiResult == null
        ? TaskPrioritySnapshotSource.rules
        : TaskPrioritySnapshotSource.hybrid,
    computedAtLocal: nowLocal,
    focus: List<TaskPriorityEntry>.unmodifiable(focus),
    scheduled: List<TaskPriorityEntry>.unmodifiable(scheduled),
    decide: List<TaskPriorityEntry>.unmodifiable(decide),
    done: List<TaskPriorityEntry>.unmodifiable(done),
    orderedActive: List<TaskPriorityEntry>.unmodifiable(orderedActive),
    selectedFocusTodoId:
        orderedActive.isEmpty ? null : orderedActive.first.todo.id,
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
    final canApplyAiPrioritySignals =
        aiEntry.confidence != TaskPriorityAiConfidence.low;

    final confidence = switch (aiEntry.confidence) {
      TaskPriorityAiConfidence.low => TaskPriorityConfidence.low,
      TaskPriorityAiConfidence.medium => TaskPriorityConfidence.medium,
      TaskPriorityAiConfidence.high => TaskPriorityConfidence.high,
    };

    return entry.copyWith(
      semanticScore: canApplyAiPrioritySignals
          ? aiEntry.semanticAdjustment
          : entry.semanticScore,
      reasonText: canApplyAiPrioritySignals && aiEntry.reason.isNotEmpty
          ? aiEntry.reason
          : null,
      confidence: confidence,
      importanceScore: canApplyAiPrioritySignals
          ? (aiEntry.isImportant == null
              ? entry.importanceScore
              : aiEntry.isImportant!
                  ? (entry.importanceScore > 0 ? entry.importanceScore : 1)
                  : (entry.importanceScore < 0 ? entry.importanceScore : -1))
          : entry.importanceScore,
      urgencyScore: canApplyAiPrioritySignals
          ? (aiEntry.isUrgent == null
              ? entry.urgencyScore
              : aiEntry.isUrgent!
                  ? (entry.urgencyScore > 0 ? entry.urgencyScore : 1)
                  : (entry.urgencyScore < 0 ? entry.urgencyScore : -1))
          : entry.urgencyScore,
      reasons: canApplyAiPrioritySignals
          ? <TaskPriorityReasonKind>[
              ...entry.reasons,
              TaskPriorityReasonKind.aiSuggested,
            ]
          : entry.reasons,
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
      importanceScore: deprioritized
          ? (next.importanceScore <= -1 ? next.importanceScore : -1)
          : next.importanceScore,
      urgencyScore: suppressed
          ? (next.urgencyScore <= -1 ? next.urgencyScore : -1)
          : next.urgencyScore,
      reasons: <TaskPriorityReasonKind>[
        ...next.reasons,
        TaskPriorityReasonKind.feedbackSuppressed,
      ],
    );
    return next;
  }).toList(growable: false);
}

List<TaskPriorityEntry> _applyManualSignals(
  List<TaskPriorityEntry> entries,
  TaskPriorityManualSignalState signalState,
) {
  return entries.map((entry) {
    final signal = signalState.byTodoId[entry.todo.id];
    if (signal == null) return entry;
    return entry.copyWith(
      importanceScore: entry.importanceScore + signal.importanceScore,
      urgencyScore: entry.urgencyScore + signal.urgencyScore,
    );
  }).toList(growable: false);
}

int _compareOverallPriority(TaskPriorityEntry a, TaskPriorityEntry b) {
  final urgencyCompare = b.effectiveUrgency.compareTo(a.effectiveUrgency);
  if (urgencyCompare != 0) return urgencyCompare;

  final importanceCompare =
      b.effectiveImportance.compareTo(a.effectiveImportance);
  if (importanceCompare != 0) return importanceCompare;

  final scoreCompare = b.totalScore.compareTo(a.totalScore);
  if (scoreCompare != 0) return scoreCompare;

  if (a.todo.dueAtMs != b.todo.dueAtMs) {
    final aDue = a.todo.dueAtMs ?? 9223372036854775807;
    final bDue = b.todo.dueAtMs ?? 9223372036854775807;
    return aDue.compareTo(bDue);
  }

  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
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
