part of 'chat_page.dart';

extension _ChatPageStateMethodsBTaskHubQuickActions on _ChatPageState {
  String _taskHubActionLabel(TaskHubQuickAction action) => switch (action) {
        TaskHubQuickAction.today => context.t.actions.taskHub.actions.today,
        TaskHubQuickAction.tomorrow =>
          context.t.actions.taskHub.actions.tomorrow,
        TaskHubQuickAction.thisWeek =>
          context.t.actions.taskHub.actions.thisWeek,
        TaskHubQuickAction.later => context.t.actions.taskHub.actions.later,
        TaskHubQuickAction.done => context.t.actions.taskHub.actions.done,
      };

  Future<void> _applyTaskHubQuickAction(
    Todo todo,
    TaskHubQuickAction action,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final controller = TaskHubQuickActionsController(
      backend: backend,
      sessionKey: sessionKey,
    );

    late final TaskHubUndoTicket ticket;
    try {
      final maybeTicket = await controller.apply(todo, action);
      if (maybeTicket == null) return;
      ticket = maybeTicket;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.t.errors.saveFailed(error: '$e')),
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }

    if (!mounted) return;

    _taskHubUndoTicket = ticket;
    syncEngine?.notifyLocalMutation();
    _refresh();

    final actionLabel = _taskHubActionLabel(action);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    _taskHubQuickActionSnackAutoDismissTimer?.cancel();
    _taskHubQuickActionSnackAutoDismissTimer = null;
    final snackToken = Object();
    _taskHubQuickActionSnackToken = snackToken;
    _taskHubQuickActionSnackMessenger = messenger;
    final snackController = messenger?.showSnackBar(
      SnackBar(
        content: Text(
          context.t.actions.taskHub.snackActionApplied(
            action: actionLabel,
            title: ticket.updatedTodo.title,
          ),
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: context.t.common.actions.undo,
          onPressed: () async {
            if (_taskHubUndoTicket != ticket) return;
            try {
              await controller.undo(ticket);
              if (!mounted) return;
              if (_taskHubUndoTicket == ticket) {
                _taskHubUndoTicket = null;
              }
              syncEngine?.notifyLocalMutation();
              _refresh();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(context.t.errors.saveFailed(error: '$e')),
                    duration: const Duration(seconds: 3),
                  ),
                );
            }
          },
        ),
      ),
    );
    if (snackController == null) {
      if (identical(_taskHubQuickActionSnackToken, snackToken)) {
        _taskHubQuickActionSnackToken = null;
        _taskHubQuickActionSnackMessenger = null;
      }
      return;
    }
    final shouldForceAutoDismiss =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    Timer? autoDismissTimer;
    if (shouldForceAutoDismiss) {
      autoDismissTimer = Timer(
        const Duration(seconds: 3),
        snackController.close,
      );
      _taskHubQuickActionSnackAutoDismissTimer = autoDismissTimer;
      _taskHubQuickActionSnackMessenger = messenger;
    }

    unawaited(
      snackController.closed.then((_) {
        autoDismissTimer?.cancel();
        if (autoDismissTimer != null &&
            identical(
                _taskHubQuickActionSnackAutoDismissTimer, autoDismissTimer)) {
          _taskHubQuickActionSnackAutoDismissTimer = null;
        }
        if (identical(_taskHubQuickActionSnackToken, snackToken)) {
          _taskHubQuickActionSnackToken = null;
          _taskHubQuickActionSnackMessenger = null;
        }
        if (!mounted) return;
        if (_taskHubUndoTicket == ticket) {
          _taskHubUndoTicket = null;
        }
      }),
    );
  }
}
