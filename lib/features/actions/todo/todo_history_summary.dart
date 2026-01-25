import '../../../src/rust/db.dart';

class WeekWindow {
  const WeekWindow({
    required this.startLocal,
    required this.endLocalExclusive,
  });

  final DateTime startLocal;
  final DateTime endLocalExclusive;

  int get startUtcMs => startLocal.toUtc().millisecondsSinceEpoch;
  int get endUtcMsExclusive => endLocalExclusive.toUtc().millisecondsSinceEpoch;
}

WeekWindow naturalWeekWindow(
  DateTime nowLocal, {
  required int offsetWeeks,
  required int spanWeeks,
}) {
  final anchor = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final daysFromMonday = anchor.weekday - DateTime.monday;
  final monday = anchor.subtract(Duration(days: daysFromMonday));

  final startLocal = monday.subtract(Duration(days: offsetWeeks * 7));
  final endLocalExclusive = startLocal.add(Duration(days: spanWeeks * 7));

  return WeekWindow(
      startLocal: startLocal, endLocalExclusive: endLocalExclusive);
}

class TodoHistoryEntry {
  const TodoHistoryEntry({
    required this.todoId,
    required this.title,
    required this.atUtcMs,
  });

  final String todoId;
  final String title;
  final int atUtcMs;
}

class TodoHistorySummary {
  const TodoHistorySummary({
    required this.window,
    required this.created,
    required this.started,
    required this.done,
    required this.dismissed,
  });

  final WeekWindow window;
  final List<TodoHistoryEntry> created;
  final List<TodoHistoryEntry> started;
  final List<TodoHistoryEntry> done;
  final List<TodoHistoryEntry> dismissed;
}

TodoHistorySummary buildTodoHistorySummary({
  required WeekWindow window,
  required List<Todo> createdTodos,
  required List<TodoActivity> activities,
  required Map<String, String> todoTitlesById,
}) {
  final created = createdTodos
      .map(
        (t) => TodoHistoryEntry(
          todoId: t.id,
          title: t.title,
          atUtcMs: t.createdAtMs,
        ),
      )
      .toList(growable: false)
    ..sort((a, b) => a.atUtcMs.compareTo(b.atUtcMs));

  final startedByTodoId = <String, TodoHistoryEntry>{};
  final doneByTodoId = <String, TodoHistoryEntry>{};
  final dismissedByTodoId = <String, TodoHistoryEntry>{};

  for (final activity in activities) {
    if (activity.activityType != 'status_change') continue;
    final to = activity.toStatus;
    if (to == null) continue;

    final title = todoTitlesById[activity.todoId] ?? activity.todoId;
    final entry = TodoHistoryEntry(
      todoId: activity.todoId,
      title: title,
      atUtcMs: activity.createdAtMs,
    );

    switch (to) {
      case 'in_progress':
        final existing = startedByTodoId[activity.todoId];
        if (existing == null || entry.atUtcMs > existing.atUtcMs) {
          startedByTodoId[activity.todoId] = entry;
        }
        break;
      case 'done':
        final existing = doneByTodoId[activity.todoId];
        if (existing == null || entry.atUtcMs > existing.atUtcMs) {
          doneByTodoId[activity.todoId] = entry;
        }
        break;
      case 'dismissed':
        final existing = dismissedByTodoId[activity.todoId];
        if (existing == null || entry.atUtcMs > existing.atUtcMs) {
          dismissedByTodoId[activity.todoId] = entry;
        }
        break;
    }
  }

  final started = startedByTodoId.values.toList(growable: false)
    ..sort((a, b) => a.atUtcMs.compareTo(b.atUtcMs));
  final done = doneByTodoId.values.toList(growable: false)
    ..sort((a, b) => a.atUtcMs.compareTo(b.atUtcMs));
  final dismissed = dismissedByTodoId.values.toList(growable: false)
    ..sort((a, b) => a.atUtcMs.compareTo(b.atUtcMs));

  return TodoHistorySummary(
    window: window,
    created: created,
    started: started,
    done: done,
    dismissed: dismissed,
  );
}

class TodoHistoryLabels {
  const TodoHistoryLabels({
    required this.created,
    required this.started,
    required this.done,
    required this.dismissed,
  });

  final String created;
  final String started;
  final String done;
  final String dismissed;

  static const zhCn = TodoHistoryLabels(
    created: '新增',
    started: '开始',
    done: '完成',
    dismissed: '不再提醒',
  );

  static const en = TodoHistoryLabels(
    created: 'Created',
    started: 'Started',
    done: 'Done',
    dismissed: 'Dismissed',
  );
}

String formatTodoHistorySummaryText(
  TodoHistorySummary summary, {
  required TodoHistoryLabels labels,
}) {
  final start = summary.window.startLocal;
  final endInclusive =
      summary.window.endLocalExclusive.subtract(const Duration(days: 1));
  final rangeText =
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}'
      ' ~ '
      '${endInclusive.year}-${endInclusive.month.toString().padLeft(2, '0')}-${endInclusive.day.toString().padLeft(2, '0')}';

  final buf = StringBuffer();
  buf.writeln(rangeText);

  void section(String title, List<TodoHistoryEntry> entries) {
    buf.writeln();
    buf.writeln('$title (${entries.length})');
    for (final entry in entries) {
      buf.writeln('- ${entry.title}');
    }
  }

  section(labels.created, summary.created);
  section(labels.started, summary.started);
  section(labels.done, summary.done);
  section(labels.dismissed, summary.dismissed);

  return buf.toString().trimRight();
}
