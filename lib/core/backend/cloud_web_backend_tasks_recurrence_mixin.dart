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
        return setTodoStatus(
          key,
          todoId: todoId,
          newStatus: newStatus,
          sourceMessageId: sourceMessageId,
        );
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
        final delta = dueAtMs - currentDueAtMs;
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
          final targetDueAtMs = scopedTodoId == todoId
              ? dueAtMs
              : (seriesTodo.dueAtMs == null
                  ? null
                  : seriesTodo.dueAtMs! + delta);
          final updated = await upsertTodo(
            key,
            id: seriesTodo.id,
            title: seriesTodo.title,
            dueAtMs: targetDueAtMs,
            status: seriesTodo.status,
            sourceEntryId: seriesTodo.sourceEntryId,
            reviewStage: seriesTodo.reviewStage,
            nextReviewAtMs: seriesTodo.nextReviewAtMs,
            lastReviewAtMs: seriesTodo.lastReviewAtMs,
            manualImportanceNudgeScore: seriesTodo.manualImportanceNudgeScore,
            manualUrgencyNudgeScore: seriesTodo.manualUrgencyNudgeScore,
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
