import '../../../src/rust/db.dart';
import 'task_priority_engine.dart';
import 'task_priority_models.dart';

class TaskHubSummary {
  const TaskHubSummary({
    required this.snapshot,
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.unscheduledCount,
    required this.dueReviewCount,
    required this.doneCount,
    required this.scheduledPreviewTodos,
    required this.unscheduledPreviewTodos,
    required this.dueTodos,
    required this.upcomingTodos,
    required this.dueReviewTodos,
    required this.unscheduledTodos,
    required this.doneTodos,
    required this.checklistProgressByTodoId,
  });

  const TaskHubSummary.empty()
      : snapshot = const TaskPrioritySnapshot.empty(),
        dueCount = 0,
        overdueCount = 0,
        upcomingCount = 0,
        unscheduledCount = 0,
        dueReviewCount = 0,
        doneCount = 0,
        scheduledPreviewTodos = const <Todo>[],
        unscheduledPreviewTodos = const <Todo>[],
        dueTodos = const <Todo>[],
        upcomingTodos = const <Todo>[],
        dueReviewTodos = const <Todo>[],
        unscheduledTodos = const <Todo>[],
        doneTodos = const <Todo>[],
        checklistProgressByTodoId = const <String, TodoChecklistProgress>{};

  final TaskPrioritySnapshot snapshot;
  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final int unscheduledCount;
  final int dueReviewCount;
  final int doneCount;
  final List<Todo> scheduledPreviewTodos;
  final List<Todo> unscheduledPreviewTodos;
  final List<Todo> dueTodos;
  final List<Todo> upcomingTodos;
  final List<Todo> dueReviewTodos;
  final List<Todo> unscheduledTodos;
  final List<Todo> doneTodos;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;

  bool get hasOverdue => overdueCount > 0;
  bool get hasDueReview => dueReviewCount > 0;

  bool get isEmpty =>
      dueCount == 0 &&
      upcomingCount == 0 &&
      unscheduledCount == 0 &&
      dueReviewCount == 0;

  static TaskHubSummary fromTodos(
    List<Todo> todos, {
    required DateTime nowLocal,
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    int scheduledPreviewLimit = 4,
    int unscheduledPreviewLimit = 4,
  }) {
    final snapshot = buildTaskPrioritySnapshot(todos, nowLocal: nowLocal);
    return fromSnapshot(
      snapshot,
      checklistProgress: checklistProgress,
      scheduledPreviewLimit: scheduledPreviewLimit,
      unscheduledPreviewLimit: unscheduledPreviewLimit,
    );
  }

  static TaskHubSummary fromSnapshot(
    TaskPrioritySnapshot snapshot, {
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    int scheduledPreviewLimit = 4,
    int unscheduledPreviewLimit = 4,
  }) {
    final primaryFocus = snapshot.primaryFocus;
    final primaryFocusId = primaryFocus?.todo.id;
    final dueEntries = snapshot.focus;
    final upcomingEntries = snapshot.scheduled;
    final scheduledPreviewEntries = primaryFocus == null
        ? <TaskPriorityEntry>[...dueEntries, ...upcomingEntries]
        : <TaskPriorityEntry>[
            primaryFocus,
            ...dueEntries
                .where((entry) => entry.todo.id != primaryFocus.todo.id),
            ...upcomingEntries
                .where((entry) => entry.todo.id != primaryFocus.todo.id),
          ];
    final dueReviewEntries = snapshot.decide
        .where((entry) => entry.isReviewDue)
        .toList(growable: false);
    final unscheduledEntries = snapshot.decide
        .where((entry) => !entry.isReviewDue)
        .toList(growable: false);
    final previewDueReviewEntries = dueReviewEntries
        .where((entry) => entry.todo.id != primaryFocusId)
        .toList(growable: false);
    final previewUnscheduledEntries = unscheduledEntries
        .where((entry) => entry.todo.id != primaryFocusId)
        .toList(growable: false);
    final doneEntries = snapshot.done;

    final scheduledPreview = <Todo>[];
    for (final entry in scheduledPreviewEntries) {
      if (scheduledPreview.length >= scheduledPreviewLimit) break;
      scheduledPreview.add(entry.todo);
    }

    final unscheduledPreview = <Todo>[];
    for (final entry in previewDueReviewEntries) {
      if (unscheduledPreview.length >= unscheduledPreviewLimit) break;
      unscheduledPreview.add(entry.todo);
    }
    for (final entry in previewUnscheduledEntries) {
      if (unscheduledPreview.length >= unscheduledPreviewLimit) break;
      unscheduledPreview.add(entry.todo);
    }

    return TaskHubSummary(
      snapshot: snapshot,
      dueCount: dueEntries.length,
      overdueCount: dueEntries.where((entry) => entry.isOverdue).length,
      upcomingCount: upcomingEntries.length,
      unscheduledCount: unscheduledEntries.length + dueReviewEntries.length,
      dueReviewCount: dueReviewEntries.length,
      doneCount: doneEntries.length,
      scheduledPreviewTodos: List<Todo>.unmodifiable(scheduledPreview),
      unscheduledPreviewTodos: List<Todo>.unmodifiable(unscheduledPreview),
      dueTodos: List<Todo>.unmodifiable(
        dueEntries.map((entry) => entry.todo),
      ),
      upcomingTodos: List<Todo>.unmodifiable(
        upcomingEntries.map((entry) => entry.todo),
      ),
      dueReviewTodos: List<Todo>.unmodifiable(
        dueReviewEntries.map((entry) => entry.todo),
      ),
      unscheduledTodos: List<Todo>.unmodifiable(
        unscheduledEntries.map((entry) => entry.todo),
      ),
      doneTodos: List<Todo>.unmodifiable(
        doneEntries.map((entry) => entry.todo),
      ),
      checklistProgressByTodoId: {
        for (final item in checklistProgress) item.todoId: item,
      },
    );
  }
}
