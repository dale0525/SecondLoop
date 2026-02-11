import '../../src/rust/db.dart';

const kReviewReminderMinimumLeadTimeMs = 60 * 1000;

final class ReviewReminderPlan {
  const ReviewReminderPlan({
    required this.pendingCount,
    required this.scheduleAtUtcMs,
  });

  final int pendingCount;
  final int scheduleAtUtcMs;

  @override
  int get hashCode => pendingCount.hashCode ^ scheduleAtUtcMs.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReviewReminderPlan &&
            pendingCount == other.pendingCount &&
            scheduleAtUtcMs == other.scheduleAtUtcMs;
  }
}

ReviewReminderPlan? buildReviewReminderPlan(
  List<Todo> todos, {
  required int nowUtcMs,
  int minimumLeadTimeMs = kReviewReminderMinimumLeadTimeMs,
}) {
  var pendingCount = 0;
  int? earliestNextReviewAtMs;

  for (final todo in todos) {
    if (todo.status == 'done' || todo.status == 'dismissed') continue;
    if (todo.dueAtMs != null) continue;

    final stage = todo.reviewStage;
    final nextReviewAtMs = todo.nextReviewAtMs;
    if (stage == null || nextReviewAtMs == null) continue;

    pendingCount += 1;
    if (earliestNextReviewAtMs == null ||
        nextReviewAtMs < earliestNextReviewAtMs) {
      earliestNextReviewAtMs = nextReviewAtMs;
    }
  }

  if (pendingCount <= 0 || earliestNextReviewAtMs == null) return null;

  final minScheduleAt = nowUtcMs + minimumLeadTimeMs;
  final scheduleAtUtcMs = earliestNextReviewAtMs < minScheduleAt
      ? minScheduleAt
      : earliestNextReviewAtMs;

  return ReviewReminderPlan(
    pendingCount: pendingCount,
    scheduleAtUtcMs: scheduleAtUtcMs,
  );
}
