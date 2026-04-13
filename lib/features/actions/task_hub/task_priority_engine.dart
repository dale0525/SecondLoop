import '../../../src/rust/db.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

const int _kMaxSafeWebInt = 0x001FFFFFFFFFFFFF;

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
  return 0;
}

TaskPrioritySnapshot buildTaskPrioritySnapshot(
  List<Todo> todos, {
  required DateTime nowLocal,
  TaskPriorityAiBatchResult? aiResult,
  TaskPriorityEnhancementSource enhancementSource =
      TaskPriorityEnhancementSource.aiLive,
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
        manualImportanceNudgeScore: todo.manualImportanceNudgeScore ?? 0,
        manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore ?? 0,
        dueDerivedUrgencyScore: _dueDerivedUrgencyScoreFor(
          todo,
          nowLocal: nowLocal,
          dueLocal: dueLocal,
        ),
      ),
    );
  }

  final baseLists = _splitTaskPriorityEntries(rawEntries);

  var entries = rawEntries;
  if (aiResult != null) {
    entries = _applyAiResult(entries, aiResult);
  }
  entries = _applyFeedback(entries, feedback);
  final finalLists = _splitTaskPriorityEntries(entries);
  final boundedOrderedActive =
      _applyBoundedUserMoveOrdering(finalLists.orderedActive);

  return TaskPrioritySnapshot(
    source: aiResult == null
        ? TaskPrioritySnapshotSource.rules
        : TaskPrioritySnapshotSource.hybrid,
    enhancementSource: aiResult == null
        ? TaskPriorityEnhancementSource.none
        : enhancementSource,
    computedAtLocal: nowLocal,
    focus: finalLists.focus,
    scheduled: finalLists.scheduled,
    decide: finalLists.decide,
    done: finalLists.done,
    orderedActive: boundedOrderedActive,
    baseFocus: baseLists.focus,
    baseScheduled: baseLists.scheduled,
    baseDecide: baseLists.decide,
    baseDone: baseLists.done,
    baseOrderedActive: baseLists.orderedActive,
    selectedFocusTodoId: boundedOrderedActive.isEmpty
        ? null
        : boundedOrderedActive.first.todo.id,
  );
}

_TaskPriorityBuckets _splitTaskPriorityEntries(
    List<TaskPriorityEntry> entries) {
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

  return _TaskPriorityBuckets(
    focus: List<TaskPriorityEntry>.unmodifiable(focus),
    scheduled: List<TaskPriorityEntry>.unmodifiable(scheduled),
    decide: List<TaskPriorityEntry>.unmodifiable(decide),
    done: List<TaskPriorityEntry>.unmodifiable(done),
    orderedActive: List<TaskPriorityEntry>.unmodifiable(orderedActive),
  );
}

final class _TaskPriorityBuckets {
  const _TaskPriorityBuckets({
    required this.focus,
    required this.scheduled,
    required this.decide,
    required this.done,
    required this.orderedActive,
  });

  final List<TaskPriorityEntry> focus;
  final List<TaskPriorityEntry> scheduled;
  final List<TaskPriorityEntry> decide;
  final List<TaskPriorityEntry> done;
  final List<TaskPriorityEntry> orderedActive;
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

int _compareOverallPriority(TaskPriorityEntry a, TaskPriorityEntry b) {
  final hardGuardCompare =
      _compareBoolDesc(a.hasHardFocusGuard, b.hasHardFocusGuard);
  if (hardGuardCompare != 0) return hardGuardCompare;

  final urgencyCompare = b.effectiveUrgency.compareTo(a.effectiveUrgency);
  if (urgencyCompare != 0) return urgencyCompare;

  final importanceCompare =
      b.effectiveImportance.compareTo(a.effectiveImportance);
  if (importanceCompare != 0) return importanceCompare;

  final scoreCompare = b.totalScore.compareTo(a.totalScore);
  if (scoreCompare != 0) return scoreCompare;

  if (a.todo.dueAtMs != b.todo.dueAtMs) {
    final aDue = a.todo.dueAtMs ?? _kMaxSafeWebInt;
    final bDue = b.todo.dueAtMs ?? _kMaxSafeWebInt;
    return aDue.compareTo(bDue);
  }

  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
}

List<TaskPriorityEntry> _applyBoundedUserMoveOrdering(
  List<TaskPriorityEntry> orderedActive,
) {
  if (orderedActive.length < 2) {
    return orderedActive;
  }

  final originalById = <String, TaskPriorityEntry>{
    for (final entry in orderedActive) entry.todo.id: entry,
  };
  final neutralEntries = orderedActive
      .map(_neutralizePureUserMoveEntry)
      .toList(growable: false)
    ..sort(_compareOverallPriority);
  final orderedIds =
      neutralEntries.map((entry) => entry.todo.id).toList(growable: true);

  for (final entry in neutralEntries) {
    final original = originalById[entry.todo.id]!;
    if (original.userMoveDirection != TaskPriorityUserMoveDirection.up) {
      continue;
    }
    final currentIndex = orderedIds.indexOf(original.todo.id);
    if (currentIndex <= 0) {
      continue;
    }
    final previous = originalById[orderedIds[currentIndex - 1]]!;
    if (!_canApplyBoundedUserMoveUp(original, previous)) {
      continue;
    }
    orderedIds[currentIndex - 1] = original.todo.id;
    orderedIds[currentIndex] = previous.todo.id;
  }

  for (var i = neutralEntries.length - 1; i >= 0; i -= 1) {
    final original = originalById[neutralEntries[i].todo.id]!;
    if (original.userMoveDirection != TaskPriorityUserMoveDirection.down) {
      continue;
    }
    final currentIndex = orderedIds.indexOf(original.todo.id);
    if (currentIndex == -1 || currentIndex >= orderedIds.length - 1) {
      continue;
    }
    final next = originalById[orderedIds[currentIndex + 1]]!;
    if (!_canApplyBoundedUserMoveDown(original, next)) {
      continue;
    }
    orderedIds[currentIndex] = next.todo.id;
    orderedIds[currentIndex + 1] = original.todo.id;
  }

  return orderedIds
      .map((todoId) => originalById[todoId]!)
      .toList(growable: false);
}

TaskPriorityEntry _neutralizePureUserMoveEntry(TaskPriorityEntry entry) {
  if (!_isPureUserMoveEntry(entry)) {
    return entry;
  }
  return entry.copyWith(
    manualUrgencyNudgeScore: 0,
    manualImportanceNudgeScore: 0,
  );
}

bool _isPureUserMoveEntry(TaskPriorityEntry entry) {
  return entry.manualImportanceNudgeScore == 0 &&
      entry.manualUrgencyNudgeScore != 0;
}

bool _canApplyBoundedUserMoveUp(
  TaskPriorityEntry current,
  TaskPriorityEntry previous,
) {
  if (!current.hasHardFocusGuard && previous.hasHardFocusGuard) {
    return false;
  }
  return true;
}

bool _canApplyBoundedUserMoveDown(
  TaskPriorityEntry current,
  TaskPriorityEntry next,
) {
  if (current.hasHardFocusGuard && !next.hasHardFocusGuard) {
    return false;
  }
  return true;
}

int _compareBoolDesc(bool left, bool right) {
  if (left == right) return 0;
  return left ? -1 : 1;
}

int _compareFocusEntries(TaskPriorityEntry a, TaskPriorityEntry b) {
  final scoreCompare = b.totalScore.compareTo(a.totalScore);
  if (scoreCompare != 0) return scoreCompare;
  return b.todo.updatedAtMs.compareTo(a.todo.updatedAtMs);
}

int _compareScheduledEntries(TaskPriorityEntry a, TaskPriorityEntry b) {
  final aDue = a.todo.dueAtMs ?? _kMaxSafeWebInt;
  final bDue = b.todo.dueAtMs ?? _kMaxSafeWebInt;
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
