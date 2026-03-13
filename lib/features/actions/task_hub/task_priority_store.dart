import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  TaskPriorityStore.fromLoaders({
    required Future<List<Todo>> Function() loadTodos,
    required DateTime Function() nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
    Future<bool> Function()? isAiEnhancementEnabled,
    TaskPriorityFeedbackStore feedbackStore = const TaskPriorityFeedbackStore(),
    Duration aiCacheTtl = const Duration(minutes: 15),
  })  : _loadTodos = loadTodos,
        _nowLocal = nowLocal,
        _resolveAiService = resolveAiService,
        _isAiEnhancementEnabled = isAiEnhancementEnabled,
        _feedbackStore = feedbackStore,
        _aiCacheTtl = aiCacheTtl;

  factory TaskPriorityStore({
    required AppBackend backend,
    required Uint8List sessionKey,
    SyncEngine? syncEngine,
    DateTime Function()? nowLocal,
    Future<TaskPriorityAiService?> Function()? resolveAiService,
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
      nowLocal: nowLocal ?? DateTime.now,
      resolveAiService: resolveAiService,
      isAiEnhancementEnabled: isAiEnhancementEnabled,
      feedbackStore: feedbackStore,
    );
  }

  final Future<List<Todo>> Function() _loadTodos;
  final DateTime Function() _nowLocal;
  final Future<TaskPriorityAiService?> Function()? _resolveAiService;
  final Future<bool> Function()? _isAiEnhancementEnabled;
  final TaskPriorityFeedbackStore _feedbackStore;
  final Duration _aiCacheTtl;

  TaskPrioritySnapshot _snapshot = const TaskPrioritySnapshot.empty();
  TaskPrioritySnapshot get snapshot => _snapshot;

  TaskPriorityAiAvailability _aiAvailability =
      TaskPriorityAiAvailability.unknown;
  TaskPriorityAiAvailability get aiAvailability => _aiAvailability;
  bool get isAiEnhancementEnabled =>
      _aiAvailability != TaskPriorityAiAvailability.disabled;
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

  void markDirty() {
    _dirty = true;
    notifyListeners();
  }

  Future<void> refresh({bool force = false}) {
    if (_inflightRefresh != null) {
      if (!force) return _inflightRefresh!;
      return _inflightRefresh!.then((_) => refresh(force: true));
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
    _isRefreshing = true;
    notifyListeners();

    try {
      final nowLocal = _nowLocal();
      final todos = await _loadTodos();
      await _feedbackStore.pruneToTodoIds(todos.map((todo) => todo.id));
      final feedbackState = await _feedbackStore.read();

      _snapshot = buildTaskPrioritySnapshot(
        todos,
        nowLocal: nowLocal,
        feedbackState: feedbackState,
      );
      _dirty = false;
      notifyListeners();

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
      if (aiService != null && _snapshot.activeEntries.isNotEmpty) {
        try {
          final request =
              buildTaskPriorityAiRequest(_snapshot, nowLocal: nowLocal);
          final signature = _buildAiSignature(request);
          final aiResult = _resolveCachedOrFreshAiResult(
            aiService,
            request: request,
            signature: signature,
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
          notifyListeners();
        } catch (_) {
          // Keep the already-published rules snapshot.
        }
      } else {
        _stickyFocusTodoId = _snapshot.primaryFocus?.todo.id;
        _stickyFocusDayLocal =
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      }
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<TaskPriorityAiBatchResult> _resolveCachedOrFreshAiResult(
    TaskPriorityAiService aiService, {
    required TaskPriorityAiRequest request,
    required String signature,
    required DateTime nowLocal,
  }) async {
    final cachedAt = _cachedAiComputedAtLocal;
    final isCacheFresh = _cachedAiResult != null &&
        _cachedAiSignature == signature &&
        cachedAt != null &&
        nowLocal.difference(cachedAt) <= _aiCacheTtl;
    if (isCacheFresh) {
      return _cachedAiResult!;
    }
    final result = await aiService.rerank(request);
    _cachedAiResult = result;
    _cachedAiSignature = signature;
    _cachedAiComputedAtLocal = nowLocal;
    return result;
  }

  String _buildAiSignature(TaskPriorityAiRequest request) {
    return request.candidates
        .map(
          (candidate) => [
            candidate.todoId,
            candidate.status,
            candidate.band.name,
            candidate.dueState,
            candidate.updatedAtMs.toString(),
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
