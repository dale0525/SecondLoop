part of 'task_hub_page.dart';

extension _TaskHubPageStateHelpers on _TaskHubPageState {
  String? _aiSourceLabel(TaskPrioritySnapshot snapshot) {
    return switch (snapshot.enhancementSource) {
      TaskPriorityEnhancementSource.none => null,
      TaskPriorityEnhancementSource.aiLive =>
        context.t.actions.taskHub.aiInsightLive,
      TaskPriorityEnhancementSource.aiSharedCache =>
        context.t.actions.taskHub.aiInsightShared,
      TaskPriorityEnhancementSource.aiLocalCache =>
        context.t.actions.taskHub.aiInsightCached,
    };
  }

  TaskHubPriorityAnimationSnapshot _visibleAnimationSnapshot(
    TaskPrioritySnapshot snapshot,
  ) {
    return TaskHubPriorityAnimationSnapshot.fromTaskPrioritySnapshot(
      snapshot,
      doneVisibleCount: _doneSectionVisibleCount(snapshot),
    );
  }

  int _doneSectionVisibleCount(TaskPrioritySnapshot snapshot) {
    if (_doneSectionCollapsed || snapshot.done.isEmpty) {
      return 0;
    }
    return _doneVisibleCount;
  }

  bool _shouldReduceTaskHubMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations ?? false;
  }

  RenderBox? _animationLayerRenderBox() {
    final renderObject = _animationLayerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject;
  }

  Rect? _rectIfVisibleInAnimationLayer(Rect? rect) {
    if (rect == null) return null;
    final renderBox = _animationLayerRenderBox();
    if (renderBox == null) return rect;
    final layerRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    return rect.overlaps(layerRect) ? rect : null;
  }

  Rect? _rectInAnimationLayer(Rect? globalRect) {
    if (globalRect == null) return null;
    final renderObject = _animationLayerRenderBox();
    if (renderObject == null) {
      return globalRect;
    }
    final topLeft = renderObject.globalToLocal(globalRect.topLeft);
    final bottomRight = renderObject.globalToLocal(globalRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  String _sectionAnchorId(TaskHubPriorityAnimationSection section) {
    return 'task_hub_section_anchor_${section.name}';
  }

  Rect? _visibleCardOrSectionRect(
    String todoId, {
    TaskHubPriorityAnimationSection? fallbackSection,
  }) {
    final todoRect = _rectInAnimationLayer(
      _rectIfVisibleInAnimationLayer(_cardAnchorRegistry.rectFor(todoId)),
    );
    if (todoRect != null) {
      return todoRect;
    }
    if (fallbackSection == null) {
      return null;
    }
    return _rectInAnimationLayer(
      _rectIfVisibleInAnimationLayer(
        _cardAnchorRegistry.rectFor(_sectionAnchorId(fallbackSection)),
      ),
    );
  }

  Rect? _fallbackAnimationRect(
    TaskHubPriorityAnimationPlan plan,
    Rect? sourceRect,
  ) {
    final pending = _pendingPriorityAnimation;
    final sourceTodoId = pending?.activeCaptureSourceTodoId;
    final sourceSnapshot = pending?.currentSourceSnapshot;
    final sourcePosition = sourceTodoId == null || sourceSnapshot == null
        ? null
        : locateTaskHubPriorityVisibleEntry(sourceSnapshot, sourceTodoId);
    return resolveTaskHubPriorityFallbackRect(
      plan: plan,
      sourceRect: sourceRect,
      sourceSection: sourcePosition?.section,
      sourceIndex: sourcePosition?.index,
    );
  }

  Rect? _resolveAnimationTargetRect({
    required String animatedTodoId,
    required TaskHubPriorityAnimationPlan plan,
    required Rect? sourceRect,
  }) {
    final targetRect = _visibleCardOrSectionRect(
      animatedTodoId,
      fallbackSection: plan.toSection,
    );
    return targetRect ?? _fallbackAnimationRect(plan, sourceRect);
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  void _refreshCardAnchors({Iterable<String>? todoIds}) {
    _cardAnchorRegistry.refresh(todoIds: todoIds);
  }

  void _refreshTrackedCardAnchors() {
    final trackedIds = <String>{};
    final pending = _pendingPriorityAnimation;
    if (pending != null) {
      trackedIds.add(pending.todoId);
      trackedIds.add(pending.activeCaptureSourceTodoId);
    }
    final overlay = _priorityAnimationController.activeOverlay;
    if (overlay != null) {
      trackedIds.add(overlay.todoId);
    }
    final inline = _priorityAnimationController.activeInlineAnimation;
    if (inline != null) {
      trackedIds.add(inline.todoId);
    }
    final plan = _priorityAnimationController.lastPlan;
    if (plan != null) {
      if (plan.fromSection != null) {
        trackedIds.add(_sectionAnchorId(plan.fromSection!));
      }
      if (plan.toSection != null) {
        trackedIds.add(_sectionAnchorId(plan.toSection!));
      }
    }
    if (trackedIds.isEmpty) {
      return;
    }
    _refreshCardAnchors(todoIds: trackedIds);
  }
}
