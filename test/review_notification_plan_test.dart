import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('returns null when there are no review-queue todos', () {
    final plan = buildReviewReminderPlan(
      const <Todo>[
        Todo(
          id: 'todo:done',
          title: 'done',
          status: 'done',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 1000,
        ),
      ],
      nowUtcMs: 10000,
    );

    expect(plan, isNull);
  });

  test('builds per-item schedule and sorts by schedule time', () {
    final plan = buildReviewReminderPlan(
      const <Todo>[
        Todo(
          id: 'todo:2',
          title: 'second',
          status: 'in_progress',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 1,
          nextReviewAtMs: 72000,
        ),
        Todo(
          id: 'todo:1',
          title: 'first',
          status: 'inbox',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 71000,
        ),
        Todo(
          id: 'todo:3',
          title: 'scheduled todo should be ignored',
          status: 'open',
          dueAtMs: 15000,
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 73000,
        ),
      ],
      nowUtcMs: 10000,
    );

    expect(plan, isNotNull);
    expect(plan!.pendingCount, 2);
    expect(plan.items.length, 2);
    expect(plan.items[0].todoId, 'todo:1');
    expect(plan.items[0].todoTitle, 'first');
    expect(plan.items[0].scheduleAtUtcMs, 71000);
    expect(plan.items[1].todoId, 'todo:2');
    expect(plan.items[1].scheduleAtUtcMs, 72000);
  });

  test('bumps past schedule time to a near-future safety window', () {
    const nowUtcMs = 20000;
    final plan = buildReviewReminderPlan(
      const <Todo>[
        Todo(
          id: 'todo:1',
          title: 'past due',
          status: 'inbox',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 10000,
        ),
      ],
      nowUtcMs: nowUtcMs,
    );

    expect(plan, isNotNull);
    expect(plan!.pendingCount, 1);
    expect(plan.items.length, 1);
    expect(
      plan.items.single.scheduleAtUtcMs,
      nowUtcMs + kReviewReminderMinimumLeadTimeMs,
    );
  });

  test('caps max scheduled notifications while retaining pending count', () {
    final todos = <Todo>[];
    for (var i = 0; i < 5; i++) {
      todos.add(
        Todo(
          id: 'todo:$i',
          title: 'todo-$i',
          status: 'inbox',
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: 0,
          nextReviewAtMs: 80000 + i,
        ),
      );
    }

    final plan = buildReviewReminderPlan(
      todos,
      nowUtcMs: 1000,
      maxItems: 3,
    );

    expect(plan, isNotNull);
    expect(plan!.pendingCount, 5);
    expect(plan.items.length, 3);
  });
}
