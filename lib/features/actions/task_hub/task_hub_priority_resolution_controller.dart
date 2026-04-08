import 'package:flutter/foundation.dart';

import 'task_priority_models.dart';

enum TaskHubPriorityResolutionStatus {
  idle,
  awaitingLocalFeedback,
  awaitingAiResolution,
  localOnlyFallback,
}

class TaskHubPriorityResolutionState {
  const TaskHubPriorityResolutionState({
    required this.todoId,
    required this.actionToken,
    required this.status,
    required this.baselineComputedAtLocal,
    required this.baselineResolutionPhase,
    required this.baselineRefreshGeneration,
  });

  const TaskHubPriorityResolutionState.idle()
      : todoId = null,
        actionToken = 0,
        status = TaskHubPriorityResolutionStatus.idle,
        baselineComputedAtLocal = null,
        baselineResolutionPhase = TaskPriorityResolutionPhase.idle,
        baselineRefreshGeneration = 0;

  final String? todoId;
  final int actionToken;
  final TaskHubPriorityResolutionStatus status;
  final DateTime? baselineComputedAtLocal;
  final TaskPriorityResolutionPhase baselineResolutionPhase;
  final int baselineRefreshGeneration;

  bool get isIdle =>
      todoId == null || status == TaskHubPriorityResolutionStatus.idle;

  TaskHubPriorityResolutionState copyWith({
    String? todoId,
    int? actionToken,
    TaskHubPriorityResolutionStatus? status,
    DateTime? baselineComputedAtLocal,
    TaskPriorityResolutionPhase? baselineResolutionPhase,
    int? baselineRefreshGeneration,
    bool clearTodoId = false,
    bool clearBaselineComputedAtLocal = false,
  }) {
    return TaskHubPriorityResolutionState(
      todoId: clearTodoId ? null : (todoId ?? this.todoId),
      actionToken: actionToken ?? this.actionToken,
      status: status ?? this.status,
      baselineComputedAtLocal: clearBaselineComputedAtLocal
          ? null
          : (baselineComputedAtLocal ?? this.baselineComputedAtLocal),
      baselineResolutionPhase:
          baselineResolutionPhase ?? this.baselineResolutionPhase,
      baselineRefreshGeneration:
          baselineRefreshGeneration ?? this.baselineRefreshGeneration,
    );
  }
}

class TaskHubPriorityResolutionController extends ChangeNotifier {
  TaskHubPriorityResolutionState _state =
      const TaskHubPriorityResolutionState.idle();
  TaskHubPriorityResolutionState get state => _state;

  int _nextActionToken = 0;
  int? _lastConsumedRefreshGeneration;
  DateTime? _lastConsumedComputedAtLocal;
  TaskPriorityResolutionPhase? _lastConsumedPhase;

  String? get pendingTodoId =>
      _state.status == TaskHubPriorityResolutionStatus.awaitingAiResolution
          ? _state.todoId
          : null;

  String? get localFallbackTodoId =>
      _state.status == TaskHubPriorityResolutionStatus.localOnlyFallback
          ? _state.todoId
          : null;

  bool isPendingTodo(String todoId) => pendingTodoId == todoId;

  void startAction({
    required String todoId,
    required DateTime? baselineComputedAtLocal,
    required TaskPriorityResolutionPhase baselineResolutionPhase,
    required int baselineRefreshGeneration,
  }) {
    _lastConsumedRefreshGeneration = null;
    _lastConsumedComputedAtLocal = null;
    _lastConsumedPhase = null;
    _setState(
      TaskHubPriorityResolutionState(
        todoId: todoId,
        actionToken: ++_nextActionToken,
        status: TaskHubPriorityResolutionStatus.awaitingLocalFeedback,
        baselineComputedAtLocal: baselineComputedAtLocal,
        baselineResolutionPhase: baselineResolutionPhase,
        baselineRefreshGeneration: baselineRefreshGeneration,
      ),
    );
  }

  void consumeSnapshot(TaskPrioritySnapshot snapshot) {
    final current = _state;
    final computedAtLocal = snapshot.computedAtLocal;
    if (current.isIdle || computedAtLocal == null) return;
    if (snapshot.refreshGeneration <= current.baselineRefreshGeneration) {
      return;
    }
    if (_lastConsumedRefreshGeneration != null &&
        _lastConsumedRefreshGeneration == snapshot.refreshGeneration &&
        _lastConsumedPhase == snapshot.resolutionPhase) {
      return;
    }
    if (_lastConsumedComputedAtLocal != null &&
        _lastConsumedPhase != null &&
        _lastConsumedComputedAtLocal!.isAtSameMomentAs(computedAtLocal) &&
        _lastConsumedPhase == snapshot.resolutionPhase) {
      return;
    }

    _lastConsumedRefreshGeneration = snapshot.refreshGeneration;
    _lastConsumedComputedAtLocal = computedAtLocal;
    _lastConsumedPhase = snapshot.resolutionPhase;

    switch (snapshot.resolutionPhase) {
      case TaskPriorityResolutionPhase.idle:
        return;
      case TaskPriorityResolutionPhase.awaitingAi:
        if (current.status !=
            TaskHubPriorityResolutionStatus.awaitingAiResolution) {
          _setState(
            current.copyWith(
              status: TaskHubPriorityResolutionStatus.awaitingAiResolution,
            ),
          );
        }
        return;
      case TaskPriorityResolutionPhase.localPublished:
      case TaskPriorityResolutionPhase.aiResolved:
        clear();
        return;
      case TaskPriorityResolutionPhase.localFallback:
        _setState(
          current.copyWith(
            status: TaskHubPriorityResolutionStatus.localOnlyFallback,
          ),
        );
        return;
    }
  }

  void clear() {
    _lastConsumedRefreshGeneration = null;
    _lastConsumedComputedAtLocal = null;
    _lastConsumedPhase = null;
    _setState(const TaskHubPriorityResolutionState.idle());
  }

  void markLocalFallback({required int actionToken}) {
    final current = _state;
    if (current.actionToken != actionToken ||
        current.status !=
            TaskHubPriorityResolutionStatus.awaitingAiResolution) {
      return;
    }
    _setState(
      current.copyWith(
        status: TaskHubPriorityResolutionStatus.localOnlyFallback,
      ),
    );
  }

  void _setState(TaskHubPriorityResolutionState next) {
    if (_state.todoId == next.todoId &&
        _state.actionToken == next.actionToken &&
        _state.status == next.status &&
        _state.baselineComputedAtLocal == next.baselineComputedAtLocal &&
        _state.baselineResolutionPhase == next.baselineResolutionPhase &&
        _state.baselineRefreshGeneration == next.baselineRefreshGeneration) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}
