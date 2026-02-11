import '../../src/rust/db.dart';

const kReviewReminderMinimumLeadTimeMs = 60 * 1000;
const kReviewReminderMaxItems = 32;

final class ReviewReminderItem {
  const ReviewReminderItem({
    required this.todoId,
    required this.todoTitle,
    required this.scheduleAtUtcMs,
  });

  final String todoId;
  final String todoTitle;
  final int scheduleAtUtcMs;

  @override
  int get hashCode =>
      todoId.hashCode ^ todoTitle.hashCode ^ scheduleAtUtcMs.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReviewReminderItem &&
            todoId == other.todoId &&
            todoTitle == other.todoTitle &&
            scheduleAtUtcMs == other.scheduleAtUtcMs;
  }
}

final class ReviewReminderPlan {
  const ReviewReminderPlan({
    required this.pendingCount,
    required this.items,
  });

  final int pendingCount;
  final List<ReviewReminderItem> items;

  @override
  int get hashCode {
    var value = pendingCount.hashCode;
    for (final item in items) {
      value = (value * 31) ^ item.hashCode;
    }
    return value;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReviewReminderPlan) return false;
    if (pendingCount != other.pendingCount) return false;
    if (items.length != other.items.length) return false;

    for (var i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return true;
  }
}

ReviewReminderPlan? buildReviewReminderPlan(
  List<Todo> todos, {
  required int nowUtcMs,
  int minimumLeadTimeMs = kReviewReminderMinimumLeadTimeMs,
  int maxItems = kReviewReminderMaxItems,
}) {
  var pendingCount = 0;
  final items = <ReviewReminderItem>[];

  for (final todo in todos) {
    if (todo.status == 'done' || todo.status == 'dismissed') continue;
    if (todo.dueAtMs != null) continue;

    final stage = todo.reviewStage;
    final nextReviewAtMs = todo.nextReviewAtMs;
    if (stage == null || nextReviewAtMs == null) continue;

    pendingCount += 1;

    final minScheduleAt = nowUtcMs + minimumLeadTimeMs;
    final scheduleAtUtcMs =
        nextReviewAtMs < minScheduleAt ? minScheduleAt : nextReviewAtMs;
    final title = todo.title.trim();

    items.add(
      ReviewReminderItem(
        todoId: todo.id,
        todoTitle: title.isEmpty ? todo.id : title,
        scheduleAtUtcMs: scheduleAtUtcMs,
      ),
    );
  }

  if (pendingCount <= 0 || items.isEmpty) return null;

  items.sort((a, b) {
    final byTime = a.scheduleAtUtcMs.compareTo(b.scheduleAtUtcMs);
    if (byTime != 0) return byTime;
    return a.todoId.compareTo(b.todoId);
  });

  final cappedItems = items.take(maxItems).toList(growable: false);
  return ReviewReminderPlan(
    pendingCount: pendingCount,
    items: cappedItems,
  );
}
