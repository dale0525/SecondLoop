import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/actions/todo/todo_history_summary.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('computes natural week windows (Mon-Sun, end exclusive)', () {
    final now = DateTime(2026, 1, 25, 13, 50); // Sunday

    final thisWeek = naturalWeekWindow(now, offsetWeeks: 0, spanWeeks: 1);
    expect(thisWeek.startLocal, DateTime(2026, 1, 19));
    expect(thisWeek.endLocalExclusive, DateTime(2026, 1, 26));

    final lastWeek = naturalWeekWindow(now, offsetWeeks: 1, spanWeeks: 1);
    expect(lastWeek.startLocal, DateTime(2026, 1, 12));
    expect(lastWeek.endLocalExclusive, DateTime(2026, 1, 19));

    final lastTwoWeeks = naturalWeekWindow(now, offsetWeeks: 2, spanWeeks: 2);
    expect(lastTwoWeeks.startLocal, DateTime(2026, 1, 5));
    expect(lastTwoWeeks.endLocalExclusive, DateTime(2026, 1, 19));
  });

  test('builds a summary from created todos + status changes', () {
    final window = WeekWindow(
      startLocal: DateTime(2026, 1, 5),
      endLocalExclusive: DateTime(2026, 1, 19),
    );

    final created = <Todo>[
      const Todo(
        id: 't1',
        title: '下午 2 点接待客户',
        status: 'open',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
      const Todo(
        id: 't2',
        title: '周末给狗狗做口粮',
        status: 'open',
        createdAtMs: 2,
        updatedAtMs: 2,
      ),
    ];

    final activities = <TodoActivity>[
      const TodoActivity(
        id: 'a1',
        todoId: 't1',
        activityType: 'status_change',
        fromStatus: 'open',
        toStatus: 'in_progress',
        createdAtMs: 10,
      ),
      const TodoActivity(
        id: 'a2',
        todoId: 't2',
        activityType: 'status_change',
        fromStatus: 'in_progress',
        toStatus: 'done',
        createdAtMs: 11,
      ),
      const TodoActivity(
        id: 'a3',
        todoId: 't1',
        activityType: 'status_change',
        fromStatus: 'in_progress',
        toStatus: 'dismissed',
        createdAtMs: 12,
      ),
    ];

    final titlesById = <String, String>{
      for (final t in created) t.id: t.title,
      't3': '其它未映射标题',
    };

    final summary = buildTodoHistorySummary(
      window: window,
      createdTodos: created,
      activities: activities,
      todoTitlesById: titlesById,
    );

    expect(summary.created.map((e) => e.todoId), containsAll(['t1', 't2']));
    expect(summary.started.map((e) => e.todoId), contains('t1'));
    expect(summary.done.map((e) => e.todoId), contains('t2'));
    expect(summary.dismissed.map((e) => e.todoId), contains('t1'));

    final text = formatTodoHistorySummaryText(
      summary,
      labels: TodoHistoryLabels.zhCn,
    );
    expect(text, contains('新增'));
    expect(text, contains('开始'));
    expect(text, contains('完成'));
    expect(text, contains('不再提醒'));
  });
}
