import '../../../src/rust/db.dart';

bool hasTaskPriorityHardGuard({
  required bool isOverdue,
  required bool isDueToday,
  required bool isInProgress,
}) {
  return isOverdue || isDueToday || isInProgress;
}

bool hasTaskPriorityHardGuardForTodo(
  Todo todo, {
  required DateTime nowLocal,
}) {
  if (todo.status == 'in_progress') return true;
  final dueAtMs = todo.dueAtMs;
  if (dueAtMs == null) return false;
  final dueLocal =
      DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
  return dueLocal.isBefore(nowLocal) ||
      (dueLocal.year == nowLocal.year &&
          dueLocal.month == nowLocal.month &&
          dueLocal.day == nowLocal.day);
}
