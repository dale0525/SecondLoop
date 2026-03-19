import '../../../src/rust/db.dart';

bool hasTaskPriorityHardGuard({
  required bool isOverdue,
  required bool isDueToday,
}) {
  return isOverdue || isDueToday;
}

bool hasTaskPriorityHardGuardForTodo(
  Todo todo, {
  required DateTime nowLocal,
}) {
  final dueAtMs = todo.dueAtMs;
  if (dueAtMs == null) return false;
  final dueLocal =
      DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
  return dueLocal.isBefore(nowLocal) ||
      (dueLocal.year == nowLocal.year &&
          dueLocal.month == nowLocal.month &&
          dueLocal.day == nowLocal.day);
}
