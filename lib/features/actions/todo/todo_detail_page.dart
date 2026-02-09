import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/backend/attachments_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_engine_gate.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_focus_ring.dart';
import '../../../ui/sl_icon_button.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import '../../attachments/attachment_card.dart';
import '../../attachments/attachment_viewer_page.dart';
import '../../chat/chat_markdown_sanitizer.dart';
import '../assistant_message_actions.dart';
import '../time/date_time_picker_dialog.dart';
import 'todo_linking.dart';
import 'todo_thread_match.dart';

class TodoDetailPage extends StatefulWidget {
  const TodoDetailPage({
    required this.initialTodo,
    super.key,
  });

  final Todo initialTodo;

  @override
  State<TodoDetailPage> createState() => _TodoDetailPageState();
}

class _TodoDetailPageState extends State<TodoDetailPage> {
  late Todo _todo = widget.initialTodo;
  Future<List<TodoActivity>>? _activitiesFuture;
  final _noteController = TextEditingController();
  final Map<String, Future<Message?>> _messageFuturesById =
      <String, Future<Message?>>{};
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByMessageId =
      <String, Future<List<Attachment>>>{};
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByActivityId =
      <String, Future<List<Attachment>>>{};
  final List<Attachment> _pendingAttachments = <Attachment>[];
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activitiesFuture ??= _loadActivities();
    _attachSyncEngine();
  }

  Future<List<TodoActivity>> _loadActivities() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return backend.listTodoActivities(sessionKey, _todo.id);
  }

  void _refreshActivities() {
    setState(() {
      _activitiesFuture = _loadActivities();
      _messageFuturesById.clear();
      _attachmentsFuturesByMessageId.clear();
      _attachmentsFuturesByActivityId.clear();
    });
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
      if (!mounted) return;
      _refreshActivities();
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  String _nextStatusForTap(String status) => switch (status) {
        'inbox' => 'in_progress',
        'open' => 'in_progress',
        'in_progress' => 'done',
        _ => 'open',
      };

  String? _formatDue(BuildContext context) {
    final dueAtMs = _todo.dueAtMs;
    if (dueAtMs == null) return null;
    final dueAtLocal =
        DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(dueAtLocal);
    final time =
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dueAtLocal));
    return '$date $time';
  }

  Future<void> _editDue() async {
    final dueAtMs = _todo.dueAtMs;
    final nowLocal = DateTime.now();
    final initialLocal = dueAtMs == null
        ? nowLocal
        : DateTime.fromMillisecondsSinceEpoch(dueAtMs, isUtc: true).toLocal();

    final picked = await showSlDateTimePickerDialog(
      context,
      initialLocal: initialLocal,
      firstDate: DateTime(nowLocal.year - 1),
      lastDate: DateTime(nowLocal.year + 3),
      title: context.t.actions.calendar.pickCustom,
      surfaceKey: const ValueKey('todo_detail_due_picker'),
    );
    if (picked == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final updated = await backend.upsertTodo(
      sessionKey,
      id: _todo.id,
      title: _todo.title,
      dueAtMs: picked.toUtc().millisecondsSinceEpoch,
      status: _todo.status,
      sourceEntryId: _todo.sourceEntryId,
      reviewStage: _todo.reviewStage,
      nextReviewAtMs: _todo.nextReviewAtMs,
      lastReviewAtMs: _todo.lastReviewAtMs,
    );
    if (!mounted) return;
    setState(() => _todo = updated);
  }

  Future<void> _setStatus(String newStatus) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final updated = await backend.setTodoStatus(
      sessionKey,
      todoId: _todo.id,
      newStatus: newStatus,
    );
    if (!mounted) return;
    setState(() => _todo = updated);
    _refreshActivities();
  }

  Future<void> _deleteTodo() async {
    final t = context.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.actions.todoDelete.dialog.title),
          content: Text(t.actions.todoDelete.dialog.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.actions.cancel),
            ),
            FilledButton(
              key: const ValueKey('todo_delete_confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(t.actions.todoDelete.dialog.confirm),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed != true) return;

    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.deleteTodo(sessionKey, todoId: _todo.id);
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      Navigator.of(context).pop(true);
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

  Future<void> _appendNote() async {
    final text = _noteController.text.trim();
    final pending = List<Attachment>.from(_pendingAttachments);
    if (text.isEmpty && pending.isEmpty) return;
    _noteController.clear();

    final backend = AppBackendScope.of(context);
    final syncEngine = SyncEngineScope.maybeOf(context);
    final attachmentsBackend =
        backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
    final sessionKey = SessionScope.of(context).sessionKey;
    final content = text.isNotEmpty
        ? text
        : context.t.actions.todoDetail.attachmentNoteDefault;
    late final TodoActivity activity;
    try {
      activity = await backend.appendTodoNote(
        sessionKey,
        todoId: _todo.id,
        content: content,
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

    syncEngine?.notifyLocalMutation();

    final activityMessageId = activity.sourceMessageId;
    for (final attachment in pending) {
      try {
        if (attachmentsBackend != null && activityMessageId != null) {
          await attachmentsBackend.linkAttachmentToMessage(
            sessionKey,
            activityMessageId,
            attachmentSha256: attachment.sha256,
          );
        } else {
          await backend.linkAttachmentToTodoActivity(
            sessionKey,
            activityId: activity.id,
            attachmentSha256: attachment.sha256,
          );
        }
      } catch (_) {
        // ignore
      }
    }
    if (!mounted) return;
    setState(_pendingAttachments.clear);
    _refreshActivities();
    syncEngine?.notifyLocalMutation();
  }

  Future<Message?> _loadMessage(String messageId) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await backend.getMessageById(sessionKey, messageId);
    } catch (_) {
      return null;
    }
  }

  String _displayTextForMessage(Message message) {
    final raw = message.content;
    final actions =
        message.role == 'assistant' ? parseAssistantMessageActions(raw) : null;
    final text = (actions?.displayText ?? raw).trim();
    if (text == 'Photo' || text == '照片') return '';
    return text;
  }

  Future<void> _copyMessageToClipboard(Message message) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: _displayTextForMessage(message)),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.actions.history.actions.copied),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _editMessage(Message message) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);

    var draft = message.content;
    try {
      final newContent = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(context.t.chat.editMessageTitle),
            content: TextFormField(
              key: const ValueKey('edit_message_content'),
              initialValue: draft,
              autofocus: true,
              maxLines: null,
              onChanged: (value) => draft = value,
            ),
            actions: [
              SlButton(
                variant: SlButtonVariant.outline,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t.common.actions.cancel),
              ),
              SlButton(
                buttonKey: const ValueKey('edit_message_save'),
                icon: const Icon(Icons.save_rounded, size: 18),
                variant: SlButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(draft),
                child: Text(context.t.common.actions.save),
              ),
            ],
          );
        },
      );

      final trimmed = newContent?.trim();
      if (trimmed == null) return;

      await backend.editMessage(sessionKey, message.id, trimmed);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refreshActivities();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.messageUpdated),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t.chat.editFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<({Todo todo, bool isSourceEntry})?> _resolveLinkedTodoInfo(
    Message message,
  ) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return null;
    }

    final todosById = <String, Todo>{};
    for (final todo in todos) {
      todosById[todo.id] = todo;
      if (todo.sourceEntryId == message.id) {
        return (todo: todo, isSourceEntry: true);
      }
    }

    try {
      final activities = await backend.listTodoActivitiesInRange(
        sessionKey,
        startAtMsInclusive: 0,
        endAtMsExclusive: DateTime.now().toUtc().millisecondsSinceEpoch + 1,
      );
      for (final activity in activities) {
        if (activity.sourceMessageId != message.id) continue;
        final todo = todosById[activity.todoId];
        if (todo != null) return (todo: todo, isSourceEntry: false);
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<void> _deleteMessage(Message message) async {
    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);

      final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
      if (!mounted) return;

      final targetTodo = linkedTodoInfo?.todo;
      final isSourceEntry = linkedTodoInfo?.isSourceEntry == true;
      if (targetTodo != null && isSourceEntry) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(t.actions.todoDelete.dialog.title),
              content: Text(t.actions.todoDelete.dialog.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  key: const ValueKey('chat_delete_todo_confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: Text(t.actions.todoDelete.dialog.confirm),
                ),
              ],
            );
          },
        );
        if (!mounted) return;
        if (confirmed != true) return;

        await backend.deleteTodo(sessionKey, todoId: targetTodo.id);
        if (!mounted) return;
        syncEngine?.notifyLocalMutation();
        if (targetTodo.id == _todo.id) {
          Navigator.of(context).pop(true);
        } else {
          _refreshActivities();
          messenger.showSnackBar(
            SnackBar(
              content: Text(t.chat.messageDeleted),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      await backend.purgeMessageAttachments(sessionKey, message.id);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refreshActivities();
      messenger.showSnackBar(
        SnackBar(
          content: Text(t.chat.messageDeleted),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.chat.deleteFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildLinkedMessageBody(
    BuildContext context,
    String content, {
    required bool isDesktopPlatform,
  }) {
    final normalized = sanitizeChatMarkdown(content);
    final markdown = MarkdownBody(
      data: normalized,
      selectable: false,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: Theme.of(context).textTheme.bodyLarge,
      ),
    );
    if (!isDesktopPlatform) return markdown;

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) =>
          const SizedBox.shrink(),
      child: markdown,
    );
  }

  Future<void> _showMessageActions(
    Message message, {
    String? sourceActivityId,
  }) async {
    if (message.id.startsWith('pending_')) return;
    final canEdit = message.role == 'user';
    final linkedTodo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) {
        final tokens = SlTokens.of(context);
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              key: const ValueKey('message_actions_sheet'),
              color: tokens.surface2,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    key: const ValueKey('message_action_copy'),
                    leading: const Icon(Icons.copy_all_rounded),
                    title: Text(context.t.common.actions.copy),
                    onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                  ),
                  if (linkedTodo == null)
                    ListTile(
                      key: const ValueKey('message_action_link_todo'),
                      leading: const Icon(Icons.link_rounded),
                      title: Text(context.t.actions.todoNoteLink.action),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.linkTodo),
                    )
                  else if (!linkedTodo.isSourceEntry)
                    ListTile(
                      key: const ValueKey('message_action_link_todo'),
                      leading: const Icon(Icons.link_rounded),
                      title: Text(context.t.chat.messageActions.linkOtherTodo),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.linkTodo),
                    ),
                  if (canEdit)
                    ListTile(
                      key: const ValueKey('message_action_edit'),
                      leading: const Icon(Icons.edit_rounded),
                      title: Text(context.t.common.actions.edit),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.edit),
                    ),
                  ListTile(
                    key: const ValueKey('message_action_delete'),
                    leading: const Icon(Icons.delete_outline_rounded),
                    iconColor: colorScheme.error,
                    textColor: colorScheme.error,
                    title: Text(context.t.common.actions.delete),
                    onTap: () =>
                        Navigator.of(context).pop(_MessageAction.delete),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message, sourceActivityId: sourceActivityId);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case null:
        break;
    }
  }

  static int _dueBoost(DateTime? dueLocal, DateTime nowLocal) {
    if (dueLocal == null) return 0;
    final diffMinutes = dueLocal.difference(nowLocal).inMinutes.abs();
    if (diffMinutes <= 120) return 1500;
    if (diffMinutes <= 360) return 800;
    if (diffMinutes <= 1440) return 200;
    return 0;
  }

  static int _semanticBoost(int rank, double distance) {
    if (!distance.isFinite) return 0;
    final base = distance <= 0.35
        ? 2200
        : distance <= 0.50
            ? 1400
            : distance <= 0.70
                ? 800
                : 0;
    if (base == 0) return 0;

    final factor = switch (rank) {
      0 => 1.0,
      1 => 0.7,
      2 => 0.5,
      3 => 0.4,
      _ => 0.3,
    };
    return (base * factor).round();
  }

  Future<List<TodoLinkCandidate>> _rankTodoCandidatesWithSemanticMatches(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required int limit,
  }) async {
    final ranked =
        rankTodoCandidates(query, targets, nowLocal: nowLocal, limit: limit);

    List<TodoThreadMatch> semantic = const <TodoThreadMatch>[];
    try {
      semantic = await backend.searchSimilarTodoThreads(
        sessionKey,
        query,
        topK: limit,
      );
    } catch (_) {
      semantic = const <TodoThreadMatch>[];
    }
    if (semantic.isEmpty) return ranked;

    final targetsById = <String, TodoLinkTarget>{};
    for (final t in targets) {
      targetsById[t.id] = t;
    }

    final scoreByTodoId = <String, int>{};
    for (final c in ranked) {
      scoreByTodoId[c.target.id] = c.score;
    }

    for (var i = 0; i < semantic.length && i < limit; i++) {
      final match = semantic[i];
      final target = targetsById[match.todoId];
      if (target == null) continue;

      final boost = _semanticBoost(i, match.distance);
      if (boost <= 0) continue;

      final existing = scoreByTodoId[target.id];
      final base = existing ?? _dueBoost(target.dueLocal, nowLocal);
      scoreByTodoId[target.id] = base + boost;
    }

    final merged = <TodoLinkCandidate>[];
    scoreByTodoId.forEach((id, score) {
      final target = targetsById[id];
      if (target == null) return;
      merged.add(TodoLinkCandidate(target: target, score: score));
    });
    merged.sort((a, b) => b.score.compareTo(a.score));
    if (merged.length <= limit) return merged;
    return merged.sublist(0, limit);
  }

  Future<void> _linkMessageToTodo(
    Message message, {
    String? sourceActivityId,
  }) async {
    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;
    final shouldMoveExisting = linkedTodoInfo != null &&
        !linkedTodoInfo.isSourceEntry &&
        sourceActivityId != null;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return;
    }

    final nowLocal = DateTime.now();
    final targets = <TodoLinkTarget>[];
    final todosById = <String, Todo>{};
    for (final todo in todos) {
      if (todo.status == 'dismissed') continue;
      todosById[todo.id] = todo;
      final dueMs = todo.dueAtMs;
      targets.add(
        TodoLinkTarget(
          id: todo.id,
          title: todo.title,
          status: todo.status,
          dueLocal: dueMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true)
                  .toLocal(),
        ),
      );
    }
    if (targets.isEmpty) return;

    final ranked = await _rankTodoCandidatesWithSemanticMatches(
      backend,
      sessionKey,
      query: message.content,
      targets: targets,
      nowLocal: nowLocal,
      limit: 10,
    );
    final selectedTodoId = await _showTodoNoteLinkSheet(
      allTargets: targets,
      ranked: ranked,
    );
    if (selectedTodoId == null || !mounted) return;

    final selected = todosById[selectedTodoId];
    if (selected == null) return;

    try {
      if (shouldMoveExisting) {
        await backend.moveTodoActivity(
          sessionKey,
          activityId: sourceActivityId,
          toTodoId: selected.id,
        );
      } else {
        final activity = await backend.appendTodoNote(
          sessionKey,
          todoId: selected.id,
          content: message.content.trim(),
          sourceMessageId: message.id,
        );

        final attachmentsBackend = backend is AttachmentsBackend
            ? backend as AttachmentsBackend
            : null;
        if (attachmentsBackend != null) {
          try {
            final attachments = await attachmentsBackend.listMessageAttachments(
                sessionKey, message.id);
            for (final attachment in attachments) {
              await backend.linkAttachmentToTodoActivity(
                sessionKey,
                activityId: activity.id,
                attachmentSha256: attachment.sha256,
              );
            }
          } catch (_) {
            // ignore
          }
        }
      }
    } catch (_) {
      return;
    }

    if (!mounted) return;
    SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
    _refreshActivities();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(context.t.actions.todoNoteLink.linked(title: selected.title)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String?> _showTodoNoteLinkSheet({
    required List<TodoLinkTarget> allTargets,
    required List<TodoLinkCandidate> ranked,
  }) async {
    final seen = <String>{};
    final candidates = <TodoLinkCandidate>[];
    for (final c in ranked) {
      candidates.add(c);
      seen.add(c.target.id);
    }
    for (final t in allTargets) {
      if (seen.contains(t.id)) continue;
      candidates.add(TodoLinkCandidate(target: t, score: 0));
    }

    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            List<TodoLinkCandidate> filtered = candidates;
            final trimmed = query.trim();
            if (trimmed.isNotEmpty) {
              final q = trimmed.toLowerCase();
              filtered = candidates
                  .where((c) => c.target.title.toLowerCase().contains(q))
                  .toList(growable: false);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SlSurface(
                  key: const ValueKey('todo_note_link_sheet'),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t.actions.todoNoteLink.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(context.t.actions.todoNoteLink.subtitle),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('todo_note_link_search'),
                        decoration: InputDecoration(
                          hintText: context.t.common.actions.search,
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  context.t.actions.todoNoteLink.noMatches,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final c = filtered[index];
                                  return ListTile(
                                    title: Text(c.target.title),
                                    subtitle: Text(
                                      _statusLabel(context, c.target.status),
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(c.target.id),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMessageContextMenu(
    Message message,
    Offset globalPosition, {
    String? sourceActivityId,
  }) async {
    if (message.id.startsWith('pending_')) return;
    final canEdit = message.role == 'user';
    final linkedTodo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_MessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_copy'),
          value: _MessageAction.copy,
          child: Text(context.t.common.actions.copy),
        ),
        if (linkedTodo == null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.actions.todoNoteLink.action),
          )
        else if (!linkedTodo.isSourceEntry)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_link_todo'),
            value: _MessageAction.linkTodo,
            child: Text(context.t.chat.messageActions.linkOtherTodo),
          ),
        if (canEdit)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_edit'),
            value: _MessageAction.edit,
            child: Text(context.t.common.actions.edit),
          ),
        PopupMenuItem<_MessageAction>(
          key: const ValueKey('message_context_delete'),
          value: _MessageAction.delete,
          child: Text(context.t.common.actions.delete),
        ),
      ],
    );
    if (!mounted) return;

    switch (action) {
      case _MessageAction.copy:
        await _copyMessageToClipboard(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message, sourceActivityId: sourceActivityId);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case null:
        break;
    }
  }

  Future<List<Attachment>> _loadMessageAttachments(String messageId) async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return const <Attachment>[];
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    return attachmentsBackend.listMessageAttachments(sessionKey, messageId);
  }

  Widget _buildActivityTile(BuildContext context, TodoActivity activity) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;
    final tsLocal =
        DateTime.fromMillisecondsSinceEpoch(activity.createdAtMs, isUtc: true)
            .toLocal();
    final timeText =
        '${tsLocal.year}-${tsLocal.month.toString().padLeft(2, '0')}-${tsLocal.day.toString().padLeft(2, '0')} '
        '${tsLocal.hour.toString().padLeft(2, '0')}:${tsLocal.minute.toString().padLeft(2, '0')}';

    final title = switch (activity.activityType) {
      'status_change' =>
        '${activity.fromStatus ?? ''} → ${activity.toStatus ?? ''}'.trim(),
      'note' => activity.content ?? '',
      'summary' => activity.content ?? '',
      _ => activity.content ?? activity.activityType,
    };

    final sourceMessageId = activity.sourceMessageId;
    final isDesktopPlatform = _isDesktopPlatform;

    final icon = switch (activity.activityType) {
      'note' => Icons.notes_rounded,
      'summary' => Icons.auto_awesome_rounded,
      'status_change' => Icons.sync_rounded,
      _ => Icons.bolt_rounded,
    };

    Widget contentForText(String text) {
      final isMarkdown = activity.activityType == 'note' ||
          activity.activityType == 'summary' ||
          (activity.activityType != 'status_change' && text.contains('\n'));
      if (isMarkdown) {
        return MarkdownBody(
          data: text,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyLarge,
          ),
        );
      }
      return Text(text, style: theme.textTheme.bodyLarge);
    }

    Widget buildTile({required Widget contentWidget, Message? message}) {
      final surface = SlSurface(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child:
                    Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  contentWidget,
                  const SizedBox(height: 6),
                  Text(
                    timeText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (sourceMessageId != null &&
                      activity.activityType != 'status_change') ...[
                    const SizedBox(height: 10),
                    FutureBuilder<List<Attachment>>(
                      future: _attachmentsFuturesByMessageId.putIfAbsent(
                        sourceMessageId,
                        () => _loadMessageAttachments(sourceMessageId),
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox.shrink();
                        }
                        final attachments =
                            snapshot.data ?? const <Attachment>[];
                        if (attachments.isEmpty) return const SizedBox.shrink();

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final attachment in attachments)
                              AttachmentCard(
                                attachment: attachment,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AttachmentViewerPage(
                                        attachment: attachment,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  FutureBuilder<List<Attachment>>(
                    future: _attachmentsFuturesByActivityId.putIfAbsent(
                      activity.id,
                      () async {
                        final backend = AppBackendScope.of(context);
                        final sessionKey = SessionScope.of(context).sessionKey;
                        return backend.listTodoActivityAttachments(
                            sessionKey, activity.id);
                      },
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox.shrink();
                      }
                      final attachments = snapshot.data ?? const <Attachment>[];
                      if (attachments.isEmpty) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final attachment in attachments)
                              AttachmentCard(
                                attachment: attachment,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AttachmentViewerPage(
                                        attachment: attachment,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (message == null) return surface;

      return Listener(
        onPointerDown: (event) {
          final kind = event.kind;
          final isPointerKind = kind == PointerDeviceKind.mouse ||
              kind == PointerDeviceKind.trackpad;
          if (!isPointerKind) return;
          if (event.buttons & kSecondaryMouseButton == 0) return;
          unawaited(
            _showMessageContextMenu(
              message,
              event.position,
              sourceActivityId: activity.id,
            ),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: isDesktopPlatform
              ? null
              : () => unawaited(
                    _showMessageActions(
                      message,
                      sourceActivityId: activity.id,
                    ),
                  ),
          child: surface,
        ),
      );
    }

    if (sourceMessageId != null && activity.activityType != 'status_change') {
      return FutureBuilder<Message?>(
        future: _messageFuturesById.putIfAbsent(
          sourceMessageId,
          () => _loadMessage(sourceMessageId),
        ),
        builder: (context, snapshot) {
          final message = snapshot.data;
          final messageText =
              message == null ? null : _displayTextForMessage(message);
          final effective =
              messageText == null || messageText.isEmpty ? title : messageText;
          final contentWidget = _buildLinkedMessageBody(
            context,
            effective,
            isDesktopPlatform: isDesktopPlatform,
          );
          return buildTile(contentWidget: contentWidget, message: message);
        },
      );
    }

    return buildTile(contentWidget: contentForText(title));
  }

  Future<void> _pickAttachment() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;

    final selected = await showModalBottomSheet<Attachment>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.actions.todoDetail.pickAttachment,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Attachment>>(
                  future: attachmentsBackend.listRecentAttachments(
                    sessionKey,
                    limit: 50,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.t.errors
                              .loadFailed(error: '${snapshot.error}'),
                        ),
                      );
                    }

                    final items = snapshot.data ?? const <Attachment>[];
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(context.t.actions.todoDetail.noAttachments),
                      );
                    }

                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final attachment in items)
                            AttachmentCard(
                              attachment: attachment,
                              onTap: () =>
                                  Navigator.of(context).pop(attachment),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      final alreadySelected =
          _pendingAttachments.any((a) => a.sha256 == selected.sha256);
      if (!alreadySelected) {
        _pendingAttachments.add(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final dueText = _formatDue(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.actions.todoDetail.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SlSurface(
                  key: const ValueKey('todo_detail_header'),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        _todo.title,
                        key: const ValueKey('todo_detail_title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _TodoStatusButton(
                            label: _statusLabel(context, _todo.status),
                            onPressed: () => unawaited(
                              _setStatus(_nextStatusForTap(_todo.status)),
                            ),
                          ),
                          const Spacer(),
                          SlIconButton(
                            key: const ValueKey('todo_detail_delete'),
                            tooltip: context.t.common.actions.delete,
                            icon: Icons.delete_outline_rounded,
                            size: 38,
                            iconSize: 18,
                            color: Theme.of(context).colorScheme.error,
                            overlayBaseColor:
                                Theme.of(context).colorScheme.error,
                            borderColor:
                                Theme.of(context).colorScheme.error.withOpacity(
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.32
                                          : 0.22,
                                    ),
                            onPressed: () => unawaited(_deleteTodo()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _TodoDueChip(
                          chipKey: const ValueKey('todo_detail_due'),
                          icon: Icons.event_rounded,
                          label:
                              dueText ?? context.t.actions.calendar.pickCustom,
                          onPressed: () => unawaited(_editDue()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<TodoActivity>>(
                  future: _activitiesFuture,
                  builder: (context, snapshot) {
                    final loading =
                        snapshot.connectionState != ConnectionState.done;
                    final activities = snapshot.data ?? const <TodoActivity>[];

                    if (snapshot.hasError && activities.isEmpty) {
                      return Center(
                        child: Text(
                          context.t.errors
                              .loadFailed(error: '${snapshot.error}'),
                        ),
                      );
                    }

                    if (loading && activities.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (activities.isEmpty) {
                      return Center(
                        child: Text(context.t.actions.todoDetail.emptyTimeline),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: activities.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildActivityTile(context, activities[index]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SlFocusRing(
                  key: const ValueKey('todo_detail_composer'),
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  child: SlSurface(
                    color: tokens.surface2,
                    borderColor: tokens.borderSubtle,
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_pendingAttachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final attachment in _pendingAttachments)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onLongPress: () {
                                          setState(
                                            () =>
                                                _pendingAttachments.removeWhere(
                                              (a) =>
                                                  a.sha256 == attachment.sha256,
                                            ),
                                          );
                                        },
                                        child: AttachmentCard(
                                          attachment: attachment,
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AttachmentViewerPage(
                                                  attachment: attachment,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _noteController,
                                decoration: InputDecoration(
                                  hintText:
                                      context.t.actions.todoDetail.noteHint,
                                  border: InputBorder.none,
                                  filled: false,
                                ),
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                minLines: 1,
                                maxLines: 6,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: context.t.actions.todoDetail.attach,
                              icon: const Icon(Icons.attach_file_rounded),
                              onPressed: () => unawaited(_pickAttachment()),
                            ),
                            const SizedBox(width: 6),
                            SlButton(
                              onPressed: () => unawaited(_appendNote()),
                              child: Text(context.t.actions.todoDetail.addNote),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MessageAction {
  copy,
  linkTodo,
  edit,
  delete,
}

final class _TodoStatusButton extends StatelessWidget {
  const _TodoStatusButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return colorScheme.primary.withOpacity(0.18);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return colorScheme.primary.withOpacity(0.12);
      }
      return null;
    });

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: tokens.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        side: BorderSide(color: tokens.borderSubtle),
      ).copyWith(overlayColor: overlay),
      icon: Icon(
        Icons.swap_horiz_rounded,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _TodoDueChip extends StatelessWidget {
  const _TodoDueChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.chipKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final colorScheme = theme.colorScheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return colorScheme.primary.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return colorScheme.primary.withOpacity(0.12);
      }
      return null;
    });

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: OutlinedButton.icon(
        key: chipKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          backgroundColor: tokens.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.borderSubtle),
          textStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: overlay),
        icon: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
