part of 'todo_detail_page.dart';

Future<List<TodoActivity>> _loadTodoDetailActivities(
  _TodoDetailPageState state,
) async {
  final backend = AppBackendScope.of(state.context);
  final sessionKey = SessionScope.of(state.context).sessionKey;

  final primaryActivities = await backend.listTodoActivities(
    sessionKey,
    state._todo.id,
  );

  var recurrenceRuleJson = state._recurrenceRuleJson;
  recurrenceRuleJson ??= await state._loadRecurrenceRuleJson();
  final normalizedRule = recurrenceRuleJson?.trim() ?? '';
  if (normalizedRule.isEmpty) return primaryActivities;

  final seriesTodos = await _findRecurringSeriesTodos(
    state,
    state._todo,
    normalizedRule,
  );
  if (seriesTodos.length <= 1) return primaryActivities;

  final mergedById = <String, TodoActivity>{
    for (final activity in primaryActivities) activity.id: activity,
  };

  for (final todo in seriesTodos) {
    if (todo.id == state._todo.id) continue;
    try {
      final activities = await backend.listTodoActivities(sessionKey, todo.id);
      for (final activity in activities) {
        mergedById[activity.id] = activity;
      }
    } catch (_) {
      // Ignore sibling activity failures and keep the primary timeline visible.
    }
  }

  final merged = mergedById.values.toList(growable: false)
    ..sort((a, b) {
      if (a.createdAtMs != b.createdAtMs) {
        return a.createdAtMs.compareTo(b.createdAtMs);
      }
      return a.id.compareTo(b.id);
    });
  return merged;
}

Future<Todo?> _findNextActiveRecurringOccurrenceForDetail(
  _TodoDetailPageState state,
  Todo current,
  String recurrenceRuleJson,
) async {
  final seriesTodos = await _findRecurringSeriesTodos(
    state,
    current,
    recurrenceRuleJson,
  );

  final active = seriesTodos
      .where((todo) => todo.id != current.id)
      .where((todo) => todo.status != 'done' && todo.status != 'dismissed')
      .toList(growable: false);
  if (active.isEmpty) return null;

  final pivotDueAtMs = current.dueAtMs;
  active.sort((a, b) {
    final bucketA = _recurringCandidateBucket(a, pivotDueAtMs);
    final bucketB = _recurringCandidateBucket(b, pivotDueAtMs);
    if (bucketA != bucketB) return bucketA.compareTo(bucketB);

    final dueA = a.dueAtMs ?? 9223372036854775807;
    final dueB = b.dueAtMs ?? 9223372036854775807;
    if (dueA != dueB) return dueA.compareTo(dueB);

    return b.updatedAtMs.compareTo(a.updatedAtMs);
  });

  return active.first;
}

Future<List<Todo>> _findRecurringSeriesTodos(
  _TodoDetailPageState state,
  Todo current,
  String recurrenceRuleJson,
) async {
  final normalizedRule = recurrenceRuleJson.trim();
  if (normalizedRule.isEmpty) return <Todo>[current];

  final backend = AppBackendScope.of(state.context);
  final sessionKey = SessionScope.of(state.context).sessionKey;

  late final List<Todo> allTodos;
  try {
    allTodos = await backend.listTodos(sessionKey);
  } catch (_) {
    return <Todo>[current];
  }

  final matched = <Todo>[current];
  for (final todo in allTodos) {
    if (todo.id == current.id) continue;
    if (!_isRecurringSiblingCandidate(todo, current)) continue;

    try {
      final rule = await backend.getTodoRecurrenceRuleJson(
        sessionKey,
        todoId: todo.id,
      );
      if (rule != null && rule.trim() == normalizedRule) {
        matched.add(todo);
      }
    } catch (_) {
      // ignore
    }
  }

  return matched;
}

bool _isRecurringSiblingCandidate(Todo todo, Todo current) {
  if (todo.title != current.title) return false;

  final currentSourceId = current.sourceEntryId;
  if (currentSourceId != null) {
    return todo.sourceEntryId == currentSourceId;
  }
  return todo.sourceEntryId == null;
}

int _recurringCandidateBucket(Todo todo, int? pivotDueAtMs) {
  final dueAtMs = todo.dueAtMs;
  if (dueAtMs == null) return 2;
  if (pivotDueAtMs == null) return 1;
  return dueAtMs >= pivotDueAtMs ? 0 : 1;
}
