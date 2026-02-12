import '../../src/rust/db.dart';
import 'review_notification_plan.dart';
import 'review_reminder_notification_scheduler.dart';

typedef ReviewTodosReader = Future<List<Todo>> Function();

final class ReviewReminderNotificationCoordinator {
  ReviewReminderNotificationCoordinator({
    required ReviewReminderNotificationScheduler scheduler,
    required ReviewTodosReader readTodos,
    int Function()? nowUtcMs,
  })  : _scheduler = scheduler,
        _readTodos = readTodos,
        _nowUtcMs =
            nowUtcMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final ReviewReminderNotificationScheduler _scheduler;
  final ReviewTodosReader _readTodos;
  final int Function() _nowUtcMs;

  bool _initialized = false;
  ReviewReminderPlan? _lastPlan;
  final Map<String, int> _overdueScheduleBySourceKey = <String, int>{};

  Future<void> refresh() async {
    if (!_initialized) {
      await _scheduler.ensureInitialized();
      _initialized = true;
    }

    final nowUtcMs = _nowUtcMs();
    final todos = await _readTodos();
    final builtPlan = buildReviewReminderPlan(todos, nowUtcMs: nowUtcMs);

    if (builtPlan == null) {
      _overdueScheduleBySourceKey.clear();
      if (_lastPlan == null) return;
      _lastPlan = null;
      await _scheduler.cancel();
      return;
    }

    final plan = _stabilizePlanForOverdueCatchUp(
      builtPlan,
      nowUtcMs: nowUtcMs,
    );

    if (_lastPlan == plan) return;

    _lastPlan = plan;
    await _scheduler.schedule(plan);
  }

  ReviewReminderPlan _stabilizePlanForOverdueCatchUp(
    ReviewReminderPlan plan, {
    required int nowUtcMs,
  }) {
    final normalizedItems = <ReviewReminderItem>[];
    final activeOverdueKeys = <String>{};

    for (final item in plan.items) {
      if (item.sourceAtUtcMs >= nowUtcMs) {
        normalizedItems.add(item);
        continue;
      }

      final key = _overdueSourceKey(item);
      activeOverdueKeys.add(key);
      final scheduledAtUtcMs = _overdueScheduleBySourceKey[key];

      if (scheduledAtUtcMs == null) {
        _overdueScheduleBySourceKey[key] = item.scheduleAtUtcMs;
        normalizedItems.add(item);
        continue;
      }

      if (scheduledAtUtcMs > nowUtcMs) {
        normalizedItems.add(
          scheduledAtUtcMs == item.scheduleAtUtcMs
              ? item
              : ReviewReminderItem(
                  todoId: item.todoId,
                  todoTitle: item.todoTitle,
                  sourceAtUtcMs: item.sourceAtUtcMs,
                  scheduleAtUtcMs: scheduledAtUtcMs,
                  kind: item.kind,
                ),
        );
      }
    }

    _overdueScheduleBySourceKey.removeWhere(
      (key, _) => !activeOverdueKeys.contains(key),
    );

    return ReviewReminderPlan(
      pendingCount: plan.pendingCount,
      items: normalizedItems,
    );
  }

  String _overdueSourceKey(ReviewReminderItem item) {
    return '${item.kind.name}:${item.todoId}:${item.sourceAtUtcMs}';
  }
}
