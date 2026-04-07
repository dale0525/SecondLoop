import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/ai/ai_routing.dart';
import '../../../core/ai/task_priority_ai_enhancement_prefs.dart';
import '../../../core/backend/app_backend.dart';
import '../../../core/cloud/cloud_auth_scope.dart';
import '../../../core/cloud/cloud_capability_auth.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/subscription/subscription_scope.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import 'task_hub_card_anchor.dart';
import 'task_hub_focus_section.dart';
import 'task_hub_page_sections.dart';
import 'task_hub_priority_animation_controller.dart';
import 'task_hub_priority_animation_overlay.dart';
import 'task_hub_priority_animation_plan.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_ai.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';
import 'task_priority_store.dart';
import '../todo/todo_detail_page.dart';

part 'task_hub_page_navigation.dart';

class TaskHubPage extends StatefulWidget {
  const TaskHubPage({super.key});

  @override
  State<TaskHubPage> createState() => _TaskHubPageState();
}

class _TaskHubPageState extends State<TaskHubPage> {
  static const _kDonePageSize = 20;
  static const _kSyncRefreshDebounce = Duration(milliseconds: 250);

  TaskPriorityStore? _store;
  final TaskPriorityFeedbackStore _feedbackStore =
      const TaskPriorityFeedbackStore();
  TaskHubUndoTicket? _undoTicket;
  Timer? _quickActionSnackAutoDismissTimer;
  Timer? _restoreHighlightTimer;
  Timer? _syncRefreshDebounceTimer;
  String? _restoredTodoId;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey _animationLayerKey = GlobalKey();
  ScaffoldMessengerState? _quickActionSnackMessenger;
  Object? _quickActionSnackToken;
  var _doneVisibleCount = _kDonePageSize;
  final TaskHubCardAnchorRegistry _cardAnchorRegistry =
      TaskHubCardAnchorRegistry();
  final TaskHubPriorityAnimationController _priorityAnimationController =
      TaskHubPriorityAnimationController();

  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _syncEngine = null;
    _syncListener = null;
    if (_quickActionSnackToken != null &&
        (_quickActionSnackMessenger?.mounted ?? false)) {
      _quickActionSnackMessenger?.removeCurrentSnackBar();
    }
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    _restoreHighlightTimer?.cancel();
    _restoreHighlightTimer = null;
    _syncRefreshDebounceTimer?.cancel();
    _syncRefreshDebounceTimer = null;
    _quickActionSnackMessenger = null;
    _quickActionSnackToken = null;
    _priorityAnimationController.dispose();
    _store?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachSyncEngine();
    _store ??= TaskPriorityStore(
      backend: AppBackendScope.of(context),
      sessionKey: Uint8List.fromList(SessionScope.of(context).sessionKey),
      syncEngine: SyncEngineScope.maybeOf(context),
      resolveAiService: _resolveAiService,
      resolveAiCacheScopeKey: _resolveAiCacheScopeKey,
      isAiEnhancementEnabled: TaskPriorityAiEnhancementPrefs.read,
      readSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required nowLocal,
      }) async =>
          aiService is BackendTaskPriorityAiService
              ? aiService.readSharedAssessments(nowLocal: nowLocal)
              : const <String, TaskPriorityAiCachedAssessment>{},
      writeSharedAiAssessments: ({
        required aiService,
        required cacheScopeKey,
        required entries,
        required activeTodoIds,
        required nowLocal,
      }) async {
        if (aiService is BackendTaskPriorityAiService) {
          await aiService.writeSharedAssessments(
            entries: entries,
            activeTodoIds: activeTodoIds,
          );
        }
      },
      feedbackStore: _feedbackStore,
    );

    unawaited(_store?.refresh() ?? Future<void>.value());
  }

  void _attachSyncEngine() {
    final engine = SyncEngineScope.maybeOf(context);
    if (identical(engine, _syncEngine)) return;

    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }

    _syncEngine = engine;
    if (engine == null) {
      _syncListener = null;
      return;
    }

    void onSyncChange() {
      final store = _store;
      if (!mounted || store == null) return;
      store.markDirty();
      _syncRefreshDebounceTimer?.cancel();
      _syncRefreshDebounceTimer = Timer(_kSyncRefreshDebounce, () {
        if (!mounted || !identical(store, _store)) return;
        unawaited(store.refresh(force: true));
      });
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<TaskPriorityAiService?> _resolveAiService() async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      final cloudUid = cloudAuthScope?.controller.uid;
      final idToken = await readCloudCapabilityIdToken(
        cloudAuthScope?.controller,
        mode: CloudCapabilityAuthMode.background,
      );
      final route = await resolveTaskPriorityAiRoute(
        backend,
        Uint8List.fromList(sessionKey),
        cloudIdToken: idToken,
        cloudGatewayBaseUrl: gatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );
      if (route == AskAiRouteKind.needsSetup) return null;
      final cacheScopeKey = await resolveTaskPriorityAiCacheScopeKey(
        backend,
        Uint8List.fromList(sessionKey),
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cloudUid: cloudUid,
      );
      return BackendTaskPriorityAiService(
        backend: backend,
        sessionKey: sessionKey,
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        idToken: (idToken ?? '').trim(),
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cacheScopeKeyOverride: cacheScopeKey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveAiCacheScopeKey() async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey =
          Uint8List.fromList(SessionScope.of(context).sessionKey);
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      final cloudUid = cloudAuthScope?.controller.uid;
      if (subscriptionStatus == SubscriptionStatus.entitled &&
          gatewayConfig.baseUrl.trim().isNotEmpty &&
          (cloudUid?.trim().isNotEmpty ?? false)) {
        final cloudScope = await resolveTaskPriorityAiCacheScopeKey(
          backend,
          sessionKey,
          route: AskAiRouteKind.cloudGateway,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          modelName: gatewayConfig.modelName,
          localeTag: localeTag,
          cloudUid: cloudUid,
        );
        if (cloudScope != null) return cloudScope;
      }
      return resolveTaskPriorityAiCacheScopeKey(
        backend,
        sessionKey,
        route: AskAiRouteKind.byok,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        modelName: gatewayConfig.modelName,
        localeTag: localeTag,
        cloudUid: cloudUid,
      );
    } catch (_) {
      return null;
    }
  }

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

  Future<void> _refresh() async {
    final store = _store;
    if (store == null) return;
    store.markDirty();
    setState(() {
      _doneVisibleCount = _kDonePageSize;
    });
    await store.refresh(force: true);
  }

  TaskHubPriorityAnimationSnapshot _visibleAnimationSnapshot(
    TaskPrioritySnapshot snapshot,
  ) {
    return TaskHubPriorityAnimationSnapshot.fromTaskPrioritySnapshot(
      snapshot,
      doneVisibleCount: _doneVisibleCount,
    );
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

  int _sectionOrder(TaskHubPriorityAnimationSection section) {
    return switch (section) {
      TaskHubPriorityAnimationSection.focus => 0,
      TaskHubPriorityAnimationSection.nextUp => 1,
      TaskHubPriorityAnimationSection.backlog => 2,
      TaskHubPriorityAnimationSection.done => 3,
    };
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
    if (sourceRect == null) {
      return null;
    }
    switch (plan.kind) {
      case TaskHubPriorityAnimationKind.sameSectionReorder:
        final fromIndex = plan.fromIndex ?? 0;
        final toIndex = plan.toIndex ?? fromIndex;
        final direction = toIndex >= fromIndex ? -1.0 : 1.0;
        return sourceRect.shift(Offset(0, 28 * direction));
      case TaskHubPriorityAnimationKind.crossSectionMove:
      case TaskHubPriorityAnimationKind.visibleInsertion:
      case TaskHubPriorityAnimationKind.visibleRemoval:
        final fromSection = plan.fromSection;
        final toSection = plan.toSection ?? fromSection;
        if (toSection == null) {
          return sourceRect.shift(const Offset(0, -28));
        }
        final fromOrder = fromSection == null
            ? _sectionOrder(toSection)
            : _sectionOrder(fromSection);
        final delta = _sectionOrder(toSection) - fromOrder;
        final direction = delta == 0 ? 1.0 : delta.sign.toDouble();
        return sourceRect.shift(Offset(0, 32 * direction));
      case TaskHubPriorityAnimationKind.none:
      case TaskHubPriorityAnimationKind.noEmphasis:
        return null;
    }
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

  Future<void> _openTodoDetail(TaskPriorityEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _wrapPushedPageWithScopes(
          context,
          TodoDetailPage(initialTodo: entry.todo),
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _applyQuickAction(
    TaskPriorityEntry entry,
    TaskHubQuickAction action,
  ) async {
    _refreshCardAnchors(todoIds: <String>[entry.todo.id]);
    final previousSnapshot = _store == null
        ? const TaskHubPriorityAnimationSnapshot()
        : _visibleAnimationSnapshot(_store!.snapshot);
    final animationCapture = _priorityAnimationController.beginAction(
      title: entry.todo.title,
      snapshot: previousSnapshot,
      reducedMotion: _shouldReduceTaskHubMotion(context),
      sourceRect:
          _rectInAnimationLayer(_cardAnchorRegistry.rectFor(entry.todo.id)),
    );
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: sessionKey,
      confirmDoneWithIncompleteChecklist: _confirmDoneWithIncompleteChecklist,
      checklistProgressByTodoId: _store?.checklistProgressByTodoId ??
          const <String, TodoChecklistProgress>{},
    );
    TaskHubUndoTicket? ticket;
    try {
      ticket = await controller.apply(entry.todo, action);
    } catch (error) {
      _showQuickActionError(error);
      return;
    }
    if (ticket == null || !mounted) return;
    final appliedTicket = ticket;
    _undoTicket = appliedTicket;
    if (appliedTicket.shouldNotifySync) {
      syncEngine?.notifyLocalMutation();
    }
    await _refresh();
    if (!mounted) return;
    unawaited(() async {
      await _waitForNextFrame();
      if (!mounted) return;
      final currentStore = _store;
      if (currentStore == null) return;
      final animatedTodoId =
          appliedTicket.createdTodoId ?? appliedTicket.updatedTodo.id;
      _refreshCardAnchors();
      final nextSnapshot = _visibleAnimationSnapshot(currentStore.snapshot);
      final plan = buildTaskHubPriorityAnimationPlan(
        previous: previousSnapshot,
        next: nextSnapshot,
        actedTodoId: animatedTodoId,
        reducedMotion: animationCapture.reducedMotion,
      );
      _priorityAnimationController.completeAction(
        animationCapture,
        animatedTodoId: animatedTodoId,
        next: nextSnapshot,
        targetRect: _resolveAnimationTargetRect(
          animatedTodoId: animatedTodoId,
          plan: plan,
          sourceRect: animationCapture.sourceRect,
        ),
      );
    }());
    final messenger = _scaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    _restoreHighlightTimer?.cancel();
    _restoreHighlightTimer = null;
    _syncRefreshDebounceTimer?.cancel();
    _syncRefreshDebounceTimer = null;
    final snackToken = Object();
    _quickActionSnackToken = snackToken;
    _quickActionSnackMessenger = messenger;
    final snackController = messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          context.t.actions.taskHub.snackActionApplied(
            action: _actionLabel(action),
            title: appliedTicket.updatedTodo.title,
          ),
        ),
        action: SnackBarAction(
          label: context.t.common.actions.undo,
          onPressed: () async {
            if (_undoTicket != appliedTicket) return;
            messenger.removeCurrentSnackBar();
            _quickActionSnackAutoDismissTimer?.cancel();
            _quickActionSnackAutoDismissTimer = null;
            try {
              await controller.undo(appliedTicket);
            } catch (error) {
              _showQuickActionError(error);
              return;
            }
            _undoTicket = null;
            if (appliedTicket.shouldNotifySync) {
              syncEngine?.notifyLocalMutation();
            }
            await _refresh();
            if (!mounted) return;
            _showRestoreHighlight(appliedTicket.todo.id);
          },
        ),
      ),
    );
    if (snackController == null) return;
    final shouldForceAutoDismiss =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    Timer? autoDismissTimer;
    if (shouldForceAutoDismiss) {
      autoDismissTimer =
          Timer(const Duration(seconds: 3), snackController.close);
      _quickActionSnackAutoDismissTimer = autoDismissTimer;
    }
    unawaited(
      snackController.closed.then((_) {
        autoDismissTimer?.cancel();
        if (autoDismissTimer != null &&
            identical(_quickActionSnackAutoDismissTimer, autoDismissTimer)) {
          _quickActionSnackAutoDismissTimer = null;
        }
        if (identical(_quickActionSnackToken, snackToken)) {
          _quickActionSnackToken = null;
          _quickActionSnackMessenger = null;
        }
      }),
    );
  }

  void _showRestoreHighlight(String todoId) {
    _restoreHighlightTimer?.cancel();
    setState(() {
      _restoredTodoId = todoId;
    });
    _restoreHighlightTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        if (_restoredTodoId == todoId) {
          _restoredTodoId = null;
        }
      });
    });
  }

  Future<bool> _confirmDoneWithIncompleteChecklist(Todo todo) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('task_hub_incomplete_checklist_dialog'),
        title: Text(context.t.actions.todoDetail.incompleteChecklistDoneTitle),
        content: Text(
          context.t.actions.todoDetail.incompleteChecklistDoneMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t.common.actions.cancel),
          ),
          FilledButton(
            key: const ValueKey('task_hub_incomplete_checklist_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t.common.actions.continueLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _recordFeedback(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  ) async {
    await _feedbackStore.record(todoId: entry.todo.id, feedback: feedback);
    if (!mounted) return;
    await _refresh();
  }

  void _showQuickActionError(Object error) {
    if (!mounted) return;
    final messenger = _scaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(context.t.errors.saveFailed(error: '$error')),
      ),
    );
  }

  String _actionLabel(TaskHubQuickAction action) => switch (action) {
        TaskHubQuickAction.today => context.t.actions.taskHub.actions.today,
        TaskHubQuickAction.tomorrow =>
          context.t.actions.taskHub.actions.tomorrow,
        TaskHubQuickAction.start => context.t.actions.taskHub.actions.start,
        TaskHubQuickAction.increaseUrgency =>
          context.t.actions.taskHub.nudges.urgencyRaised,
        TaskHubQuickAction.decreaseUrgency =>
          context.t.actions.taskHub.nudges.urgencyLowered,
        TaskHubQuickAction.increaseImportance =>
          context.t.actions.taskHub.nudges.importanceRaised,
        TaskHubQuickAction.decreaseImportance =>
          context.t.actions.taskHub.nudges.importanceLowered,
        TaskHubQuickAction.done => context.t.actions.taskHub.actions.done,
        TaskHubQuickAction.reopen => context.t.actions.taskHub.actions.reopen,
        TaskHubQuickAction.redo => context.t.actions.taskHub.actions.redo,
        TaskHubQuickAction.dismiss => context.t.common.actions.delete,
      };

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(title: Text(context.t.actions.taskHub.title)),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            store,
            _priorityAnimationController,
          ]),
          builder: (context, _) {
            final snapshot = store.snapshot;
            final visibleFocus = snapshot.primaryFocus == null
                ? const <TaskPriorityEntry>[]
                : <TaskPriorityEntry>[snapshot.primaryFocus!];
            final visibleNextUp = snapshot.nextUpEntries;
            final visibleBacklog = snapshot.backlogEntries;
            final visibleDone = snapshot.done.take(_doneVisibleCount).toList();
            final activeInlineAnimation =
                _priorityAnimationController.activeInlineAnimation;
            return Stack(
              key: _animationLayerKey,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth != 0) return false;
                    _refreshCardAnchors();
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      key: const ValueKey('task_hub_page'),
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (store.isRefreshing && snapshot.allEntries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          if (_aiSourceLabel(snapshot)
                              case final aiSourceLabel?) ...[
                            SlSurface(
                              key: const ValueKey('task_hub_page_ai_source'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                aiSourceLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (snapshot.primaryFocus != null)
                            TaskHubFocusSection(
                              entries: visibleFocus,
                              checklistProgressByTodoId:
                                  store.checklistProgressByTodoId,
                              anchorRegistry: _cardAnchorRegistry,
                              anchorId: _sectionAnchorId(
                                TaskHubPriorityAnimationSection.focus,
                              ),
                              inlineAnimation: activeInlineAnimation,
                              onInlineAnimationCompleted:
                                  activeInlineAnimation == null
                                      ? null
                                      : () => _priorityAnimationController
                                              .clearInlineAnimation(
                                            activeInlineAnimation.todoId,
                                            activeInlineAnimation.token,
                                          ),
                              restoredTodoId: _restoredTodoId,
                              onOpenTodo: _openTodoDetail,
                              onQuickAction: _applyQuickAction,
                              onFeedback: _recordFeedback,
                            )
                          else
                            SlSurface(
                              key: const ValueKey('task_hub_page_wrap_up'),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.t.actions.taskHub.wrapUpTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    context.t.actions.taskHub.wrapUpSubtitle(
                                      upcoming: visibleNextUp.length,
                                      backlog: visibleBacklog.length,
                                      done: snapshot.done.length,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (store.shouldShowAiUpgradeHint) ...[
                            const SizedBox(height: 12),
                            SlSurface(
                              key: const ValueKey(
                                  'task_hub_page_ai_upgrade_hint'),
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                context.t.actions.taskHub.aiUpgradeHint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TaskHubPageSection(
                            title: context.t.actions.taskHub.scheduledSection,
                            sectionKey: const ValueKey(
                                'task_hub_page_section_upcoming'),
                            entries: visibleNextUp,
                            checklistProgressByTodoId:
                                store.checklistProgressByTodoId,
                            anchorRegistry: _cardAnchorRegistry,
                            anchorId: _sectionAnchorId(
                              TaskHubPriorityAnimationSection.nextUp,
                            ),
                            inlineAnimation: activeInlineAnimation,
                            onInlineAnimationCompleted:
                                activeInlineAnimation == null
                                    ? null
                                    : () => _priorityAnimationController
                                            .clearInlineAnimation(
                                          activeInlineAnimation.todoId,
                                          activeInlineAnimation.token,
                                        ),
                            restoredTodoId: _restoredTodoId,
                            sectionKind: TaskHubPageSectionKind.scheduled,
                            onOpenTodo: _openTodoDetail,
                            onQuickAction: _applyQuickAction,
                            onFeedback: _recordFeedback,
                          ),
                          TaskHubPageSection(
                            title: context.t.actions.taskHub.unscheduledSection,
                            sectionKey:
                                const ValueKey('task_hub_page_section_backlog'),
                            entries: visibleBacklog,
                            checklistProgressByTodoId:
                                store.checklistProgressByTodoId,
                            anchorRegistry: _cardAnchorRegistry,
                            anchorId: _sectionAnchorId(
                              TaskHubPriorityAnimationSection.backlog,
                            ),
                            inlineAnimation: activeInlineAnimation,
                            onInlineAnimationCompleted:
                                activeInlineAnimation == null
                                    ? null
                                    : () => _priorityAnimationController
                                            .clearInlineAnimation(
                                          activeInlineAnimation.todoId,
                                          activeInlineAnimation.token,
                                        ),
                            restoredTodoId: _restoredTodoId,
                            sectionKind: TaskHubPageSectionKind.decide,
                            onOpenTodo: _openTodoDetail,
                            onQuickAction: _applyQuickAction,
                            onFeedback: _recordFeedback,
                          ),
                          TaskHubPageSection(
                            title: context.t.actions.taskHub.doneSection,
                            sectionKey:
                                const ValueKey('task_hub_page_section_done'),
                            entries: visibleDone,
                            checklistProgressByTodoId:
                                store.checklistProgressByTodoId,
                            anchorRegistry: _cardAnchorRegistry,
                            anchorId: _sectionAnchorId(
                              TaskHubPriorityAnimationSection.done,
                            ),
                            inlineAnimation: activeInlineAnimation,
                            onInlineAnimationCompleted:
                                activeInlineAnimation == null
                                    ? null
                                    : () => _priorityAnimationController
                                            .clearInlineAnimation(
                                          activeInlineAnimation.todoId,
                                          activeInlineAnimation.token,
                                        ),
                            restoredTodoId: _restoredTodoId,
                            sectionKind: TaskHubPageSectionKind.done,
                            onOpenTodo: _openTodoDetail,
                            onQuickAction: _applyQuickAction,
                            footer: snapshot.done.length > _doneVisibleCount
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: SlButton(
                                      buttonKey: const ValueKey(
                                          'task_hub_page_done_load_more'),
                                      variant: SlButtonVariant.outline,
                                      onPressed: () {
                                        setState(() {
                                          _doneVisibleCount += _kDonePageSize;
                                        });
                                      },
                                      child: Text(
                                          context.t.common.actions.showMore),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_priorityAnimationController.activeOverlay
                    case final activeOverlay?)
                  Positioned.fill(
                    child: TaskHubPriorityAnimationOverlay(
                      animation: activeOverlay,
                      onCompleted: () =>
                          _priorityAnimationController.clearOverlay(
                        activeOverlay.todoId,
                        activeOverlay.token,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
