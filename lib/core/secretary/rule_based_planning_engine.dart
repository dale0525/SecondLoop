import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import 'secretary_models.dart';

class RuleBasedPlanningEngine {
  const RuleBasedPlanningEngine({
    required DateTime Function() nowLocal,
  }) : _nowLocal = nowLocal;

  final DateTime Function() _nowLocal;

  SecretaryPlan generateDailyPlan(List<Todo> todos) {
    final now = _nowLocal();
    final openTodos = todos.where(_isOpenTodo).toList(growable: false);
    final focus = <SecretaryPlanItem>[];
    final dueSoon = <SecretaryPlanItem>[];
    final needsDecision = <SecretaryPlanItem>[];
    final missingNextAction = <SecretaryPlanItem>[];

    for (final todo in openTodos) {
      final dueAtMs = platformIntToNullableInt(todo.dueAtMs);
      final dueAt =
          dueAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dueAtMs);
      final itemBase = _itemBase(todo, dueAtMs: dueAtMs);

      if (dueAt != null && !_isAfterTomorrow(dueAt, now)) {
        if (_isDueTodayOrEarlier(dueAt, now)) {
          focus.add(
            itemBase.copyWith(
              reason: dueAt.isBefore(now) ? 'Overdue' : 'Due today',
              requiresConfirmation: true,
            ),
          );
        } else {
          dueSoon.add(itemBase.copyWith(reason: 'Due tomorrow'));
        }
        continue;
      }

      if (_needsDecision(todo, now)) {
        needsDecision.add(
          itemBase.copyWith(
            reason: 'Stale or repeatedly deferred',
            requiresConfirmation: true,
          ),
        );
        continue;
      }

      if (dueAt == null) {
        missingNextAction.add(
          itemBase.copyWith(reason: 'No schedule or next action'),
        );
      }
    }

    focus.sort(_sortByDueThenUpdated);
    dueSoon.sort(_sortByDueThenUpdated);
    needsDecision.sort(_sortByUpdatedOldestFirst);
    missingNextAction.sort(_sortByUpdatedOldestFirst);

    return SecretaryPlan(
      id: 'daily-plan-${now.millisecondsSinceEpoch}',
      title: 'Daily plan',
      generatedAtMs: now.millisecondsSinceEpoch,
      route: 'local_rules',
      sections: SecretaryPlanSections(
        focus: focus.take(5).toList(growable: false),
        dueSoon: dueSoon.take(5).toList(growable: false),
        needsDecision: needsDecision.take(5).toList(growable: false),
        missingNextAction: missingNextAction.take(5).toList(growable: false),
      ),
    );
  }

  bool _isOpenTodo(Todo todo) {
    final status = todo.status.toLowerCase();
    return status != 'done' &&
        status != 'completed' &&
        status != 'archived' &&
        status != 'deleted';
  }

  SecretaryPlanItem _itemBase(Todo todo, {required int? dueAtMs}) {
    return SecretaryPlanItem(
      id: 'plan-item-${todo.id}',
      todoId: todo.id,
      title: todo.title,
      reason: '',
      dueAtMs: dueAtMs,
    );
  }

  bool _isDueTodayOrEarlier(DateTime dueAt, DateTime now) {
    return !_startOfDay(dueAt).isAfter(_startOfDay(now));
  }

  bool _isAfterTomorrow(DateTime dueAt, DateTime now) {
    return _startOfDay(dueAt)
        .isAfter(_startOfDay(now).add(const Duration(days: 1)));
  }

  bool _needsDecision(Todo todo, DateTime now) {
    final reviewStage = platformIntToNullableInt(todo.reviewStage) ?? 0;
    if (reviewStage >= 2) return true;

    final nextReviewAtMs = platformIntToNullableInt(todo.nextReviewAtMs);
    if (nextReviewAtMs != null &&
        nextReviewAtMs <= now.millisecondsSinceEpoch) {
      return true;
    }

    final updatedAtMs = platformIntToInt(todo.updatedAtMs);
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    return now.difference(updatedAt) >= const Duration(days: 7);
  }

  int _sortByDueThenUpdated(SecretaryPlanItem a, SecretaryPlanItem b) {
    const farFutureMs = 1 << 62;
    final dueCompare =
        (a.dueAtMs ?? farFutureMs).compareTo(b.dueAtMs ?? farFutureMs);
    if (dueCompare != 0) return dueCompare;
    return a.title.compareTo(b.title);
  }

  int _sortByUpdatedOldestFirst(SecretaryPlanItem a, SecretaryPlanItem b) {
    return a.title.compareTo(b.title);
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

extension on SecretaryPlanItem {
  SecretaryPlanItem copyWith({
    String? reason,
    bool? requiresConfirmation,
  }) {
    return SecretaryPlanItem(
      id: id,
      todoId: todoId,
      title: title,
      reason: reason ?? this.reason,
      dueAtMs: dueAtMs,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
    );
  }
}
