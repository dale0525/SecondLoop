import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'task_hub_priority_animation_plan.dart';

enum TaskHubPriorityAnimationSource {
  localConfirmation,
  aiReconciliation,
}

class TaskHubPriorityAnimationCapture {
  const TaskHubPriorityAnimationCapture({
    required this.generation,
    required this.source,
    required this.sourceTodoId,
    required this.title,
    required this.previous,
    required this.reducedMotion,
    this.sourceRect,
  });

  final int generation;
  final TaskHubPriorityAnimationSource source;
  final String sourceTodoId;
  final String title;
  final TaskHubPriorityAnimationSnapshot previous;
  final bool reducedMotion;
  final Rect? sourceRect;
}

class TaskHubPriorityOverlayState {
  const TaskHubPriorityOverlayState({
    required this.todoId,
    required this.title,
    required this.token,
    required this.beginRect,
    required this.endRect,
    this.duration = const Duration(milliseconds: 320),
  });

  final String todoId;
  final String title;
  final int token;
  final Rect beginRect;
  final Rect endRect;
  final Duration duration;
}

class TaskHubPriorityInlineAnimationState {
  const TaskHubPriorityInlineAnimationState({
    required this.todoId,
    required this.beginOffset,
    required this.token,
    this.duration = const Duration(milliseconds: 240),
  });

  final String todoId;
  final Offset beginOffset;
  final int token;
  final Duration duration;
}

class TaskHubPriorityAnimationController extends ChangeNotifier {
  TaskHubPriorityOverlayState? _activeOverlay;
  TaskHubPriorityOverlayState? get activeOverlay => _activeOverlay;
  TaskHubPriorityInlineAnimationState? _activeInlineAnimation;
  TaskHubPriorityInlineAnimationState? get activeInlineAnimation =>
      _activeInlineAnimation;

  TaskHubPriorityAnimationPlan? _lastPlan;
  TaskHubPriorityAnimationPlan? get lastPlan => _lastPlan;
  TaskHubPriorityAnimationSource? _lastAnimationSource;
  @visibleForTesting
  TaskHubPriorityAnimationSource? get lastAnimationSource =>
      _lastAnimationSource;
  int _animationToken = 0;
  int _actionGeneration = 0;

  TaskHubPriorityAnimationCapture captureAction({
    required String sourceTodoId,
    required String title,
    required TaskHubPriorityAnimationSnapshot snapshot,
    required bool reducedMotion,
    Rect? sourceRect,
  }) {
    final generation = ++_actionGeneration;
    return TaskHubPriorityAnimationCapture(
      generation: generation,
      source: TaskHubPriorityAnimationSource.localConfirmation,
      sourceTodoId: sourceTodoId,
      title: title,
      previous: snapshot,
      reducedMotion: reducedMotion,
      sourceRect: sourceRect,
    );
  }

  void activateLocalFeedback(TaskHubPriorityAnimationCapture capture) {
    if (capture.generation != _actionGeneration) {
      return;
    }
    _activeOverlay = null;
    _activeInlineAnimation = capture.reducedMotion
        ? null
        : TaskHubPriorityInlineAnimationState(
            todoId: capture.sourceTodoId,
            beginOffset: const Offset(0, -18),
            token: ++_animationToken,
            duration: const Duration(milliseconds: 180),
          );
    _lastPlan = null;
    _lastAnimationSource = null;
    notifyListeners();
  }

  TaskHubPriorityAnimationCapture beginAction({
    required String sourceTodoId,
    required String title,
    required TaskHubPriorityAnimationSnapshot snapshot,
    required bool reducedMotion,
    Rect? sourceRect,
  }) {
    final capture = captureAction(
      sourceTodoId: sourceTodoId,
      title: title,
      snapshot: snapshot,
      reducedMotion: reducedMotion,
      sourceRect: sourceRect,
    );
    activateLocalFeedback(capture);
    return capture;
  }

  TaskHubPriorityAnimationCapture prepareAction({
    required TaskHubPriorityAnimationSource source,
    required String sourceTodoId,
    required String title,
    required TaskHubPriorityAnimationSnapshot snapshot,
    required bool reducedMotion,
    Rect? sourceRect,
  }) {
    final generation = ++_actionGeneration;
    _activeOverlay = null;
    _activeInlineAnimation = null;
    _lastPlan = null;
    _lastAnimationSource = null;
    notifyListeners();
    return TaskHubPriorityAnimationCapture(
      generation: generation,
      source: source,
      sourceTodoId: sourceTodoId,
      title: title,
      previous: snapshot,
      reducedMotion: reducedMotion,
      sourceRect: sourceRect,
    );
  }

  void completeAction(
    TaskHubPriorityAnimationCapture capture, {
    required String animatedTodoId,
    required TaskHubPriorityAnimationSnapshot next,
    Rect? targetRect,
  }) {
    if (capture.generation != _actionGeneration) {
      return;
    }
    _lastPlan = buildTaskHubPriorityAnimationPlan(
      previous: capture.previous,
      next: next,
      actedTodoId: animatedTodoId,
      reducedMotion: capture.reducedMotion,
    );
    final overlayDuration =
        capture.source == TaskHubPriorityAnimationSource.aiReconciliation
            ? const Duration(milliseconds: 220)
            : const Duration(milliseconds: 320);
    final inlineDuration =
        capture.source == TaskHubPriorityAnimationSource.aiReconciliation
            ? const Duration(milliseconds: 160)
            : const Duration(milliseconds: 240);
    if ((_lastPlan?.kind == TaskHubPriorityAnimationKind.crossSectionMove ||
            _lastPlan?.kind == TaskHubPriorityAnimationKind.visibleInsertion ||
            _lastPlan?.kind == TaskHubPriorityAnimationKind.visibleRemoval) &&
        capture.sourceRect != null &&
        targetRect != null) {
      _activeOverlay = TaskHubPriorityOverlayState(
        todoId: animatedTodoId,
        title: capture.title,
        token: ++_animationToken,
        beginRect: capture.sourceRect!,
        endRect: targetRect,
        duration: overlayDuration,
      );
      _activeInlineAnimation = null;
    } else if (_lastPlan?.kind ==
            TaskHubPriorityAnimationKind.sameSectionReorder &&
        capture.sourceRect != null &&
        targetRect != null) {
      final delta = capture.sourceRect!.topLeft - targetRect.topLeft;
      _activeOverlay = null;
      _activeInlineAnimation = TaskHubPriorityInlineAnimationState(
        todoId: animatedTodoId,
        beginOffset: delta,
        token: ++_animationToken,
        duration: inlineDuration,
      );
    } else if (capture.source ==
            TaskHubPriorityAnimationSource.localConfirmation &&
        _activeInlineAnimation?.todoId == animatedTodoId) {
      _activeOverlay = null;
    } else {
      _activeOverlay = null;
      _activeInlineAnimation = null;
    }
    _lastAnimationSource =
        _lastPlan?.kind == TaskHubPriorityAnimationKind.none &&
                !(capture.source ==
                        TaskHubPriorityAnimationSource.localConfirmation &&
                    _activeInlineAnimation?.todoId == animatedTodoId)
            ? null
            : capture.source;
    notifyListeners();
  }

  void clearOverlay(String todoId, int token) {
    final active = _activeOverlay;
    if (active == null || active.todoId != todoId || active.token != token) {
      return;
    }
    _activeOverlay = null;
    notifyListeners();
  }

  void clearInlineAnimation(String todoId, int token) {
    final active = _activeInlineAnimation;
    if (active == null || active.todoId != todoId || active.token != token) {
      return;
    }
    _activeInlineAnimation = null;
    notifyListeners();
  }

  void reset() {
    final hadState = _activeOverlay != null ||
        _activeInlineAnimation != null ||
        _lastPlan != null ||
        _lastAnimationSource != null;
    _activeOverlay = null;
    _activeInlineAnimation = null;
    _lastPlan = null;
    _lastAnimationSource = null;
    _actionGeneration += 1;
    if (hadState) {
      notifyListeners();
    }
  }
}
