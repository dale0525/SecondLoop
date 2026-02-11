import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_coordinator.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('schedules reminder for pending review todos', () async {
    final scheduler = _FakeScheduler();
    final coordinator = ReviewReminderNotificationCoordinator(
      scheduler: scheduler,
      nowUtcMs: () => 10000,
      readTodos: () async => const <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review me',
          status: 'inbox',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 11000,
        ),
      ],
    );

    await coordinator.refresh();

    expect(scheduler.initializedCount, 1);
    expect(scheduler.scheduledPlans.length, 1);
    expect(scheduler.scheduledPlans.single.pendingCount, 1);
    expect(scheduler.cancelCount, 0);
  });

  test('does not reschedule when plan is unchanged', () async {
    final scheduler = _FakeScheduler();
    final coordinator = ReviewReminderNotificationCoordinator(
      scheduler: scheduler,
      nowUtcMs: () => 10000,
      readTodos: () async => const <Todo>[
        Todo(
          id: 'todo:1',
          title: 'review me',
          status: 'inbox',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 11000,
        ),
      ],
    );

    await coordinator.refresh();
    await coordinator.refresh();

    expect(scheduler.scheduledPlans.length, 1);
  });

  test('cancels reminder after queue becomes empty', () async {
    final scheduler = _FakeScheduler();
    var includeTodo = true;

    final coordinator = ReviewReminderNotificationCoordinator(
      scheduler: scheduler,
      nowUtcMs: () => 10000,
      readTodos: () async {
        if (!includeTodo) return const <Todo>[];
        return const <Todo>[
          Todo(
            id: 'todo:1',
            title: 'review me',
            status: 'inbox',
            createdAtMs: 1,
            updatedAtMs: 1,
            reviewStage: 0,
            nextReviewAtMs: 11000,
          ),
        ];
      },
    );

    await coordinator.refresh();
    includeTodo = false;
    await coordinator.refresh();

    expect(scheduler.scheduledPlans.length, 1);
    expect(scheduler.cancelCount, 1);
  });
}

final class _FakeScheduler implements ReviewReminderNotificationScheduler {
  int initializedCount = 0;
  int cancelCount = 0;
  final List<ReviewReminderPlan> scheduledPlans = <ReviewReminderPlan>[];

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> ensureInitialized() async {
    initializedCount += 1;
  }

  @override
  Future<void> schedule(ReviewReminderPlan plan) async {
    scheduledPlans.add(plan);
  }
}
