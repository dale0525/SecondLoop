import '../../../src/rust/db.dart';
import 'task_priority_engine.dart';
import 'task_priority_models.dart';

class TaskHubSummary {
  const TaskHubSummary({
    required this.snapshot,
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.backlogCount,
    required this.reviewCount,
    required this.doneCount,
    required this.upcomingPreviewTodos,
    required this.backlogPreviewTodos,
    required this.dueTodos,
    required this.upcomingTodos,
    required this.reviewTodos,
    required this.backlogTodos,
    required this.doneTodos,
    required this.checklistProgressByTodoId,
  });

  const TaskHubSummary.empty()
      : snapshot = const TaskPrioritySnapshot.empty(),
        dueCount = 0,
        overdueCount = 0,
        upcomingCount = 0,
        backlogCount = 0,
        reviewCount = 0,
        doneCount = 0,
        upcomingPreviewTodos = const <Todo>[],
        backlogPreviewTodos = const <Todo>[],
        dueTodos = const <Todo>[],
        upcomingTodos = const <Todo>[],
        reviewTodos = const <Todo>[],
        backlogTodos = const <Todo>[],
        doneTodos = const <Todo>[],
        checklistProgressByTodoId = const <String, TodoChecklistProgress>{};

  final TaskPrioritySnapshot snapshot;
  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final int backlogCount;
  final int reviewCount;
  final int doneCount;
  final List<Todo> upcomingPreviewTodos;
  final List<Todo> backlogPreviewTodos;
  final List<Todo> dueTodos;
  final List<Todo> upcomingTodos;
  final List<Todo> reviewTodos;
  final List<Todo> backlogTodos;
  final List<Todo> doneTodos;
  final Map<String, TodoChecklistProgress> checklistProgressByTodoId;

  bool get hasOverdue => overdueCount > 0;
  bool get hasReview => reviewCount > 0;

  bool get isEmpty =>
      dueTodos.isEmpty && upcomingTodos.isEmpty && backlogTodos.isEmpty;

  static TaskHubSummary fromTodos(
    List<Todo> todos, {
    required DateTime nowLocal,
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    int upcomingPreviewLimit = 4,
    int backlogPreviewLimit = 4,
  }) {
    final snapshot = buildTaskPrioritySnapshot(todos, nowLocal: nowLocal);
    return fromSnapshot(
      snapshot,
      checklistProgress: checklistProgress,
      upcomingPreviewLimit: upcomingPreviewLimit,
      backlogPreviewLimit: backlogPreviewLimit,
    );
  }

  static TaskHubSummary fromSnapshot(
    TaskPrioritySnapshot snapshot, {
    List<TodoChecklistProgress> checklistProgress =
        const <TodoChecklistProgress>[],
    int upcomingPreviewLimit = 4,
    int backlogPreviewLimit = 4,
  }) {
    final dueEntries = snapshot.focus;
    final openEntriesForSummary = snapshot.openEntries;
    final reviewEntriesForSummary = snapshot.activeEntries
        .where((entry) => entry.isReviewDue)
        .toList(growable: false);
    final doneEntries = snapshot.done;

    final upcomingPreview = <Todo>[];
    for (final entry in openEntriesForSummary) {
      if (upcomingPreview.length >= upcomingPreviewLimit) break;
      upcomingPreview.add(entry.todo);
    }

    return TaskHubSummary(
      snapshot: snapshot,
      dueCount: dueEntries.length,
      overdueCount: dueEntries.where((entry) => entry.isOverdue).length,
      upcomingCount: snapshot.openDisplayCount,
      backlogCount: 0,
      reviewCount: reviewEntriesForSummary.length,
      doneCount: doneEntries.length,
      upcomingPreviewTodos: List<Todo>.unmodifiable(upcomingPreview),
      backlogPreviewTodos: const <Todo>[],
      dueTodos: List<Todo>.unmodifiable(
        dueEntries.map((entry) => entry.todo),
      ),
      upcomingTodos: List<Todo>.unmodifiable(
        openEntriesForSummary.map((entry) => entry.todo),
      ),
      reviewTodos: List<Todo>.unmodifiable(
        reviewEntriesForSummary.map((entry) => entry.todo),
      ),
      backlogTodos: const <Todo>[],
      doneTodos: List<Todo>.unmodifiable(
        doneEntries.map((entry) => entry.todo),
      ),
      checklistProgressByTodoId: {
        for (final item in checklistProgress) item.todoId: item,
      },
    );
  }
}
