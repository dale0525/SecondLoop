import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_relative_time.dart';

void main() {
  const labels = TaskHubRelativeTimeLabels(
    noDeadline: 'No deadline',
    today: 'Today',
    inHours: _inHours,
    inDays: _inDays,
    inWeeks: _inWeeks,
    overdueHours: _overdueHours,
    overdueDays: _overdueDays,
    overdueWeeks: _overdueWeeks,
  );

  test('returns null for no-deadline tasks', () {
    final now = DateTime(2026, 4, 13, 10);

    final result = formatTaskHubRelativeTime(
      dueAtMs: null,
      nowLocal: now,
      labels: labels,
    );

    expect(result, isNull);
  });

  test('formats same-day deadlines as today', () {
    final now = DateTime(2026, 4, 13, 10);
    final due = DateTime(2026, 4, 13, 18).toUtc().millisecondsSinceEpoch;

    final result = formatTaskHubRelativeTime(
      dueAtMs: due,
      nowLocal: now,
      labels: labels,
    );

    expect(result, 'Today');
  });

  test('formats short overdue deadlines in hours', () {
    final now = DateTime(2026, 4, 13, 10);
    final due =
        now.subtract(const Duration(hours: 3)).toUtc().millisecondsSinceEpoch;

    final result = formatTaskHubRelativeTime(
      dueAtMs: due,
      nowLocal: now,
      labels: labels,
    );

    expect(result, 'Overdue by 3 h');
  });

  test('formats future deadlines in days and weeks', () {
    final now = DateTime(2026, 4, 13, 10);
    final inThreeDays = now
        .add(const Duration(days: 3, hours: 1))
        .toUtc()
        .millisecondsSinceEpoch;
    final inTwoWeeks =
        now.add(const Duration(days: 14)).toUtc().millisecondsSinceEpoch;

    expect(
      formatTaskHubRelativeTime(
        dueAtMs: inThreeDays,
        nowLocal: now,
        labels: labels,
      ),
      'In 3 d',
    );
    expect(
      formatTaskHubRelativeTime(
        dueAtMs: inTwoWeeks,
        nowLocal: now,
        labels: labels,
      ),
      'In 2 w',
    );
  });
}

String _inHours(int count) => 'In $count h';
String _inDays(int count) => 'In $count d';
String _inWeeks(int count) => 'In $count w';
String _overdueHours(int count) => 'Overdue by $count h';
String _overdueDays(int count) => 'Overdue by $count d';
String _overdueWeeks(int count) => 'Overdue by $count w';
