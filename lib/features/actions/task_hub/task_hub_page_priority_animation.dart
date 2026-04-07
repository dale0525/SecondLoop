part of 'task_hub_page.dart';

extension _TaskHubPageStatePriorityAnimation on _TaskHubPageState {
  void _handlePriorityAnimationSnapshot(TaskPrioritySnapshot snapshot) {
    final pending = _pendingPriorityAnimation;
    final computedAtLocal = snapshot.computedAtLocal;
    if (pending == null || computedAtLocal == null) return;
    if (snapshot.refreshGeneration <= pending.baselineRefreshGeneration) {
      return;
    }

    final nextSnapshot = _visibleAnimationSnapshot(snapshot);
    switch (snapshot.resolutionPhase) {
      case TaskPriorityResolutionPhase.idle:
        return;
      case TaskPriorityResolutionPhase.awaitingAi:
      case TaskPriorityResolutionPhase.localPublished:
      case TaskPriorityResolutionPhase.localFallback:
        if (pending.localSnapshot != null) {
          return;
        }
        final updatedPending = pending.copyWith(localSnapshot: nextSnapshot);
        _pendingPriorityAnimation = updatedPending;
        _schedulePriorityAnimationCompletion(
          pending: updatedPending,
          capture: updatedPending.localCapture,
          nextSnapshot: nextSnapshot,
          clearPendingAfterRun: snapshot.resolutionPhase !=
              TaskPriorityResolutionPhase.awaitingAi,
        );
        return;
      case TaskPriorityResolutionPhase.aiResolved:
        final localSnapshot = pending.localSnapshot;
        if (localSnapshot == null) {
          final updatedPending = pending.copyWith(localSnapshot: nextSnapshot);
          _pendingPriorityAnimation = updatedPending;
          _schedulePriorityAnimationCompletion(
            pending: updatedPending,
            capture: updatedPending.localCapture,
            nextSnapshot: nextSnapshot,
            clearPendingAfterRun: true,
          );
          return;
        }

        final reconciliationPlan = buildTaskHubPriorityAnimationPlan(
          previous: localSnapshot,
          next: nextSnapshot,
          actedTodoId: pending.todoId,
          reducedMotion: pending.localCapture.reducedMotion,
        );
        if (reconciliationPlan.kind == TaskHubPriorityAnimationKind.none ||
            reconciliationPlan.kind ==
                TaskHubPriorityAnimationKind.noEmphasis) {
          _pendingPriorityAnimation = null;
          return;
        }

        final capture = _priorityAnimationController.prepareAction(
          source: TaskHubPriorityAnimationSource.aiReconciliation,
          sourceTodoId: pending.todoId,
          title: pending.title,
          snapshot: localSnapshot,
          reducedMotion: pending.localCapture.reducedMotion,
          sourceRect: _rectInAnimationLayer(
              _cardAnchorRegistry.rectFor(pending.todoId)),
        );
        _schedulePriorityAnimationCompletion(
          pending: pending,
          capture: capture,
          nextSnapshot: nextSnapshot,
          clearPendingAfterRun: true,
        );
        return;
    }
  }

  void _schedulePriorityAnimationCompletion({
    required _TaskHubPendingPriorityAnimation pending,
    required TaskHubPriorityAnimationCapture capture,
    required TaskHubPriorityAnimationSnapshot nextSnapshot,
    required bool clearPendingAfterRun,
  }) {
    unawaited(() async {
      await _waitForNextFrame();
      if (!mounted) return;
      final activePending = _pendingPriorityAnimation;
      if (activePending == null || activePending.actionId != pending.actionId) {
        return;
      }
      _refreshCardAnchors(todoIds: <String>[pending.todoId]);
      final plan = buildTaskHubPriorityAnimationPlan(
        previous: capture.previous,
        next: nextSnapshot,
        actedTodoId: pending.todoId,
        reducedMotion: capture.reducedMotion,
      );
      _priorityAnimationController.completeAction(
        capture,
        animatedTodoId: pending.todoId,
        next: nextSnapshot,
        targetRect: _resolveAnimationTargetRect(
          animatedTodoId: pending.todoId,
          plan: plan,
          sourceRect: capture.sourceRect,
        ),
      );
      if (clearPendingAfterRun &&
          _pendingPriorityAnimation?.actionId == pending.actionId) {
        _pendingPriorityAnimation = null;
      }
    }());
  }
}

final class _TaskHubPendingPriorityAnimation {
  const _TaskHubPendingPriorityAnimation({
    required this.todoId,
    required this.title,
    required this.localCapture,
    required this.previousSnapshot,
    required this.baselineComputedAtLocal,
    required this.baselineResolutionPhase,
    required this.baselineRefreshGeneration,
    this.localSnapshot,
  });

  final String todoId;
  final String title;
  final TaskHubPriorityAnimationCapture localCapture;
  final TaskHubPriorityAnimationSnapshot previousSnapshot;
  final DateTime? baselineComputedAtLocal;
  final TaskPriorityResolutionPhase baselineResolutionPhase;
  final int baselineRefreshGeneration;
  final TaskHubPriorityAnimationSnapshot? localSnapshot;

  int get actionId => localCapture.generation;

  _TaskHubPendingPriorityAnimation copyWith({
    TaskHubPriorityAnimationSnapshot? localSnapshot,
  }) {
    return _TaskHubPendingPriorityAnimation(
      todoId: todoId,
      title: title,
      localCapture: localCapture,
      previousSnapshot: previousSnapshot,
      baselineComputedAtLocal: baselineComputedAtLocal,
      baselineResolutionPhase: baselineResolutionPhase,
      baselineRefreshGeneration: baselineRefreshGeneration,
      localSnapshot: localSnapshot ?? this.localSnapshot,
    );
  }
}
