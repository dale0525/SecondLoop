part of 'todo_agenda_page.dart';

extension _TodoAgendaPageStateActions on _TodoAgendaPageState {
  void _refresh() {
    unawaited(_loadTodos());
  }

  Widget _wrapPushedPageWithScopes(BuildContext context, Widget child) {
    Widget wrapped = child;

    final syncEngine = SyncEngineScope.maybeOf(context);
    if (syncEngine != null) {
      wrapped = SyncEngineScope(engine: syncEngine, child: wrapped);
    }

    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    if (cloudAuthScope != null) {
      wrapped = CloudAuthScope(
        controller: cloudAuthScope.controller,
        gatewayConfig: cloudAuthScope.gatewayConfig,
        child: wrapped,
      );
    }

    final subscriptionController = SubscriptionScope.maybeOf(context);
    if (subscriptionController != null) {
      wrapped = SubscriptionScope(
        controller: subscriptionController,
        child: wrapped,
      );
    }

    final sessionScope = SessionScope.maybeOf(context);
    if (sessionScope != null) {
      wrapped = SessionScope(
        sessionKey: sessionScope.sessionKey,
        lock: sessionScope.lock,
        child: wrapped,
      );
    }

    final backend = AppBackendScope.maybeOf(context);
    if (backend != null) {
      wrapped = AppBackendScope(backend: backend, child: wrapped);
    }

    return wrapped;
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  Future<void> _setStatus(Todo todo, String newStatus) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    var scope = TodoRecurrenceEditScope.thisOnly;
    if (newStatus != 'done') {
      final ruleJson = _recurrenceRuleByTodoId[todo.id];
      if (ruleJson != null && ruleJson.trim().isNotEmpty) {
        if (!mounted) return;
        final selectedScope = await showTodoRecurrenceEditScopeDialog(context);
        if (selectedScope == null || !mounted) return;
        scope = selectedScope;
      }
    }

    try {
      await backend.updateTodoStatusWithScope(
        sessionKey,
        todoId: todo.id,
        newStatus: newStatus,
        scope: scope,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refresh();
  }

  Future<void> _deleteTodo(Todo todo) async {
    final t = context.t;
    final confirmed = await showSlDeleteConfirmDialog(
      context,
      title: t.actions.todoDelete.dialog.title,
      message: t.actions.todoDelete.dialog.message,
      confirmLabel: t.actions.todoDelete.dialog.confirm,
      confirmButtonKey: ValueKey('todo_agenda_delete_confirm_${todo.id}'),
    );
    if (!mounted) return;
    if (!confirmed) return;

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.deleteTodo(sessionKey, todoId: todo.id);
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _editDue(Todo todo) async {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return;

    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final nowLocal = DateTime.now();
    final picked = await showSlDateTimePickerDialog(
      context,
      initialLocal: dueAtLocal,
      firstDate: DateTime(nowLocal.year - 1),
      lastDate: DateTime(nowLocal.year + 3),
      title: context.t.actions.calendar.pickCustom,
      surfaceKey: ValueKey('todo_agenda_due_picker_${todo.id}'),
    );
    if (picked == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    var scope = TodoRecurrenceEditScope.thisOnly;
    final ruleJson = _recurrenceRuleByTodoId[todo.id];
    if (ruleJson != null && ruleJson.trim().isNotEmpty) {
      if (!mounted) return;
      final selectedScope = await showTodoRecurrenceEditScopeDialog(context);
      if (selectedScope == null || !mounted) return;
      scope = selectedScope;
    }

    try {
      await backend.updateTodoDueWithScope(
        sessionKey,
        todoId: todo.id,
        dueAtMs: picked.toUtc().millisecondsSinceEpoch,
        scope: scope,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refresh();
  }

  String? _formatDue(BuildContext context, Todo todo) {
    final dueAtMs = todo.dueAtMs;
    if (dueAtMs == null) return null;
    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(dueAtLocal);
    final time =
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dueAtLocal));
    return '$date $time';
  }

  String _recurrenceFrequencyLabel(
    BuildContext context,
    TodoRecurrenceFrequency frequency,
  ) =>
      switch (frequency) {
        TodoRecurrenceFrequency.daily =>
          context.t.actions.todoRecurrenceRule.daily,
        TodoRecurrenceFrequency.weekly =>
          context.t.actions.todoRecurrenceRule.weekly,
        TodoRecurrenceFrequency.monthly =>
          context.t.actions.todoRecurrenceRule.monthly,
        TodoRecurrenceFrequency.yearly =>
          context.t.actions.todoRecurrenceRule.yearly,
      };

  String _formatRecurrenceRule(
    BuildContext context,
    TodoRecurrenceRule rule,
  ) {
    final frequencyLabel = _recurrenceFrequencyLabel(context, rule.frequency);
    if (rule.interval <= 1) {
      return frequencyLabel;
    }
    return '$frequencyLabel x${rule.interval}';
  }

  Future<void> _editRecurrenceRule(Todo todo) async {
    final existingRuleJson = _recurrenceRuleByTodoId[todo.id];
    final existingRule = TodoRecurrenceRule.tryParseJson(existingRuleJson);
    if (existingRule == null) return;

    final nextRule = await showTodoRecurrenceRuleDialog(
      context,
      initialRule: existingRule,
    );
    if (nextRule == null || !mounted) return;

    final scope = await showTodoRecurrenceEditScopeDialog(context);
    if (scope == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      await backend.updateTodoRecurrenceRuleWithScope(
        sessionKey,
        todoId: todo.id,
        ruleJson: nextRule.toJsonString(),
        scope: scope,
      );
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
