import '../../../src/rust/db.dart';

import 'task_priority_guards.dart';

enum TaskPriorityNudgeDirection {
  none,
  up,
  down,
}

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

enum TaskPriorityEnhancementSource {
  none,
  aiLive,
  aiSharedCache,
  aiLocalCache,
}

enum TaskPriorityDisplayBucket {
  nextUp,
  backlog,
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
    int importanceScore = 0,
    int urgencyScore = 0,
    bool isImportant = false,
    bool isUrgent = false,
    this.manualImportanceNudgeScore = 0,
    this.manualUrgencyNudgeScore = 0,
    this.dueDerivedUrgencyScore = 0,
  })  : importanceScore =
            importanceScore != 0 ? importanceScore : (isImportant ? 1 : 0),
        urgencyScore = urgencyScore != 0 ? urgencyScore : (isUrgent ? 1 : 0);

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
  final int importanceScore;
  final int urgencyScore;
  final int manualImportanceNudgeScore;
  final int manualUrgencyNudgeScore;
  final int dueDerivedUrgencyScore;

  double get totalScore => ruleScore + semanticScore;

  int get effectiveUrgency =>
      urgencyScore + manualUrgencyNudgeScore + dueDerivedUrgencyScore;

  int get effectiveImportance => importanceScore + manualImportanceNudgeScore;

  bool get hasManualImportanceNudge => manualImportanceNudgeScore != 0;

  bool get hasManualUrgencyNudge => manualUrgencyNudgeScore != 0;

  bool get hasManualNudges => hasManualImportanceNudge || hasManualUrgencyNudge;

  TaskPriorityNudgeDirection get manualImportanceNudgeDirection =>
      _directionFromScore(manualImportanceNudgeScore);

  TaskPriorityNudgeDirection get manualUrgencyNudgeDirection =>
      _directionFromScore(manualUrgencyNudgeScore);

  bool get isExplicitlyImportant =>
      manualImportanceNudgeDirection == TaskPriorityNudgeDirection.up;

  bool get isExplicitlyUrgent =>
      manualUrgencyNudgeDirection == TaskPriorityNudgeDirection.up;

  bool get isImportant => effectiveImportance > 0;

  bool get isUrgent => effectiveUrgency > 0;

  bool get hasHardFocusGuard => hasTaskPriorityHardGuard(
        isOverdue: isOverdue,
        isDueToday: isDueToday,
      );

  TaskPriorityDisplayBucket get displayBucket {
    if (hasHardFocusGuard || isImportant || isUrgent || isReviewDue) {
      return TaskPriorityDisplayBucket.nextUp;
    }
    if (todo.dueAtMs != null) {
      return TaskPriorityDisplayBucket.nextUp;
    }
    return TaskPriorityDisplayBucket.backlog;
  }

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
    int? importanceScore,
    int? urgencyScore,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
    int? dueDerivedUrgencyScore,
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
      importanceScore: importanceScore ?? this.importanceScore,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      manualImportanceNudgeScore:
          manualImportanceNudgeScore ?? this.manualImportanceNudgeScore,
      manualUrgencyNudgeScore:
          manualUrgencyNudgeScore ?? this.manualUrgencyNudgeScore,
      dueDerivedUrgencyScore:
          dueDerivedUrgencyScore ?? this.dueDerivedUrgencyScore,
    );
  }

  static TaskPriorityNudgeDirection _directionFromScore(int score) {
    if (score > 0) return TaskPriorityNudgeDirection.up;
    if (score < 0) return TaskPriorityNudgeDirection.down;
    return TaskPriorityNudgeDirection.none;
  }
}

class TaskPrioritySnapshot {
  const TaskPrioritySnapshot({
    required this.source,
    required this.focus,
    required this.scheduled,
    required this.decide,
    required this.done,
    required this.orderedActive,
    this.enhancementSource = TaskPriorityEnhancementSource.none,
    List<TaskPriorityEntry>? baseFocus,
    List<TaskPriorityEntry>? baseScheduled,
    List<TaskPriorityEntry>? baseDecide,
    List<TaskPriorityEntry>? baseDone,
    List<TaskPriorityEntry>? baseOrderedActive,
    this.selectedFocusTodoId,
    this.computedAtLocal,
  })  : baseFocus = baseFocus ?? focus,
        baseScheduled = baseScheduled ?? scheduled,
        baseDecide = baseDecide ?? decide,
        baseDone = baseDone ?? done,
        baseOrderedActive = baseOrderedActive ?? orderedActive;

  const TaskPrioritySnapshot.empty()
      : source = TaskPrioritySnapshotSource.rules,
        enhancementSource = TaskPriorityEnhancementSource.none,
        focus = const <TaskPriorityEntry>[],
        scheduled = const <TaskPriorityEntry>[],
        decide = const <TaskPriorityEntry>[],
        done = const <TaskPriorityEntry>[],
        orderedActive = const <TaskPriorityEntry>[],
        baseFocus = const <TaskPriorityEntry>[],
        baseScheduled = const <TaskPriorityEntry>[],
        baseDecide = const <TaskPriorityEntry>[],
        baseDone = const <TaskPriorityEntry>[],
        baseOrderedActive = const <TaskPriorityEntry>[],
        selectedFocusTodoId = null,
        computedAtLocal = null;

  final TaskPrioritySnapshotSource source;
  final TaskPriorityEnhancementSource enhancementSource;
  final List<TaskPriorityEntry> focus;
  final List<TaskPriorityEntry> scheduled;
  final List<TaskPriorityEntry> decide;
  final List<TaskPriorityEntry> done;
  final List<TaskPriorityEntry> orderedActive;
  final List<TaskPriorityEntry> baseFocus;
  final List<TaskPriorityEntry> baseScheduled;
  final List<TaskPriorityEntry> baseDecide;
  final List<TaskPriorityEntry> baseDone;
  final List<TaskPriorityEntry> baseOrderedActive;
  final String? selectedFocusTodoId;
  final DateTime? computedAtLocal;

  bool get isEmpty => focus.isEmpty && scheduled.isEmpty && decide.isEmpty;

  bool get hasAiEnhancement =>
      enhancementSource != TaskPriorityEnhancementSource.none;

  TaskPriorityEntry? get basePrimaryFocus {
    final focusTodoId = selectedFocusTodoId;
    if (focusTodoId != null) {
      for (final entry in baseOrderedActive) {
        if (entry.todo.id == focusTodoId) return entry;
      }
    }
    return baseOrderedActive.isEmpty ? null : baseOrderedActive.first;
  }

  List<TaskPriorityEntry> get baseActiveEntries => baseOrderedActive;

  TaskPrioritySnapshot get baseSnapshot => TaskPrioritySnapshot(
        source: TaskPrioritySnapshotSource.rules,
        enhancementSource: TaskPriorityEnhancementSource.none,
        focus: baseFocus,
        scheduled: baseScheduled,
        decide: baseDecide,
        done: baseDone,
        orderedActive: baseOrderedActive,
        selectedFocusTodoId:
            baseOrderedActive.isEmpty ? null : baseOrderedActive.first.todo.id,
        computedAtLocal: computedAtLocal,
      );

  TaskPriorityEntry? get primaryFocus {
    final focusTodoId = selectedFocusTodoId;
    if (focusTodoId != null) {
      for (final entry in orderedActive) {
        if (entry.todo.id == focusTodoId) return entry;
      }
    }
    return orderedActive.isEmpty ? null : orderedActive.first;
  }

  List<TaskPriorityEntry> get activeEntries => orderedActive;

  List<TaskPriorityEntry> get remainingActiveEntries {
    final primaryTodoId = primaryFocus?.todo.id;
    if (primaryTodoId == null) return orderedActive;
    return orderedActive
        .where((entry) => entry.todo.id != primaryTodoId)
        .toList(growable: false);
  }

  List<TaskPriorityEntry> get nextUpEntries => remainingActiveEntries
      .where((entry) => entry.displayBucket == TaskPriorityDisplayBucket.nextUp)
      .toList(growable: false);

  List<TaskPriorityEntry> get backlogEntries => remainingActiveEntries
      .where(
          (entry) => entry.displayBucket == TaskPriorityDisplayBucket.backlog)
      .toList(growable: false);

  List<TaskPriorityEntry> get upcomingDisplayEntries {
    final primary = primaryFocus;
    if (primary == null) return nextUpEntries;
    return <TaskPriorityEntry>[
      primary,
      ...nextUpEntries.where((entry) => entry.todo.id != primary.todo.id),
    ];
  }

  int get upcomingDisplayCount => upcomingDisplayEntries.length;

  int get backlogDisplayCount => backlogEntries.length;

  List<TaskPriorityEntry> get allEntries => <TaskPriorityEntry>[
        ...orderedActive,
        ...done,
      ];

  TaskPrioritySnapshot copyWith({
    TaskPrioritySnapshotSource? source,
    TaskPriorityEnhancementSource? enhancementSource,
    List<TaskPriorityEntry>? focus,
    List<TaskPriorityEntry>? scheduled,
    List<TaskPriorityEntry>? decide,
    List<TaskPriorityEntry>? done,
    List<TaskPriorityEntry>? orderedActive,
    List<TaskPriorityEntry>? baseFocus,
    List<TaskPriorityEntry>? baseScheduled,
    List<TaskPriorityEntry>? baseDecide,
    List<TaskPriorityEntry>? baseDone,
    List<TaskPriorityEntry>? baseOrderedActive,
    String? selectedFocusTodoId,
    bool clearSelectedFocusTodoId = false,
    DateTime? computedAtLocal,
  }) {
    return TaskPrioritySnapshot(
      source: source ?? this.source,
      enhancementSource: enhancementSource ?? this.enhancementSource,
      focus: focus ?? this.focus,
      scheduled: scheduled ?? this.scheduled,
      decide: decide ?? this.decide,
      done: done ?? this.done,
      orderedActive: orderedActive ?? this.orderedActive,
      baseFocus: baseFocus ?? this.baseFocus,
      baseScheduled: baseScheduled ?? this.baseScheduled,
      baseDecide: baseDecide ?? this.baseDecide,
      baseDone: baseDone ?? this.baseDone,
      baseOrderedActive: baseOrderedActive ?? this.baseOrderedActive,
      selectedFocusTodoId: clearSelectedFocusTodoId
          ? null
          : (selectedFocusTodoId ?? this.selectedFocusTodoId),
      computedAtLocal: computedAtLocal ?? this.computedAtLocal,
    );
  }
}
