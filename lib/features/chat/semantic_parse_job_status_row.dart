import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../actions/review/review_backoff.dart';
import '../actions/settings/actions_settings_store.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../actions/todo/todo_detail_page.dart';
import '../tags/tag_picker.dart';
import '../tags/tag_repository.dart';
import 'chat_route_scope_wrapper.dart';

class SemanticParseJobStatusRow extends StatefulWidget {
  const SemanticParseJobStatusRow({
    required this.message,
    required this.job,
    this.tagRepository = const TagRepository(),
    super.key,
  });

  final Message message;
  final SemanticParseJob job;
  final TagRepository tagRepository;

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
        oldWidget.job.appliedActionKind != widget.job.appliedActionKind ||
        oldWidget.job.tagSuggestionState != widget.job.tagSuggestionState ||
        oldWidget.job.suggestedTags != widget.job.suggestedTags ||
        oldWidget.job.appliedTagIds != widget.job.appliedTagIds) {
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

  String _tagSuggestionState(SemanticParseJob job) {
    final normalized = job.tagSuggestionState?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return 'none';
    switch (normalized) {
      case 'pending':
      case 'applied':
      case 'dismissed':
      case 'none':
        return normalized;
      default:
        return 'none';
    }
  }

  List<String> _suggestedTagsForDisplay(SemanticParseJob job) {
    final source = job.suggestedTags ?? const <String>[];
    if (source.isEmpty) return const <String>[];

    final out = <String>[];
    final seen = <String>{};
    for (final raw in source) {
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      out.add(normalized);
      if (out.length >= 3) break;
    }
    return out;
  }

  bool _isTagSuggestionPending(SemanticParseJob job) {
    if (job.status != 'succeeded') return false;
    if (job.appliedActionKind != null && job.appliedActionKind != 'none') {
      return false;
    }
    if (_tagSuggestionState(job) != 'pending') return false;
    return _suggestedTagsForDisplay(job).isNotEmpty;
  }

  bool _isTagSuggestionApplied(SemanticParseJob job) {
    if (job.status != 'succeeded') return false;
    if (job.appliedActionKind != null && job.appliedActionKind != 'none') {
      return false;
    }
    if (_tagSuggestionState(job) != 'applied') return false;
    return _suggestedTagsForDisplay(job).isNotEmpty;
  }

  String _formatSuggestedTags(List<String> tags) {
    if (tags.isEmpty) return '';
    return tags.join(' · ');
  }

  void _notifyJobStatusChanged({required bool didMutateTags}) {
    final syncEngine = SyncEngineScope.maybeOf(context);
    if (didMutateTags) {
      syncEngine?.notifyLocalMutation();
    } else {
      syncEngine?.notifyExternalChange();
    }
  }

  Future<void> _persistTagSuggestionState({
    required String state,
    List<String>? appliedTagIds,
  }) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final job = widget.job;
    final suggestedTags = _suggestedTagsForDisplay(job);

    await backend.markSemanticParseJobSucceeded(
      sessionKey,
      messageId: widget.message.id,
      appliedActionKind: (job.appliedActionKind ?? 'none').trim().isEmpty
          ? 'none'
          : job.appliedActionKind!.trim(),
      appliedTodoId: job.appliedTodoId,
      appliedTodoTitle: job.appliedTodoTitle,
      appliedPrevTodoStatus: job.appliedPrevTodoStatus,
      suggestedTags: suggestedTags.isEmpty ? null : suggestedTags,
      suggestedTagConfidence: job.suggestedTagConfidence,
      tagSuggestionState: state,
      appliedTagIds: appliedTagIds,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _dismissTagSuggestion() async {
    try {
      await _persistTagSuggestionState(state: 'dismissed');
      _notifyJobStatusChanged(didMutateTags: false);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _viewTagSuggestion() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    FocusManager.instance.primaryFocus?.unfocus();

    final changed = await showMessageTagPicker(
      context: context,
      sessionKey: sessionKey,
      messageId: widget.message.id,
      repository: widget.tagRepository,
    );
    if (!mounted || !changed) return;

    final suggested = _suggestedTagsForDisplay(widget.job);
    if (suggested.isEmpty) {
      _notifyJobStatusChanged(didMutateTags: true);
      return;
    }

    try {
      final currentTags = await widget.tagRepository
          .listMessageTags(sessionKey, widget.message.id);
      final normalizedCurrent = <String>{};
      for (final tag in currentTags) {
        final name = tag.name.trim().toLowerCase();
        if (name.isNotEmpty) normalizedCurrent.add(name);
        final systemKey = tag.systemKey?.trim().toLowerCase();
        if (systemKey != null && systemKey.isNotEmpty) {
          normalizedCurrent.add(systemKey);
        }
      }

      final allCovered = suggested.every(normalizedCurrent.contains);
      await _persistTagSuggestionState(
        state: allCovered ? 'applied' : 'pending',
        appliedTagIds: null,
      );
      _notifyJobStatusChanged(didMutateTags: true);
    } catch (_) {
      _notifyJobStatusChanged(didMutateTags: true);
    }
  }

  Future<void> _applyTagSuggestion() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final suggested = _suggestedTagsForDisplay(widget.job);
    if (suggested.isEmpty) return;

    try {
      final existing = await widget.tagRepository
          .listMessageTags(sessionKey, widget.message.id);
      final nextTagIds = existing.map((tag) => tag.id).toSet();
      final appliedTagIds = <String>[];

      for (final suggestedName in suggested) {
        final tag =
            await widget.tagRepository.upsertTag(sessionKey, suggestedName);
        if (nextTagIds.add(tag.id)) {
          appliedTagIds.add(tag.id);
        }
      }

      if (appliedTagIds.isNotEmpty) {
        final sortedTagIds = nextTagIds.toList(growable: false)..sort();
        await widget.tagRepository
            .setMessageTags(sessionKey, widget.message.id, sortedTagIds);
      }

      await _persistTagSuggestionState(
        state: 'applied',
        appliedTagIds: appliedTagIds.isEmpty ? null : appliedTagIds,
      );
      _notifyJobStatusChanged(didMutateTags: true);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _undoTagSuggestion() async {
    final sessionKey = SessionScope.of(context).sessionKey;
    final removable = widget.job.appliedTagIds ?? const <String>[];
    var didMutateTags = false;

    try {
      if (removable.isNotEmpty) {
        final current = await widget.tagRepository
            .listMessageTags(sessionKey, widget.message.id);
        final removableSet = removable.toSet();
        final nextIds = <String>[];
        for (final tag in current) {
          if (removableSet.contains(tag.id)) continue;
          nextIds.add(tag.id);
        }
        nextIds.sort();
        await widget.tagRepository
            .setMessageTags(sessionKey, widget.message.id, nextIds);
        didMutateTags = true;
      }

      final hasSuggested = _suggestedTagsForDisplay(widget.job).isNotEmpty;
      await _persistTagSuggestionState(
        state: hasSuggested ? 'pending' : 'none',
        appliedTagIds: null,
      );
      _notifyJobStatusChanged(didMutateTags: didMutateTags);
    } catch (_) {
      // ignore
    }
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;

    final job = widget.job;
    final status = job.status;
    final undoneAtMs = job.undoneAtMs?.toInt();

    if (undoneAtMs == null && status != 'succeeded' && status != 'canceled') {
      return;
    }
    if (status == 'succeeded' &&
        (job.appliedActionKind == null || job.appliedActionKind == 'none') &&
        !_isTagSuggestionApplied(job)) {
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
          final prevDueAtMs = widget.job.appliedPrevTodoDueAtMs?.toInt();
          final dueChanged = widget.job.appliedDueChanged;
          if ((prev == null || prev.isEmpty) && !dueChanged) return;

          final todos = await backend.listTodos(sessionKey);
          Todo? current;
          for (final todo in todos) {
            if (todo.id == todoId) {
              current = todo;
              break;
            }
          }
          if (current == null) return;

          await backend.upsertTodo(
            sessionKey,
            id: current.id,
            title: current.title,
            dueAtMs: dueChanged ? prevDueAtMs : current.dueAtMs?.toInt(),
            status: (prev != null && prev.isNotEmpty) ? prev : current.status,
            sourceEntryId: current.sourceEntryId,
            reviewStage: current.reviewStage?.toInt(),
            nextReviewAtMs: current.nextReviewAtMs?.toInt(),
            lastReviewAtMs: current.lastReviewAtMs?.toInt(),
            manualImportanceNudgeScore:
                current.manualImportanceNudgeScore?.toInt(),
            manualUrgencyNudgeScore: current.manualUrgencyNudgeScore?.toInt(),
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
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          TodoDetailPage(initialTodo: todo!),
        ),
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
    final isMobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final shouldShowPending = ageMs >= _kSoftDelay.inMilliseconds;
    final isSlow = ageMs >= _kSlowThreshold.inMilliseconds;

    if (isPending && !shouldShowPending) {
      return const SizedBox.shrink();
    }

    final isTagSuggestionPending = _isTagSuggestionPending(widget.job);
    final isTagSuggestionApplied = _isTagSuggestionApplied(widget.job);

    if (status == 'succeeded' &&
        (widget.job.appliedActionKind == null ||
            widget.job.appliedActionKind == 'none') &&
        !isTagSuggestionPending &&
        !isTagSuggestionApplied) {
      return const SizedBox.shrink();
    }

    final undone = widget.job.undoneAtMs != null;
    final showMobileStayOpenHint = !undone && isPending && isMobilePlatform;

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
          return const SizedBox.shrink();
        case 'succeeded':
          final kind = widget.job.appliedActionKind;
          if (kind == null || kind == 'none') {
            final suggested = _suggestedTagsForDisplay(widget.job);
            final suggestedLabel = _formatSuggestedTags(suggested);

            if (isTagSuggestionPending) {
              label =
                  t.chat.semanticParseStatusTagSuggested(tags: suggestedLabel);
              leading = Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: colorScheme.outline,
              );
              actions = [
                TextButton(
                  onPressed: _applyTagSuggestion,
                  child: Text(t.common.actions.apply),
                ),
                TextButton(
                  onPressed: _viewTagSuggestion,
                  child: Text(t.common.actions.view),
                ),
                TextButton(
                  onPressed: _dismissTagSuggestion,
                  child: Text(t.common.actions.ignore),
                ),
              ];
            } else if (isTagSuggestionApplied) {
              label =
                  t.chat.semanticParseStatusTagApplied(tags: suggestedLabel);
              leading = Icon(
                Icons.local_offer_outlined,
                size: 14,
                color: colorScheme.outline,
              );
              actions = [
                if ((widget.job.appliedTagIds?.isNotEmpty ?? false))
                  TextButton(
                    onPressed: _undoTagSuggestion,
                    child: Text(t.common.actions.undo),
                  ),
                TextButton(
                  onPressed: _viewTagSuggestion,
                  child: Text(t.common.actions.view),
                ),
              ];
            } else {
              return const SizedBox.shrink();
            }
            break;
          }

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showMobileStayOpenHint) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.chat.semanticParseMobileStayOpenHint,
                    style: textStyle?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.68),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
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
