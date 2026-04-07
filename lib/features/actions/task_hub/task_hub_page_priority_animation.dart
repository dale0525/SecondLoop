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
      case TaskPriorityResolutionPhase.localFallback:
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
        if (pending.localAnimationSettled) {
          _pendingPriorityAnimation = null;
          return;
        }
        _pendingPriorityAnimation = pending.copyWith(
          clearPendingAfterLocalAnimation: true,
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
        _pendingPriorityAnimation = pending.copyWith(
          currentSourceSnapshot: localSnapshot,
          activeCaptureSourceTodoId: pending.todoId,
        );
        _schedulePriorityAnimationCompletion(
          pending: _pendingPriorityAnimation!,
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
      final plan = buildTaskHubPriorityAnimationPlan(
        previous: capture.previous,
        next: nextSnapshot,
        actedTodoId: pending.todoId,
        reducedMotion: capture.reducedMotion,
      );
      final anchorIds = <String>{pending.todoId};
      final targetSection = plan.toSection;
      if (targetSection != null) {
        anchorIds.add(_sectionAnchorId(targetSection));
      }
      _refreshCardAnchors(todoIds: anchorIds);
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
      final latestPending = _pendingPriorityAnimation;
      if (latestPending == null || latestPending.actionId != pending.actionId) {
        return;
      }
      if (capture.source == TaskHubPriorityAnimationSource.localConfirmation) {
        _pendingPriorityAnimation = latestPending.copyWith(
          localAnimationSettled: true,
        );
      }
      final updatedPending = _pendingPriorityAnimation;
      final shouldClearPending = clearPendingAfterRun ||
          (updatedPending != null &&
              updatedPending.actionId == pending.actionId &&
              updatedPending.clearPendingAfterLocalAnimation);
      if (shouldClearPending) {
        _pendingPriorityAnimation = null;
      }
    }());
  }
}

final class _TaskHubPendingPriorityAnimation {
  _TaskHubPendingPriorityAnimation({
    required this.todoId,
    required this.title,
    required this.localCapture,
    required this.previousSnapshot,
    required this.currentSourceSnapshot,
    required this.baselineComputedAtLocal,
    required this.baselineResolutionPhase,
    required this.baselineRefreshGeneration,
    String? activeCaptureSourceTodoId,
    this.localSnapshot,
    this.localAnimationSettled = false,
    this.clearPendingAfterLocalAnimation = false,
  }) : activeCaptureSourceTodoId =
            activeCaptureSourceTodoId ?? localCapture.sourceTodoId;

  final String todoId;
  final String title;
  final TaskHubPriorityAnimationCapture localCapture;
  final TaskHubPriorityAnimationSnapshot previousSnapshot;
  final TaskHubPriorityAnimationSnapshot currentSourceSnapshot;
  final DateTime? baselineComputedAtLocal;
  final TaskPriorityResolutionPhase baselineResolutionPhase;
  final int baselineRefreshGeneration;
  final String activeCaptureSourceTodoId;
  final TaskHubPriorityAnimationSnapshot? localSnapshot;
  final bool localAnimationSettled;
  final bool clearPendingAfterLocalAnimation;

  int get actionId => localCapture.generation;

  _TaskHubPendingPriorityAnimation copyWith({
    TaskHubPriorityAnimationSnapshot? localSnapshot,
    TaskHubPriorityAnimationSnapshot? currentSourceSnapshot,
    String? activeCaptureSourceTodoId,
    bool? localAnimationSettled,
    bool? clearPendingAfterLocalAnimation,
  }) {
    return _TaskHubPendingPriorityAnimation(
      todoId: todoId,
      title: title,
      localCapture: localCapture,
      previousSnapshot: previousSnapshot,
      currentSourceSnapshot:
          currentSourceSnapshot ?? this.currentSourceSnapshot,
      baselineComputedAtLocal: baselineComputedAtLocal,
      baselineResolutionPhase: baselineResolutionPhase,
      baselineRefreshGeneration: baselineRefreshGeneration,
      activeCaptureSourceTodoId:
          activeCaptureSourceTodoId ?? this.activeCaptureSourceTodoId,
      localSnapshot: localSnapshot ?? this.localSnapshot,
      localAnimationSettled:
          localAnimationSettled ?? this.localAnimationSettled,
      clearPendingAfterLocalAnimation: clearPendingAfterLocalAnimation ??
          this.clearPendingAfterLocalAnimation,
    );
  }
}

final class _TaskHubPendingPriorityMutation {
  const _TaskHubPendingPriorityMutation({
    required this.todoId,
    required this.status,
    required this.dueAtMs,
    required this.reviewStage,
    required this.nextReviewAtMs,
    required this.lastReviewAtMs,
    required this.manualImportanceNudgeScore,
    required this.manualUrgencyNudgeScore,
    required this.shouldExistInSnapshot,
    required this.baselineRefreshGeneration,
  });

  factory _TaskHubPendingPriorityMutation.fromUndoTicket(
    TaskHubUndoTicket ticket, {
    required int baselineRefreshGeneration,
  }) {
    final todo = ticket.updatedTodo;
    return _TaskHubPendingPriorityMutation(
      todoId: ticket.createdTodoId ?? todo.id,
      status: todo.status,
      dueAtMs: todo.dueAtMs,
      reviewStage: todo.reviewStage,
      nextReviewAtMs: todo.nextReviewAtMs,
      lastReviewAtMs: todo.lastReviewAtMs,
      manualImportanceNudgeScore: todo.manualImportanceNudgeScore ?? 0,
      manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore ?? 0,
      shouldExistInSnapshot: todo.status != 'dismissed',
      baselineRefreshGeneration: baselineRefreshGeneration,
    );
  }

  final String todoId;
  final String status;
  final int? dueAtMs;
  final int? reviewStage;
  final int? nextReviewAtMs;
  final int? lastReviewAtMs;
  final int manualImportanceNudgeScore;
  final int manualUrgencyNudgeScore;
  final bool shouldExistInSnapshot;
  final int baselineRefreshGeneration;
}
