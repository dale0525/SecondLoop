import '../../../src/rust/db.dart';

enum TaskPriorityBand {
  focus,
  scheduled,
  decide,
  done,
}

enum TaskPrioritySuggestionKind {
  doNow,
  schedule,
  defer,
  clarify,
}

enum TaskPriorityConfidence {
  none,
  low,
  medium,
  high,
}

enum TaskPriorityReasonKind {
  overdue,
  dueToday,
  scheduledSoon,
  inProgress,
  reviewDue,
  unscheduled,
  snoozed,
  done,
  aiSuggested,
  feedbackSuppressed,
}

enum TaskPrioritySnapshotSource {
  rules,
  hybrid,
}

class TaskPriorityEntry {
  const TaskPriorityEntry({
    required this.todo,
    required this.band,
    required this.ruleScore,
    required this.semanticScore,
    required this.reasons,
    required this.suggestedAction,
    this.confidence = TaskPriorityConfidence.none,
    this.reasonText,
    this.isReviewDue = false,
    this.isSnoozed = false,
    this.isOverdue = false,
    this.isDueToday = false,
    this.isInProgress = false,
    this.isFutureScheduled = false,
  });

  final Todo todo;
  final TaskPriorityBand band;
  final double ruleScore;
  final double semanticScore;
  final List<TaskPriorityReasonKind> reasons;
  final TaskPrioritySuggestionKind suggestedAction;
  final TaskPriorityConfidence confidence;
  final String? reasonText;
  final bool isReviewDue;
  final bool isSnoozed;
  final bool isOverdue;
  final bool isDueToday;
  final bool isInProgress;
  final bool isFutureScheduled;

  double get totalScore => ruleScore + semanticScore;

  bool get hasHardFocusGuard => isOverdue || isDueToday || isInProgress;

  TaskPriorityEntry copyWith({
    TaskPriorityBand? band,
    double? ruleScore,
    double? semanticScore,
    List<TaskPriorityReasonKind>? reasons,
    TaskPrioritySuggestionKind? suggestedAction,
    TaskPriorityConfidence? confidence,
    String? reasonText,
    bool clearReasonText = false,
    bool? isReviewDue,
    bool? isSnoozed,
    bool? isOverdue,
    bool? isDueToday,
    bool? isInProgress,
    bool? isFutureScheduled,
  }) {
    return TaskPriorityEntry(
      todo: todo,
      band: band ?? this.band,
      ruleScore: ruleScore ?? this.ruleScore,
      semanticScore: semanticScore ?? this.semanticScore,
      reasons: reasons ?? this.reasons,
      suggestedAction: suggestedAction ?? this.suggestedAction,
      confidence: confidence ?? this.confidence,
      reasonText: clearReasonText ? null : (reasonText ?? this.reasonText),
      isReviewDue: isReviewDue ?? this.isReviewDue,
      isSnoozed: isSnoozed ?? this.isSnoozed,
      isOverdue: isOverdue ?? this.isOverdue,
      isDueToday: isDueToday ?? this.isDueToday,
      isInProgress: isInProgress ?? this.isInProgress,
      isFutureScheduled: isFutureScheduled ?? this.isFutureScheduled,
    );
  }
}

class TaskPrioritySnapshot {
  const TaskPrioritySnapshot({
    required this.source,
    required this.focus,
    required this.scheduled,
    required this.decide,
    required this.done,
    this.computedAtLocal,
  });

  const TaskPrioritySnapshot.empty()
      : source = TaskPrioritySnapshotSource.rules,
        focus = const <TaskPriorityEntry>[],
        scheduled = const <TaskPriorityEntry>[],
        decide = const <TaskPriorityEntry>[],
        done = const <TaskPriorityEntry>[],
        computedAtLocal = null;

  final TaskPrioritySnapshotSource source;
  final List<TaskPriorityEntry> focus;
  final List<TaskPriorityEntry> scheduled;
  final List<TaskPriorityEntry> decide;
  final List<TaskPriorityEntry> done;
  final DateTime? computedAtLocal;

  bool get isEmpty => focus.isEmpty && scheduled.isEmpty && decide.isEmpty;

  TaskPriorityEntry? get primaryFocus => focus.isEmpty ? null : focus.first;

  List<TaskPriorityEntry> get activeEntries => <TaskPriorityEntry>[
        ...focus,
        ...scheduled,
        ...decide,
      ];

  List<TaskPriorityEntry> get allEntries => <TaskPriorityEntry>[
        ...focus,
        ...scheduled,
        ...decide,
        ...done,
      ];
}
