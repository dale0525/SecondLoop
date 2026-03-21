import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../src/rust/db.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';
import 'task_priority_ai.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_engine.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';

enum TaskPriorityAiAvailability {
  unknown,
  disabled,
  unavailable,
  available,
}

class TaskPriorityStore extends ChangeNotifier {
  static const _kAiCachePrefsKey = 'task_priority_ai_cache_v3';
  final Map<String, _InMemoryAiAssessment> _inMemoryAiAssessments =
      <String, _InMemoryAiAssessment>{};

  TaskPriorityStore.fromLoaders({
    required Future<List<Todo>> Function() loadTodos,
    Future<List<TodoChecklistProgress>> Function()? loadChecklistProgress,
    required DateTime Function() nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
    Future<String?> Function()? resolveAiCacheScopeKey,
    Future<bool> Function()? isAiEnhancementEnabled,
    Future<Map<String, TaskPriorityAiCachedAssessment>> Function({
      required TaskPriorityAiService? aiService,
      required String cacheScopeKey,
      required DateTime nowLocal,
    })? readSharedAiAssessments,
    Future<void> Function({
      required TaskPriorityAiService? aiService,
      required String cacheScopeKey,
      required Map<String, TaskPriorityAiCachedAssessment> entries,
      required Iterable<String> activeTodoIds,
    })? writeSharedAiAssessments,
    TaskPriorityFeedbackStore feedbackStore = const TaskPriorityFeedbackStore(),
    Duration aiCacheTtl = const Duration(minutes: 15),
  })  : _loadTodos = loadTodos,
        _loadChecklistProgress = loadChecklistProgress,
        _nowLocal = nowLocal,
        _resolveAiService = resolveAiService,
        _resolveAiCacheScopeKey = resolveAiCacheScopeKey,
        _isAiEnhancementEnabled = isAiEnhancementEnabled,
        _readSharedAiAssessments = readSharedAiAssessments,
        _writeSharedAiAssessments = writeSharedAiAssessments,
        _feedbackStore = feedbackStore,
        _aiCacheTtl = aiCacheTtl;

  factory TaskPriorityStore({
    required AppBackend backend,
    required Uint8List sessionKey,
    SyncEngine? syncEngine,
    DateTime Function()? nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
    Future<String?> Function()? resolveAiCacheScopeKey,
    Future<bool> Function()? isAiEnhancementEnabled,
    Future<Map<String, TaskPriorityAiCachedAssessment>> Function({
      required TaskPriorityAiService? aiService,
      required String cacheScopeKey,
      required DateTime nowLocal,
    })? readSharedAiAssessments,
    Future<void> Function({
      required TaskPriorityAiService? aiService,
      required String cacheScopeKey,
      required Map<String, TaskPriorityAiCachedAssessment> entries,
      required Iterable<String> activeTodoIds,
    })? writeSharedAiAssessments,
    TaskPriorityFeedbackStore feedbackStore = const TaskPriorityFeedbackStore(),
  }) {
    return TaskPriorityStore.fromLoaders(
      loadTodos: () => _loadAndNormalizeTodos(
        backend,
        sessionKey: sessionKey,
        syncEngine: syncEngine,
        nowLocal: (nowLocal ?? DateTime.now)(),
      ),
      loadChecklistProgress: () =>
          backend.listTodoChecklistProgress(sessionKey),
      nowLocal: nowLocal ?? DateTime.now,
      resolveAiService: resolveAiService,
      resolveAiCacheScopeKey: resolveAiCacheScopeKey,
      isAiEnhancementEnabled: isAiEnhancementEnabled,
      readSharedAiAssessments: readSharedAiAssessments,
      writeSharedAiAssessments: writeSharedAiAssessments,
      feedbackStore: feedbackStore,
    );
  }

  final Future<List<Todo>> Function() _loadTodos;
  final Future<List<TodoChecklistProgress>> Function()? _loadChecklistProgress;
  final DateTime Function() _nowLocal;
  final Future<TaskPriorityAiService?> Function()? _resolveAiService;
  final Future<String?> Function()? _resolveAiCacheScopeKey;
  final Future<bool> Function()? _isAiEnhancementEnabled;
  final Future<Map<String, TaskPriorityAiCachedAssessment>> Function({
    required TaskPriorityAiService? aiService,
    required String cacheScopeKey,
    required DateTime nowLocal,
  })? _readSharedAiAssessments;
  final Future<void> Function({
    required TaskPriorityAiService? aiService,
    required String cacheScopeKey,
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  })? _writeSharedAiAssessments;
  final TaskPriorityFeedbackStore _feedbackStore;
  final Duration _aiCacheTtl;

  TaskPrioritySnapshot _snapshot = const TaskPrioritySnapshot.empty();
  TaskPrioritySnapshot get snapshot => _snapshot;
  TaskPrioritySnapshot get baseSnapshot => _snapshot.baseSnapshot;
  bool get isBasePriorityAvailable => _snapshot.computedAtLocal != null;
  bool get shouldShowAiUpgradeHint =>
      isAiEnhancementEnabled &&
      !isAiEnhancementAvailable &&
      !_snapshot.hasAiEnhancement;

  Map<String, TodoChecklistProgress> _checklistProgressByTodoId =
      const <String, TodoChecklistProgress>{};
  Map<String, TodoChecklistProgress> get checklistProgressByTodoId =>
      _checklistProgressByTodoId;

  TaskPriorityAiAvailability _aiAvailability =
      TaskPriorityAiAvailability.unknown;
  TaskPriorityAiAvailability get aiAvailability => _aiAvailability;
  bool get isAiEnhancementEnabled =>
      _aiAvailability != TaskPriorityAiAvailability.disabled &&
      _aiAvailability != TaskPriorityAiAvailability.unknown;
  bool get isAiEnhancementAvailable =>
      _aiAvailability == TaskPriorityAiAvailability.available;

  bool _dirty = true;
  bool get isDirty => _dirty;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  String? _stickyFocusTodoId;
  DateTime? _stickyFocusDayLocal;
  Map<String, String> _stickyFocusDueStateByTodoId = const <String, String>{};

  Future<void>? _inflightRefresh;
  bool _disposed = false;

  void markDirty() {
    _dirty = true;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    if (_inflightRefresh != null) {
      if (!force) return _inflightRefresh!;
      return _inflightRefresh!.then((_) {
        if (_disposed) return Future<void>.value();
        return refresh(force: true);
      });
    }
    if (!force && !_dirty && _snapshot.computedAtLocal != null) {
      return Future<void>.value();
    }
    final future = _refreshImpl();
    _inflightRefresh = future.whenComplete(() {
      _inflightRefresh = null;
    });
    return _inflightRefresh!;
  }

  Future<void> _refreshImpl() async {
    if (_disposed) return;
    _isRefreshing = true;
    _safeNotify();

    try {
      final nowLocal = _nowLocal();
      final todos = await _loadTodos();
      try {
        final checklistProgressRows = await _loadChecklistProgress?.call() ??
            const <TodoChecklistProgress>[];
        _checklistProgressByTodoId = {
          for (final item in checklistProgressRows) item.todoId: item,
        };
      } catch (_) {
        // Keep the previously loaded checklist progress on transient failures.
      }

      await _feedbackStore.pruneToTodoIds(todos.map((todo) => todo.id));
      final feedbackState = await _feedbackStore.read();
      _snapshot = buildTaskPrioritySnapshot(
        todos,
        nowLocal: nowLocal,
        feedbackState: feedbackState,
      );
      _dirty = false;
      _safeNotify();

      final aiEnhancementEnabled =
          await _isAiEnhancementEnabled?.call() ?? true;
      if (!aiEnhancementEnabled) {
        _aiAvailability = TaskPriorityAiAvailability.disabled;
        _rememberStickyFocus(nowLocal);
        return;
      }

      TaskPriorityAiService? aiService;
      try {
        aiService = await _resolveAiService?.call();
        _aiAvailability = aiService == null
            ? TaskPriorityAiAvailability.unavailable
            : TaskPriorityAiAvailability.available;
      } catch (_) {
        _aiAvailability = TaskPriorityAiAvailability.unavailable;
        aiService = null;
      }

      if (_snapshot.activeEntries.isEmpty) {
        _rememberStickyFocus(nowLocal);
        return;
      }

      final request = buildTaskPriorityAiRequest(_snapshot, nowLocal: nowLocal);
      if (request.candidates.isEmpty) {
        _rememberStickyFocus(nowLocal);
        return;
      }

      final cacheScopeKey =
          (aiService?.cacheScopeKey ?? await _resolveAiCacheScopeKey?.call())
              ?.trim();
      final canUsePersistedCache =
          cacheScopeKey != null && cacheScopeKey.isNotEmpty;
      final canUseInMemoryCache = !canUsePersistedCache;

      final sharedPersisted = canUsePersistedCache
          ? await _readSharedAiAssessments?.call(
                aiService: aiService,
                cacheScopeKey: cacheScopeKey,
                nowLocal: nowLocal,
              ) ??
              const <String, TaskPriorityAiCachedAssessment>{}
          : const <String, TaskPriorityAiCachedAssessment>{};
      final persisted = canUsePersistedCache
          ? await _readPersistedAiAssessments(
              cacheScopeKey: cacheScopeKey,
              nowLocal: nowLocal,
            )
          : const <String, TaskPriorityAiCachedAssessment>{};
      final memoryCached = canUseInMemoryCache
          ? _readInMemoryAiAssessments(nowLocal: nowLocal)
          : const <String, TaskPriorityAiCachedAssessment>{};
      final freshEntries = <String, TaskPriorityAiEntry>{};
      final cachedEnhancementSources = <String, TaskPriorityEnhancementSource>{
        if (canUsePersistedCache) ...<String, TaskPriorityEnhancementSource>{
          for (final entry in persisted.entries)
            entry.key: TaskPriorityEnhancementSource.aiLocalCache,
          for (final entry in sharedPersisted.entries)
            entry.key: TaskPriorityEnhancementSource.aiSharedCache,
        } else ...<String, TaskPriorityEnhancementSource>{
          for (final entry in memoryCached.entries)
            entry.key: TaskPriorityEnhancementSource.aiLocalCache,
        },
      };
      final sharedCacheTodoIds = <String>{};
      final localCacheTodoIds = <String>{};
      final liveTodoIds = <String>{};
      final mergedPersisted = Map<String, TaskPriorityAiCachedAssessment>.from(
        canUsePersistedCache
            ? <String, TaskPriorityAiCachedAssessment>{
                ...persisted,
                ...sharedPersisted
              }
            : memoryCached,
      );
      final staleCandidates = <TaskPriorityAiCandidate>[];
      final candidateByTodoId = <String, TaskPriorityAiCandidate>{
        for (final candidate in request.candidates) candidate.todoId: candidate,
      };

      for (final candidate in request.candidates) {
        final requestSignature = _buildCandidateRequestSignature(
          candidate,
          nowLocal: nowLocal,
        );
        final cached = mergedPersisted[candidate.todoId];
        if (cached != null && cached.requestSignature == requestSignature) {
          freshEntries[candidate.todoId] = cached.entry;
          switch (cachedEnhancementSources[candidate.todoId]) {
            case TaskPriorityEnhancementSource.aiSharedCache:
              sharedCacheTodoIds.add(candidate.todoId);
              localCacheTodoIds.remove(candidate.todoId);
              break;
            case TaskPriorityEnhancementSource.aiLocalCache:
              localCacheTodoIds.add(candidate.todoId);
              sharedCacheTodoIds.remove(candidate.todoId);
              break;
            default:
              break;
          }
        } else {
          mergedPersisted.remove(candidate.todoId);
          cachedEnhancementSources.remove(candidate.todoId);
          sharedCacheTodoIds.remove(candidate.todoId);
          localCacheTodoIds.remove(candidate.todoId);
          staleCandidates.add(candidate);
        }
      }

      final stalePersistedTodoIds = <String>{};
      for (final activeEntry in _snapshot.activeEntries) {
        final cached = mergedPersisted[activeEntry.todo.id];
        if (cached == null) continue;
        final candidate = candidateByTodoId[activeEntry.todo.id];
        if (candidate == null) {
          stalePersistedTodoIds.add(activeEntry.todo.id);
          continue;
        }
        final requestSignature = _buildCandidateRequestSignature(
          candidate,
          nowLocal: nowLocal,
        );
        if (cached.requestSignature != requestSignature) {
          stalePersistedTodoIds.add(activeEntry.todo.id);
        }
      }
      for (final todoId in stalePersistedTodoIds) {
        mergedPersisted.remove(todoId);
        cachedEnhancementSources.remove(todoId);
        freshEntries.remove(todoId);
        sharedCacheTodoIds.remove(todoId);
        localCacheTodoIds.remove(todoId);
      }

      if (aiService != null && staleCandidates.isNotEmpty) {
        try {
          final result = await aiService.rerank(
            request.copyWith(candidates: staleCandidates),
          );
          for (final entry in result.entries) {
            TaskPriorityAiCandidate? candidate;
            for (final item in staleCandidates) {
              if (item.todoId == entry.todoId) {
                candidate = item;
                break;
              }
            }
            if (candidate == null) continue;
            final requestSignature = _buildCandidateRequestSignature(
              candidate,
              nowLocal: nowLocal,
            );
            freshEntries[entry.todoId] = entry;
            liveTodoIds.add(entry.todoId);
            sharedCacheTodoIds.remove(entry.todoId);
            localCacheTodoIds.remove(entry.todoId);
            mergedPersisted[entry.todoId] = TaskPriorityAiCachedAssessment(
              entry: entry,
              requestSignature: requestSignature,
              computedAtLocal: nowLocal,
            );
            cachedEnhancementSources[entry.todoId] =
                TaskPriorityEnhancementSource.aiLive;
          }
        } catch (_) {
          _aiAvailability = TaskPriorityAiAvailability.unavailable;
          // Keep the already-published rules snapshot.
        }
      }

      if (canUsePersistedCache) {
        await _writePersistedAiAssessments(
          cacheScopeKey: cacheScopeKey,
          entries: mergedPersisted,
          activeTodoIds: _snapshot.activeEntries.map((entry) => entry.todo.id),
        );
        await _writeSharedAiAssessments?.call(
          aiService: aiService,
          cacheScopeKey: cacheScopeKey,
          entries: mergedPersisted,
          activeTodoIds: _snapshot.activeEntries.map((entry) => entry.todo.id),
        );
      } else if (canUseInMemoryCache) {
        _writeInMemoryAiAssessments(
          entries: mergedPersisted,
          activeTodoIds: _snapshot.activeEntries.map((entry) => entry.todo.id),
        );
      }

      final aiEntries = <TaskPriorityAiEntry>[];
      for (final activeEntry in _snapshot.activeEntries) {
        final todoId = activeEntry.todo.id;
        final entry = freshEntries[todoId] ?? mergedPersisted[todoId]?.entry;
        if (entry != null) aiEntries.add(entry);
      }
      if (aiEntries.isEmpty) {
        _aiAvailability = TaskPriorityAiAvailability.unavailable;
        _rememberStickyFocus(nowLocal);
        return;
      }

      final enhancementSource = liveTodoIds.isNotEmpty
          ? TaskPriorityEnhancementSource.aiLive
          : sharedCacheTodoIds.isNotEmpty
              ? TaskPriorityEnhancementSource.aiSharedCache
              : TaskPriorityEnhancementSource.aiLocalCache;
      var hybridSnapshot = buildTaskPrioritySnapshot(
        todos,
        nowLocal: nowLocal,
        aiResult: TaskPriorityAiBatchResult(entries: aiEntries),
        enhancementSource: enhancementSource,
        feedbackState: feedbackState,
      );
      hybridSnapshot = _applyStickyFocus(hybridSnapshot, nowLocal: nowLocal);
      _snapshot = hybridSnapshot;
      _rememberStickyFocus(nowLocal);
      _safeNotify();
    } finally {
      _isRefreshing = false;
      _safeNotify();
    }
  }

  void _rememberStickyFocus(DateTime nowLocal) {
    _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
    _stickyFocusDayLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    _stickyFocusDueStateByTodoId = _buildStickyStateSignatures(_snapshot);
  }

  Future<Map<String, TaskPriorityAiCachedAssessment>>
      _readPersistedAiAssessments({
    required String cacheScopeKey,
    required DateTime nowLocal,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAiCachePrefsKey);
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
      final rawEntries = rawScope['entries'];
      if (rawEntries is! Map) {
        return const <String, TaskPriorityAiCachedAssessment>{};
      }
      final entries = <String, TaskPriorityAiCachedAssessment>{};
      for (final item in rawEntries.entries) {
        final todoId = item.key.toString().trim();
        if (todoId.isEmpty || item.value is! Map) continue;
        final parsed = TaskPriorityAiCachedAssessment.fromJson(
          (item.value as Map)
              .map((key, value) => MapEntry(key.toString(), value)),
        );
        if (parsed == null) continue;
        if (nowLocal.difference(parsed.computedAtLocal).abs() > _aiCacheTtl) {
          continue;
        }
        entries[todoId] = parsed;
      }
      return entries;
    } catch (_) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
  }

  Map<String, TaskPriorityAiCachedAssessment> _readInMemoryAiAssessments({
    required DateTime nowLocal,
  }) {
    final entries = <String, TaskPriorityAiCachedAssessment>{};
    for (final item in _inMemoryAiAssessments.entries) {
      if (nowLocal.difference(item.value.computedAtLocal).abs() > _aiCacheTtl) {
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

  void _writeInMemoryAiAssessments({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) {
    final activeIds = activeTodoIds.map((value) => value.trim()).toSet();
    _inMemoryAiAssessments
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

  Future<void> _writePersistedAiAssessments({
    required String cacheScopeKey,
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, Object?> root;
      final raw = prefs.getString(_kAiCachePrefsKey);
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
          if (_nowLocal().difference(parsed.computedAtLocal).abs() <=
              _aiCacheTtl) {
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
      scopes[cacheScopeKey] = <String, Object?>{
        'entries': prunedEntries.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
      root['scopes'] = scopes;
      await prefs.setString(_kAiCachePrefsKey, jsonEncode(root));
    } catch (_) {
      // Ignore cache write failures.
    }
  }

  String _buildCandidateRequestSignature(
    TaskPriorityAiCandidate candidate, {
    required DateTime nowLocal,
  }) {
    return jsonEncode(<String, Object?>{
      'time_bucket': buildTaskPriorityAiTimeBucket(nowLocal),
      'candidate': candidate.toJson(),
    });
  }

  TaskPrioritySnapshot _applyStickyFocus(
    TaskPrioritySnapshot snapshot, {
    required DateTime nowLocal,
  }) {
    final stickyTodoId = _stickyFocusTodoId;
    final stickyDay = _stickyFocusDayLocal;
    if (stickyTodoId == null || stickyDay == null) return snapshot;

    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (today != stickyDay) return snapshot;
    final primary = snapshot.primaryFocus;
    if (primary == null || primary.todo.id == stickyTodoId) return snapshot;
    if (primary.hasHardFocusGuard ||
        primary.confidence == TaskPriorityConfidence.high) {
      return snapshot;
    }
    if (_didStickyDueStateChange(snapshot)) return snapshot;

    final stickyExists = snapshot.activeEntries.any(
      (entry) => entry.todo.id == stickyTodoId,
    );
    if (!stickyExists) return snapshot;

    return snapshot.copyWith(selectedFocusTodoId: stickyTodoId);
  }

  Map<String, String> _buildStickyStateSignatures(
    TaskPrioritySnapshot snapshot,
  ) {
    return <String, String>{
      for (final entry in snapshot.activeEntries)
        entry.todo.id: jsonEncode(<Object?>[
          entry.todo.status,
          entry.todo.dueAtMs,
          entry.todo.reviewStage,
          entry.todo.nextReviewAtMs,
          entry.isOverdue,
          entry.isDueToday,
          entry.isReviewDue,
          entry.isFutureScheduled,
          entry.isInProgress,
          entry.effectiveUrgency,
          entry.effectiveImportance,
          entry.urgencyScore,
          entry.importanceScore,
          entry.dueDerivedUrgencyScore,
          entry.semanticScore,
          entry.confidence.name,
        ]),
    };
  }

  bool _didStickyDueStateChange(TaskPrioritySnapshot snapshot) {
    final previous = _stickyFocusDueStateByTodoId;
    if (previous.isEmpty) return false;
    final current = _buildStickyStateSignatures(snapshot);
    if (current.length != previous.length) return true;
    for (final entry in current.entries) {
      if (previous[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  static Future<List<Todo>> _loadAndNormalizeTodos(
    AppBackend backend, {
    required Uint8List sessionKey,
    required SyncEngine? syncEngine,
    required DateTime nowLocal,
  }) async {
    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return const <Todo>[];
    }

    late final ActionsSettings settings;
    try {
      settings = await ActionsSettingsStore.load();
    } catch (_) {
      settings = ActionsSettingsStore.defaultSettings;
    }

    final normalizedTodos = <Todo>[];
    var didMutate = false;
    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) {
        normalizedTodos.add(todo);
        continue;
      }

      final scheduledLocal =
          DateTime.fromMillisecondsSinceEpoch(nextMs, isUtc: true).toLocal();
      final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
        stage: stage,
        scheduledAtLocal: scheduledLocal,
        nowLocal: nowLocal,
        settings: settings,
      );
      if (rolled.stage == stage && rolled.nextReviewAtLocal == scheduledLocal) {
        normalizedTodos.add(todo);
        continue;
      }

      try {
        final updated = await backend.upsertTodo(
          sessionKey,
          id: todo.id,
          title: todo.title,
          dueAtMs: todo.dueAtMs,
          status: todo.status,
          sourceEntryId: todo.sourceEntryId,
          reviewStage: rolled.stage,
          nextReviewAtMs:
              rolled.nextReviewAtLocal.toUtc().millisecondsSinceEpoch,
          lastReviewAtMs: todo.lastReviewAtMs,
        );
        normalizedTodos.add(updated);
        didMutate = true;
      } catch (_) {
        normalizedTodos.add(todo);
      }
    }

    if (didMutate) {
      syncEngine?.notifyLocalMutation();
    }
    return normalizedTodos;
  }
}

final class _InMemoryAiAssessment {
  const _InMemoryAiAssessment({
    required this.entry,
    required this.requestSignature,
    required this.computedAtLocal,
  });

  final TaskPriorityAiEntry entry;
  final String requestSignature;
  final DateTime computedAtLocal;
}
