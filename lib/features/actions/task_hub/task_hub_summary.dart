import '../../../src/rust/db.dart';

bool _isSameLocalDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class TaskHubSummary {
  const TaskHubSummary({
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.unscheduledCount,
    required this.dueReviewCount,
    required this.scheduledPreviewTodos,
    required this.unscheduledPreviewTodos,
    required this.dueTodos,
    required this.upcomingTodos,
    required this.dueReviewTodos,
    required this.unscheduledTodos,
  });

  const TaskHubSummary.empty()
      : dueCount = 0,
        overdueCount = 0,
        upcomingCount = 0,
        unscheduledCount = 0,
        dueReviewCount = 0,
        scheduledPreviewTodos = const <Todo>[],
        unscheduledPreviewTodos = const <Todo>[],
        dueTodos = const <Todo>[],
        upcomingTodos = const <Todo>[],
        dueReviewTodos = const <Todo>[],
        unscheduledTodos = const <Todo>[];

  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final int unscheduledCount;
  final int dueReviewCount;

  final List<Todo> scheduledPreviewTodos;
  final List<Todo> unscheduledPreviewTodos;

  final List<Todo> dueTodos;
  final List<Todo> upcomingTodos;
  final List<Todo> dueReviewTodos;
  final List<Todo> unscheduledTodos;

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
    int scheduledPreviewLimit = 4,
    int unscheduledPreviewLimit = 4,
  }) {
    final due = <({Todo todo, DateTime dueLocal})>[];
    final upcoming = <({Todo todo, DateTime dueLocal})>[];
    final dueReview = <Todo>[];
    final unscheduled = <Todo>[];

    final nowUtcMs = nowLocal.toUtc().millisecondsSinceEpoch;

    for (final todo in todos) {
      if (todo.status == 'done' || todo.status == 'dismissed') continue;

      final dueMs = todo.dueAtMs;
      if (dueMs != null) {
        final dueLocal =
            DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true).toLocal();
        final isOverdue = dueLocal.isBefore(nowLocal);
        final isToday = _isSameLocalDate(dueLocal, nowLocal);
        if (isOverdue || isToday) {
          due.add((todo: todo, dueLocal: dueLocal));
        } else {
          upcoming.add((todo: todo, dueLocal: dueLocal));
        }
        continue;
      }

      final isDueReview = todo.reviewStage != null &&
          todo.nextReviewAtMs != null &&
          todo.nextReviewAtMs! <= nowUtcMs;
      if (isDueReview) {
        dueReview.add(todo);
        continue;
      }
      unscheduled.add(todo);
    }

    due.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    upcoming.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    dueReview.sort((a, b) {
      final aNext = a.nextReviewAtMs ?? 9223372036854775807;
      final bNext = b.nextReviewAtMs ?? 9223372036854775807;
      if (aNext != bNext) return aNext.compareTo(bNext);
      return b.updatedAtMs.compareTo(a.updatedAtMs);
    });
    unscheduled.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

    final scheduledPreview = <Todo>[];
    for (final item in due) {
      if (scheduledPreview.length >= scheduledPreviewLimit) break;
      scheduledPreview.add(item.todo);
    }
    for (final item in upcoming) {
      if (scheduledPreview.length >= scheduledPreviewLimit) break;
      scheduledPreview.add(item.todo);
    }

    final unscheduledPreview = <Todo>[];
    for (final item in dueReview) {
      if (unscheduledPreview.length >= unscheduledPreviewLimit) break;
      unscheduledPreview.add(item);
    }
    for (final item in unscheduled) {
      if (unscheduledPreview.length >= unscheduledPreviewLimit) break;
      unscheduledPreview.add(item);
    }

    final overdueCount = due.where((e) => e.dueLocal.isBefore(nowLocal)).length;

    return TaskHubSummary(
      dueCount: due.length,
      overdueCount: overdueCount,
      upcomingCount: upcoming.length,
      unscheduledCount: dueReview.length + unscheduled.length,
      dueReviewCount: dueReview.length,
      scheduledPreviewTodos: scheduledPreview,
      unscheduledPreviewTodos: unscheduledPreview,
      dueTodos: due.map((e) => e.todo).toList(growable: false),
      upcomingTodos: upcoming.map((e) => e.todo).toList(growable: false),
      dueReviewTodos: dueReview.toList(growable: false),
      unscheduledTodos: unscheduled.toList(growable: false),
    );
  }
}
