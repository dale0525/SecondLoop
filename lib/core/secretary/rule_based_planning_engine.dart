import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import '../../features/actions/task_hub/task_priority_models.dart';
import 'secretary_models.dart';

class RuleBasedPlanningEngine {
  const RuleBasedPlanningEngine({
    required DateTime Function() nowLocal,
  }) : _nowLocal = nowLocal;

  final DateTime Function() _nowLocal;

  SecretaryPlan generateDailyPlanFromPrioritySnapshot(
    TaskPrioritySnapshot snapshot,
  ) {
    final now = _nowLocal();
    if (snapshot.activeEntries.isEmpty) {
      return SecretaryPlan(
        id: 'daily-plan-${now.millisecondsSinceEpoch}',
        title: 'Daily plan',
        generatedAtMs: now.millisecondsSinceEpoch,
        route: 'local_rules',
        sections: const SecretaryPlanSections.empty(),
      );
    }

    final focus = <SecretaryPlanItem>[];
    final dueSoon = <SecretaryPlanItem>[];
    final needsDecision = <SecretaryPlanItem>[];
    final missingNextAction = <SecretaryPlanItem>[];
    final seenTodoIds = <String>{};

    for (final entry in snapshot.activeEntries) {
      final todo = entry.todo;
      if (!_isOpenTodo(todo) || !seenTodoIds.add(todo.id)) continue;

      final dueAtMs = platformIntToNullableInt(todo.dueAtMs);
      final itemBase = _itemBase(todo, dueAtMs: dueAtMs);

      if (entry.hasHardFocusGuard ||
          entry.isOverdue ||
          entry.isDueToday ||
          entry.band == TaskPriorityBand.focus) {
        focus.add(
          itemBase.copyWith(
            reason: _reasonForPriorityEntry(
              entry,
              fallback: entry.isOverdue ? 'Overdue' : 'Due today',
            ),
            requiresConfirmation: entry.isOverdue || entry.isDueToday,
          ),
        );
        continue;
      }

      if (entry.isFutureScheduled || entry.band == TaskPriorityBand.scheduled) {
        dueSoon.add(
          itemBase.copyWith(
            reason: _reasonForPriorityEntry(entry, fallback: 'Scheduled soon'),
          ),
        );
        continue;
      }

      if (entry.isReviewDue ||
          entry.isSnoozed ||
          entry.hasManualNudges ||
          entry.suggestedAction == TaskPrioritySuggestionKind.clarify) {
        needsDecision.add(
          itemBase.copyWith(
            reason: _reasonForPriorityEntry(
              entry,
              fallback: entry.hasManualNudges
                  ? 'User priority signal needs review'
                  : 'Needs decision',
            ),
            requiresConfirmation: true,
          ),
        );
        continue;
      }

      if (dueAtMs == null) {
        missingNextAction.add(
          itemBase.copyWith(
            reason: _reasonForPriorityEntry(
              entry,
              fallback: 'No schedule or next action',
            ),
          ),
        );
      }
    }

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

  String _reasonForPriorityEntry(
    TaskPriorityEntry entry, {
    required String fallback,
  }) {
    final aiReason = entry.reasonText?.trim();
    if (aiReason != null && aiReason.isNotEmpty) return aiReason;
    if (entry.isOverdue) return 'Overdue';
    if (entry.isDueToday) return 'Due today';
    if (entry.isFutureScheduled) return 'Scheduled soon';
    if (entry.isReviewDue) return 'Review due';
    if (entry.isSnoozed) return 'Snoozed';
    if (entry.hasManualNudges) return 'User priority signal needs review';
    if (entry.reasons.contains(TaskPriorityReasonKind.aiSuggested)) {
      return 'AI priority signal';
    }
    return fallback;
  }
}
