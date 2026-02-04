import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../actions/review/review_backoff.dart';
import '../actions/settings/actions_settings_store.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../actions/todo/todo_detail_page.dart';

class SemanticParseJobStatusRow extends StatefulWidget {
  const SemanticParseJobStatusRow({
    required this.message,
    required this.job,
    super.key,
  });

  final Message message;
  final SemanticParseJob job;

  @override
  State<SemanticParseJobStatusRow> createState() =>
      _SemanticParseJobStatusRowState();
}

class _SemanticParseJobStatusRowState extends State<SemanticParseJobStatusRow> {
  static const _kSoftDelay = Duration(milliseconds: 700);
  static const _kSlowThreshold = Duration(seconds: 3);
  static const _kAutoHideResultDelay = Duration(seconds: 10);

  Timer? _softTimer;
  Timer? _slowTimer;
  Timer? _autoHideTimer;
  bool _autoHidden = false;
  bool _didEnsureCreateTodoReviewQueue = false;

  @override
  void initState() {
    super.initState();
    _scheduleAutoHide();
    _scheduleTickers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeEnsureCreateTodoInReviewQueue();
  }

  @override
  void didUpdateWidget(covariant SemanticParseJobStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.status != widget.job.status ||
        oldWidget.job.createdAtMs != widget.job.createdAtMs ||
        oldWidget.job.updatedAtMs != widget.job.updatedAtMs ||
        oldWidget.job.undoneAtMs != widget.job.undoneAtMs ||
        oldWidget.job.appliedActionKind != widget.job.appliedActionKind) {
      if (mounted) _autoHidden = false;
      _maybeEnsureCreateTodoInReviewQueue();
      _scheduleAutoHide();
      _scheduleTickers();
    }
  }

  @override
  void dispose() {
    _softTimer?.cancel();
    _slowTimer?.cancel();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;

    final job = widget.job;
    final status = job.status;
    final undoneAtMs = job.undoneAtMs?.toInt();

    if (undoneAtMs == null && status != 'succeeded') return;
    if (status == 'succeeded' &&
        (job.appliedActionKind == null || job.appliedActionKind == 'none')) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final referenceMs = undoneAtMs ?? job.updatedAtMs.toInt();
    final ageMs = nowMs - referenceMs;

    if (ageMs >= _kAutoHideResultDelay.inMilliseconds) {
      _autoHidden = true;
      return;
    }

    final remaining = _kAutoHideResultDelay -
        Duration(milliseconds: ageMs.clamp(0, 1 << 31).toInt());
    _autoHideTimer = Timer(remaining, () {
      if (!mounted) return;
      setState(() => _autoHidden = true);
    });
  }

  void _scheduleTickers() {
    _softTimer?.cancel();
    _slowTimer?.cancel();

    final status = widget.job.status;
    if (status != 'pending' && status != 'running') return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdAtMs = widget.job.createdAtMs.toInt();
    final ageMs = nowMs - createdAtMs;

    final softDelayMs = _kSoftDelay.inMilliseconds - ageMs;
    if (softDelayMs > 0) {
      _softTimer = Timer(Duration(milliseconds: softDelayMs), () {
        if (!mounted) return;
        setState(() {});
      });
    }

    final slowDelayMs = _kSlowThreshold.inMilliseconds - ageMs;
    if (slowDelayMs > 0) {
      _slowTimer = Timer(Duration(milliseconds: slowDelayMs), () {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  void _maybeEnsureCreateTodoInReviewQueue() {
    if (_didEnsureCreateTodoReviewQueue) return;

    final job = widget.job;
    if (job.status != 'succeeded') return;
    if (job.undoneAtMs != null) return;
    if (job.appliedActionKind != 'create') return;
    final todoId = job.appliedTodoId?.trim();
    if (todoId == null || todoId.isEmpty) return;

    _didEnsureCreateTodoReviewQueue = true;
    unawaited(_ensureCreateTodoInReviewQueue(todoId));
  }

  Future<void> _ensureCreateTodoInReviewQueue(String todoId) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    Todo? todo;
    try {
      final todos = await backend.listTodos(sessionKey);
      for (final t in todos) {
        if (t.id == todoId) {
          todo = t;
          break;
        }
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (todo == null) return;

    if (todo.dueAtMs != null) return;
    if (todo.status == 'done' || todo.status == 'dismissed') return;
    if (todo.reviewStage != null && todo.nextReviewAtMs != null) return;

    final settings = await ActionsSettingsStore.load();
    if (!mounted) return;
    final nextLocal =
        ReviewBackoff.initialNextReviewAt(DateTime.now(), settings);
    try {
      await backend.upsertTodo(
        sessionKey,
        id: todo.id,
        title: todo.title,
        dueAtMs: null,
        status: todo.status,
        sourceEntryId: todo.sourceEntryId,
        reviewStage: 0,
        nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
        lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      syncEngine?.notifyLocalMutation();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _cancelJob() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    try {
      await backend.markSemanticParseJobCanceled(
        sessionKey,
        messageId: widget.message.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      syncEngine?.notifyExternalChange();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _retryJob() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    try {
      await backend.markSemanticParseJobRetry(
        sessionKey,
        messageId: widget.message.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      syncEngine?.notifyExternalChange();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _undoAction() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    final todoId = widget.job.appliedTodoId?.trim();
    if (todoId == null || todoId.isEmpty) return;

    try {
      switch (widget.job.appliedActionKind) {
        case 'create':
          await backend.deleteTodo(sessionKey, todoId: todoId);
          break;
        case 'followup':
          final prev = widget.job.appliedPrevTodoStatus?.trim();
          if (prev == null || prev.isEmpty) return;
          await backend.setTodoStatus(
            sessionKey,
            todoId: todoId,
            newStatus: prev,
          );
          break;
      }

      await backend.markSemanticParseJobUndone(
        sessionKey,
        messageId: widget.message.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      syncEngine?.notifyLocalMutation();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _openTodo() async {
    final todoId = widget.job.appliedTodoId?.trim();
    if (todoId == null || todoId.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    Todo? todo;
    try {
      final todos = await backend.listTodos(sessionKey);
      for (final t in todos) {
        if (t.id == todoId) {
          todo = t;
          break;
        }
      }
    } catch (_) {
      todo = null;
    }

    if (!mounted) return;
    if (todo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TodoDetailPage(initialTodo: todo!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_autoHidden) {
      return const SizedBox.shrink();
    }

    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;

    final status = widget.job.status;
    final createdAtMs = widget.job.createdAtMs.toInt();
    final ageMs = DateTime.now().millisecondsSinceEpoch - createdAtMs;

    final isPending = status == 'pending' || status == 'running';
    final shouldShowPending = ageMs >= _kSoftDelay.inMilliseconds;
    final isSlow = ageMs >= _kSlowThreshold.inMilliseconds;

    if (isPending && !shouldShowPending) {
      return const SizedBox.shrink();
    }

    if (status == 'succeeded' &&
        (widget.job.appliedActionKind == null ||
            widget.job.appliedActionKind == 'none')) {
      return const SizedBox.shrink();
    }

    final undone = widget.job.undoneAtMs != null;

    String label;
    late Widget leading;
    List<Widget> actions = const [];

    if (undone) {
      label = t.chat.semanticParseStatusUndone;
      leading = Icon(Icons.undo_rounded, size: 14, color: colorScheme.outline);
      actions = [
        TextButton(
          onPressed: _openTodo,
          child: Text(t.common.actions.open),
        ),
      ];
    } else {
      switch (status) {
        case 'pending':
        case 'running':
          label = isSlow
              ? t.chat.semanticParseStatusSlow
              : t.chat.semanticParseStatusRunning;
          leading = SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.outline,
            ),
          );
          actions = isSlow
              ? [
                  TextButton(
                    onPressed: _cancelJob,
                    child: Text(t.common.actions.cancel),
                  ),
                ]
              : const [];
          break;
        case 'failed':
          label = t.chat.semanticParseStatusFailed;
          leading = Icon(Icons.error_outline_rounded,
              size: 14, color: colorScheme.error);
          actions = [
            TextButton(
              onPressed: _retryJob,
              child: Text(t.common.actions.retry),
            ),
            TextButton(
              onPressed: _cancelJob,
              child: Text(t.common.actions.ignore),
            ),
          ];
          break;
        case 'canceled':
          label = t.chat.semanticParseStatusCanceled;
          leading =
              Icon(Icons.block_rounded, size: 14, color: colorScheme.outline);
          actions = [
            TextButton(
              onPressed: _retryJob,
              child: Text(t.common.actions.retry),
            ),
          ];
          break;
        case 'succeeded':
          final kind = widget.job.appliedActionKind;
          if (kind == 'create') {
            final title = widget.job.appliedTodoTitle?.trim().isNotEmpty == true
                ? widget.job.appliedTodoTitle!.trim()
                : widget.message.content.trim();
            label = t.chat.semanticParseStatusCreated(title: title);
          } else {
            final title = widget.job.appliedTodoTitle?.trim();
            label = title == null || title.isEmpty
                ? t.chat.semanticParseStatusUpdatedGeneric
                : t.chat.semanticParseStatusUpdated(title: title);
          }
          leading = Icon(Icons.auto_awesome_rounded,
              size: 14, color: colorScheme.outline);
          actions = [
            TextButton(
              onPressed: _undoAction,
              child: Text(t.common.actions.undo),
            ),
            TextButton(
              onPressed: _openTodo,
              child: Text(t.common.actions.open),
            ),
          ];
          break;
        default:
          return const SizedBox.shrink();
      }
    }

    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withOpacity(0.78),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 6),
            ...actions.map(
              (a) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: a,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
