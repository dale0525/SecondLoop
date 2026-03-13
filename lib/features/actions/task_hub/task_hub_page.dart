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
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import 'task_hub_focus_section.dart';
import 'task_hub_page_sections.dart';
import 'task_hub_quick_actions.dart';
import 'task_priority_ai.dart';
import 'task_priority_feedback_store.dart';
import 'task_priority_models.dart';
import 'task_priority_store.dart';
import '../todo/todo_detail_page.dart';

class TaskHubPage extends StatefulWidget {
  const TaskHubPage({super.key});

  @override
  State<TaskHubPage> createState() => _TaskHubPageState();
}

class _TaskHubPageState extends State<TaskHubPage> {
  static const _kDonePageSize = 20;

  TaskPriorityStore? _store;
  final TaskPriorityFeedbackStore _feedbackStore =
      const TaskPriorityFeedbackStore();
  TaskHubUndoTicket? _undoTicket;
  Timer? _quickActionSnackAutoDismissTimer;
  ScaffoldMessengerState? _quickActionSnackMessenger;
  Object? _quickActionSnackToken;
  var _doneVisibleCount = _kDonePageSize;

  @override
  void dispose() {
    if (_quickActionSnackToken != null) {
      _quickActionSnackMessenger?.hideCurrentSnackBar();
    }
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    _quickActionSnackMessenger = null;
    _quickActionSnackToken = null;
    _store?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store ??= TaskPriorityStore(
      backend: AppBackendScope.of(context),
      sessionKey: Uint8List.fromList(SessionScope.of(context).sessionKey),
      syncEngine: SyncEngineScope.maybeOf(context),
      resolveAiService: _resolveAiService,
      isAiEnhancementEnabled: TaskPriorityAiEnhancementPrefs.read,
      feedbackStore: _feedbackStore,
    );
    unawaited(_store!.refresh());
  }

  Future<TaskPriorityAiService?> _resolveAiService() async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
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
      return BackendTaskPriorityAiService(
        backend: backend,
        sessionKey: sessionKey,
        route: route,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        idToken: (idToken ?? '').trim(),
        modelName: gatewayConfig.modelName,
      );
    } catch (_) {
      return null;
    }
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

  Future<void> _openTodoDetail(TaskPriorityEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TodoDetailPage(initialTodo: entry.todo),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _applyQuickAction(
    TaskPriorityEntry entry,
    TaskHubQuickAction action,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: sessionKey,
    );
    final ticket = await controller.apply(entry.todo, action);
    if (ticket == null || !mounted) return;
    _undoTicket = ticket;
    syncEngine?.notifyLocalMutation();
    await _refresh();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    _quickActionSnackAutoDismissTimer?.cancel();
    _quickActionSnackAutoDismissTimer = null;
    final snackToken = Object();
    _quickActionSnackToken = snackToken;
    _quickActionSnackMessenger = messenger;
    final snackController = messenger?.showSnackBar(
      SnackBar(
        content: Text(
          context.t.actions.taskHub.snackActionApplied(
            action: _actionLabel(action),
            title: ticket.updatedTodo.title,
          ),
        ),
        action: SnackBarAction(
          label: context.t.common.actions.undo,
          onPressed: () async {
            if (_undoTicket != ticket) return;
            await controller.undo(ticket);
            syncEngine?.notifyLocalMutation();
            if (!mounted) return;
            await _refresh();
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

  Future<void> _recordFeedback(
    TaskPriorityEntry entry,
    TaskPriorityFeedbackKind feedback,
  ) async {
    await _feedbackStore.record(todoId: entry.todo.id, feedback: feedback);
    if (!mounted) return;
    await _refresh();
  }

  String _actionLabel(TaskHubQuickAction action) => switch (action) {
        TaskHubQuickAction.today => context.t.actions.taskHub.actions.today,
        TaskHubQuickAction.tonight => context.t.actions.taskHub.actions.tonight,
        TaskHubQuickAction.tomorrow =>
          context.t.actions.taskHub.actions.tomorrow,
        TaskHubQuickAction.pauseTomorrow =>
          context.t.actions.taskHub.actions.pauseTomorrow,
        TaskHubQuickAction.thisWeek =>
          context.t.actions.taskHub.actions.thisWeek,
        TaskHubQuickAction.later => context.t.actions.taskHub.actions.later,
        TaskHubQuickAction.start => context.t.actions.taskHub.actions.start,
        TaskHubQuickAction.moveToInbox =>
          context.t.actions.taskHub.actions.moveToInbox,
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
    return Scaffold(
      appBar: AppBar(title: Text(context.t.actions.taskHub.title)),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final snapshot = store.snapshot;
          final visibleDone = snapshot.done.take(_doneVisibleCount).toList();
          return RefreshIndicator(
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
                  if (snapshot.focus.isNotEmpty)
                    TaskHubFocusSection(
                      entries: snapshot.focus.take(3).toList(growable: false),
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
                              decide: snapshot.decide.length,
                              done: snapshot.done.length,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (store.isAiEnhancementEnabled &&
                      !store.isAiEnhancementAvailable) ...[
                    const SizedBox(height: 12),
                    SlSurface(
                      key: const ValueKey('task_hub_page_ai_upgrade_hint'),
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
                    sectionKey:
                        const ValueKey('task_hub_page_section_scheduled'),
                    entries: snapshot.scheduled,
                    sectionKind: TaskHubPageSectionKind.scheduled,
                    onOpenTodo: _openTodoDetail,
                    onQuickAction: _applyQuickAction,
                    onFeedback: _recordFeedback,
                  ),
                  TaskHubPageSection(
                    title: context.t.actions.taskHub.decideSection,
                    sectionKey: const ValueKey('task_hub_page_section_decide'),
                    entries: snapshot.decide,
                    sectionKind: TaskHubPageSectionKind.decide,
                    onOpenTodo: _openTodoDetail,
                    onQuickAction: _applyQuickAction,
                    onFeedback: _recordFeedback,
                  ),
                  TaskHubPageSection(
                    title: context.t.actions.taskHub.doneSection,
                    sectionKey: const ValueKey('task_hub_page_section_done'),
                    entries: visibleDone,
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
                              child: Text(context.t.common.actions.showMore),
                            ),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
