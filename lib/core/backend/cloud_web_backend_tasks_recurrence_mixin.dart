part of 'cloud_web_backend.dart';

mixin _CloudWebBackendTasksRecurrenceMixin on AppBackend {
  final Map<String, String> _todoRecurrenceRuleJsonByTodoId =
      <String, String>{};
  final Map<String, String> _todoRecurrenceSeriesIdByTodoId =
      <String, String>{};
  final Map<String, int> _todoRecurrenceOccurrenceIndexByTodoId =
      <String, int>{};

  String _nextId(String prefix);
  Map<String, Todo> get _todosById;
  int _touchNow();
  PlatformInt64 _asPlatformInt64(int value);

  ({String freq, int interval}) _parseRecurrenceRule(String ruleJson) {
    final decoded = jsonDecode(ruleJson);
    if (decoded is! Map) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final rawFreq = decoded['freq'];
    if (rawFreq is! String) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final freq = rawFreq.trim().toLowerCase();
    if (!const <String>{'daily', 'weekly', 'monthly', 'yearly'}
        .contains(freq)) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final rawInterval = decoded['interval'];
    final interval = switch (rawInterval) {
      null => 1,
      int value => value,
      num value when value == value.toInt() => value.toInt(),
      _ => 1,
    }
        .clamp(1, 10000);
    return (freq: freq, interval: interval);
  }

  int _nextDueAtMs(int baseDueAtMs, String ruleJson) {
    final rule = _parseRecurrenceRule(ruleJson);
    switch (rule.freq) {
      case 'daily':
        return baseDueAtMs + rule.interval * Duration.millisecondsPerDay;
      case 'weekly':
        return baseDueAtMs + rule.interval * 7 * Duration.millisecondsPerDay;
      case 'monthly':
        final base =
            DateTime.fromMillisecondsSinceEpoch(baseDueAtMs, isUtc: true);
        return DateTime.utc(
          base.year,
          base.month + rule.interval,
          base.day,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        ).millisecondsSinceEpoch;
      case 'yearly':
        final base =
            DateTime.fromMillisecondsSinceEpoch(baseDueAtMs, isUtc: true);
        return DateTime.utc(
          base.year + rule.interval,
          base.month,
          base.day,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        ).millisecondsSinceEpoch;
    }
    throw StateError('unsupported recurrence freq: ${rule.freq}');
  }

  Future<void> _maybeSpawnNextRecurringTodo(
    Uint8List key, {
    required Todo todo,
    required String newStatus,
  }) async {
    if (newStatus != 'done') return;
    final baseDueAtMs = todo.dueAtMs;
    if (baseDueAtMs == null) return;
    final seriesId = _todoRecurrenceSeriesIdByTodoId[todo.id];
    final occurrenceIndex = _todoRecurrenceOccurrenceIndexByTodoId[todo.id];
    final ruleJson = _todoRecurrenceRuleJsonByTodoId[todo.id];
    if (seriesId == null || occurrenceIndex == null || ruleJson == null) {
      return;
    }

    final nextIndex = occurrenceIndex + 1;
    final existingNext = _todoRecurrenceOccurrenceIndexByTodoId.entries.any(
      (entry) =>
          entry.value == nextIndex &&
          _todoRecurrenceSeriesIdByTodoId[entry.key] == seriesId,
    );
    if (existingNext) return;

    final nextTodoId = 'todo:$seriesId:$nextIndex';
    final nextDueAtMs = _nextDueAtMs(baseDueAtMs.toInt(), ruleJson);
    final now = _touchNow();
    _todosById[nextTodoId] = Todo(
      id: nextTodoId,
      title: todo.title,
      dueAtMs: _asPlatformInt64(nextDueAtMs),
      status: 'open',
      sourceEntryId: todo.sourceEntryId,
      createdAtMs: _asPlatformInt64(now),
      updatedAtMs: _asPlatformInt64(now),
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: _asPlatformInt64(now),
      manualImportanceNudgeScore: todo.manualImportanceNudgeScore,
      manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore,
    );
    _assignRecurrenceToTodo(
      nextTodoId,
      seriesId: seriesId,
      ruleJson: ruleJson,
      occurrenceIndex: nextIndex,
    );
  }

  void _validateRecurrenceRuleJson(String ruleJson) {
    final decoded = jsonDecode(ruleJson);
    if (decoded is! Map) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final rawFreq = decoded['freq'];
    if (rawFreq is! String) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final frequency = rawFreq.trim().toLowerCase();
    if (!const <String>{'daily', 'weekly', 'monthly', 'yearly'}
        .contains(frequency)) {
      throw const FormatException('invalid_recurrence_rule');
    }
    final rawInterval = decoded['interval'];
    final interval = switch (rawInterval) {
      null => 1,
      int value => value,
      num value when value == value.toInt() => value.toInt(),
      _ => 1,
    };
    if (interval < 1) {
      throw const FormatException('invalid_recurrence_rule');
    }
  }

  List<String> _seriesTodoIds(String seriesId) {
    final todoIds = _todoRecurrenceSeriesIdByTodoId.entries
        .where((entry) => entry.value == seriesId)
        .map((entry) => entry.key)
        .toList(growable: false)
      ..sort((left, right) {
        final leftIndex = _todoRecurrenceOccurrenceIndexByTodoId[left] ?? 0;
        final rightIndex = _todoRecurrenceOccurrenceIndexByTodoId[right] ?? 0;
        final byIndex = leftIndex.compareTo(rightIndex);
        if (byIndex != 0) {
          return byIndex;
        }
        return left.compareTo(right);
      });
    return todoIds;
  }

  List<String> _scopedRecurrenceTodoIds(
    String seriesId,
    int currentOccurrenceIndex,
    TodoRecurrenceEditScope scope,
  ) {
    final todoIds = _seriesTodoIds(seriesId);
    return todoIds.where((todoId) {
      final occurrenceIndex =
          _todoRecurrenceOccurrenceIndexByTodoId[todoId] ?? 0;
      return switch (scope) {
        TodoRecurrenceEditScope.thisOnly =>
          occurrenceIndex == currentOccurrenceIndex,
        TodoRecurrenceEditScope.thisAndFuture =>
          occurrenceIndex >= currentOccurrenceIndex,
        TodoRecurrenceEditScope.wholeSeries => true,
      };
    }).toList(growable: false);
  }

  void _assignRecurrenceToTodo(
    String todoId, {
    required String seriesId,
    required String ruleJson,
    required int occurrenceIndex,
  }) {
    _todoRecurrenceSeriesIdByTodoId[todoId] = seriesId;
    _todoRecurrenceRuleJsonByTodoId[todoId] = ruleJson;
    _todoRecurrenceOccurrenceIndexByTodoId[todoId] = occurrenceIndex;
  }

  String _nextUniqueSplitSeriesId() {
    var seriesId = _nextId('series-split');
    while (_todoRecurrenceSeriesIdByTodoId.containsValue(seriesId)) {
      seriesId = _nextId('series-split');
    }
    return seriesId;
  }

  void _splitScopedRecurrenceSeries({
    required int currentOccurrenceIndex,
    required List<String> scopedTodoIds,
    required String ruleJson,
    required TodoRecurrenceEditScope scope,
  }) {
    if (scope == TodoRecurrenceEditScope.wholeSeries) {
      throw StateError('wholeSeries scope cannot split recurrence series');
    }
    final splitSeriesId = _nextUniqueSplitSeriesId();
    for (final todoId in scopedTodoIds) {
      final occurrenceIndex =
          _todoRecurrenceOccurrenceIndexByTodoId[todoId] ?? 0;
      final splitOccurrenceIndex = switch (scope) {
        TodoRecurrenceEditScope.thisOnly => 0,
        TodoRecurrenceEditScope.thisAndFuture =>
          occurrenceIndex - currentOccurrenceIndex,
        TodoRecurrenceEditScope.wholeSeries => throw StateError('unreachable'),
      };
      _assignRecurrenceToTodo(
        todoId,
        seriesId: splitSeriesId,
        ruleJson: ruleJson,
        occurrenceIndex: splitOccurrenceIndex,
      );
    }
  }

  @override
  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) async {
    final existing = _todosById[todoId];
    if (existing == null) {
      throw StateError('unknown_todo:$todoId');
    }

    var applyScope = scope;
    final seriesId = _todoRecurrenceSeriesIdByTodoId[todoId];
    final occurrenceIndex = _todoRecurrenceOccurrenceIndexByTodoId[todoId];
    final ruleJson = _todoRecurrenceRuleJsonByTodoId[todoId];
    if (seriesId == null ||
        occurrenceIndex == null ||
        ruleJson == null ||
        newStatus == 'done') {
      applyScope = TodoRecurrenceEditScope.thisOnly;
    }

    switch (applyScope) {
      case TodoRecurrenceEditScope.thisOnly:
        final updated = await setTodoStatus(
          key,
          todoId: todoId,
          newStatus: newStatus,
          sourceMessageId: sourceMessageId,
        );
        await _maybeSpawnNextRecurringTodo(
          key,
          todo: updated,
          newStatus: newStatus,
        );
        return updated;
      case TodoRecurrenceEditScope.thisAndFuture:
      case TodoRecurrenceEditScope.wholeSeries:
        final resolvedSeriesId = seriesId!;
        final resolvedOccurrenceIndex = occurrenceIndex!;
        final resolvedRuleJson = ruleJson!;
        final scopedTodoIds = _scopedRecurrenceTodoIds(
          resolvedSeriesId,
          resolvedOccurrenceIndex,
          applyScope,
        );
        Todo? updatedCurrent;
        for (final scopedTodoId in scopedTodoIds) {
          final updated = await setTodoStatus(
            key,
            todoId: scopedTodoId,
            newStatus: newStatus,
            sourceMessageId: sourceMessageId,
          );
          if (scopedTodoId == todoId) {
            updatedCurrent = updated;
          }
        }
        if (applyScope == TodoRecurrenceEditScope.thisAndFuture) {
          _splitScopedRecurrenceSeries(
            currentOccurrenceIndex: resolvedOccurrenceIndex,
            scopedTodoIds: scopedTodoIds,
            ruleJson: resolvedRuleJson,
            scope: TodoRecurrenceEditScope.thisAndFuture,
          );
        }
        if (updatedCurrent == null) {
          throw StateError('current todo not found in recurrence scope');
        }
        return updatedCurrent;
    }
  }

  @override
  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) async {
    final current = _todosById[todoId];
    if (current == null) {
      throw StateError('unknown_todo:$todoId');
    }

    var applyScope = scope;
    final seriesId = _todoRecurrenceSeriesIdByTodoId[todoId];
    final occurrenceIndex = _todoRecurrenceOccurrenceIndexByTodoId[todoId];
    final ruleJson = _todoRecurrenceRuleJsonByTodoId[todoId];
    if (seriesId == null || occurrenceIndex == null || ruleJson == null) {
      applyScope = TodoRecurrenceEditScope.thisOnly;
    }

    switch (applyScope) {
      case TodoRecurrenceEditScope.thisOnly:
        return transitionTodo(
          key,
          todoId: todoId,
          dueAtMs: dueAtMs,
        );
      case TodoRecurrenceEditScope.thisAndFuture:
      case TodoRecurrenceEditScope.wholeSeries:
        final resolvedSeriesId = seriesId!;
        final resolvedOccurrenceIndex = occurrenceIndex!;
        final resolvedRuleJson = ruleJson!;
        final currentDueAtMs = current.dueAtMs;
        if (currentDueAtMs == null) {
          throw StateError('todo has no dueAtMs, cannot apply scoped due edit');
        }
        final delta = dueAtMs - currentDueAtMs.toInt();
        final scopedTodoIds = _scopedRecurrenceTodoIds(
          resolvedSeriesId,
          resolvedOccurrenceIndex,
          applyScope,
        );
        Todo? updatedCurrent;
        for (final scopedTodoId in scopedTodoIds) {
          final seriesTodo = _todosById[scopedTodoId];
          if (seriesTodo == null) {
            continue;
          }
          final int? targetDueAtMs = scopedTodoId == todoId
              ? dueAtMs
              : (seriesTodo.dueAtMs == null
                  ? null
                  : seriesTodo.dueAtMs!.toInt() + delta);
          final updated = await upsertTodo(
            key,
            id: seriesTodo.id,
            title: seriesTodo.title,
            dueAtMs: targetDueAtMs,
            status: seriesTodo.status,
            sourceEntryId: seriesTodo.sourceEntryId,
            reviewStage: seriesTodo.reviewStage?.toInt(),
            nextReviewAtMs: seriesTodo.nextReviewAtMs?.toInt(),
            lastReviewAtMs: seriesTodo.lastReviewAtMs?.toInt(),
            manualImportanceNudgeScore:
                seriesTodo.manualImportanceNudgeScore?.toInt(),
            manualUrgencyNudgeScore:
                seriesTodo.manualUrgencyNudgeScore?.toInt(),
          );
          if (scopedTodoId == todoId) {
            updatedCurrent = updated;
          }
        }
        if (applyScope == TodoRecurrenceEditScope.thisAndFuture) {
          _splitScopedRecurrenceSeries(
            currentOccurrenceIndex: resolvedOccurrenceIndex,
            scopedTodoIds: scopedTodoIds,
            ruleJson: resolvedRuleJson,
            scope: TodoRecurrenceEditScope.thisAndFuture,
          );
        }
        if (updatedCurrent == null) {
          throw StateError('current todo not found in recurrence scope');
        }
        return updatedCurrent;
    }
  }

  @override
  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) async {
    if (!_todosById.containsKey(todoId)) {
      throw StateError('unknown_todo:$todoId');
    }
    _validateRecurrenceRuleJson(ruleJson);
    final existingOccurrenceIndex =
        _todoRecurrenceOccurrenceIndexByTodoId[todoId];
    final occurrenceIndex = existingOccurrenceIndex ??
        _seriesTodoIds(seriesId)
                .map((id) => _todoRecurrenceOccurrenceIndexByTodoId[id] ?? 0)
                .fold<int>(
                  -1,
                  (maxIndex, value) => value > maxIndex ? value : maxIndex,
                ) +
            1;
    for (final existingTodoId in _seriesTodoIds(seriesId)) {
      _todoRecurrenceRuleJsonByTodoId[existingTodoId] = ruleJson;
    }
    _assignRecurrenceToTodo(
      todoId,
      seriesId: seriesId,
      ruleJson: ruleJson,
      occurrenceIndex: occurrenceIndex,
    );
  }

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async {
    return _todoRecurrenceRuleJsonByTodoId[todoId];
  }

  @override
  Future<void> updateTodoRecurrenceRuleWithScope(
    Uint8List key, {
    required String todoId,
    required String ruleJson,
    required TodoRecurrenceEditScope scope,
  }) async {
    if (!_todosById.containsKey(todoId)) {
      throw StateError('unknown_todo:$todoId');
    }
    _validateRecurrenceRuleJson(ruleJson);
    final seriesId = _todoRecurrenceSeriesIdByTodoId[todoId];
    final occurrenceIndex = _todoRecurrenceOccurrenceIndexByTodoId[todoId];
    if (seriesId == null || occurrenceIndex == null) {
      throw StateError('todo recurrence metadata missing');
    }
    switch (scope) {
      case TodoRecurrenceEditScope.wholeSeries:
        for (final scopedTodoId in _seriesTodoIds(seriesId)) {
          _todoRecurrenceRuleJsonByTodoId[scopedTodoId] = ruleJson;
        }
        return;
      case TodoRecurrenceEditScope.thisOnly:
      case TodoRecurrenceEditScope.thisAndFuture:
        final scopedTodoIds = _scopedRecurrenceTodoIds(
          seriesId,
          occurrenceIndex,
          scope,
        );
        _splitScopedRecurrenceSeries(
          currentOccurrenceIndex: occurrenceIndex,
          scopedTodoIds: scopedTodoIds,
          ruleJson: ruleJson,
          scope: scope,
        );
        return;
    }
  }
}
