part of 'task_priority_store.dart';

Future<Map<String, TaskPriorityAiCachedAssessment>>
    _readTaskPriorityPersistedAiAssessments({
  required String cacheScopeKey,
  required DateTime nowLocal,
  required Duration aiCacheTtl,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(TaskPriorityStore._kAiCachePrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    final data = decoded.map((key, value) => MapEntry(key.toString(), value));
    final rawScopes = data['scopes'];
    if (rawScopes is! Map) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    final rawScope = rawScopes[cacheScopeKey];
    if (rawScope is! Map) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    return _parseTaskPriorityPersistedAssessmentEntries(
      rawScope,
      nowLocal: nowLocal,
      aiCacheTtl: aiCacheTtl,
    );
  } catch (_) {
    return const <String, TaskPriorityAiCachedAssessment>{};
  }
}

Future<Map<String, TaskPriorityAiCachedAssessment>>
    _readMatchingTaskPriorityPersistedAiAssessments({
  required Map<String, TaskPriorityAiCandidate> candidateByTodoId,
  required DateTime nowLocal,
  required Duration aiCacheTtl,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(TaskPriorityStore._kAiCachePrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    final data = decoded.map((key, value) => MapEntry(key.toString(), value));
    final rawScopes = data['scopes'];
    if (rawScopes is! Map) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }

    final normalizedScopes =
        rawScopes.map((key, value) => MapEntry(key.toString(), value));
    final lastScope =
        (data[TaskPriorityStore._kAiCacheLastScopeKey] ?? '').toString().trim();
    final candidateScopes = <MapEntry<String, Object?>>[];
    if (lastScope.isNotEmpty) {
      final scope = normalizedScopes[lastScope];
      if (scope != null) {
        candidateScopes.add(MapEntry(lastScope, scope));
      } else {
        return const <String, TaskPriorityAiCachedAssessment>{};
      }
    } else if (normalizedScopes.length == 1) {
      candidateScopes.add(normalizedScopes.entries.single);
    } else {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }

    for (final scopeEntry in candidateScopes) {
      final scope = scopeEntry.value;
      if (scope is! Map) continue;
      final matched = _filterMatchingTaskPriorityPersistedAiAssessments(
        _parseTaskPriorityPersistedAssessmentEntries(
          scope,
          nowLocal: nowLocal,
          aiCacheTtl: aiCacheTtl,
        ),
        candidateByTodoId: candidateByTodoId,
        nowLocal: nowLocal,
      );
      if (matched.isEmpty) continue;
      return matched;
    }
    return const <String, TaskPriorityAiCachedAssessment>{};
  } catch (_) {
    return const <String, TaskPriorityAiCachedAssessment>{};
  }
}

Map<String, TaskPriorityAiCachedAssessment>
    _parseTaskPriorityPersistedAssessmentEntries(
  Map rawScope, {
  required DateTime nowLocal,
  required Duration aiCacheTtl,
}) {
  final rawEntries = rawScope['entries'];
  if (rawEntries is! Map) {
    return const <String, TaskPriorityAiCachedAssessment>{};
  }
  final entries = <String, TaskPriorityAiCachedAssessment>{};
  for (final item in rawEntries.entries) {
    final todoId = item.key.toString().trim();
    if (todoId.isEmpty || item.value is! Map) continue;
    final parsed = TaskPriorityAiCachedAssessment.fromJson(
      (item.value as Map).map((key, value) => MapEntry(key.toString(), value)),
    );
    if (parsed == null) continue;
    if (nowLocal.difference(parsed.computedAtLocal).abs() > aiCacheTtl) {
      continue;
    }
    entries[todoId] = parsed;
  }
  return entries;
}

Map<String, TaskPriorityAiCachedAssessment>
    _filterMatchingTaskPriorityPersistedAiAssessments(
  Map<String, TaskPriorityAiCachedAssessment> entries, {
  required Map<String, TaskPriorityAiCandidate> candidateByTodoId,
  required DateTime nowLocal,
}) {
  final matched = <String, TaskPriorityAiCachedAssessment>{};
  for (final entry in entries.entries) {
    final candidate = candidateByTodoId[entry.key];
    if (candidate == null) continue;
    final requestSignature = _buildTaskPriorityCandidateRequestSignature(
      candidate,
      nowLocal: nowLocal,
    );
    if (entry.value.requestSignature != requestSignature) continue;
    matched[entry.key] = entry.value;
  }
  return matched;
}

Map<String, TaskPriorityAiCachedAssessment> _mergeTaskPriorityCachedAssessments(
  Map<String, TaskPriorityAiCachedAssessment> primary,
  Map<String, TaskPriorityAiCachedAssessment> fallback,
) {
  final merged = Map<String, TaskPriorityAiCachedAssessment>.from(fallback);
  for (final entry in primary.entries) {
    final existing = merged[entry.key];
    if (existing == null ||
        entry.value.computedAtLocal.isAfter(existing.computedAtLocal)) {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

Map<String, TaskPriorityAiCachedAssessment>
    _readTaskPriorityInMemoryAiAssessments(
  Map<String, _InMemoryAiAssessment> inMemoryAiAssessments, {
  required DateTime nowLocal,
  required Duration aiCacheTtl,
}) {
  final entries = <String, TaskPriorityAiCachedAssessment>{};
  for (final item in inMemoryAiAssessments.entries) {
    if (nowLocal.difference(item.value.computedAtLocal).abs() > aiCacheTtl) {
      continue;
    }
    entries[item.key] = TaskPriorityAiCachedAssessment(
      entry: item.value.entry,
      requestSignature: item.value.requestSignature,
      computedAtLocal: item.value.computedAtLocal,
    );
  }
  return entries;
}

void _writeTaskPriorityInMemoryAiAssessments(
  Map<String, _InMemoryAiAssessment> inMemoryAiAssessments, {
  required Map<String, TaskPriorityAiCachedAssessment> entries,
  required Iterable<String> activeTodoIds,
}) {
  final activeIds = activeTodoIds.map((value) => value.trim()).toSet();
  inMemoryAiAssessments
    ..clear()
    ..addEntries(
      entries.entries.where((entry) => activeIds.contains(entry.key)).map(
            (entry) => MapEntry(
              entry.key,
              _InMemoryAiAssessment(
                entry: entry.value.entry,
                requestSignature: entry.value.requestSignature,
                computedAtLocal: entry.value.computedAtLocal,
              ),
            ),
          ),
    );
}

Future<void> _writeTaskPriorityPersistedAiAssessments({
  required String cacheScopeKey,
  required Map<String, TaskPriorityAiCachedAssessment> entries,
  required Iterable<String> activeTodoIds,
  required DateTime nowLocal,
  required Duration aiCacheTtl,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    Map<String, Object?> root;
    final raw = prefs.getString(TaskPriorityStore._kAiCachePrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      root = <String, Object?>{};
    } else {
      final decoded = jsonDecode(raw);
      root = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};
    }

    final scopes = root['scopes'] is Map
        ? (root['scopes'] as Map)
            .map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    scopes.removeWhere((_, value) {
      if (value is! Map) return true;
      final rawEntries = value['entries'];
      if (rawEntries is! Map || rawEntries.isEmpty) return true;
      var hasFreshEntry = false;
      for (final item in rawEntries.entries) {
        if (item.value is! Map) continue;
        final parsed = TaskPriorityAiCachedAssessment.fromJson(
          (item.value as Map)
              .map((key, value) => MapEntry(key.toString(), value)),
        );
        if (parsed == null) continue;
        if (nowLocal.difference(parsed.computedAtLocal).abs() <= aiCacheTtl) {
          hasFreshEntry = true;
          break;
        }
      }
      return !hasFreshEntry;
    });
    final activeIds = activeTodoIds.map((value) => value.trim()).toSet();
    final prunedEntries = <String, TaskPriorityAiCachedAssessment>{};
    for (final entry in entries.entries) {
      if (activeIds.contains(entry.key)) {
        prunedEntries[entry.key] = entry.value;
      }
    }
    if (prunedEntries.isEmpty) {
      scopes.remove(cacheScopeKey);
    } else {
      scopes[cacheScopeKey] = <String, Object?>{
        'entries': prunedEntries.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
    }
    if (scopes.isEmpty) {
      root.remove('scopes');
    } else {
      root['scopes'] = scopes;
    }
    if (prunedEntries.isNotEmpty) {
      root[TaskPriorityStore._kAiCacheLastScopeKey] = cacheScopeKey;
    } else {
      final lastScope = (root[TaskPriorityStore._kAiCacheLastScopeKey] ?? '')
          .toString()
          .trim();
      if (lastScope.isNotEmpty && scopes.containsKey(lastScope)) {
        // Keep the previous non-empty scope so startup fallback stays usable.
      } else {
        root.remove(TaskPriorityStore._kAiCacheLastScopeKey);
      }
    }
    if (scopes.isEmpty) {
      root.remove(TaskPriorityStore._kAiCacheLastScopeKey);
    }
    await prefs.setString(
        TaskPriorityStore._kAiCachePrefsKey, jsonEncode(root));
  } catch (_) {
    // Ignore cache write failures.
  }
}

String _buildTaskPriorityCandidateRequestSignature(
  TaskPriorityAiCandidate candidate, {
  required DateTime nowLocal,
}) {
  // Volatile prompt context should not invalidate semantic AI assessments.
  final stableCandidate = <String, Object?>{
    'todo_id': candidate.todoId,
    'title': candidate.title,
    'status': candidate.status,
    'band': candidate.band.name,
    'due_state': candidate.dueState,
    'source_summary': candidate.sourceSummary,
    'is_repeatedly_deferred': candidate.isRepeatedlyDeferred,
    'is_potential_blocker': candidate.isPotentialBlocker,
    'is_quick_win': candidate.isQuickWin,
    'rule_is_important': candidate.ruleIsImportant,
    'rule_is_urgent': candidate.ruleIsUrgent,
  };
  return jsonEncode(<String, Object?>{
    'candidate': stableCandidate,
  });
}
