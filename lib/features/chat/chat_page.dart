import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_focus_ring.dart';
import '../../ui/sl_icon_button_frame.dart';
import '../../ui/sl_icon_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../actions/assistant_message_actions.dart';
import '../actions/agenda/todo_agenda_banner.dart';
import '../actions/agenda/todo_agenda_page.dart';
import '../actions/calendar/calendar_action.dart';
import '../actions/review/review_backoff.dart';
import '../actions/review/review_queue_banner.dart';
import '../actions/review/review_queue_page.dart';
import '../actions/settings/actions_settings_store.dart';
import '../actions/suggestions_card.dart';
import '../actions/suggestions_parser.dart';
import '../actions/todo/todo_detail_page.dart';
import '../actions/todo/todo_linking.dart';
import '../actions/todo/todo_thread_match.dart';
import '../actions/time/time_resolver.dart';
import '../attachments/attachment_card.dart';
import '../attachments/attachment_viewer_page.dart';
import '../settings/cloud_account_page.dart';
import '../settings/llm_profiles_page.dart';
import 'message_viewer_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversation, super.key});

  final Conversation conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Future<List<Message>>? _messagesFuture;
  Future<int>? _reviewCountFuture;
  Future<_TodoAgendaSummary>? _agendaFuture;
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByMessageId =
      <String, Future<List<Attachment>>>{};
  List<Message> _paginatedMessages = <Message>[];
  bool _loadingMoreMessages = false;
  bool _hasMoreMessages = true;
  bool _isAtBottom = true;
  bool _hasUnseenNewMessages = false;
  bool _sending = false;
  bool _asking = false;
  bool _stopRequested = false;
  bool _thisThreadOnly = false;
  bool _hoverActionsEnabled = false;
  String? _hoveredMessageId;
  String? _pendingQuestion;
  String _streamingAnswer = '';
  String? _askError;
  StreamSubscription<String>? _askSub;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  static const _kAskAiDataConsentPrefsKey = 'ask_ai_data_consent_v1';
  static const _kAskAiCloudFallbackSnackKey = ValueKey(
    'ask_ai_cloud_fallback_snack',
  );
  static const _kAskAiEmailNotVerifiedSnackKey = ValueKey(
    'ask_ai_email_not_verified_snack',
  );
  static const _kCollapsedMessageHeight = 280.0;
  static const _kLongMessageRuneThreshold = 600;
  static const _kLongMessageLineThreshold = 12;
  static const _kMessagePageSize = 60;
  static const _kLoadMoreThresholdPx = 200.0;
  static const _kBottomThresholdPx = 60.0;

  bool get _usePagination => widget.conversation.id == 'main_stream';
  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels <= _kBottomThresholdPx;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _hasUnseenNewMessages = false;
      });
    }

    if (!_usePagination) return;

    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining > _kLoadMoreThresholdPx) return;
    unawaited(_loadOlderMessages());
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
      if (!_isAtBottom) {
        setState(() {
          _hasUnseenNewMessages = true;
          _reviewCountFuture = _loadReviewQueueCount();
          _agendaFuture = _loadTodoAgendaSummary();
        });
        return;
      }
      _refresh();
    }

    _syncListener = onSyncChange;
    engine.changes.addListener(onSyncChange);
  }

  Future<void> _showMessageActions(Message message) async {
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
                      key: const ValueKey('message_action_convert_todo'),
                      leading: const Icon(Icons.task_alt_rounded),
                      title: Text(context.t.chat.messageActions.convertToTodo),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.convertTodo),
                    )
                  else
                    ListTile(
                      key: const ValueKey('message_action_open_todo'),
                      leading: const Icon(Icons.chevron_right_rounded),
                      title: Text(context.t.chat.messageActions.openTodo),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.openTodo),
                    ),
                  if (canEdit)
                    ListTile(
                      key: const ValueKey('message_action_edit'),
                      leading: const Icon(Icons.edit_rounded),
                      title: Text(context.t.common.actions.edit),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.edit),
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
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case null:
        break;
    }
  }

  String _displayTextForMessage(Message message) {
    final raw = message.content;
    final actions =
        message.role == 'assistant' ? parseAssistantMessageActions(raw) : null;
    return (actions?.displayText ?? raw).trim();
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
      SnackBar(content: Text(context.t.actions.history.actions.copied)),
    );
  }

  Future<void> _pasteIntoChatInput() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text;
    if (text == null || text.isEmpty) return;

    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;
    _controller.value = value.copyWith(
      text: value.text.replaceRange(normalizedStart, normalizedEnd, text),
      selection: TextSelection.collapsed(offset: normalizedStart + text.length),
      composing: TextRange.empty,
    );
  }

  bool _shouldCollapseMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.runes.length >= _kLongMessageRuneThreshold) return true;
    final lineCount = '\n'.allMatches(trimmed).length + 1;
    if (lineCount >= _kLongMessageLineThreshold) return true;
    return false;
  }

  Widget _buildMessageMarkdown(
    String content, {
    required bool isDesktopPlatform,
  }) {
    final markdown = MarkdownBody(data: content, selectable: false);
    if (!isDesktopPlatform) return markdown;

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) =>
          const SizedBox.shrink(),
      child: markdown,
    );
  }

  Future<void> _openMessageViewer(String content) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MessageViewerPage(content: content),
      ),
    );
  }

  Future<void> _showMessageContextMenu(
    Message message,
    Offset globalPosition,
  ) async {
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
            key: const ValueKey('message_context_convert_todo'),
            value: _MessageAction.convertTodo,
            child: Text(context.t.chat.messageActions.convertToTodo),
          )
        else
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_open_todo'),
            value: _MessageAction.openTodo,
            child: Text(context.t.chat.messageActions.openTodo),
          ),
        if (canEdit)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_edit'),
            value: _MessageAction.edit,
            child: Text(context.t.common.actions.edit),
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
      case _MessageAction.convertTodo:
        await _convertMessageToTodo(message);
        break;
      case _MessageAction.openTodo:
        await _openLinkedTodo(linkedTodo?.todo);
        break;
      case _MessageAction.edit:
        await _editMessage(message);
        break;
      case _MessageAction.linkTodo:
        await _linkMessageToTodo(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
      case null:
        break;
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

  Future<void> _convertMessageToTodo(Message message) async {
    if (!mounted) return;

    final rawText = _displayTextForMessage(message);
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final todoId = 'todo:${message.id}';

    try {
      await backend.upsertTodo(
        sessionKey,
        id: todoId,
        title: trimmed,
        dueAtMs: null,
        status: 'open',
        sourceEntryId: message.id,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }

    if (!mounted) return;
    _refresh();
  }

  Future<void> _openLinkedTodo(Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TodoDetailPage(initialTodo: linkedTodo),
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
      _refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.messageUpdated)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.editFailed(error: '$e'))),
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);

      await backend.setMessageDeleted(sessionKey, message.id, true);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.chat.messageDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.chat.deleteFailed(error: '$e'))),
      );
    }
  }

  @override
  void dispose() {
    final oldEngine = _syncEngine;
    final oldListener = _syncListener;
    if (oldEngine != null && oldListener != null) {
      oldEngine.changes.removeListener(oldListener);
    }
    _askSub?.cancel();
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Message>> _loadMessages() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    if (_usePagination) {
      final page = await backend.listMessagesPage(
        sessionKey,
        widget.conversation.id,
        limit: _kMessagePageSize,
      );
      if (mounted) {
        setState(() {
          _paginatedMessages = page;
          _hasMoreMessages = page.length == _kMessagePageSize;
          _loadingMoreMessages = false;
        });
      }
      return page;
    }

    return backend.listMessages(sessionKey, widget.conversation.id);
  }

  Future<void> _loadOlderMessages() async {
    if (!_usePagination) return;
    if (_loadingMoreMessages || !_hasMoreMessages) return;
    if (_paginatedMessages.isEmpty) return;

    final oldest = _paginatedMessages.last;
    setState(() => _loadingMoreMessages = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final page = await backend.listMessagesPage(
        sessionKey,
        widget.conversation.id,
        beforeCreatedAtMs: oldest.createdAtMs,
        beforeId: oldest.id,
        limit: _kMessagePageSize,
      );
      if (!mounted) return;

      setState(() {
        if (page.isEmpty) {
          _hasMoreMessages = false;
        } else {
          final existingIds =
              _paginatedMessages.map((message) => message.id).toSet();
          final deduped = page
              .where((message) => !existingIds.contains(message.id))
              .toList(growable: false);
          _paginatedMessages = <Message>[..._paginatedMessages, ...deduped];
          _hasMoreMessages = page.length == _kMessagePageSize;
        }
        _loadingMoreMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMoreMessages = false);
    }
  }

  Future<void> _jumpToLatest() async {
    if (_hasUnseenNewMessages) {
      _refresh();
      final future = _messagesFuture;
      if (future != null) {
        try {
          await future;
        } catch (_) {
          // ignore
        }
      }
    }

    if (!mounted) return;
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;
    setState(() {
      _hasUnseenNewMessages = false;
      _isAtBottom = true;
    });
  }

  Future<int> _loadReviewQueueCount() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final settings = await ActionsSettingsStore.load();

    final nowLocal = DateTime.now();
    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return 0;
    }

    var pendingCount = 0;
    for (final todo in todos) {
      final nextMs = todo.nextReviewAtMs;
      final stage = todo.reviewStage;
      if (nextMs == null || stage == null) continue;

      final scheduledLocal =
          DateTime.fromMillisecondsSinceEpoch(nextMs, isUtc: true).toLocal();
      final rolled = ReviewBackoff.rollForwardUntilDueOrFuture(
        stage: stage,
        scheduledAtLocal: scheduledLocal,
        nowLocal: nowLocal,
        settings: settings,
      );
      if (rolled.stage != stage || rolled.nextReviewAtLocal != scheduledLocal) {
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todo.id,
            title: todo.title,
            dueAtMs: todo.dueAtMs,
            status: todo.status,
            sourceEntryId: todo.sourceEntryId,
            reviewStage: rolled.stage,
            nextReviewAtMs:
                rolled.nextReviewAtLocal.toUtc().millisecondsSinceEpoch,
            lastReviewAtMs: todo.lastReviewAtMs,
          );
        } catch (_) {
          return 0;
        }
      }

      if (todo.dueAtMs != null) continue;
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
      pendingCount += 1;
    }

    return pendingCount;
  }

  Future<_TodoAgendaSummary> _loadTodoAgendaSummary() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    late final List<Todo> todos;
    try {
      todos = await backend.listTodos(sessionKey);
    } catch (_) {
      return const _TodoAgendaSummary.empty();
    }

    final nowLocal = DateTime.now();
    final due = <({Todo todo, DateTime dueLocal})>[];
    for (final todo in todos) {
      final dueMs = todo.dueAtMs;
      if (dueMs == null) continue;
      if (todo.status == 'done' || todo.status == 'dismissed') continue;

      final dueLocal =
          DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true).toLocal();
      final isOverdue = dueLocal.isBefore(nowLocal);
      final isToday = _isSameLocalDate(dueLocal, nowLocal);
      if (!isOverdue && !isToday) continue;
      due.add((todo: todo, dueLocal: dueLocal));
    }

    due.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    if (due.isEmpty) return const _TodoAgendaSummary.empty();

    final overdueCount = due.where((e) => e.dueLocal.isBefore(nowLocal)).length;
    final previewTodos = due.take(2).map((e) => e.todo).toList(growable: false);

    return _TodoAgendaSummary(
      dueCount: due.length,
      overdueCount: overdueCount,
      previewTodos: previewTodos,
    );
  }

  static bool _isSameLocalDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  void _refresh() {
    setState(() {
      if (_usePagination) {
        _paginatedMessages = <Message>[];
        _loadingMoreMessages = false;
        _hasMoreMessages = true;
      }
      _messagesFuture = _loadMessages();
      _reviewCountFuture = _loadReviewQueueCount();
      _agendaFuture = _loadTodoAgendaSummary();
      _attachmentsFuturesByMessageId.clear();
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_asking) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final message = await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: text,
      );
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _controller.clear();
      _refresh();
      if (_isDesktopPlatform) {
        _inputFocusNode.requestFocus();
      }
      if (_usePagination) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_scrollController.hasClients) return;
          unawaited(
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
            ),
          );
        });
      }
      unawaited(_maybeSuggestTodoFromCapture(message, text));
      unawaited(_maybeLinkMessageToExistingTodo(message, text));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _maybeSuggestTodoFromCapture(
      Message message, String rawText) async {
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final settings = await ActionsSettingsStore.load();

    final timeResolution = LocalTimeResolver.resolve(
      rawText,
      DateTime.now(),
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );
    final looksLikeReview = LocalTimeResolver.looksLikeReviewIntent(rawText);
    if (timeResolution == null && !looksLikeReview) return;

    if (!mounted) return;
    final decision = await showCaptureTodoSuggestionSheet(
      context,
      title: rawText.trim(),
      timeResolution: timeResolution,
    );
    if (decision == null || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final todoId = 'todo:${message.id}';

    switch (decision) {
      case CaptureTodoScheduleDecision(:final dueAtLocal):
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: rawText.trim(),
            dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
            status: 'open',
            sourceEntryId: message.id,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoReviewDecision():
        final nextLocal = ReviewBackoff.initialNextReviewAt(
          DateTime.now(),
          settings,
        );
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: rawText.trim(),
            dueAtMs: null,
            status: 'inbox',
            sourceEntryId: message.id,
            reviewStage: 0,
            nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoNoThanksDecision():
        return;
    }

    if (!mounted) return;
    _refresh();
  }

  Future<void> _maybeLinkMessageToExistingTodo(
    Message message,
    String rawText,
  ) async {
    if (!mounted) return;

    final locale = Localizations.localeOf(context);
    final settings = await ActionsSettingsStore.load();
    final timeResolution = LocalTimeResolver.resolve(
      rawText,
      DateTime.now(),
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );
    final looksLikeReview = LocalTimeResolver.looksLikeReviewIntent(rawText);
    if (timeResolution != null || looksLikeReview) return;

    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
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
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
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

    final intent = inferTodoUpdateIntent(rawText);
    final ranked = await _rankTodoCandidatesWithSemanticMatches(
      backend,
      sessionKey,
      query: rawText,
      targets: targets,
      nowLocal: nowLocal,
      limit: 5,
    );
    if (ranked.isEmpty) return;

    final top = ranked[0];
    final secondScore = ranked.length > 1 ? ranked[1].score : 0;
    final isHighConfidence = top.score >= 3200 ||
        (top.score >= 2400 && (top.score - secondScore) >= 900);
    final shouldPrompt = intent.isExplicit || top.score >= 1600;
    if (!shouldPrompt) {
      final looksLikeLongFormNote =
          rawText.contains('\n') || rawText.trim().runes.length >= 160;
      if (looksLikeLongFormNote && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.actions.todoNoteLink.suggest),
            action: SnackBarAction(
              label: context.t.actions.todoNoteLink.actionShort,
              onPressed: () => unawaited(_linkMessageToTodo(message)),
            ),
          ),
        );
      }
      return;
    }

    final selectedTodoId = isHighConfidence
        ? top.target.id
        : await _showTodoLinkSheet(
            ranked: ranked,
            defaultActionStatus: intent.newStatus,
          );
    if (selectedTodoId == null || !mounted) return;

    final selected = todosById[selectedTodoId];
    if (selected == null) return;

    final previousStatus = selected.status;

    try {
      await backend.setTodoStatus(
        sessionKey,
        todoId: selected.id,
        newStatus: intent.newStatus,
        sourceMessageId: message.id,
      );
    } catch (_) {
      return;
    }

    try {
      final activity = await backend.appendTodoNote(
        sessionKey,
        todoId: selected.id,
        content: rawText.trim(),
        sourceMessageId: message.id,
      );
      final attachmentsBackend =
          backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
      if (attachmentsBackend != null) {
        final attachments = await attachmentsBackend.listMessageAttachments(
            sessionKey, message.id);
        for (final attachment in attachments) {
          await backend.linkAttachmentToTodoActivity(
            sessionKey,
            activityId: activity.id,
            attachmentSha256: attachment.sha256,
          );
        }
      }
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    _refresh();

    final snackText = context.t.actions.todoLink.updated(
      title: selected.title,
      status: _todoStatusLabel(context, intent.newStatus),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        action: SnackBarAction(
          label: context.t.common.actions.undo,
          onPressed: () async {
            try {
              await backend.setTodoStatus(
                sessionKey,
                todoId: selected.id,
                newStatus: previousStatus,
              );
            } catch (_) {
              return;
            }
            if (!mounted) return;
            _refresh();
          },
        ),
      ),
    );
  }

  Future<void> _linkMessageToTodo(Message message) async {
    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

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

    late final TodoActivity activity;
    try {
      activity = await backend.appendTodoNote(
        sessionKey,
        todoId: selected.id,
        content: message.content.trim(),
        sourceMessageId: message.id,
      );
    } catch (_) {
      return;
    }

    final attachmentsBackend =
        backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
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

    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(context.t.actions.todoNoteLink.linked(title: selected.title)),
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
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final c = candidates[index];
                        return ListTile(
                          title: Text(c.target.title),
                          subtitle:
                              Text(_todoStatusLabel(context, c.target.status)),
                          onTap: () => Navigator.of(context).pop(c.target.id),
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
  }

  String _todoStatusLabel(BuildContext context, String status) =>
      switch (status) {
        'inbox' => context.t.actions.todoStatus.inbox,
        'open' => context.t.actions.todoStatus.open,
        'in_progress' => context.t.actions.todoStatus.inProgress,
        'done' => context.t.actions.todoStatus.done,
        'dismissed' => context.t.actions.todoStatus.dismissed,
        _ => status,
      };

  Future<String?> _showTodoLinkSheet({
    required List<TodoLinkCandidate> ranked,
    required String defaultActionStatus,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final statusLabel = _todoStatusLabel(context, defaultActionStatus);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.actions.todoLink.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                      context.t.actions.todoLink.subtitle(status: statusLabel)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: ranked.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final c = ranked[index];
                        return ListTile(
                          title: Text(c.target.title),
                          subtitle:
                              Text(_todoStatusLabel(context, c.target.status)),
                          onTap: () => Navigator.of(context).pop(c.target.id),
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
  }

  Future<void> _handleAssistantSuggestion(
    Message sourceMessage,
    ActionSuggestion suggestion,
    int index,
  ) async {
    if (!mounted) return;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final locale = Localizations.localeOf(context);

    if (suggestion.type == 'event') {
      final settings = await ActionsSettingsStore.load();
      final timeResolution =
          (suggestion.whenText == null || suggestion.whenText!.trim().isEmpty)
              ? null
              : LocalTimeResolver.resolve(
                  suggestion.whenText!,
                  DateTime.now(),
                  locale: locale,
                  dayEndMinutes: settings.dayEndMinutes,
                );

      if (!mounted) return;
      final startLocal = await _pickEventStartTime(
        title: suggestion.title,
        timeResolution: timeResolution,
      );
      if (startLocal == null || !mounted) return;

      final startUtc = startLocal.toUtc();
      final endUtc = startLocal.add(const Duration(hours: 1)).toUtc();
      final tz = _formatTzOffset(startLocal.timeZoneOffset);
      final eventId = 'event:${sourceMessage.id}:$index';

      try {
        await CalendarAction.shareEventAsIcs(
          uid: eventId,
          title: suggestion.title,
          startUtc: startUtc,
          endUtc: endUtc,
        );
      } catch (_) {
        // ignore
      }

      try {
        await backend.upsertEvent(
          sessionKey,
          id: eventId,
          title: suggestion.title.trim(),
          startAtMs: startUtc.millisecondsSinceEpoch,
          endAtMs: endUtc.millisecondsSinceEpoch,
          tz: tz,
          sourceEntryId: sourceMessage.id,
        );
      } catch (_) {
        return;
      }

      if (!mounted) return;
      _refresh();
      return;
    }

    if (suggestion.type != 'todo') return;

    final settings = await ActionsSettingsStore.load();
    final timeResolution =
        (suggestion.whenText == null || suggestion.whenText!.trim().isEmpty)
            ? null
            : LocalTimeResolver.resolve(
                suggestion.whenText!,
                DateTime.now(),
                locale: locale,
                dayEndMinutes: settings.dayEndMinutes,
              );

    if (!mounted) return;
    final decision = await showCaptureTodoSuggestionSheet(
      context,
      title: suggestion.title,
      timeResolution: timeResolution,
    );
    if (decision == null || !mounted) return;

    final todoId = 'todo:${sourceMessage.id}:$index';

    switch (decision) {
      case CaptureTodoScheduleDecision(:final dueAtLocal):
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: suggestion.title.trim(),
            dueAtMs: dueAtLocal.toUtc().millisecondsSinceEpoch,
            status: 'open',
            sourceEntryId: sourceMessage.id,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoReviewDecision():
        final nextLocal = ReviewBackoff.initialNextReviewAt(
          DateTime.now(),
          settings,
        );
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: suggestion.title.trim(),
            dueAtMs: null,
            status: 'inbox',
            sourceEntryId: sourceMessage.id,
            reviewStage: 0,
            nextReviewAtMs: nextLocal.toUtc().millisecondsSinceEpoch,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
        } catch (_) {
          return;
        }
        break;
      case CaptureTodoNoThanksDecision():
        return;
    }

    if (!mounted) return;
    _refresh();
  }

  Future<DateTime?> _pickEventStartTime({
    required String title,
    required LocalTimeResolution? timeResolution,
  }) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.actions.calendar.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(title),
                  const SizedBox(height: 12),
                  Text(
                    context.t.actions.calendar.pickTime,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  if (timeResolution != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in timeResolution.candidates)
                          SlButton(
                            onPressed: () =>
                                Navigator.of(context).pop(c.dueAtLocal),
                            child: Text(c.label),
                          ),
                      ],
                    )
                  else
                    Text(
                      context.t.actions.calendar.noAutoTime,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  SlButton(
                    variant: SlButtonVariant.outline,
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: DateTime.now(),
                      );
                      if (date == null) return;
                      if (!context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(DateTime.now()),
                      );
                      if (time == null) return;
                      if (!context.mounted) return;
                      Navigator.of(context).pop(
                        DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    },
                    child: Text(context.t.actions.calendar.pickCustom),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatTzOffset(Duration offset) {
    final minutes = offset.inMinutes;
    final sign = minutes >= 0 ? '+' : '-';
    final abs = minutes.abs();
    final hh = (abs ~/ 60).toString().padLeft(2, '0');
    final mm = (abs % 60).toString().padLeft(2, '0');
    return '$sign$hh:$mm';
  }

  Future<void> _stopAsk() async {
    final sub = _askSub;
    if (!_asking || _stopRequested) return;

    setState(() {
      _stopRequested = true;
      _askSub = null;
      _asking = false;
      _pendingQuestion = null;
      _streamingAnswer = '';
    });

    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (!mounted) return;
    setState(() => _stopRequested = false);
  }

  Future<void> _askAi() async {
    if (_asking) return;
    if (_sending) return;

    final question = _controller.text.trim();
    if (question.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    String? cloudIdToken;
    try {
      cloudIdToken = await cloudAuthScope?.controller.getIdToken();
    } catch (_) {
      cloudIdToken = null;
    }

    if (!mounted) return;
    final cloudGatewayConfig =
        cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    final route = await decideAskAiRoute(
      backend,
      sessionKey,
      cloudIdToken: cloudIdToken,
      cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      subscriptionStatus: subscriptionStatus,
    );

    if (route == AskAiRouteKind.needsSetup) {
      final configured = await _ensureAskAiConfigured(backend, sessionKey);
      if (!configured) return;
    }

    final consented = await _ensureAskAiDataConsent();
    if (!consented) return;

    setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    _controller.clear();

    try {
      await _prepareEmbeddingsForAskAi(backend, sessionKey);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _askError = '$e';
        _askSub = null;
        _asking = false;
        _pendingQuestion = null;
        _streamingAnswer = '';
      });
      _refresh();
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      return;
    }

    Stream<String> stream;
    switch (route) {
      case AskAiRouteKind.cloudGateway:
        stream = backend.askAiStreamCloudGateway(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: 10,
          thisThreadOnly: _thisThreadOnly,
          gatewayBaseUrl: cloudGatewayConfig.baseUrl,
          idToken: cloudIdToken ?? '',
          modelName: cloudGatewayConfig.modelName,
        );
        break;
      case AskAiRouteKind.byok:
      case AskAiRouteKind.needsSetup:
        stream = backend.askAiStream(
          sessionKey,
          widget.conversation.id,
          question: question,
          topK: 10,
          thisThreadOnly: _thisThreadOnly,
        );
        break;
    }

    Future<void> startStream(Stream<String> stream,
        {required bool fromCloud}) async {
      late final StreamSubscription<String> sub;
      sub = stream.listen(
        (delta) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          setState(() => _streamingAnswer += delta);
        },
        onError: (e) async {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;

          if (fromCloud && isCloudEmailNotVerifiedError(e)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiEmailNotVerifiedSnackKey,
                content: Text(context.t.chat.cloudGateway.emailNotVerified),
                action: SnackBarAction(
                  label: context.t.settings.cloudAccount.title,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CloudAccountPage(),
                      ),
                    );
                  },
                ),
              ),
            );

            if (!mounted) return;
            setState(() {
              _askError = null;
              _askSub = null;
              _asking = false;
              _pendingQuestion = null;
              _streamingAnswer = '';
            });
            _refresh();
            SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
            return;
          }

          final cloudStatus = fromCloud ? parseHttpStatusFromError(e) : null;

          final hasByok = await hasActiveLlmProfile(backend, sessionKey);
          if (!mounted) return;
          if (fromCloud && hasByok && isCloudFallbackableError(e)) {
            final message = switch (cloudStatus) {
              401 => context.t.chat.cloudGateway.fallback.auth,
              402 => context.t.chat.cloudGateway.fallback.entitlement,
              429 => context.t.chat.cloudGateway.fallback.rateLimited,
              _ => context.t.chat.cloudGateway.fallback.generic,
            };

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: _kAskAiCloudFallbackSnackKey,
                content: Text(message),
              ),
            );

            if (!mounted) return;
            setState(() {
              _askError = null;
              _streamingAnswer = '';
            });

            final byokStream = backend.askAiStream(
              sessionKey,
              widget.conversation.id,
              question: question,
              topK: 10,
              thisThreadOnly: _thisThreadOnly,
            );
            await startStream(byokStream, fromCloud: false);
            return;
          }

          if (!mounted) return;
          setState(() {
            _askError = fromCloud
                ? switch (cloudStatus) {
                    401 => context.t.chat.cloudGateway.errors.auth,
                    402 => context.t.chat.cloudGateway.errors.entitlement,
                    429 => context.t.chat.cloudGateway.errors.rateLimited,
                    _ => context.t.chat.cloudGateway.errors.generic,
                  }
                : '$e';
            _askSub = null;
            _asking = false;
            _pendingQuestion = null;
            _streamingAnswer = '';
          });
          _refresh();
          SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
        },
        onDone: () {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          setState(() {
            _askSub = null;
            _asking = false;
            _pendingQuestion = null;
            _streamingAnswer = '';
          });
          _refresh();
          SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
        },
        cancelOnError: true,
      );

      if (!mounted) return;
      setState(() => _askSub = sub);
    }

    await startStream(stream, fromCloud: route == AskAiRouteKind.cloudGateway);
  }

  Future<bool> _ensureAskAiDataConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getBool(_kAskAiDataConsentPrefsKey) ?? false;
    if (skip) return true;
    if (!mounted) return false;

    var dontShowAgain = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.t;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const ValueKey('ask_ai_consent_dialog'),
              title: Text(t.chat.askAiConsent.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chat.askAiConsent.body),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('ask_ai_consent_dont_show_again'),
                    contentPadding: EdgeInsets.zero,
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? false);
                    },
                    title: Text(t.chat.askAiConsent.dontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  key: const ValueKey('ask_ai_consent_continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.common.actions.continueLabel),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) return false;
    if (dontShowAgain) {
      await prefs.setBool(_kAskAiDataConsentPrefsKey, true);
    }
    return true;
  }

  Future<bool> _ensureAskAiConfigured(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final hasActiveProfile = await hasActiveLlmProfile(backend, sessionKey);
      if (hasActiveProfile) return true;
    } catch (_) {
      return true;
    }
    if (!mounted) return false;

    final action = await showDialog<_AskAiSetupAction>(
      context: context,
      builder: (context) {
        final t = context.t;
        return AlertDialog(
          key: const ValueKey('ask_ai_setup_dialog'),
          title: Text(t.chat.askAiSetup.title),
          content: Text(t.chat.askAiSetup.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.actions.cancel),
            ),
            TextButton(
              key: const ValueKey('ask_ai_setup_subscribe'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.subscribe),
              child: Text(t.chat.askAiSetup.actions.subscribe),
            ),
            FilledButton(
              key: const ValueKey('ask_ai_setup_configure_byok'),
              onPressed: () =>
                  Navigator.of(context).pop(_AskAiSetupAction.configureByok),
              child: Text(t.chat.askAiSetup.actions.configureByok),
            ),
          ],
        );
      },
    );

    if (!mounted) return false;

    switch (action) {
      case _AskAiSetupAction.configureByok:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LlmProfilesPage()),
        );
        break;
      case _AskAiSetupAction.subscribe:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudAccountPage()),
        );
        break;
      case null:
        break;
    }

    return false;
  }

  Future<void> _prepareEmbeddingsForAskAi(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    final t = context.t;
    final status = ValueNotifier<String>(t.semanticSearch.preparing);
    final elapsedSeconds = ValueNotifier<int>(0);
    var dialogShown = false;

    final elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds.value += 1;
    });

    final showTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (context, value, child) {
                    return Row(
                      children: [
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(value)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: elapsedSeconds,
                  builder: (context, value, child) {
                    return Text(
                      context.t.common.labels.elapsedSeconds(seconds: value),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    });

    try {
      var totalProcessed = 0;
      while (true) {
        final processed = await backend
            .processPendingMessageEmbeddings(sessionKey, limit: 256);
        if (processed <= 0) break;
        totalProcessed += processed;
        status.value = t.semanticSearch.indexingMessages(count: totalProcessed);
      }
    } finally {
      showTimer.cancel();
      elapsedTimer.cancel();
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      status.dispose();
      elapsedSeconds.dispose();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
    _reviewCountFuture ??= _loadReviewQueueCount();
    _agendaFuture ??= _loadTodoAgendaSummary();
    _attachSyncEngine();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    final isDesktopPlatform = _isDesktopPlatform;
    final title = widget.conversation.id == 'main_stream'
        ? context.t.chat.mainStreamTitle
        : widget.conversation.title;
    return Scaffold(
      floatingActionButton: _usePagination && !_isAtBottom
          ? FloatingActionButton.small(
              key: const ValueKey('chat_jump_to_latest'),
              onPressed: _jumpToLatest,
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              child: const Icon(Icons.arrow_downward_rounded),
            )
          : null,
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _thisThreadOnly,
            onSelected: (value) => setState(() => _thisThreadOnly = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Text(context.t.chat.focus.allMemories),
              ),
              PopupMenuItem(
                value: true,
                child: Text(context.t.chat.focus.thisThread),
              ),
            ],
            tooltip: context.t.chat.focus.tooltip,
            child: const SlIconButtonFrame(
              key: ValueKey('chat_filter_menu'),
              icon: Icons.filter_alt_rounded,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<_TodoAgendaSummary>(
            future: _agendaFuture,
            builder: (context, snapshot) {
              final summary = snapshot.data ?? const _TodoAgendaSummary.empty();
              return TodoAgendaBanner(
                dueCount: summary.dueCount,
                overdueCount: summary.overdueCount,
                previewTodos: summary.previewTodos,
                onViewAll: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TodoAgendaPage(),
                    ),
                  );
                  if (!mounted) return;
                  _refresh();
                },
              );
            },
          ),
          FutureBuilder<int>(
            future: _reviewCountFuture,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return ReviewQueueBanner(
                count: count,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ReviewQueuePage(),
                    ),
                  );
                  if (!mounted) return;
                  _refresh();
                },
              );
            },
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: FutureBuilder(
                  future: _messagesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          context.t.errors
                              .loadFailed(error: '${snapshot.error}'),
                        ),
                      );
                    }

                    final messages = _usePagination
                        ? _paginatedMessages
                        : snapshot.data ?? const <Message>[];
                    final pendingQuestion = _pendingQuestion;
                    final hasPendingAssistant = _asking && !_stopRequested;
                    final extraCount = (hasPendingAssistant ? 1 : 0) +
                        (pendingQuestion == null ? 0 : 1);
                    if (messages.isEmpty && extraCount == 0) {
                      return Center(
                        child: Text(context.t.chat.noMessagesYet),
                      );
                    }

                    return ListView.builder(
                      key: _usePagination
                          ? const ValueKey('chat_message_list')
                          : null,
                      controller: _usePagination ? _scrollController : null,
                      reverse: _usePagination,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      itemCount: messages.length + extraCount,
                      itemBuilder: (context, index) {
                        final backend = AppBackendScope.of(context);
                        final attachmentsBackend = backend is AttachmentsBackend
                            ? backend as AttachmentsBackend
                            : null;
                        final sessionKey = SessionScope.of(context).sessionKey;

                        Message? msg;
                        String? textOverride;
                        if (_usePagination) {
                          if (index < extraCount) {
                            var extraIndex = index;
                            if (hasPendingAssistant) {
                              if (extraIndex == 0) {
                                msg = Message(
                                  id: 'pending_assistant',
                                  conversationId: widget.conversation.id,
                                  role: 'assistant',
                                  content: '',
                                  createdAtMs: 0,
                                  isMemory: false,
                                );
                                textOverride = _streamingAnswer.isEmpty
                                    ? '…'
                                    : _streamingAnswer;
                              }
                              extraIndex -= 1;
                            }
                            if (msg == null &&
                                pendingQuestion != null &&
                                extraIndex == 0) {
                              msg = Message(
                                id: 'pending_user',
                                conversationId: widget.conversation.id,
                                role: 'user',
                                content: pendingQuestion,
                                createdAtMs: 0,
                                isMemory: false,
                              );
                            }
                          } else {
                            msg = messages[index - extraCount];
                          }
                        } else {
                          if (index < messages.length) {
                            msg = messages[index];
                          } else {
                            var extraIndex = index - messages.length;
                            if (pendingQuestion != null) {
                              if (extraIndex == 0) {
                                msg = Message(
                                  id: 'pending_user',
                                  conversationId: widget.conversation.id,
                                  role: 'user',
                                  content: pendingQuestion,
                                  createdAtMs: 0,
                                  isMemory: false,
                                );
                              }
                              extraIndex -= 1;
                            }
                            if (msg == null &&
                                _asking &&
                                !_stopRequested &&
                                extraIndex == 0) {
                              msg = Message(
                                id: 'pending_assistant',
                                conversationId: widget.conversation.id,
                                role: 'assistant',
                                content: '',
                                createdAtMs: 0,
                                isMemory: false,
                              );
                              textOverride = _streamingAnswer.isEmpty
                                  ? '…'
                                  : _streamingAnswer;
                            }
                          }
                        }

                        final stableMsg = msg;
                        if (stableMsg == null) {
                          return const SizedBox.shrink();
                        }

                        final isUser = stableMsg.role == 'user';
                        final bubbleShape = RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: isUser
                                ? colorScheme.primary.withOpacity(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.28
                                        : 0.22,
                                  )
                                : tokens.borderSubtle,
                          ),
                        );
                        final bubbleColor = isUser
                            ? colorScheme.primaryContainer
                            : tokens.surface2;

                        final isPending = stableMsg.id.startsWith('pending_');
                        final showHoverMenu =
                            !isPending && _hoveredMessageId == stableMsg.id;

                        final supportsAttachments =
                            attachmentsBackend != null && !isPending;

                        final rawText = textOverride ?? stableMsg.content;
                        final assistantActions =
                            (!isPending && stableMsg.role == 'assistant')
                                ? parseAssistantMessageActions(rawText)
                                : null;
                        final displayText =
                            assistantActions?.displayText ?? rawText;
                        final actionSuggestions =
                            assistantActions?.suggestions?.suggestions ??
                                const <ActionSuggestion>[];

                        final shouldCollapse = !isPending &&
                            _shouldCollapseMessage(displayText) &&
                            actionSuggestions.isEmpty;

                        final hoverMenuSlot = _hoverActionsEnabled && !isPending
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: SizedBox(
                                  width: 72,
                                  height: 32,
                                  child: showHoverMenu
                                      ? Row(
                                          mainAxisAlignment: isUser
                                              ? MainAxisAlignment.end
                                              : MainAxisAlignment.start,
                                          children: [
                                            if (isUser) ...[
                                              SlIconButton(
                                                key: ValueKey(
                                                    'message_edit_${stableMsg.id}'),
                                                icon: Icons.edit_rounded,
                                                onPressed: () =>
                                                    _editMessage(stableMsg),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            SlIconButton(
                                              key: ValueKey(
                                                  'message_delete_${stableMsg.id}'),
                                              icon:
                                                  Icons.delete_outline_rounded,
                                              color: colorScheme.error,
                                              overlayBaseColor:
                                                  colorScheme.error,
                                              borderColor:
                                                  colorScheme.error.withOpacity(
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? 0.32
                                                    : 0.22,
                                              ),
                                              onPressed: () =>
                                                  _deleteMessage(stableMsg),
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              )
                            : const SizedBox.shrink();

                        final bubble = ConstrainedBox(
                          key: ValueKey('message_bubble_${stableMsg.id}'),
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Material(
                            color: bubbleColor,
                            shape: bubbleShape,
                            child: Listener(
                              onPointerDown: isPending
                                  ? null
                                  : (event) {
                                      final kind = event.kind;
                                      final isPointerKind = kind ==
                                              PointerDeviceKind.mouse ||
                                          kind == PointerDeviceKind.trackpad;
                                      if (!isPointerKind) return;
                                      if (event.buttons &
                                              kSecondaryMouseButton ==
                                          0) {
                                        return;
                                      }
                                      unawaited(
                                        _showMessageContextMenu(
                                          stableMsg,
                                          event.position,
                                        ),
                                      );
                                    },
                              child: InkWell(
                                onTap: shouldCollapse
                                    ? () => unawaited(
                                          _openMessageViewer(displayText),
                                        )
                                    : null,
                                onLongPress: isDesktopPlatform
                                    ? null
                                    : () => _showMessageActions(stableMsg),
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!stableMsg.isMemory)
                                        Padding(
                                          key: ValueKey(
                                            'message_ask_ai_badge_${stableMsg.id}',
                                          ),
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.auto_awesome_rounded,
                                                size: 14,
                                                color: colorScheme.secondary,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                context.t.common.actions.askAi,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          colorScheme.secondary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (shouldCollapse)
                                        SizedBox(
                                          height: _kCollapsedMessageHeight,
                                          child: ClipRect(
                                            child: Stack(
                                              children: [
                                                SingleChildScrollView(
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  child: _buildMessageMarkdown(
                                                    displayText,
                                                    isDesktopPlatform:
                                                        isDesktopPlatform,
                                                  ),
                                                ),
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  bottom: 0,
                                                  height: 32,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: [
                                                          bubbleColor
                                                              .withOpacity(0),
                                                          bubbleColor,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      else
                                        _buildMessageMarkdown(
                                          displayText,
                                          isDesktopPlatform: isDesktopPlatform,
                                        ),
                                      if (shouldCollapse)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            key: ValueKey(
                                              'message_view_full_${stableMsg.id}',
                                            ),
                                            onPressed: () => unawaited(
                                              _openMessageViewer(displayText),
                                            ),
                                            child:
                                                Text(context.t.chat.viewFull),
                                          ),
                                        ),
                                      if (actionSuggestions.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (var i = 0;
                                                  i < actionSuggestions.length;
                                                  i++)
                                                SlButton(
                                                  variant:
                                                      SlButtonVariant.outline,
                                                  onPressed: () =>
                                                      _handleAssistantSuggestion(
                                                    stableMsg,
                                                    actionSuggestions[i],
                                                    i,
                                                  ),
                                                  icon: Icon(
                                                    actionSuggestions[i].type ==
                                                            'event'
                                                        ? Icons.event_rounded
                                                        : Icons
                                                            .check_circle_outline_rounded,
                                                    size: 18,
                                                  ),
                                                  child: Text(
                                                    actionSuggestions[i]
                                                                .whenText
                                                                ?.trim()
                                                                .isNotEmpty ==
                                                            true
                                                        ? '${actionSuggestions[i].title} (${actionSuggestions[i].whenText})'
                                                        : actionSuggestions[i]
                                                            .title,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      if (supportsAttachments)
                                        FutureBuilder(
                                          future: _attachmentsFuturesByMessageId
                                              .putIfAbsent(
                                            stableMsg.id,
                                            () => attachmentsBackend
                                                .listMessageAttachments(
                                              sessionKey,
                                              stableMsg.id,
                                            ),
                                          ),
                                          builder: (context, snapshot) {
                                            final items = snapshot.data ??
                                                const <Attachment>[];
                                            if (items.isEmpty) {
                                              return const SizedBox.shrink();
                                            }

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(
                                                  children: [
                                                    for (final attachment
                                                        in items)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          right: 8,
                                                        ),
                                                        child: AttachmentCard(
                                                          attachment:
                                                              attachment,
                                                          onTap: () {
                                                            Navigator.of(
                                                                    context)
                                                                .push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (context) {
                                                                  return AttachmentViewerPage(
                                                                    attachment:
                                                                        attachment,
                                                                  );
                                                                },
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: MouseRegion(
                            onEnter: isPending
                                ? null
                                : (_) => setState(
                                      () {
                                        _hoverActionsEnabled = true;
                                        _hoveredMessageId = stableMsg.id;
                                      },
                                    ),
                            onExit: isPending
                                ? null
                                : (_) => setState(() {
                                      if (_hoveredMessageId == stableMsg.id) {
                                        _hoveredMessageId = null;
                                      }
                                    }),
                            child: Row(
                              mainAxisAlignment: isUser
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (isUser) hoverMenuSlot,
                                Flexible(child: bubble),
                                if (!isUser) hoverMenuSlot,
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          if (_askError != null)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _askError!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SlFocusRing(
                    key: const ValueKey('chat_input_ring'),
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    child: SlSurface(
                      color: tokens.surface2,
                      borderColor: tokens.borderSubtle,
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Focus(
                              // ignore: deprecated_member_use
                              onKey: (node, event) {
                                // ignore: deprecated_member_use
                                if (event is! RawKeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }

                                final key = event.logicalKey;
                                final composing = _controller.value.composing;
                                final isComposing =
                                    composing.isValid && !composing.isCollapsed;

                                // ignore: deprecated_member_use
                                final metaPressed = event.isMetaPressed;
                                // ignore: deprecated_member_use
                                final controlPressed = event.isControlPressed;
                                // ignore: deprecated_member_use
                                final shiftPressed = event.isShiftPressed;

                                final isPaste =
                                    key == LogicalKeyboardKey.paste ||
                                        (key == LogicalKeyboardKey.keyV &&
                                            (metaPressed || controlPressed));
                                if (isPaste) {
                                  unawaited(_pasteIntoChatInput());
                                  return KeyEventResult.handled;
                                }

                                final isSelectAll =
                                    key == LogicalKeyboardKey.keyA &&
                                        (metaPressed || controlPressed);
                                if (isSelectAll) {
                                  final textLength =
                                      _controller.value.text.length;
                                  _controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: textLength,
                                  );
                                  return KeyEventResult.handled;
                                }

                                final isCopy =
                                    (key == LogicalKeyboardKey.copy ||
                                            key == LogicalKeyboardKey.keyC) &&
                                        (metaPressed || controlPressed);
                                if (isCopy) {
                                  final value = _controller.value;
                                  final selection = value.selection;
                                  if (selection.isValid &&
                                      !selection.isCollapsed) {
                                    final start = selection.start;
                                    final end = selection.end;
                                    final normalizedStart =
                                        start < end ? start : end;
                                    final normalizedEnd =
                                        start < end ? end : start;
                                    final selectedText = value.text.substring(
                                      normalizedStart,
                                      normalizedEnd,
                                    );
                                    unawaited(
                                      Clipboard.setData(
                                        ClipboardData(text: selectedText),
                                      ),
                                    );
                                  }
                                  return KeyEventResult.handled;
                                }

                                final isCut = (key == LogicalKeyboardKey.cut ||
                                        key == LogicalKeyboardKey.keyX) &&
                                    (metaPressed || controlPressed);
                                if (isCut) {
                                  final value = _controller.value;
                                  final selection = value.selection;
                                  if (selection.isValid &&
                                      !selection.isCollapsed) {
                                    final start = selection.start;
                                    final end = selection.end;
                                    final normalizedStart =
                                        start < end ? start : end;
                                    final normalizedEnd =
                                        start < end ? end : start;
                                    final selectedText = value.text.substring(
                                      normalizedStart,
                                      normalizedEnd,
                                    );
                                    unawaited(
                                      Clipboard.setData(
                                        ClipboardData(text: selectedText),
                                      ),
                                    );
                                    final updatedText = value.text.replaceRange(
                                      normalizedStart,
                                      normalizedEnd,
                                      '',
                                    );
                                    _controller.value = value.copyWith(
                                      text: updatedText,
                                      selection: TextSelection.collapsed(
                                        offset: normalizedStart,
                                      ),
                                      composing: TextRange.empty,
                                    );
                                  }
                                  return KeyEventResult.handled;
                                }

                                if (key != LogicalKeyboardKey.enter &&
                                    key != LogicalKeyboardKey.numpadEnter) {
                                  return KeyEventResult.ignored;
                                }

                                if (event.repeat) {
                                  return KeyEventResult.handled;
                                }

                                if (isComposing) {
                                  return KeyEventResult.ignored;
                                }

                                if (shiftPressed) {
                                  final value = _controller.value;
                                  final selection = value.selection;
                                  final start = selection.isValid
                                      ? selection.start
                                      : value.text.length;
                                  final end = selection.isValid
                                      ? selection.end
                                      : value.text.length;
                                  final normalizedStart =
                                      start < end ? start : end;
                                  final normalizedEnd =
                                      start < end ? end : start;
                                  final updatedText = value.text.replaceRange(
                                    normalizedStart,
                                    normalizedEnd,
                                    '\n',
                                  );
                                  _controller.value = value.copyWith(
                                    text: updatedText,
                                    selection: TextSelection.collapsed(
                                      offset: normalizedStart + 1,
                                    ),
                                    composing: TextRange.empty,
                                  );
                                  return KeyEventResult.handled;
                                }

                                unawaited(_send());
                                return KeyEventResult.handled;
                              },
                              child: TextField(
                                key: const ValueKey('chat_input'),
                                focusNode: _inputFocusNode,
                                controller: _controller,
                                decoration: InputDecoration(
                                  hintText: context.t.common.fields.message,
                                  border: InputBorder.none,
                                  filled: false,
                                ),
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                minLines: 1,
                                maxLines: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SlButton(
                            buttonKey: const ValueKey('chat_send'),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            variant: SlButtonVariant.primary,
                            onPressed: (_sending || _asking) ? null : _send,
                            child: Text(context.t.common.actions.send),
                          ),
                          const SizedBox(width: 8),
                          if (_asking)
                            SlButton(
                              buttonKey: const ValueKey('chat_stop'),
                              icon: const Icon(
                                Icons.stop_circle_outlined,
                                size: 18,
                              ),
                              variant: SlButtonVariant.outline,
                              onPressed: _stopRequested ? null : _stopAsk,
                              child: Text(
                                _stopRequested
                                    ? context.t.common.actions.stopping
                                    : context.t.common.actions.stop,
                              ),
                            )
                          else
                            SlButton(
                              buttonKey: const ValueKey('chat_ask_ai'),
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                              ),
                              variant: SlButtonVariant.secondary,
                              onPressed: (_sending || _asking) ? null : _askAi,
                              child: Text(context.t.common.actions.askAi),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _TodoAgendaSummary {
  const _TodoAgendaSummary({
    required this.dueCount,
    required this.overdueCount,
    required this.previewTodos,
  });

  const _TodoAgendaSummary.empty()
      : dueCount = 0,
        overdueCount = 0,
        previewTodos = const <Todo>[];

  final int dueCount;
  final int overdueCount;
  final List<Todo> previewTodos;
}

enum _MessageAction {
  copy,
  convertTodo,
  openTodo,
  edit,
  linkTodo,
  delete,
}

enum _AskAiSetupAction {
  subscribe,
  configureByok,
}
