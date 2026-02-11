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

  Future<void> refresh() async {
    if (!_initialized) {
      await _scheduler.ensureInitialized();
      _initialized = true;
    }

    final todos = await _readTodos();
    final plan = buildReviewReminderPlan(todos, nowUtcMs: _nowUtcMs());

    if (plan == null) {
      if (_lastPlan == null) return;
      _lastPlan = null;
      await _scheduler.cancel();
      return;
    }

    if (_lastPlan == plan) return;

    _lastPlan = plan;
    await _scheduler.schedule(plan);
  }
}
