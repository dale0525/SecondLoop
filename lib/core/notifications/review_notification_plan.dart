import '../../src/rust/db.dart';

const kReviewReminderMinimumLeadTimeMs = 5 * 1000;
const kReviewReminderMaxItems = 32;

enum ReviewReminderItemKind {
  reviewQueue,
  dueTodo,
}

final class ReviewReminderItem {
  const ReviewReminderItem({
    required this.todoId,
    required this.todoTitle,
    required this.sourceAtUtcMs,
    required this.scheduleAtUtcMs,
    required this.kind,
  });

  final String todoId;
  final String todoTitle;
  final int sourceAtUtcMs;
  final int scheduleAtUtcMs;
  final ReviewReminderItemKind kind;

  @override
  int get hashCode =>
      todoId.hashCode ^
      todoTitle.hashCode ^
      sourceAtUtcMs.hashCode ^
      scheduleAtUtcMs.hashCode ^
      kind.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReviewReminderItem &&
            todoId == other.todoId &&
            todoTitle == other.todoTitle &&
            sourceAtUtcMs == other.sourceAtUtcMs &&
            scheduleAtUtcMs == other.scheduleAtUtcMs &&
            kind == other.kind;
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

  final minScheduleAt = nowUtcMs + minimumLeadTimeMs;

  for (final todo in todos) {
    if (todo.status == 'done' || todo.status == 'dismissed') continue;

    final title = todo.title.trim();
    final todoTitle = title.isEmpty ? todo.id : title;
    final dueAtMs = todo.dueAtMs;

    if (dueAtMs != null) {
      pendingCount += 1;
      final scheduleAtUtcMs = dueAtMs < minScheduleAt ? minScheduleAt : dueAtMs;
      items.add(
        ReviewReminderItem(
          todoId: todo.id,
          todoTitle: todoTitle,
          sourceAtUtcMs: dueAtMs,
          scheduleAtUtcMs: scheduleAtUtcMs,
          kind: ReviewReminderItemKind.dueTodo,
        ),
      );
      continue;
    }

    final stage = todo.reviewStage;
    final nextReviewAtMs = todo.nextReviewAtMs;
    if (stage == null || nextReviewAtMs == null) continue;

    pendingCount += 1;

    final scheduleAtUtcMs =
        nextReviewAtMs < minScheduleAt ? minScheduleAt : nextReviewAtMs;
    items.add(
      ReviewReminderItem(
        todoId: todo.id,
        todoTitle: todoTitle,
        sourceAtUtcMs: nextReviewAtMs,
        scheduleAtUtcMs: scheduleAtUtcMs,
        kind: ReviewReminderItemKind.reviewQueue,
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
