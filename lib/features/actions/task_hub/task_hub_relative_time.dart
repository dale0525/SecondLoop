import 'dart:math' as math;

final class TaskHubRelativeTimeLabels {
  const TaskHubRelativeTimeLabels({
    required this.noDeadline,
    required this.today,
    required this.inHours,
    required this.inDays,
    required this.inWeeks,
    required this.overdueHours,
    required this.overdueDays,
    required this.overdueWeeks,
  });

  final String noDeadline;
  final String today;
  final String Function(int count) inHours;
  final String Function(int count) inDays;
  final String Function(int count) inWeeks;
  final String Function(int count) overdueHours;
  final String Function(int count) overdueDays;
  final String Function(int count) overdueWeeks;
}

bool _isSameLocalDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String formatTaskHubRelativeTime({
  required int? dueAtMs,
  required DateTime nowLocal,
  required TaskHubRelativeTimeLabels labels,
}) {
  if (dueAtMs == null) return labels.noDeadline;

  final dueLocal =
      DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
  final diff = dueLocal.difference(nowLocal);
  final absHours = math.max(1, diff.inHours.abs());
  final absDays = math.max(1, diff.inDays.abs());
  final absWeeks = math.max(1, (absDays / 7).ceil());

  if (diff.isNegative) {
    if (absHours < 24) return labels.overdueHours(absHours);
    if (absDays < 7) return labels.overdueDays(absDays);
    return labels.overdueWeeks(absWeeks);
  }

  if (_isSameLocalDate(dueLocal, nowLocal)) return labels.today;
  if (diff.inHours < 24) return labels.inHours(math.max(1, diff.inHours));
  if (diff.inDays < 7) return labels.inDays(math.max(1, diff.inDays));
  return labels.inWeeks(absWeeks);
}
