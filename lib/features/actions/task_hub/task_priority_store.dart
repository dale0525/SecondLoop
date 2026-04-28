import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../src/rust/db.dart';
import '../../../src/rust/platform_int.dart';
import '../review/review_backoff.dart';
import '../settings/actions_settings_store.dart';
import 'task_priority_ai.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_engine.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';
import 'task_priority_sticky_focus.dart';

part 'task_priority_store_ai_cache.dart';

enum TaskPriorityAiAvailability {
  unknown,
  disabled,
  unavailable,
  available,
}

class TaskPriorityStore extends ChangeNotifier {
  static const _kAiCachePrefsKey = 'task_priority_ai_cache_v3';
  static const _kAiCacheLastScopeKey = 'last_scope';
  final Map<String, _InMemoryAiAssessment> _inMemoryAiAssessments =
      <String, _InMemoryAiAssessment>{};

  TaskPriorityStore.fromLoaders({
    required Future<List<Todo>> Function() loadTodos,
    Future<List<TodoChecklistProgress>> Function()? loadChecklistProgress,
    required DateTime Function() nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
    Future<String?> Function()? resolveAiCacheScopeKey,
    Future<bool> Function()? isAiEnhancementEnabled,
    Future<BackendTaskPriorityAiSharedAssessmentsClient?> Function({
      required String cacheScopeKey,
    })? resolveSharedAiAssessmentsClient,
    // Legacy test seam; production callers should use
    // resolveSharedAiAssessmentsClient instead.
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
      required DateTime nowLocal,
    })? writeSharedAiAssessments,
    TaskPriorityFeedbackStore feedbackStore = const TaskPriorityFeedbackStore(),
    Duration aiCacheTtl = defaultTaskPriorityAiCacheTtl,
  })  : _loadTodos = loadTodos,
        _loadChecklistProgress = loadChecklistProgress,
        _nowLocal = nowLocal,
        _resolveAiService = resolveAiService,
        _resolveAiCacheScopeKey = resolveAiCacheScopeKey,
        _isAiEnhancementEnabled = isAiEnhancementEnabled,
        _resolveSharedAiAssessmentsClient = resolveSharedAiAssessmentsClient,
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
    Future<BackendTaskPriorityAiSharedAssessmentsClient?> Function({
      required String cacheScopeKey,
    })? resolveSharedAiAssessmentsClient,
    // Legacy test seam; production callers should use
    // resolveSharedAiAssessmentsClient instead.
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
      required DateTime nowLocal,
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
      resolveSharedAiAssessmentsClient: resolveSharedAiAssessmentsClient,
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
  final Future<BackendTaskPriorityAiSharedAssessmentsClient?> Function({
    required String cacheScopeKey,
  })? _resolveSharedAiAssessmentsClient;
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
    required DateTime nowLocal,
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
  final TaskPriorityStickyFocusState _stickyFocus =
      TaskPriorityStickyFocusState();
  Future<void>? _inflightRefresh;
  Future<void>? _inflightForcedLocalRefresh;
  bool _refreshQueuedAfterInflight = false;
  int _refreshGeneration = 0;
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
      if (force) {
        _refreshQueuedAfterInflight = true;
        _inflightForcedLocalRefresh ??=
            _publishLatestLocalSnapshotWhileInflight().whenComplete(() {
          _inflightForcedLocalRefresh = null;
        });
        return _inflightForcedLocalRefresh!;
      }
      return _inflightRefresh!;
    }
    if (!force && !_dirty && _snapshot.computedAtLocal != null) {
      return Future<void>.value();
    }
    final future = _runRefreshCycle();
    _inflightRefresh = future.whenComplete(() {
      _inflightRefresh = null;
    });
    return _inflightRefresh!;
  }

  Future<void> _runRefreshCycle() async {
    await _refreshImpl();
    while (!_disposed && _refreshQueuedAfterInflight) {
      _refreshQueuedAfterInflight = false;
      await _refreshImpl();
    }
  }

  Future<void> _refreshImpl() async {
    if (_disposed) return;
    _isRefreshing = true;
    _safeNotify();

    try {
      final nowLocal = _nowLocal();
      final refreshGeneration = ++_refreshGeneration;
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
      final rulesSnapshot = buildTaskPrioritySnapshot(
        todos,
        nowLocal: nowLocal,
        feedbackState: feedbackState,
      ).copyWith(refreshGeneration: refreshGeneration);
      _dirty = false;

      final aiEnhancementEnabled =
          await _isAiEnhancementEnabled?.call() ?? true;
      if (!aiEnhancementEnabled) {
        final published = _publishSnapshot(
          rulesSnapshot.copyWith(
            resolutionPhase: TaskPriorityResolutionPhase.localPublished,
          ),
          nowLocal: nowLocal,
          rememberStickyFocus: true,
        );
        _aiAvailability = TaskPriorityAiAvailability.disabled;
        if (published) {
          _safeNotify();
        }
        return;
      }

      if (rulesSnapshot.activeEntries.isEmpty) {
        final published = _publishSnapshot(
          rulesSnapshot.copyWith(
            resolutionPhase: TaskPriorityResolutionPhase.localPublished,
          ),
          nowLocal: nowLocal,
          rememberStickyFocus: true,
        );
        if (published) {
          _safeNotify();
        }
        return;
      }

      final request = buildTaskPriorityAiRequest(
        rulesSnapshot,
        nowLocal: nowLocal,
      );
      if (request.candidates.isEmpty) {
        final published = _publishSnapshot(
          rulesSnapshot.copyWith(
            resolutionPhase: TaskPriorityResolutionPhase.localPublished,
          ),
          nowLocal: nowLocal,
          rememberStickyFocus: true,
        );
        if (published) {
          _safeNotify();
        }
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
      if (_disposed) return;

      final serviceCacheScopeKey = aiService?.cacheScopeKey.trim();
      final resolvedCacheScopeKey =
          (await _resolveAiCacheScopeKey?.call())?.trim();
      if (_disposed) return;
      final sharedCacheScopeKey = (serviceCacheScopeKey?.isNotEmpty ?? false)
          ? serviceCacheScopeKey
          : resolvedCacheScopeKey;
      final persistedCacheScopeKey =
          (resolvedCacheScopeKey?.isNotEmpty ?? false)
              ? resolvedCacheScopeKey
              : serviceCacheScopeKey;
      final canUseSharedCache =
          sharedCacheScopeKey != null && sharedCacheScopeKey.isNotEmpty;
      final canUsePersistedCache =
          persistedCacheScopeKey != null && persistedCacheScopeKey.isNotEmpty;
      final canUseInMemoryCache = !canUsePersistedCache;
      BackendTaskPriorityAiSharedAssessmentsClient? sharedAssessmentsClient;
      var didResolveSharedAssessmentsClient = false;

      Future<BackendTaskPriorityAiSharedAssessmentsClient?>
          resolveSharedAssessmentsClient() async {
        if (!canUseSharedCache || didResolveSharedAssessmentsClient) {
          return sharedAssessmentsClient;
        }
        didResolveSharedAssessmentsClient = true;
        sharedAssessmentsClient = await _resolveSharedAiAssessmentsClient?.call(
          cacheScopeKey: sharedCacheScopeKey,
        );
        return sharedAssessmentsClient;
      }

      Future<Map<String, TaskPriorityAiCachedAssessment>>
          readSharedPersistedAssessments() async {
        final client = await resolveSharedAssessmentsClient();
        if (_disposed) {
          return const <String, TaskPriorityAiCachedAssessment>{};
        }
        if (client != null) {
          return client.read(
            nowLocal: nowLocal,
            cacheTtl: _aiCacheTtl,
          );
        }
        return await _readSharedAiAssessments?.call(
              aiService: aiService,
              cacheScopeKey: sharedCacheScopeKey!,
              nowLocal: nowLocal,
            ) ??
            const <String, TaskPriorityAiCachedAssessment>{};
      }

      Future<void> writeSharedPersistedAssessments({
        required Map<String, TaskPriorityAiCachedAssessment> entries,
        required Iterable<String> activeTodoIds,
      }) async {
        final client = await resolveSharedAssessmentsClient();
        if (_disposed) return;
        if (client != null) {
          await client.write(
            entries: entries,
            activeTodoIds: activeTodoIds,
          );
        } else {
          await _writeSharedAiAssessments?.call(
            aiService: aiService,
            cacheScopeKey: sharedCacheScopeKey!,
            entries: entries,
            activeTodoIds: activeTodoIds,
            nowLocal: nowLocal,
          );
        }
      }

      final candidateByTodoId = <String, TaskPriorityAiCandidate>{
        for (final candidate in request.candidates) candidate.todoId: candidate,
      };
      final bootstrapPersisted = canUsePersistedCache
          ? _filterMatchingPersistedAiAssessments(
              await _readPersistedAiAssessments(
                cacheScopeKey: persistedCacheScopeKey,
                nowLocal: nowLocal,
              ),
              candidateByTodoId: candidateByTodoId,
              nowLocal: nowLocal,
            )
          : await _readMatchingPersistedAiAssessments(
              candidateByTodoId: candidateByTodoId,
              nowLocal: nowLocal,
            );
      if (_disposed) return;
      final bootstrapHasCompleteCoverage = request.candidates.isNotEmpty &&
          request.candidates.every(
            (candidate) => bootstrapPersisted.containsKey(candidate.todoId),
          );
      final publishedBootstrap = bootstrapPersisted.isNotEmpty
          ? _publishSnapshot(
              buildTaskPrioritySnapshot(
                todos,
                nowLocal: nowLocal,
                aiResult: TaskPriorityAiBatchResult(
                  entries: bootstrapPersisted.values
                      .map((value) => value.entry)
                      .toList(growable: false),
                ),
                enhancementSource: TaskPriorityEnhancementSource.aiLocalCache,
                feedbackState: feedbackState,
              ).copyWith(
                resolutionPhase: aiService == null
                    ? TaskPriorityResolutionPhase.aiResolved
                    : bootstrapHasCompleteCoverage
                        ? TaskPriorityResolutionPhase.aiResolved
                        : TaskPriorityResolutionPhase.awaitingAi,
                refreshGeneration: refreshGeneration,
              ),
              nowLocal: nowLocal,
            )
          : _publishSnapshot(
              rulesSnapshot.copyWith(
                resolutionPhase: aiService == null
                    ? TaskPriorityResolutionPhase.localPublished
                    : TaskPriorityResolutionPhase.awaitingAi,
              ),
              nowLocal: nowLocal,
            );
      if (publishedBootstrap) {
        _safeNotify();
      }

      if (_disposed) return;
      final sharedPersisted = canUseSharedCache && !bootstrapHasCompleteCoverage
          ? await readSharedPersistedAssessments()
          : const <String, TaskPriorityAiCachedAssessment>{};
      if (_disposed) return;
      final persisted = canUsePersistedCache
          ? await _readPersistedAiAssessments(
              cacheScopeKey: persistedCacheScopeKey,
              nowLocal: nowLocal,
            )
          : const <String, TaskPriorityAiCachedAssessment>{};
      if (_disposed) return;
      final memoryCached = canUseInMemoryCache
          ? _readInMemoryAiAssessments(nowLocal: nowLocal)
          : const <String, TaskPriorityAiCachedAssessment>{};
      final freshEntries = <String, TaskPriorityAiEntry>{};
      final cachedEnhancementSources =
          <String, TaskPriorityEnhancementSource>{};
      final sharedCacheTodoIds = <String>{};
      final localCacheTodoIds = <String>{};
      final liveTodoIds = <String>{};
      final mergedPersisted = <String, TaskPriorityAiCachedAssessment>{};
      if (canUsePersistedCache) {
        for (final entry in persisted.entries) {
          mergedPersisted[entry.key] = entry.value;
          cachedEnhancementSources[entry.key] =
              TaskPriorityEnhancementSource.aiLocalCache;
        }
        for (final entry in sharedPersisted.entries) {
          final existing = mergedPersisted[entry.key];
          if (existing == null ||
              entry.value.computedAtLocal.isAfter(existing.computedAtLocal)) {
            mergedPersisted[entry.key] = entry.value;
            cachedEnhancementSources[entry.key] =
                TaskPriorityEnhancementSource.aiSharedCache;
          }
        }
      } else {
        mergedPersisted.addAll(
          _mergeCachedAssessments(memoryCached, bootstrapPersisted),
        );
        for (final todoId in mergedPersisted.keys) {
          cachedEnhancementSources[todoId] =
              TaskPriorityEnhancementSource.aiLocalCache;
        }
      }
      final staleCandidates = <TaskPriorityAiCandidate>[];

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
      for (final activeEntry in rulesSnapshot.activeEntries) {
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

      var didLiveRerankFail = false;
      if (aiService != null && staleCandidates.isNotEmpty) {
        final staleCandidateByTodoId = <String, TaskPriorityAiCandidate>{
          for (final candidate in staleCandidates) candidate.todoId: candidate,
        };
        try {
          final result = await aiService.rerank(
            request.copyWith(candidates: staleCandidates),
          );
          if (_disposed) return;
          for (final entry in result.entries) {
            final candidate = staleCandidateByTodoId[entry.todoId];
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
          didLiveRerankFail = true;
        }
      }

      if (canUsePersistedCache) {
        await _writePersistedAiAssessments(
          cacheScopeKey: persistedCacheScopeKey,
          entries: mergedPersisted,
          activeTodoIds:
              rulesSnapshot.activeEntries.map((entry) => entry.todo.id),
          nowLocal: nowLocal,
        );
      } else if (canUseInMemoryCache) {
        _writeInMemoryAiAssessments(
          entries: mergedPersisted,
          activeTodoIds:
              rulesSnapshot.activeEntries.map((entry) => entry.todo.id),
        );
      }
      if (_disposed) return;
      if (canUseSharedCache && liveTodoIds.isNotEmpty) {
        final activeTodoIds =
            rulesSnapshot.activeEntries.map((entry) => entry.todo.id);
        await writeSharedPersistedAssessments(
          entries: mergedPersisted,
          activeTodoIds: activeTodoIds,
        );
      }
      if (_disposed) return;

      final aiEntries = <TaskPriorityAiEntry>[];
      for (final activeEntry in rulesSnapshot.activeEntries) {
        final todoId = activeEntry.todo.id;
        final entry = freshEntries[todoId] ?? mergedPersisted[todoId]?.entry;
        if (entry != null) aiEntries.add(entry);
      }
      if (aiEntries.isEmpty) {
        _aiAvailability = TaskPriorityAiAvailability.unavailable;
        final published = _publishSnapshot(
          rulesSnapshot.copyWith(
            resolutionPhase: didLiveRerankFail
                ? TaskPriorityResolutionPhase.localFallback
                : TaskPriorityResolutionPhase.localPublished,
          ),
          nowLocal: nowLocal,
          rememberStickyFocus: true,
        );
        if (published) {
          _safeNotify();
        }
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
      hybridSnapshot = _stickyFocus.apply(
        hybridSnapshot.copyWith(
          resolutionPhase: TaskPriorityResolutionPhase.aiResolved,
          refreshGeneration: refreshGeneration,
        ),
        nowLocal: nowLocal,
      );
      final published = _publishSnapshot(
        hybridSnapshot,
        nowLocal: nowLocal,
        rememberStickyFocus: true,
      );
      if (published) {
        _safeNotify();
      }
    } finally {
      _isRefreshing = false;
      _safeNotify();
    }
  }

  Future<void> _publishLatestLocalSnapshotWhileInflight() async {
    if (_disposed) return;

    final nowLocal = _nowLocal();
    final refreshGeneration = ++_refreshGeneration;
    final todos = await _loadTodos();
    final previewFeedbackState = await _feedbackStore.read();
    final rulesSnapshot = buildTaskPrioritySnapshot(
      todos,
      nowLocal: nowLocal,
      feedbackState: previewFeedbackState,
    ).copyWith(refreshGeneration: refreshGeneration);
    _dirty = false;

    // Keep the preview path read-only with respect to shared store state.
    // The queued full refresh owns checklist-progress publication and feedback
    // pruning once the current in-flight refresh settles.
    await _publishLocalPreviewSnapshot(
      rulesSnapshot: rulesSnapshot,
      nowLocal: nowLocal,
      aiEnhancementEnabled: await _isAiEnhancementEnabled?.call() ?? true,
    );
  }

  Future<void> _publishLocalPreviewSnapshot({
    required TaskPrioritySnapshot rulesSnapshot,
    required DateTime nowLocal,
    required bool aiEnhancementEnabled,
  }) async {
    if (!aiEnhancementEnabled || rulesSnapshot.activeEntries.isEmpty) {
      if (_publishSnapshot(
        rulesSnapshot.copyWith(
          resolutionPhase: TaskPriorityResolutionPhase.localPublished,
        ),
        nowLocal: nowLocal,
      )) {
        if (!aiEnhancementEnabled) {
          _aiAvailability = TaskPriorityAiAvailability.disabled;
        }
        _safeNotify();
      }
      return;
    }

    if (_publishSnapshot(
      rulesSnapshot.copyWith(
        resolutionPhase: TaskPriorityResolutionPhase.awaitingAi,
      ),
      nowLocal: nowLocal,
    )) {
      _safeNotify();
    }
    // The active refresh cycle already owns AI service resolution and reranking.
    // Avoid resolving it again here so force-refresh only republishes the newest
    // local snapshot while the in-flight refresh completes or reruns.
  }

  bool _publishSnapshot(
    TaskPrioritySnapshot snapshot, {
    DateTime? nowLocal,
    bool rememberStickyFocus = false,
  }) {
    if (_disposed) return false;
    if (nowLocal != null &&
        snapshot.resolutionPhase != TaskPriorityResolutionPhase.idle) {
      snapshot = _stickyFocus.apply(snapshot, nowLocal: nowLocal);
    }
    if (snapshot.refreshGeneration < _snapshot.refreshGeneration) {
      return false;
    }
    _snapshot = snapshot;
    if (rememberStickyFocus && nowLocal != null) {
      _stickyFocus.remember(_snapshot, nowLocal);
    }
    return true;
  }

  Future<Map<String, TaskPriorityAiCachedAssessment>>
      _readPersistedAiAssessments({
    required String cacheScopeKey,
    required DateTime nowLocal,
  }) {
    return _readTaskPriorityPersistedAiAssessments(
      cacheScopeKey: cacheScopeKey,
      nowLocal: nowLocal,
      aiCacheTtl: _aiCacheTtl,
    );
  }

  Future<Map<String, TaskPriorityAiCachedAssessment>>
      _readMatchingPersistedAiAssessments({
    required Map<String, TaskPriorityAiCandidate> candidateByTodoId,
    required DateTime nowLocal,
  }) {
    return _readMatchingTaskPriorityPersistedAiAssessments(
      candidateByTodoId: candidateByTodoId,
      nowLocal: nowLocal,
      aiCacheTtl: _aiCacheTtl,
    );
  }

  Map<String, TaskPriorityAiCachedAssessment>
      _filterMatchingPersistedAiAssessments(
    Map<String, TaskPriorityAiCachedAssessment> entries, {
    required Map<String, TaskPriorityAiCandidate> candidateByTodoId,
    required DateTime nowLocal,
  }) {
    return _filterMatchingTaskPriorityPersistedAiAssessments(
      entries,
      candidateByTodoId: candidateByTodoId,
      nowLocal: nowLocal,
    );
  }

  Map<String, TaskPriorityAiCachedAssessment> _mergeCachedAssessments(
    Map<String, TaskPriorityAiCachedAssessment> primary,
    Map<String, TaskPriorityAiCachedAssessment> fallback,
  ) {
    return _mergeTaskPriorityCachedAssessments(primary, fallback);
  }

  Map<String, TaskPriorityAiCachedAssessment> _readInMemoryAiAssessments({
    required DateTime nowLocal,
  }) {
    return _readTaskPriorityInMemoryAiAssessments(
      _inMemoryAiAssessments,
      nowLocal: nowLocal,
      aiCacheTtl: _aiCacheTtl,
    );
  }

  void _writeInMemoryAiAssessments({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) {
    _writeTaskPriorityInMemoryAiAssessments(
      _inMemoryAiAssessments,
      entries: entries,
      activeTodoIds: activeTodoIds,
    );
  }

  Future<void> _writePersistedAiAssessments({
    required String cacheScopeKey,
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
    required DateTime nowLocal,
  }) {
    return _writeTaskPriorityPersistedAiAssessments(
      cacheScopeKey: cacheScopeKey,
      entries: entries,
      activeTodoIds: activeTodoIds,
      nowLocal: nowLocal,
      aiCacheTtl: _aiCacheTtl,
    );
  }

  String _buildCandidateRequestSignature(
    TaskPriorityAiCandidate candidate, {
    required DateTime nowLocal,
  }) {
    return _buildTaskPriorityCandidateRequestSignature(
      candidate,
      nowLocal: nowLocal,
    );
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

      final scheduledLocal = DateTime.fromMillisecondsSinceEpoch(
        platformIntToInt(nextMs),
        isUtc: true,
      ).toLocal();
      final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
        stage: platformIntToInt(stage),
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
          dueAtMs: coerceNullablePlatformInt(todo.dueAtMs),
          status: todo.status,
          sourceEntryId: todo.sourceEntryId,
          reviewStage: rolled.stage,
          nextReviewAtMs:
              rolled.nextReviewAtLocal.toUtc().millisecondsSinceEpoch,
          lastReviewAtMs: coerceNullablePlatformInt(todo.lastReviewAtMs),
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
