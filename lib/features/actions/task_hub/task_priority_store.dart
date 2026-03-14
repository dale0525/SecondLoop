import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static const _kAiCachePrefsKey = 'task_priority_ai_cache_v1';
  TaskPriorityStore.fromLoaders({
    required Future<List<Todo>> Function() loadTodos,
    Future<List<TodoChecklistProgress>> Function()? loadChecklistProgress,
    required DateTime Function() nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
    Future<String?> Function()? resolveAiCacheScopeKey,
    Future<bool> Function()? isAiEnhancementEnabled,
    TaskPriorityFeedbackStore feedbackStore = const TaskPriorityFeedbackStore(),
    Duration aiCacheTtl = const Duration(minutes: 15),
  })  : _loadTodos = loadTodos,
        _loadChecklistProgress = loadChecklistProgress,
        _nowLocal = nowLocal,
        _resolveAiService = resolveAiService,
        _resolveAiCacheScopeKey = resolveAiCacheScopeKey,
        _isAiEnhancementEnabled = isAiEnhancementEnabled,
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
      feedbackStore: feedbackStore,
    );
  }

  final Future<List<Todo>> Function() _loadTodos;
  final Future<List<TodoChecklistProgress>> Function()? _loadChecklistProgress;
  final DateTime Function() _nowLocal;
  final Future<TaskPriorityAiService?> Function()? _resolveAiService;
  final Future<String?> Function()? _resolveAiCacheScopeKey;
  final Future<bool> Function()? _isAiEnhancementEnabled;
  final TaskPriorityFeedbackStore _feedbackStore;
  final Duration _aiCacheTtl;

  TaskPrioritySnapshot _snapshot = const TaskPrioritySnapshot.empty();
  TaskPrioritySnapshot get snapshot => _snapshot;

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

  TaskPriorityAiBatchResult? _cachedAiResult;
  String? _cachedAiSignature;
  DateTime? _cachedAiComputedAtLocal;
  String? _stickyFocusTodoId;
  DateTime? _stickyFocusDayLocal;

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
      List<TodoChecklistProgress> checklistProgressRows;
      try {
        checklistProgressRows = await _loadChecklistProgress?.call() ??
            const <TodoChecklistProgress>[];
      } catch (_) {
        checklistProgressRows = const <TodoChecklistProgress>[];
      }
      _checklistProgressByTodoId = {
        for (final item in checklistProgressRows) item.todoId: item,
      };
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
        _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
        _stickyFocusDayLocal =
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
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
      if (_snapshot.activeEntries.isNotEmpty) {
        final request =
            buildTaskPriorityAiRequest(_snapshot, nowLocal: nowLocal);
        final requestSignature = _buildAiRequestSignature(request);
        if (aiService != null) {
          try {
            final signature = _buildAiSignature(
              request,
              cacheScopeKey: aiService.cacheScopeKey,
            );
            final aiResult = _resolveCachedOrFreshAiResult(
              aiService,
              request: request,
              signature: signature,
              requestSignature: requestSignature,
              nowLocal: nowLocal,
            );
            var hybridSnapshot = buildTaskPrioritySnapshot(
              todos,
              nowLocal: nowLocal,
              aiResult: await aiResult,
              feedbackState: feedbackState,
            );
            hybridSnapshot =
                _applyStickyFocus(hybridSnapshot, nowLocal: nowLocal);
            _snapshot = hybridSnapshot;
            _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
            _stickyFocusDayLocal =
                DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
            _safeNotify();
          } catch (_) {
            // Keep the already-published rules snapshot.
          }
        } else {
          final cacheScopeKey = await _resolveAiCacheScopeKey?.call();
          final persisted = cacheScopeKey == null
              ? null
              : await _readPersistedAiCache(
                  signature: _buildAiSignature(
                    request,
                    cacheScopeKey: cacheScopeKey,
                  ),
                  requestSignature: requestSignature,
                  nowLocal: nowLocal,
                );
          if (persisted != null) {
            var hybridSnapshot = buildTaskPrioritySnapshot(
              todos,
              nowLocal: nowLocal,
              aiResult: persisted.result,
              feedbackState: feedbackState,
            );
            hybridSnapshot =
                _applyStickyFocus(hybridSnapshot, nowLocal: nowLocal);
            _snapshot = hybridSnapshot;
            _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
            _stickyFocusDayLocal =
                DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
            _safeNotify();
          } else {
            _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
            _stickyFocusDayLocal =
                DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
          }
        }
      } else {
        _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
        _stickyFocusDayLocal =
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      }
    } finally {
      _isRefreshing = false;
      _safeNotify();
    }
  }

  Future<TaskPriorityAiBatchResult> _resolveCachedOrFreshAiResult(
    TaskPriorityAiService aiService, {
    required TaskPriorityAiRequest request,
    required String signature,
    required String requestSignature,
    required DateTime nowLocal,
  }) async {
    final cachedAt = _cachedAiComputedAtLocal;
    final isMemoryCacheFresh = _cachedAiResult != null &&
        _cachedAiSignature == signature &&
        cachedAt != null &&
        nowLocal.difference(cachedAt) <= _aiCacheTtl;
    if (isMemoryCacheFresh) {
      return _cachedAiResult!;
    }

    final persisted = await _readPersistedAiCache(
      signature: signature,
      requestSignature: requestSignature,
      nowLocal: nowLocal,
    );
    if (persisted != null) {
      _cachedAiResult = persisted.result;
      _cachedAiSignature = signature;
      _cachedAiComputedAtLocal = persisted.computedAtLocal;
      return persisted.result;
    }

    final result = await aiService.rerank(request);
    _cachedAiResult = result;
    _cachedAiSignature = signature;
    _cachedAiComputedAtLocal = nowLocal;
    await _writePersistedAiCache(
      signature: signature,
      requestSignature: requestSignature,
      computedAtLocal: nowLocal,
      result: result,
    );
    return result;
  }

  Future<_PersistedAiCache?> _readPersistedAiCache({
    String? signature,
    required String requestSignature,
    required DateTime nowLocal,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAiCachePrefsKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final persistedSignature = (data['signature'] ?? '').toString();
      if (signature != null && persistedSignature != signature) return null;
      final persistedRequestSignature =
          (data['request_signature'] ?? '').toString();
      if (persistedRequestSignature != requestSignature) return null;
      final computedAtMs = data['computed_at_ms'];
      final computedAtLocal = computedAtMs is num
          ? DateTime.fromMillisecondsSinceEpoch(computedAtMs.toInt())
          : null;
      if (computedAtLocal == null ||
          nowLocal.difference(computedAtLocal) > _aiCacheTtl) {
        return null;
      }
      final resultJson = data['result'];
      if (resultJson is! Map) return null;
      final result = TaskPriorityAiBatchResult.fromJson(
        resultJson.map((key, value) => MapEntry(key.toString(), value)),
      );
      return _PersistedAiCache(
        result: result,
        computedAtLocal: computedAtLocal,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePersistedAiCache({
    required String signature,
    required String requestSignature,
    required DateTime computedAtLocal,
    required TaskPriorityAiBatchResult result,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kAiCachePrefsKey,
        jsonEncode(<String, Object?>{
          'signature': signature,
          'request_signature': requestSignature,
          'computed_at_ms': computedAtLocal.millisecondsSinceEpoch,
          'result': result.toJson(),
        }),
      );
    } catch (_) {
      // Ignore cache write failures.
    }
  }

  String _buildAiSignature(
    TaskPriorityAiRequest request, {
    required String cacheScopeKey,
  }) {
    return [
      cacheScopeKey,
      request.candidates
          .map(
            (candidate) => [
              candidate.todoId,
              candidate.status,
              candidate.band.name,
              candidate.dueState,
            ].join(':'),
          )
          .join('|'),
    ].join('||');
  }

  String _buildAiRequestSignature(TaskPriorityAiRequest request) {
    return request.candidates
        .map(
          (candidate) => [
            candidate.todoId,
            candidate.status,
            candidate.band.name,
            candidate.dueState,
          ].join(':'),
        )
        .join('|');
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

    final stickyIndex = snapshot.focus.indexWhere(
      (entry) => entry.todo.id == stickyTodoId,
    );
    if (stickyIndex <= 0) return snapshot;

    final reorderedFocus = List<TaskPriorityEntry>.from(snapshot.focus);
    final stickyEntry = reorderedFocus.removeAt(stickyIndex);
    reorderedFocus.insert(0, stickyEntry);
    return TaskPrioritySnapshot(
      source: snapshot.source,
      computedAtLocal: snapshot.computedAtLocal,
      focus: List<TaskPriorityEntry>.unmodifiable(reorderedFocus),
      scheduled: snapshot.scheduled,
      decide: snapshot.decide,
      done: snapshot.done,
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
      settings = const ActionsSettings(
        morningTime: TimeOfDay(hour: 8, minute: 0),
        dayEndTime: TimeOfDay(hour: 21, minute: 0),
        weeklyReviewTime: TimeOfDay(hour: 21, minute: 0),
      );
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

final class _PersistedAiCache {
  const _PersistedAiCache({
    required this.result,
    required this.computedAtLocal,
  });

  final TaskPriorityAiBatchResult result;
  final DateTime computedAtLocal;
}
