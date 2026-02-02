import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/ai/embeddings_data_consent_prefs.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/platform/android_media_location_permission.dart';
import '../../core/platform/platform_location.dart';
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
import '../actions/todo/message_action_resolver.dart';
import '../actions/todo/message_auto_actions_queue.dart';
import '../actions/todo/todo_thread_match.dart';
import '../actions/time/date_time_picker_dialog.dart';
import '../actions/time/time_resolver.dart';
import '../attachments/attachment_card.dart';
import '../attachments/attachment_viewer_page.dart';
import '../attachments/image_exif_metadata.dart';
import '../attachments/platform_exif_metadata.dart';
import '../media_backup/image_compression.dart';
import '../settings/cloud_account_page.dart';
import '../settings/llm_profiles_page.dart';
import '../settings/settings_page.dart';
import 'chat_image_attachment_thumbnail.dart';
import 'deferred_attachment_location_upsert.dart';
import 'chat_markdown_sanitizer.dart';
import 'message_viewer_page.dart';
import 'ask_ai_intent_resolver.dart';

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
  final Map<String, List<Attachment>> _attachmentsCacheByMessageId =
      <String, List<Attachment>>{};
  final Map<String, Future<_AttachmentEnrichment>>
      _attachmentEnrichmentFuturesBySha256 =
      <String, Future<_AttachmentEnrichment>>{};
  final Map<String, _AttachmentEnrichment> _attachmentEnrichmentCacheBySha256 =
      <String, _AttachmentEnrichment>{};
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
  bool _cloudEmbeddingsConsented = false;
  String? _hoveredMessageId;
  String? _pendingQuestion;
  String _streamingAnswer = '';
  String? _askError;
  String? _askFailureMessage;
  String? _askFailureQuestion;
  Timer? _askFailureTimer;
  StreamSubscription<String>? _askSub;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  MessageAutoActionsQueue? _messageAutoActionsQueue;

  static const _kAskAiDataConsentPrefsKey = 'ask_ai_data_consent_v1';
  static const _kEmbeddingsDataConsentPrefsKey = 'embeddings_data_consent_v1';
  static const _kCloudEmbeddingsModelName = 'baai/bge-m3';
  static const _kAskAiCloudFallbackSnackKey = ValueKey(
    'ask_ai_cloud_fallback_snack',
  );
  static const _kAskAiEmailNotVerifiedSnackKey = ValueKey(
    'ask_ai_email_not_verified_snack',
  );
  static const _kAskAiErrorPrefix = '\u001eSL_ERROR\u001e';
  static const _kCollapsedMessageHeight = 280.0;
  static const _kLongMessageRuneThreshold = 600;
  static const _kLongMessageLineThreshold = 12;
  static const _kMessagePageSize = 60;
  static const _kLoadMoreThresholdPx = 200.0;
  static const _kBottomThresholdPx = 60.0;
  static const _kTodoAutoSemanticTimeout = Duration(milliseconds: 280);
  static const _kTodoLinkSheetRerankTimeout = Duration(milliseconds: 5000);

  bool get _usePagination => widget.conversation.id == 'main_stream';
  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  bool get _supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _supportsImageUpload => _supportsCamera || _isDesktopPlatform;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadEmbeddingsDataConsentPreference());
  }

  Future<void> _loadEmbeddingsDataConsentPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kEmbeddingsDataConsentPrefsKey)) return;

    final value = prefs.getBool(_kEmbeddingsDataConsentPrefsKey) ?? false;
    if (!mounted) return;
    setState(() => _cloudEmbeddingsConsented = value);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels <= _kBottomThresholdPx;
    final shouldRefreshOnReturnToBottom =
        atBottom && !_isAtBottom && _hasUnseenNewMessages;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _hasUnseenNewMessages = false;
      });
      if (shouldRefreshOnReturnToBottom) {
        _refresh();
      }
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
    final canConvertToTodo =
        linkedTodo == null && _displayTextForMessage(message).trim().isNotEmpty;
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
                  if (canConvertToTodo)
                    ListTile(
                      key: const ValueKey('message_action_convert_todo'),
                      leading: const Icon(Icons.task_alt_rounded),
                      title: Text(context.t.chat.messageActions.convertToTodo),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.convertTodo),
                    )
                  else if (linkedTodo != null) ...[
                    ListTile(
                      key: const ValueKey('message_action_open_todo'),
                      leading: const Icon(Icons.chevron_right_rounded),
                      title: Text(context.t.chat.messageActions.openTodo),
                      onTap: () =>
                          Navigator.of(context).pop(_MessageAction.openTodo),
                    ),
                    if (linkedTodo.isSourceEntry)
                      ListTile(
                        key: const ValueKey('message_action_convert_to_info'),
                        leading: const Icon(Icons.undo_rounded),
                        title: Text(
                            context.t.chat.messageActions.convertTodoToInfo),
                        onTap: () => Navigator.of(context)
                            .pop(_MessageAction.convertTodoToInfo),
                      ),
                  ],
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
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
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
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
        break;
      case null:
        break;
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

  bool _isPhotoPlaceholderText(BuildContext context, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final localized = context.t.chat.photoMessage.trim();
    if (localized.isNotEmpty && trimmed == localized) return true;
    return trimmed == 'Photo' || trimmed == '照片';
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
    final normalized = sanitizeChatMarkdown(content);
    final markdown = MarkdownBody(
      data: normalized,
      selectable: false,
    );
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
        builder: (context) =>
            MessageViewerPage(content: sanitizeChatMarkdown(content)),
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
    final canConvertToTodo =
        linkedTodo == null && _displayTextForMessage(message).trim().isNotEmpty;
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
        if (canConvertToTodo)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_todo'),
            value: _MessageAction.convertTodo,
            child: Text(context.t.chat.messageActions.convertToTodo),
          )
        else if (linkedTodo != null)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_open_todo'),
            value: _MessageAction.openTodo,
            child: Text(context.t.chat.messageActions.openTodo),
          ),
        if (linkedTodo != null && linkedTodo.isSourceEntry)
          PopupMenuItem<_MessageAction>(
            key: const ValueKey('message_context_convert_to_info'),
            value: _MessageAction.convertTodoToInfo,
            child: Text(context.t.chat.messageActions.convertTodoToInfo),
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
      case _MessageAction.convertTodoToInfo:
        await _convertMessageTodoToInfo(message, linkedTodo?.todo);
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
        await _deleteMessage(message, linkedTodoInfo: linkedTodo);
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

    final locale = Localizations.localeOf(context);
    final settings = await ActionsSettingsStore.load();
    if (!mounted) return;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      trimmed,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );

    DateTime? dueAtLocal;
    final candidates = timeResolution?.candidates ?? const <DueCandidate>[];
    if (candidates.isNotEmpty) {
      dueAtLocal = candidates.first.dueAtLocal;
    } else {
      final initialLocal = DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        settings.dayEndTime.hour,
        settings.dayEndTime.minute,
      );
      dueAtLocal = await showSlDateTimePickerDialog(
        context,
        initialLocal: initialLocal,
        firstDate: DateTime(nowLocal.year - 1),
        lastDate: DateTime(nowLocal.year + 3),
        title: context.t.actions.calendar.pickCustom,
        surfaceKey: ValueKey('message_convert_todo_due_picker_${message.id}'),
      );
    }

    if (dueAtLocal == null || !mounted) return;

    try {
      await backend.upsertTodo(
        sessionKey,
        id: todoId,
        title: trimmed,
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

    if (!mounted) return;
    _refresh();
  }

  Future<void> _convertMessageTodoToInfo(
      Message message, Todo? linkedTodo) async {
    if (linkedTodo == null) return;
    if (linkedTodo.sourceEntryId != message.id) return;
    if (!mounted) return;

    final shouldConvert = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmTitle),
          content:
              Text(context.t.chat.messageActions.convertTodoToInfoConfirmBody),
          actions: [
            SlButton(
              variant: SlButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            SlButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.common.fields.confirm),
            ),
          ],
        );
      },
    );
    if (shouldConvert != true || !mounted) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      await backend.upsertTodo(
        sessionKey,
        id: linkedTodo.id,
        title: linkedTodo.title,
        dueAtMs: null,
        status: 'dismissed',
        sourceEntryId: null,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: linkedTodo.lastReviewAtMs,
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

  Future<void> _deleteMessage(
    Message message, {
    ({Todo todo, bool isSourceEntry})? linkedTodoInfo,
  }) async {
    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final messenger = ScaffoldMessenger.of(context);

      var resolvedLinkedTodoInfo = linkedTodoInfo;
      if (resolvedLinkedTodoInfo == null) {
        resolvedLinkedTodoInfo = await _resolveLinkedTodoInfo(message);
        if (!mounted) return;
      }

      final targetTodo = resolvedLinkedTodoInfo?.todo;
      final isSourceEntry = resolvedLinkedTodoInfo?.isSourceEntry == true;
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
        _refresh();
        messenger.showSnackBar(
          SnackBar(content: Text(t.chat.messageDeleted)),
        );
        return;
      }

      await backend.purgeMessageAttachments(sessionKey, message.id);
      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      _refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(t.chat.messageDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.chat.deleteFailed(error: '$e'))),
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
    _messageAutoActionsQueue?.dispose();
    _askSub?.cancel();
    _askFailureTimer?.cancel();
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showAskAiFailure(String question, {String? message}) {
    _askFailureTimer?.cancel();
    final failureMessage = message ?? context.t.chat.askAiFailedTemporary;

    setState(() {
      _askError = null;
      _askSub = null;
      _asking = false;
      _stopRequested = false;
      _pendingQuestion = question;
      _streamingAnswer = '';
      _askFailureQuestion = question;
      _askFailureMessage = failureMessage;
    });

    _askFailureTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final stillSameAttempt = _askFailureQuestion == question;
      if (!stillSameAttempt) return;

      final shouldRestoreInput = _controller.text.trim().isEmpty;
      setState(() {
        if (_pendingQuestion == question) {
          _pendingQuestion = null;
        }
        _askFailureQuestion = null;
        _askFailureMessage = null;
      });

      if (!shouldRestoreInput) return;
      _controller.text = question;
      _controller.selection = TextSelection.collapsed(offset: question.length);
      if (_isDesktopPlatform) {
        _inputFocusNode.requestFocus();
      }
    });
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
    final upcoming = <({Todo todo, DateTime dueLocal})>[];
    for (final todo in todos) {
      final dueMs = todo.dueAtMs;
      if (dueMs == null) continue;
      if (todo.status == 'done' || todo.status == 'dismissed') continue;

      final dueLocal =
          DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true).toLocal();
      final isOverdue = dueLocal.isBefore(nowLocal);
      final isToday = _isSameLocalDate(dueLocal, nowLocal);
      if (isOverdue || isToday) {
        due.add((todo: todo, dueLocal: dueLocal));
        continue;
      }

      // Upcoming preview: only show future todos that haven't started yet.
      if (todo.status == 'open') {
        upcoming.add((todo: todo, dueLocal: dueLocal));
      }
    }

    due.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    upcoming.sort((a, b) => a.dueLocal.compareTo(b.dueLocal));
    if (due.isEmpty && upcoming.isEmpty) {
      return const _TodoAgendaSummary.empty();
    }

    final overdueCount = due.where((e) => e.dueLocal.isBefore(nowLocal)).length;
    const duePreviewLimit = 2;
    const upcomingPreviewLimit = 2;
    final previewTodos = <Todo>[
      ...due.take(duePreviewLimit).map((e) => e.todo),
      ...upcoming.take(upcomingPreviewLimit).map((e) => e.todo),
    ];

    return _TodoAgendaSummary(
      dueCount: due.length,
      overdueCount: overdueCount,
      upcomingCount: upcoming.length,
      previewTodos: previewTodos.toList(growable: false),
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

  static List<TodoLinkCandidate> _mergeTodoCandidatesWithSemanticMatches({
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required List<TodoThreadMatch> semanticMatches,
    required int limit,
  }) {
    final ranked =
        rankTodoCandidates(query, targets, nowLocal: nowLocal, limit: limit);
    if (semanticMatches.isEmpty) return ranked;

    final targetsById = <String, TodoLinkTarget>{};
    for (final t in targets) {
      targetsById[t.id] = t;
    }

    final scoreByTodoId = <String, int>{};
    for (final c in ranked) {
      scoreByTodoId[c.target.id] = c.score;
    }

    for (var i = 0; i < semanticMatches.length && i < limit; i++) {
      final match = semanticMatches[i];
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

  Future<List<TodoThreadMatch>> _resolveTodoSemanticMatchesForSendFlow(
    AppBackend backend,
    Uint8List sessionKey, {
    required String query,
    required int topK,
    bool requireCloud = false,
  }) async {
    Future<List<TodoThreadMatch>> resolveSemanticMatches() async {
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final cloudGatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      String? cloudIdToken;
      try {
        cloudIdToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        cloudIdToken = null;
      }

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              cloudIdToken != null &&
              cloudIdToken.trim().isNotEmpty &&
              cloudGatewayConfig.baseUrl.trim().isNotEmpty;

      if (cloudAvailable) {
        if (requireCloud && !_cloudEmbeddingsConsented) {
          return const <TodoThreadMatch>[];
        }

        // Avoid prompting for consent during send flow.
        if (_cloudEmbeddingsConsented) {
          return backend.searchSimilarTodoThreadsCloudGateway(
            sessionKey,
            query,
            topK: topK,
            gatewayBaseUrl: cloudGatewayConfig.baseUrl,
            idToken: cloudIdToken,
            modelName: _kCloudEmbeddingsModelName,
          );
        }
        return backend.searchSimilarTodoThreads(sessionKey, query, topK: topK);
      }

      if (requireCloud) return const <TodoThreadMatch>[];

      if (_cloudEmbeddingsConsented &&
          subscriptionStatus != SubscriptionStatus.notEntitled) {
        return const <TodoThreadMatch>[];
      }

      try {
        return await backend.searchSimilarTodoThreadsBrok(
          sessionKey,
          query,
          topK: topK,
        );
      } catch (_) {
        return backend.searchSimilarTodoThreads(sessionKey, query, topK: topK);
      }
    }

    try {
      return await resolveSemanticMatches();
    } catch (_) {
      return const <TodoThreadMatch>[];
    }
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
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final cloudGatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      String? cloudIdToken;
      try {
        cloudIdToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        cloudIdToken = null;
      }

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              cloudIdToken != null &&
              cloudIdToken.trim().isNotEmpty &&
              cloudGatewayConfig.baseUrl.trim().isNotEmpty;

      if (cloudAvailable) {
        final allowCloudEmbeddings =
            _cloudEmbeddingsConsented || await _ensureEmbeddingsDataConsent();
        if (allowCloudEmbeddings) {
          semantic = await backend.searchSimilarTodoThreadsCloudGateway(
            sessionKey,
            query,
            topK: limit,
            gatewayBaseUrl: cloudGatewayConfig.baseUrl,
            idToken: cloudIdToken,
            modelName: _kCloudEmbeddingsModelName,
          );
        } else {
          semantic = await backend.searchSimilarTodoThreads(
            sessionKey,
            query,
            topK: limit,
          );
        }
      } else {
        if (_cloudEmbeddingsConsented &&
            subscriptionStatus != SubscriptionStatus.notEntitled) {
          semantic = const <TodoThreadMatch>[];
        } else {
          try {
            semantic = await backend.searchSimilarTodoThreadsBrok(
              sessionKey,
              query,
              topK: limit,
            );
          } catch (_) {
            semantic = await backend.searchSimilarTodoThreads(
              sessionKey,
              query,
              topK: limit,
            );
          }
        }
      }
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
        _loadingMoreMessages = false;
        _hasMoreMessages = true;
      }
      _messagesFuture = _loadMessages();
      _reviewCountFuture = _loadReviewQueueCount();
      _agendaFuture = _loadTodoAgendaSummary();
      _attachmentsFuturesByMessageId.clear();
      _attachmentEnrichmentFuturesBySha256.clear();
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
      _messageAutoActionsQueue ??= MessageAutoActionsQueue(
        backend: backend,
        sessionKey: sessionKey,
        handler: _handleMessageAutoActions,
      );
      _messageAutoActionsQueue!.enqueue(
        message: message,
        rawText: text,
        createdAtMs: message.createdAtMs,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _inferImageMimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  Future<void> _maybeEnqueueCloudMediaBackup(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    final store = SyncConfigStore();
    final backendType = await store.readBackendType();
    if (backendType != SyncBackendType.managedVault &&
        backendType != SyncBackendType.webdav) {
      return;
    }

    final enabled = await store.readCloudMediaBackupEnabled();
    if (!enabled) return;

    await backend.enqueueCloudMediaBackup(
      sessionKey,
      attachmentSha256: attachmentSha256,
      desiredVariant: 'original',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _maybeEnqueueAttachmentPlaceEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    try {
      await backend.enqueueAttachmentPlace(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }
  }

  Future<_AttachmentEnrichment> _loadAttachmentEnrichment(
    AttachmentsBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    final placeFuture = backend
        .readAttachmentPlaceDisplayName(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    final captionFuture = backend
        .readAttachmentAnnotationCaptionLong(
          sessionKey,
          sha256: attachmentSha256,
        )
        .catchError((_) => null);
    return _AttachmentEnrichment(
      placeDisplayName: await placeFuture,
      captionLong: await captionFuture,
    );
  }

  Future<void> _pickAndSendMedia() async {
    if (_isDesktopPlatform) {
      return _pickAndSendImageFromFile();
    }
    return _pickAndSendImageFromGallery();
  }

  Future<void> _openAttachmentSheet() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsImageUpload) return;

    if (_isDesktopPlatform) {
      await _pickAndSendImageFromFile();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('chat_attach_pick_media'),
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(context.t.chat.attachPickMedia),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_pickAndSendMedia());
                },
              ),
              if (_supportsCamera)
                ListTile(
                  key: const ValueKey('chat_attach_take_photo'),
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: Text(context.t.chat.attachTakePhoto),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_captureAndSendPhoto());
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _captureAndSendPhoto() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsCamera) return;

    setState(() => _sending = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: true,
      );
      if (picked == null) return;
      if (!mounted) return;

      final lang = Localizations.localeOf(context).toLanguageTag();
      final backendAny = AppBackendScope.of(context);
      final backend = backendAny is NativeAppBackend ? backendAny : null;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);

      final platformExif =
          await PlatformExifReader.tryReadImageMetadataFromPath(picked.path);
      final hasValidExifLocation = platformExif != null &&
          platformExif.hasLocation &&
          !(platformExif.latitude == 0.0 && platformExif.longitude == 0.0) &&
          !(platformExif.latitude?.isNaN ?? false) &&
          !(platformExif.longitude?.isNaN ?? false);

      final Future<PlatformLocation?>? locationFuture = hasValidExifLocation
          ? null
          : PlatformLocationReader.tryGetCurrentLocation();
      PlatformExifMetadata? platformExifToSend = platformExif;
      if (!hasValidExifLocation) {
        // Many camera implementations don't embed GPS EXIF when saving to an
        // app-scoped file. We request location now (may prompt permission),
        // but we don't block sending. Location will be backfilled later.
      }
      final rawBytes = await picked.readAsBytes();
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      int? fallbackCapturedAtMs;
      try {
        fallbackCapturedAtMs =
            (await picked.lastModified()).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      final sent = await _sendImageAttachment(
        rawBytes,
        inferredMimeType,
        fallbackCapturedAtMs: fallbackCapturedAtMs,
        platformExif: platformExifToSend,
      );

      if (locationFuture != null && sent != null && backend != null) {
        unawaited(
          deferAttachmentLocationUpsert(
            locationFuture: locationFuture,
            capturedAtMs: sent.capturedAtMs,
            upsert: ({
              required int? capturedAtMs,
              required double latitude,
              required double longitude,
            }) async {
              await backend.upsertAttachmentExifMetadata(
                sessionKey,
                sha256: sent.sha256,
                capturedAtMs: capturedAtMs,
                latitude: latitude,
                longitude: longitude,
              );
              unawaited(
                _maybeEnqueueAttachmentPlaceEnrichment(
                  backend,
                  sessionKey,
                  sent.sha256,
                  lang: lang,
                ),
              );
              syncEngine?.notifyLocalMutation();
              if (!mounted) return;
              _refresh();
            },
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.chat.photoFailed(error: '$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImageFromGallery() async {
    if (_sending) return;
    if (_asking) return;
    if (!_supportsCamera) return;

    setState(() => _sending = true);
    try {
      await AndroidMediaLocationPermission.requestIfNeeded();
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: true,
      );
      if (picked == null) return;

      final platformExif =
          await PlatformExifReader.tryReadImageMetadataFromPath(picked.path);
      final rawBytes = await picked.readAsBytes();
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      int? fallbackCapturedAtMs;
      try {
        fallbackCapturedAtMs =
            (await picked.lastModified()).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      await _sendImageAttachment(
        rawBytes,
        inferredMimeType,
        fallbackCapturedAtMs: fallbackCapturedAtMs,
        platformExif: platformExif,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.chat.photoFailed(error: '$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImageFromFile() async {
    if (_sending) return;
    if (_asking) return;
    if (!_isDesktopPlatform) return;

    setState(() => _sending = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final rawBytes = file.bytes;
      if (rawBytes == null) {
        throw Exception('file_picker returned no bytes');
      }

      final inferredMimeType = _inferImageMimeTypeFromPath(file.name);
      await _sendImageAttachment(rawBytes, inferredMimeType);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.chat.photoFailed(error: '$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<({String sha256, int? capturedAtMs})?> _sendImageAttachment(
    Uint8List rawBytes,
    String inferredMimeType, {
    int? fallbackCapturedAtMs,
    PlatformExifMetadata? platformExif,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return null;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final lang = Localizations.localeOf(context).toLanguageTag();

    final compressed =
        await compressImageForStorage(rawBytes, mimeType: inferredMimeType);
    final rawExif = tryReadImageExifMetadata(rawBytes);
    final storedExif = tryReadImageExifMetadata(compressed.bytes);
    final capturedAtMs = platformExif?.capturedAtMsUtc ??
        rawExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
        storedExif?.capturedAt?.toUtc().millisecondsSinceEpoch ??
        fallbackCapturedAtMs;

    (double, double)? pickLatLon(ImageExifMetadata? meta) {
      final lat = meta?.latitude;
      final lon = meta?.longitude;
      if (lat == null || lon == null) return null;
      if (lat == 0.0 && lon == 0.0) return null;
      if (lat.isNaN || lon.isNaN) return null;
      return (lat, lon);
    }

    final latLon = pickLatLon(platformExif?.toImageExifMetadata()) ??
        pickLatLon(rawExif) ??
        pickLatLon(storedExif);
    final latitude = latLon?.$1;
    final longitude = latLon?.$2;

    final attachment = await backend.insertAttachment(
      sessionKey,
      bytes: compressed.bytes,
      mimeType: compressed.mimeType,
    );
    if (capturedAtMs != null || latitude != null || longitude != null) {
      await backend.upsertAttachmentExifMetadata(
        sessionKey,
        sha256: attachment.sha256,
        capturedAtMs: capturedAtMs,
        latitude: latitude,
        longitude: longitude,
      );
    }
    if (latitude != null && longitude != null) {
      unawaited(
        _maybeEnqueueAttachmentPlaceEnrichment(
          backend,
          sessionKey,
          attachment.sha256,
          lang: lang,
        ),
      );
    }
    unawaited(_maybeEnqueueCloudMediaBackup(
      backend,
      sessionKey,
      attachment.sha256,
    ));
    final message = await backend.insertMessage(
      sessionKey,
      widget.conversation.id,
      role: 'user',
      content: '',
    );
    await backend.linkAttachmentToMessage(
      sessionKey,
      message.id,
      attachmentSha256: attachment.sha256,
    );

    syncEngine?.notifyLocalMutation();
    if (!mounted) {
      return (sha256: attachment.sha256, capturedAtMs: capturedAtMs);
    }
    _refresh();

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

    return (sha256: attachment.sha256, capturedAtMs: capturedAtMs);
  }

  Future<void> _handleMessageAutoActions(
      Message message, String rawText) async {
    if (!mounted) return;

    final locale = Localizations.localeOf(context);
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final settingsFuture = ActionsSettingsStore.load();
    final todosFuture =
        Future<List<Todo>>.sync(() => backend.listTodos(sessionKey))
            .catchError((_) => const <Todo>[]);

    final settings = await settingsFuture;
    if (!mounted) return;
    final todos = await todosFuture;

    final nowLocal = DateTime.now();
    final timeResolution = LocalTimeResolver.resolve(
      rawText,
      nowLocal,
      locale: locale,
      dayEndMinutes: settings.dayEndMinutes,
    );
    final looksLikeReview = LocalTimeResolver.looksLikeReviewIntent(rawText);
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

    var semanticMatches = const <TodoThreadMatch>[];
    var semanticTimedOut = false;
    if (targets.isNotEmpty && timeResolution == null && !looksLikeReview) {
      try {
        semanticMatches = await _resolveTodoSemanticMatchesForSendFlow(
          backend,
          sessionKey,
          query: rawText,
          topK: 5,
        ).timeout(
          _kTodoAutoSemanticTimeout,
          onTimeout: () {
            semanticTimedOut = true;
            return const <TodoThreadMatch>[];
          },
        );
      } catch (_) {
        semanticMatches = const <TodoThreadMatch>[];
        semanticTimedOut = true;
      }
    }

    final decision = MessageActionResolver.resolve(
      rawText,
      locale: locale,
      nowLocal: nowLocal,
      dayEndMinutes: settings.dayEndMinutes,
      openTodoTargets: targets,
      semanticMatches: semanticMatches,
    );

    switch (decision) {
      case MessageActionFollowUpDecision(:final todoId, :final newStatus):
        final selected = todosById[todoId];
        if (selected == null) return;

        final previousStatus = selected.status;
        try {
          await backend.setTodoStatus(
            sessionKey,
            todoId: selected.id,
            newStatus: newStatus,
            sourceMessageId: message.id,
          );
          syncEngine?.notifyLocalMutation();
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
          final attachmentsBackend = backend is AttachmentsBackend
              ? backend as AttachmentsBackend
              : null;
          if (attachmentsBackend != null) {
            final attachments = await attachmentsBackend.listMessageAttachments(
              sessionKey,
              message.id,
            );
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
          status: _todoStatusLabel(context, newStatus),
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
                  syncEngine?.notifyLocalMutation();
                } catch (_) {
                  return;
                }
                if (!mounted) return;
                _refresh();
              },
            ),
          ),
        );
        return;
      case MessageActionCreateDecision(
          :final title,
          :final status,
          :final dueAtLocal,
        ):
        final todoId = 'todo:${message.id}';
        try {
          await backend.upsertTodo(
            sessionKey,
            id: todoId,
            title: title,
            dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
            status: status,
            sourceEntryId: message.id,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
          syncEngine?.notifyLocalMutation();
        } catch (_) {
          return;
        }

        if (!mounted) return;
        _refresh();

        final snackText = context.t.actions.todoAuto.created(title: title);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackText),
            action: SnackBarAction(
              label: context.t.common.actions.undo,
              onPressed: () async {
                try {
                  await backend.deleteTodo(sessionKey, todoId: todoId);
                  syncEngine?.notifyLocalMutation();
                } catch (_) {
                  return;
                }
                if (!mounted) return;
                _refresh();
              },
            ),
          ),
        );
        return;
      case MessageActionNoneDecision():
        break;
    }

    // Fallback: keep legacy prompts for non-auto cases.
    if (timeResolution != null || looksLikeReview) {
      if (!mounted) return;
      final decision = await showCaptureTodoSuggestionSheet(
        context,
        title: rawText.trim(),
        timeResolution: timeResolution,
      );
      if (decision == null || !mounted) return;

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
            syncEngine?.notifyLocalMutation();
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
            syncEngine?.notifyLocalMutation();
          } catch (_) {
            return;
          }
          break;
        case CaptureTodoNoThanksDecision():
          return;
      }

      if (!mounted) return;
      _refresh();
      return;
    }

    if (targets.isEmpty) return;

    final intent = inferTodoUpdateIntent(rawText);
    final ranked = _mergeTodoCandidatesWithSemanticMatches(
      query: rawText,
      targets: targets,
      nowLocal: nowLocal,
      semanticMatches: semanticMatches,
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
            backend: backend,
            sessionKey: sessionKey,
            query: rawText,
            targets: targets,
            nowLocal: nowLocal,
            ranked: ranked,
            defaultActionStatus: intent.newStatus,
            allowAsyncRerank: semanticTimedOut,
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
      syncEngine?.notifyLocalMutation();
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
              syncEngine?.notifyLocalMutation();
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

    final linkedTodoInfo = await _resolveLinkedTodoInfo(message);
    if (!mounted) return;
    final shouldMoveExisting =
        linkedTodoInfo != null && !linkedTodoInfo.isSourceEntry;

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
      if (shouldMoveExisting && linkedTodoInfo.todo.id != selected.id) {
        String? sourceActivityId;
        try {
          final activities = await backend.listTodoActivities(
              sessionKey, linkedTodoInfo.todo.id);
          for (final activity in activities) {
            if (activity.sourceMessageId == message.id) {
              sourceActivityId = activity.id;
              break;
            }
          }
        } catch (_) {
          sourceActivityId = null;
        }

        if (sourceActivityId != null) {
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
              final attachments = await attachmentsBackend
                  .listMessageAttachments(sessionKey, message.id);
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
                                    subtitle: Text(_todoStatusLabel(
                                      context,
                                      c.target.status,
                                    )),
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
    required AppBackend backend,
    required Uint8List sessionKey,
    required String query,
    required List<TodoLinkTarget> targets,
    required DateTime nowLocal,
    required List<TodoLinkCandidate> ranked,
    required String defaultActionStatus,
    required bool allowAsyncRerank,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final statusLabel = _todoStatusLabel(sheetContext, defaultActionStatus);
        final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
            SubscriptionStatus.unknown;
        final cloudAuthScope = CloudAuthScope.maybeOf(context);
        final cloudGatewayConfig =
            cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
        final showEnableCloudButton = !_cloudEmbeddingsConsented &&
            subscriptionStatus == SubscriptionStatus.entitled &&
            cloudAuthScope != null &&
            cloudGatewayConfig.baseUrl.trim().isNotEmpty;

        Future<List<TodoLinkCandidate>>? rerankFuture() {
          if (!allowAsyncRerank) return null;
          return _resolveTodoSemanticMatchesForSendFlow(
            backend,
            sessionKey,
            query: query,
            topK: 5,
          )
              .timeout(
            _kTodoLinkSheetRerankTimeout,
            onTimeout: () => const <TodoThreadMatch>[],
          )
              .then((matches) {
            if (matches.isEmpty) return ranked;
            return _mergeTodoCandidatesWithSemanticMatches(
              query: query,
              targets: targets,
              nowLocal: nowLocal,
              semanticMatches: matches,
              limit: 5,
            );
          });
        }

        Future<List<TodoLinkCandidate>?> rerankWithCloudEmbeddings() async {
          final matches = await _resolveTodoSemanticMatchesForSendFlow(
            backend,
            sessionKey,
            query: query,
            topK: 5,
            requireCloud: true,
          ).timeout(
            _kTodoLinkSheetRerankTimeout,
            onTimeout: () => const <TodoThreadMatch>[],
          );
          if (matches.isEmpty) return null;
          return _mergeTodoCandidatesWithSemanticMatches(
            query: query,
            targets: targets,
            nowLocal: nowLocal,
            semanticMatches: matches,
            limit: 5,
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _TodoLinkSheet(
              initialRanked: ranked,
              statusLabel: statusLabel,
              requestImprovedRanked: rerankFuture(),
              showEnableCloudButton: showEnableCloudButton,
              ensureCloudEmbeddingsConsented: () =>
                  _ensureEmbeddingsDataConsent(forceDialog: true),
              requestCloudRanked: rerankWithCloudEmbeddings,
              todoStatusLabel: (status) =>
                  _todoStatusLabel(sheetContext, status),
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

  static String _formatMessageTimestamp(BuildContext context, int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final alwaysUse24HourFormat = MediaQuery.of(context).alwaysUse24HourFormat;
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: alwaysUse24HourFormat,
    );
    return time;
  }

  static DateTime? _messageLocalDay(int ms) {
    if (ms <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateTime(dt.year, dt.month, dt.day);
  }

  static String _formatMessageDateDividerLabel(
    BuildContext context,
    DateTime dayLocal,
  ) {
    final localizations = MaterialLocalizations.of(context);
    final nowLocal = DateTime.now();
    if (dayLocal.year != nowLocal.year) {
      return localizations.formatMediumDate(dayLocal);
    }
    return localizations.formatShortMonthDay(dayLocal);
  }

  static Widget _buildMessageDateDividerChip(
    BuildContext context,
    DateTime dayLocal, {
    required Key key,
  }) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = _formatMessageDateDividerLabel(context, dayLocal);

    return Center(
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surface.withOpacity(isDark ? 0.72 : 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: tokens.borderSubtle.withOpacity(isDark ? 0.78 : 1),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(
                  isDark ? 0.9 : 0.82,
                ),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
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

    _askFailureTimer?.cancel();
    _askFailureTimer = null;

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

    final allowCloudEmbeddings = route == AskAiRouteKind.cloudGateway &&
        await _ensureEmbeddingsDataConsent();
    final hasBrokEmbeddings = route == AskAiRouteKind.byok &&
        await _hasActiveEmbeddingProfile(backend, sessionKey);
    const topK = 10;

    setState(() {
      _asking = true;
      _stopRequested = false;
      _askError = null;
      _askFailureMessage = null;
      _askFailureQuestion = null;
      _pendingQuestion = question;
      _streamingAnswer = '';
    });
    _controller.clear();

    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final firstDayOfWeekIndex =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final intent = AskAiIntentResolver.resolve(
      question,
      DateTime.now(),
      locale: locale,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );
    final timeRange = intent.timeRange;
    final timeStartMs = timeRange?.startLocal.toUtc().millisecondsSinceEpoch;
    final timeEndMs = timeRange?.endLocal.toUtc().millisecondsSinceEpoch;
    final hasTimeWindow = timeStartMs != null && timeEndMs != null;

    Stream<String> stream;
    switch (route) {
      case AskAiRouteKind.cloudGateway:
        if (allowCloudEmbeddings) {
          stream = hasTimeWindow
              ? backend.askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  timeStartMs: timeStartMs,
                  timeEndMs: timeEndMs,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                  embeddingsModelName: _kCloudEmbeddingsModelName,
                )
              : backend.askAiStreamCloudGatewayWithEmbeddings(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                  embeddingsModelName: _kCloudEmbeddingsModelName,
                );
        } else {
          stream = hasTimeWindow
              ? backend.askAiStreamCloudGatewayTimeWindow(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  timeStartMs: timeStartMs,
                  timeEndMs: timeEndMs,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                )
              : backend.askAiStreamCloudGateway(
                  sessionKey,
                  widget.conversation.id,
                  question: question,
                  topK: topK,
                  thisThreadOnly: _thisThreadOnly,
                  gatewayBaseUrl: cloudGatewayConfig.baseUrl,
                  idToken: cloudIdToken ?? '',
                  modelName: cloudGatewayConfig.modelName,
                );
        }
        break;
      case AskAiRouteKind.byok:
      case AskAiRouteKind.needsSetup:
        stream = hasBrokEmbeddings
            ? (hasTimeWindow
                ? backend.askAiStreamWithBrokEmbeddingsTimeWindow(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    timeStartMs: timeStartMs,
                    timeEndMs: timeEndMs,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStreamWithBrokEmbeddings(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  ))
            : (hasTimeWindow
                ? backend.askAiStreamTimeWindow(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    timeStartMs: timeStartMs,
                    timeEndMs: timeEndMs,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStream(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: topK,
                    thisThreadOnly: _thisThreadOnly,
                  ));
        break;
    }

    Future<void> startStream(Stream<String> stream,
        {required bool fromCloud}) async {
      late final StreamSubscription<String> sub;
      var sawError = false;

      Future<void> handleStreamError(Object e) async {
        try {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          sawError = true;

          if (!fromCloud) {
            final message =
                '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
            _showAskAiFailure(question, message: message);
            return;
          }

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
            if (!identical(_askSub, sub)) return;
            _showAskAiFailure(question);
            return;
          }

          final cloudStatus = fromCloud ? parseHttpStatusFromError(e) : null;

          bool hasByok;
          try {
            hasByok = await hasActiveLlmProfile(backend, sessionKey);
          } catch (_) {
            hasByok = false;
          }
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;

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
            if (!identical(_askSub, sub)) return;
            setState(() {
              _askError = null;
              _streamingAnswer = '';
            });

            final hasBrokEmbeddings =
                await _hasActiveEmbeddingProfile(backend, sessionKey);
            if (!mounted) return;
            if (!identical(_askSub, sub)) return;

            final byokStream = hasBrokEmbeddings
                ? backend.askAiStreamWithBrokEmbeddings(
                    sessionKey,
                    widget.conversation.id,
                    question: question,
                    topK: 10,
                    thisThreadOnly: _thisThreadOnly,
                  )
                : backend.askAiStream(
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
          if (!identical(_askSub, sub)) return;
          final message = fromCloud
              ? null
              : '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
          _showAskAiFailure(question, message: message);
        } catch (_) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          final message = fromCloud
              ? null
              : '${context.t.chat.askAiFailedTemporary}\n\n${e.toString()}';
          _showAskAiFailure(question, message: message);
        }
      }

      sub = stream.listen(
        (delta) {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          if (delta.startsWith(_kAskAiErrorPrefix)) {
            sawError = true;
            final errText = delta.substring(_kAskAiErrorPrefix.length).trim();
            unawaited(handleStreamError(errText));
            return;
          }
          setState(() => _streamingAnswer += delta);
        },
        onError: (e, st) {
          sawError = true;
          unawaited(
            () async {
              await handleStreamError(e);
            }(),
          );
        },
        onDone: () {
          if (!mounted) return;
          if (!identical(_askSub, sub)) return;
          if (sawError) {
            return;
          }
          if (_streamingAnswer.trim().isEmpty) {
            _showAskAiFailure(question);
            return;
          }
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
              scrollable: true,
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

  Future<bool> _ensureEmbeddingsDataConsent({bool forceDialog = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getBool(_kEmbeddingsDataConsentPrefsKey);
    if (existing == true) {
      _cloudEmbeddingsConsented = true;
      return true;
    }
    if (existing == false && !forceDialog) {
      _cloudEmbeddingsConsented = false;
      return false;
    }
    if (!mounted) return false;

    var dontShowAgain = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.t;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const ValueKey('embeddings_consent_dialog'),
              scrollable: true,
              title: Text(t.chat.embeddingsConsent.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.chat.embeddingsConsent.body),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('embeddings_consent_dont_show_again'),
                    contentPadding: EdgeInsets.zero,
                    value: dontShowAgain,
                    onChanged: (value) {
                      setState(() => dontShowAgain = value ?? true);
                    },
                    title: Text(t.chat.embeddingsConsent.dontShowAgain),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.chat.embeddingsConsent.actions.useLocal),
                ),
                FilledButton(
                  key: const ValueKey('embeddings_consent_continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.chat.embeddingsConsent.actions.enableCloud),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved != true) {
      await EmbeddingsDataConsentPrefs.setEnabled(prefs, false);
      _cloudEmbeddingsConsented = false;
      return false;
    }

    _cloudEmbeddingsConsented = true;
    await EmbeddingsDataConsentPrefs.setEnabled(prefs, true);
    return true;
  }

  Future<bool> _hasActiveEmbeddingProfile(
    AppBackend backend,
    Uint8List sessionKey,
  ) async {
    try {
      final profiles = await backend.listEmbeddingProfiles(sessionKey);
      return profiles.any((p) => p.isActive);
    } catch (_) {
      return false;
    }
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagesFuture ??= _loadMessages();
    _reviewCountFuture ??= _loadReviewQueueCount();
    _agendaFuture ??= _loadTodoAgendaSummary();
    _attachSyncEngine();
  }

  Widget _buildComposerInlineButton(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color backgroundColor,
    required Color foregroundColor,
    Color? borderColor,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPressed != null;

    final effectiveBackground =
        isEnabled ? backgroundColor : backgroundColor.withOpacity(0.52);
    final effectiveForeground =
        isEnabled ? foregroundColor : foregroundColor.withOpacity(0.62);

    final borderRadius = BorderRadius.circular(999);
    final borderSide =
        borderColor == null ? BorderSide.none : BorderSide(color: borderColor);

    return Semantics(
      key: key,
      button: true,
      label: label,
      child: Material(
        color: effectiveBackground,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: borderSide,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: effectiveForeground),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: textTheme.labelLarge?.copyWith(
                      color: effectiveForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    final isDesktopPlatform = _isDesktopPlatform;
    final useCompactComposer = !isDesktopPlatform;
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
          if (!isDesktopPlatform)
            IconButton(
              key: const ValueKey('chat_open_settings'),
              tooltip: context.t.app.tabs.settings,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(context.t.settings.title)),
                      body: const SettingsPage(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined),
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
                upcomingCount: summary.upcomingCount,
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
                    final isLoading =
                        snapshot.connectionState != ConnectionState.done;
                    final messages = _usePagination
                        ? _paginatedMessages
                        : snapshot.data ?? const <Message>[];
                    final pendingQuestion = _pendingQuestion;
                    final pendingFailureMessage = _askFailureMessage;
                    final hasPendingAssistant = (_asking && !_stopRequested) ||
                        pendingFailureMessage != null;
                    final pendingAssistantText = pendingFailureMessage ??
                        (_streamingAnswer.isEmpty ? '…' : _streamingAnswer);
                    final extraCount = (hasPendingAssistant ? 1 : 0) +
                        (pendingQuestion == null ? 0 : 1);
                    if (messages.isEmpty && extraCount == 0) {
                      if (isLoading) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            context.t.errors
                                .loadFailed(error: '${snapshot.error}'),
                          ),
                        );
                      }
                      return Center(
                        child: Text(context.t.chat.noMessagesYet),
                      );
                    }

                    final messageIndexById = <String, int>{};
                    for (var i = 0; i < messages.length; i++) {
                      messageIndexById[messages[i].id] = i;
                    }

                    return ListView.builder(
                      key: _usePagination
                          ? const ValueKey('chat_message_list')
                          : null,
                      controller: _usePagination ? _scrollController : null,
                      reverse: _usePagination,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey) return null;
                        final v = key.value;
                        if (v is! String) return null;
                        if (!v.startsWith('chat_message_row_')) return null;
                        final messageId =
                            v.substring('chat_message_row_'.length);

                        if (messageId == 'pending_assistant') {
                          if (!hasPendingAssistant) return null;
                          if (_usePagination) return 0;
                          return messages.length +
                              (pendingQuestion == null ? 0 : 1);
                        }

                        if (messageId == 'pending_user') {
                          if (pendingQuestion == null) return null;
                          if (_usePagination) {
                            return hasPendingAssistant ? 1 : 0;
                          }
                          return messages.length;
                        }

                        final messageIndex = messageIndexById[messageId];
                        if (messageIndex == null) return null;
                        return _usePagination
                            ? messageIndex + extraCount
                            : messageIndex;
                      },
                      itemCount: messages.length + extraCount,
                      itemBuilder: (context, index) {
                        final backend = AppBackendScope.of(context);
                        final attachmentsBackend = backend is AttachmentsBackend
                            ? backend as AttachmentsBackend
                            : null;
                        final sessionKey = SessionScope.of(context).sessionKey;

                        Message? messageAt(int targetIndex) {
                          if (_usePagination) {
                            if (targetIndex < extraCount) {
                              var extraIndex = targetIndex;
                              if (hasPendingAssistant) {
                                if (extraIndex == 0) {
                                  return Message(
                                    id: 'pending_assistant',
                                    conversationId: widget.conversation.id,
                                    role: 'assistant',
                                    content: '',
                                    createdAtMs: 0,
                                    isMemory: false,
                                  );
                                }
                                extraIndex -= 1;
                              }
                              if (pendingQuestion != null && extraIndex == 0) {
                                return Message(
                                  id: 'pending_user',
                                  conversationId: widget.conversation.id,
                                  role: 'user',
                                  content: pendingQuestion,
                                  createdAtMs: 0,
                                  isMemory: false,
                                );
                              }
                              return null;
                            }
                            final messageIndex = targetIndex - extraCount;
                            if (messageIndex < 0 ||
                                messageIndex >= messages.length) {
                              return null;
                            }
                            return messages[messageIndex];
                          }

                          if (targetIndex < messages.length) {
                            return messages[targetIndex];
                          }

                          var extraIndex = targetIndex - messages.length;
                          if (pendingQuestion != null) {
                            if (extraIndex == 0) {
                              return Message(
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
                          if (_asking && !_stopRequested && extraIndex == 0) {
                            return Message(
                              id: 'pending_assistant',
                              conversationId: widget.conversation.id,
                              role: 'assistant',
                              content: '',
                              createdAtMs: 0,
                              isMemory: false,
                            );
                          }
                          return null;
                        }

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
                                textOverride = pendingAssistantText;
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
                                hasPendingAssistant &&
                                extraIndex == 0) {
                              msg = Message(
                                id: 'pending_assistant',
                                conversationId: widget.conversation.id,
                                role: 'assistant',
                                content: '',
                                createdAtMs: 0,
                                isMemory: false,
                              );
                              textOverride = pendingAssistantText;
                            }
                          }
                        }

                        final stableMsg = msg;
                        if (stableMsg == null) {
                          return const SizedBox.shrink();
                        }

                        final itemCount = messages.length + extraCount;
                        final dayLocal =
                            _messageLocalDay(stableMsg.createdAtMs);
                        var showDateDivider = false;
                        if (dayLocal != null &&
                            !stableMsg.id.startsWith('pending_')) {
                          final step = _usePagination ? 1 : -1;
                          var neighborIndex = index + step;
                          DateTime? neighborDay;
                          while (
                              neighborIndex >= 0 && neighborIndex < itemCount) {
                            final neighborMsg = messageAt(neighborIndex);
                            if (neighborMsg == null) break;
                            final neighborDayLocal =
                                _messageLocalDay(neighborMsg.createdAtMs);
                            if (neighborDayLocal != null &&
                                !neighborMsg.id.startsWith('pending_')) {
                              neighborDay = neighborDayLocal;
                              break;
                            }
                            neighborIndex += step;
                          }
                          showDateDivider =
                              neighborDay == null || neighborDay != dayLocal;
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
                        final rawDisplayText =
                            assistantActions?.displayText ?? rawText;
                        final displayText =
                            _isPhotoPlaceholderText(context, rawDisplayText)
                                ? ''
                                : rawDisplayText;
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

                        final hasContentAboveAttachments =
                            displayText.trim().isNotEmpty ||
                                shouldCollapse ||
                                actionSuggestions.isNotEmpty ||
                                !stableMsg.isMemory;

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
                                onTap: shouldCollapse && !isDesktopPlatform
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
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(
                                          right: (!isPending &&
                                                  stableMsg.createdAtMs > 0)
                                              ? 54
                                              : 0,
                                          bottom: (!isPending &&
                                                  stableMsg.createdAtMs > 0)
                                              ? 16
                                              : 0,
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
                                                padding: const EdgeInsets.only(
                                                    bottom: 6),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .auto_awesome_rounded,
                                                      size: 14,
                                                      color:
                                                          colorScheme.secondary,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      context.t.common.actions
                                                          .askAi,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: colorScheme
                                                                .secondary,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (shouldCollapse)
                                              SizedBox(
                                                height:
                                                    _kCollapsedMessageHeight,
                                                child: ClipRect(
                                                  child: Stack(
                                                    children: [
                                                      ScrollConfiguration(
                                                        behavior:
                                                            ScrollConfiguration
                                                                    .of(context)
                                                                .copyWith(
                                                          scrollbars: false,
                                                          overscroll: false,
                                                        ),
                                                        child:
                                                            SingleChildScrollView(
                                                          physics:
                                                              const NeverScrollableScrollPhysics(),
                                                          child:
                                                              _buildMessageMarkdown(
                                                            displayText,
                                                            isDesktopPlatform:
                                                                isDesktopPlatform,
                                                          ),
                                                        ),
                                                      ),
                                                      Positioned(
                                                        left: 0,
                                                        right: 0,
                                                        bottom: 0,
                                                        height: 32,
                                                        child: DecoratedBox(
                                                          decoration:
                                                              BoxDecoration(
                                                            gradient:
                                                                LinearGradient(
                                                              begin: Alignment
                                                                  .topCenter,
                                                              end: Alignment
                                                                  .bottomCenter,
                                                              colors: [
                                                                bubbleColor
                                                                    .withOpacity(
                                                                        0),
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
                                              displayText.trim().isEmpty
                                                  ? const SizedBox.shrink()
                                                  : _buildMessageMarkdown(
                                                      displayText,
                                                      isDesktopPlatform:
                                                          isDesktopPlatform,
                                                    ),
                                            if (shouldCollapse)
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: TextButton(
                                                  key: ValueKey(
                                                    'message_view_full_${stableMsg.id}',
                                                  ),
                                                  onPressed: () => unawaited(
                                                    _openMessageViewer(
                                                        displayText),
                                                  ),
                                                  child: Text(
                                                      context.t.chat.viewFull),
                                                ),
                                              ),
                                            if (actionSuggestions.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    for (var i = 0;
                                                        i <
                                                            actionSuggestions
                                                                .length;
                                                        i++)
                                                      SlButton(
                                                        variant: SlButtonVariant
                                                            .outline,
                                                        onPressed: () =>
                                                            _handleAssistantSuggestion(
                                                          stableMsg,
                                                          actionSuggestions[i],
                                                          i,
                                                        ),
                                                        icon: Icon(
                                                          actionSuggestions[i]
                                                                      .type ==
                                                                  'event'
                                                              ? Icons
                                                                  .event_rounded
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
                                                              : actionSuggestions[
                                                                      i]
                                                                  .title,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            if (supportsAttachments)
                                              FutureBuilder(
                                                initialData:
                                                    _attachmentsCacheByMessageId[
                                                        stableMsg.id],
                                                future:
                                                    _attachmentsFuturesByMessageId
                                                        .putIfAbsent(
                                                  stableMsg.id,
                                                  () => attachmentsBackend
                                                      .listMessageAttachments(
                                                    sessionKey,
                                                    stableMsg.id,
                                                  )
                                                      .then((items) {
                                                    _attachmentsCacheByMessageId[
                                                        stableMsg.id] = items;
                                                    return items;
                                                  }),
                                                ),
                                                builder: (context, snapshot) {
                                                  final items = snapshot.data ??
                                                      const <Attachment>[];
                                                  if (items.isEmpty) {
                                                    return const SizedBox
                                                        .shrink();
                                                  }

                                                  return Padding(
                                                    padding: EdgeInsets.only(
                                                      top:
                                                          hasContentAboveAttachments
                                                              ? 8
                                                              : 0,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        SingleChildScrollView(
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
                                                                  child: attachment
                                                                          .mimeType
                                                                          .startsWith(
                                                                              'image/')
                                                                      ? ChatImageAttachmentThumbnail(
                                                                          key:
                                                                              ValueKey(
                                                                            'chat_attachment_image_${attachment.sha256}',
                                                                          ),
                                                                          attachment:
                                                                              attachment,
                                                                          attachmentsBackend:
                                                                              attachmentsBackend,
                                                                          onTap:
                                                                              () {
                                                                            Navigator.of(context).push(
                                                                              MaterialPageRoute(
                                                                                builder: (context) {
                                                                                  return AttachmentViewerPage(
                                                                                    attachment: attachment,
                                                                                  );
                                                                                },
                                                                              ),
                                                                            );
                                                                          },
                                                                        )
                                                                      : AttachmentCard(
                                                                          attachment:
                                                                              attachment,
                                                                          onTap:
                                                                              () {
                                                                            Navigator.of(context).push(
                                                                              MaterialPageRoute(
                                                                                builder: (context) {
                                                                                  return AttachmentViewerPage(
                                                                                    attachment: attachment,
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
                                                        Builder(
                                                          builder: (context) {
                                                            String?
                                                                firstImageSha256;
                                                            for (final a
                                                                in items) {
                                                              if (a.mimeType
                                                                  .startsWith(
                                                                      'image/')) {
                                                                firstImageSha256 =
                                                                    a.sha256;
                                                                break;
                                                              }
                                                            }
                                                            final sha256 =
                                                                firstImageSha256;
                                                            if (sha256 ==
                                                                null) {
                                                              return const SizedBox
                                                                  .shrink();
                                                            }

                                                            return FutureBuilder(
                                                              initialData:
                                                                  _attachmentEnrichmentCacheBySha256[
                                                                      sha256],
                                                              future:
                                                                  _attachmentEnrichmentFuturesBySha256
                                                                      .putIfAbsent(
                                                                sha256,
                                                                () =>
                                                                    _loadAttachmentEnrichment(
                                                                  attachmentsBackend,
                                                                  sessionKey,
                                                                  sha256,
                                                                ).then((value) {
                                                                  _attachmentEnrichmentCacheBySha256[
                                                                          sha256] =
                                                                      value;
                                                                  return value;
                                                                }),
                                                              ),
                                                              builder: (context,
                                                                  snapshot) {
                                                                final enrichment =
                                                                    snapshot
                                                                        .data;
                                                                final place =
                                                                    enrichment
                                                                        ?.placeDisplayName
                                                                        ?.trim();
                                                                final caption =
                                                                    enrichment
                                                                        ?.captionLong
                                                                        ?.trim();

                                                                final hasPlace =
                                                                    place !=
                                                                            null &&
                                                                        place
                                                                            .isNotEmpty;
                                                                final hasCaption =
                                                                    caption !=
                                                                            null &&
                                                                        caption
                                                                            .isNotEmpty;
                                                                if (!hasPlace &&
                                                                    !hasCaption) {
                                                                  return const SizedBox
                                                                      .shrink();
                                                                }

                                                                final textStyle = Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall
                                                                    ?.copyWith(
                                                                      color: isUser
                                                                          ? colorScheme.onPrimaryContainer.withOpacity(
                                                                              0.78)
                                                                          : colorScheme
                                                                              .onSurfaceVariant
                                                                              .withOpacity(0.86),
                                                                    );

                                                                return Padding(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .only(
                                                                    top: 6,
                                                                  ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      if (hasPlace)
                                                                        Text(
                                                                          place,
                                                                          key:
                                                                              ValueKey(
                                                                            'chat_image_enrichment_location_$sha256',
                                                                          ),
                                                                          maxLines:
                                                                              1,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style:
                                                                              textStyle,
                                                                        ),
                                                                      if (hasPlace &&
                                                                          hasCaption)
                                                                        const SizedBox(
                                                                            height:
                                                                                2),
                                                                      if (hasCaption)
                                                                        Text(
                                                                          caption,
                                                                          key:
                                                                              ValueKey(
                                                                            'chat_image_enrichment_caption_$sha256',
                                                                          ),
                                                                          maxLines:
                                                                              2,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style:
                                                                              textStyle,
                                                                        ),
                                                                    ],
                                                                  ),
                                                                );
                                                              },
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
                                      if (!isPending &&
                                          stableMsg.createdAtMs > 0)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Text(
                                            _formatMessageTimestamp(
                                              context,
                                              stableMsg.createdAtMs,
                                            ),
                                            key: ValueKey(
                                              'message_timestamp_${stableMsg.id}',
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: isUser
                                                      ? colorScheme
                                                          .onPrimaryContainer
                                                          .withOpacity(0.62)
                                                      : colorScheme
                                                          .onSurfaceVariant
                                                          .withOpacity(0.78),
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );

                        return Padding(
                          key: ValueKey('chat_message_row_${stableMsg.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDateDivider && dayLocal != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: _buildMessageDateDividerChip(
                                    context,
                                    dayLocal,
                                    key: ValueKey(
                                      'message_date_divider_${stableMsg.id}',
                                    ),
                                  ),
                                ),
                              MouseRegion(
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
                                          if (_hoveredMessageId ==
                                              stableMsg.id) {
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
                            ],
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
                  child: useCompactComposer
                      ? SlFocusRing(
                          key: const ValueKey('chat_input_ring'),
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          child: SlSurface(
                            color: tokens.surface2,
                            borderColor: tokens.borderSubtle,
                            borderRadius:
                                BorderRadius.circular(tokens.radiusLg),
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (_supportsImageUpload) ...[
                                  SlIconButton(
                                    key: const ValueKey('chat_attach'),
                                    icon: Icons.add_rounded,
                                    size: 44,
                                    iconSize: 22,
                                    tooltip: context.t.chat.attachTooltip,
                                    onPressed: (_sending || _asking)
                                        ? null
                                        : _openAttachmentSheet,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Focus(
                                    // ignore: deprecated_member_use
                                    onKey: (node, event) {
                                      // ignore: deprecated_member_use
                                      if (event is! RawKeyDownEvent) {
                                        return KeyEventResult.ignored;
                                      }

                                      final key = event.logicalKey;
                                      bool isShortcutChar(String char) =>
                                          char == 'a' ||
                                          char == 'c' ||
                                          char == 'v' ||
                                          char == 'x';

                                      String? keyChar;
                                      final keyLabel = event.data.keyLabel;
                                      if (keyLabel.length == 1) {
                                        final lowered = keyLabel.toLowerCase();
                                        if (isShortcutChar(lowered)) {
                                          keyChar = lowered;
                                        }
                                      }
                                      if (keyChar == null) {
                                        final rawChar = event.character;
                                        if (rawChar != null &&
                                            rawChar.length == 1) {
                                          final lowered = rawChar.toLowerCase();
                                          if (isShortcutChar(lowered)) {
                                            keyChar = lowered;
                                          }
                                        }
                                      }
                                      final composing =
                                          _controller.value.composing;
                                      final isComposing = composing.isValid &&
                                          !composing.isCollapsed;

                                      final hardware =
                                          HardwareKeyboard.instance;
                                      final metaPressed =
                                          hardware.isMetaPressed;
                                      final controlPressed =
                                          hardware.isControlPressed;
                                      final shiftPressed =
                                          hardware.isShiftPressed;
                                      final hasModifier =
                                          metaPressed || controlPressed;

                                      final isPaste =
                                          key == LogicalKeyboardKey.paste ||
                                              ((keyChar == 'v' ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .keyV) &&
                                                  hasModifier);
                                      if (isPaste) {
                                        unawaited(_pasteIntoChatInput());
                                        return KeyEventResult.handled;
                                      }

                                      final isSelectAll = hasModifier &&
                                          (keyChar == 'a' ||
                                              (keyChar == null &&
                                                  key ==
                                                      LogicalKeyboardKey.keyA));
                                      if (isSelectAll) {
                                        final textLength =
                                            _controller.value.text.length;
                                        _controller.selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: textLength,
                                        );
                                        return KeyEventResult.handled;
                                      }

                                      final isCopy = (key ==
                                                  LogicalKeyboardKey.copy ||
                                              keyChar == 'c' ||
                                              key == LogicalKeyboardKey.keyC) &&
                                          hasModifier;
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
                                          final selectedText =
                                              value.text.substring(
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

                                      final isCut = (key ==
                                                  LogicalKeyboardKey.cut ||
                                              keyChar == 'x' ||
                                              key == LogicalKeyboardKey.keyX) &&
                                          hasModifier;
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
                                          final selectedText =
                                              value.text.substring(
                                            normalizedStart,
                                            normalizedEnd,
                                          );
                                          unawaited(
                                            Clipboard.setData(
                                              ClipboardData(text: selectedText),
                                            ),
                                          );
                                          final updatedText =
                                              value.text.replaceRange(
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
                                          key !=
                                              LogicalKeyboardKey.numpadEnter) {
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
                                        final updatedText =
                                            value.text.replaceRange(
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
                                        hintText:
                                            context.t.common.fields.message,
                                        border: InputBorder.none,
                                        filled: false,
                                        isDense: true,
                                      ),
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.newline,
                                      minLines: 1,
                                      maxLines: 6,
                                    ),
                                  ),
                                ),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _controller,
                                  builder: (context, value, child) {
                                    final hasText =
                                        value.text.trim().isNotEmpty;

                                    if (_asking) {
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _buildComposerInlineButton(
                                          context,
                                          key: const ValueKey('chat_stop'),
                                          label: _stopRequested
                                              ? context
                                                  .t.common.actions.stopping
                                              : context.t.common.actions.stop,
                                          icon: Icons.stop_circle_outlined,
                                          onPressed:
                                              _stopRequested ? null : _stopAsk,
                                          backgroundColor: Colors.transparent,
                                          foregroundColor:
                                              colorScheme.onSurface,
                                          borderColor: tokens.borderSubtle,
                                        ),
                                      );
                                    }

                                    if (!hasText) {
                                      return const SizedBox.shrink();
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildComposerInlineButton(
                                            context,
                                            key: const ValueKey('chat_ask_ai'),
                                            label:
                                                context.t.common.actions.askAi,
                                            icon: Icons.auto_awesome_rounded,
                                            onPressed: (_sending || _asking)
                                                ? null
                                                : _askAi,
                                            backgroundColor:
                                                colorScheme.secondaryContainer,
                                            foregroundColor: colorScheme
                                                .onSecondaryContainer,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildComposerInlineButton(
                                            context,
                                            key: const ValueKey('chat_send'),
                                            label:
                                                context.t.common.actions.send,
                                            icon: Icons.send_rounded,
                                            onPressed: (_sending || _asking)
                                                ? null
                                                : _send,
                                            backgroundColor:
                                                colorScheme.primary,
                                            foregroundColor:
                                                colorScheme.onPrimary,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      : SlFocusRing(
                          key: const ValueKey('chat_input_ring'),
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          child: SlSurface(
                            color: tokens.surface2,
                            borderColor: tokens.borderSubtle,
                            borderRadius:
                                BorderRadius.circular(tokens.radiusLg),
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
                                      bool isShortcutChar(String char) =>
                                          char == 'a' ||
                                          char == 'c' ||
                                          char == 'v' ||
                                          char == 'x';

                                      String? keyChar;
                                      final keyLabel = event.data.keyLabel;
                                      if (keyLabel.length == 1) {
                                        final lowered = keyLabel.toLowerCase();
                                        if (isShortcutChar(lowered)) {
                                          keyChar = lowered;
                                        }
                                      }
                                      if (keyChar == null) {
                                        final rawChar = event.character;
                                        if (rawChar != null &&
                                            rawChar.length == 1) {
                                          final lowered = rawChar.toLowerCase();
                                          if (isShortcutChar(lowered)) {
                                            keyChar = lowered;
                                          }
                                        }
                                      }
                                      final composing =
                                          _controller.value.composing;
                                      final isComposing = composing.isValid &&
                                          !composing.isCollapsed;

                                      final hardware =
                                          HardwareKeyboard.instance;
                                      final metaPressed =
                                          hardware.isMetaPressed;
                                      final controlPressed =
                                          hardware.isControlPressed;
                                      final shiftPressed =
                                          hardware.isShiftPressed;
                                      final hasModifier =
                                          metaPressed || controlPressed;

                                      final isPaste =
                                          key == LogicalKeyboardKey.paste ||
                                              ((keyChar == 'v' ||
                                                      key ==
                                                          LogicalKeyboardKey
                                                              .keyV) &&
                                                  hasModifier);
                                      if (isPaste) {
                                        unawaited(_pasteIntoChatInput());
                                        return KeyEventResult.handled;
                                      }

                                      final isSelectAll = hasModifier &&
                                          (keyChar == 'a' ||
                                              (keyChar == null &&
                                                  key ==
                                                      LogicalKeyboardKey.keyA));
                                      if (isSelectAll) {
                                        final textLength =
                                            _controller.value.text.length;
                                        _controller.selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: textLength,
                                        );
                                        return KeyEventResult.handled;
                                      }

                                      final isCopy = (key ==
                                                  LogicalKeyboardKey.copy ||
                                              keyChar == 'c' ||
                                              key == LogicalKeyboardKey.keyC) &&
                                          hasModifier;
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
                                          final selectedText =
                                              value.text.substring(
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

                                      final isCut = (key ==
                                                  LogicalKeyboardKey.cut ||
                                              keyChar == 'x' ||
                                              key == LogicalKeyboardKey.keyX) &&
                                          hasModifier;
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
                                          final selectedText =
                                              value.text.substring(
                                            normalizedStart,
                                            normalizedEnd,
                                          );
                                          unawaited(
                                            Clipboard.setData(
                                              ClipboardData(text: selectedText),
                                            ),
                                          );
                                          final updatedText =
                                              value.text.replaceRange(
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
                                          key !=
                                              LogicalKeyboardKey.numpadEnter) {
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
                                        final updatedText =
                                            value.text.replaceRange(
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
                                        hintText:
                                            context.t.common.fields.message,
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
                                if (_supportsImageUpload) ...[
                                  Semantics(
                                    label: context.t.chat.attachTooltip,
                                    button: true,
                                    child: SlIconButton(
                                      key: const ValueKey('chat_attach'),
                                      icon: Icons.add_rounded,
                                      size: 44,
                                      iconSize: 22,
                                      tooltip: context.t.chat.attachTooltip,
                                      onPressed: (_sending || _asking)
                                          ? null
                                          : _openAttachmentSheet,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _controller,
                                  builder: (context, value, child) {
                                    final hasText =
                                        value.text.trim().isNotEmpty;

                                    if (_asking) {
                                      return SlButton(
                                        buttonKey: const ValueKey('chat_stop'),
                                        icon: const Icon(
                                          Icons.stop_circle_outlined,
                                          size: 18,
                                        ),
                                        variant: SlButtonVariant.outline,
                                        onPressed:
                                            _stopRequested ? null : _stopAsk,
                                        child: Text(
                                          _stopRequested
                                              ? context
                                                  .t.common.actions.stopping
                                              : context.t.common.actions.stop,
                                        ),
                                      );
                                    }

                                    if (!hasText) {
                                      return const SizedBox.shrink();
                                    }

                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SlButton(
                                          buttonKey:
                                              const ValueKey('chat_ask_ai'),
                                          icon: const Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 18,
                                          ),
                                          variant: SlButtonVariant.secondary,
                                          onPressed: (_sending || _asking)
                                              ? null
                                              : _askAi,
                                          child: Text(
                                            context.t.common.actions.askAi,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SlButton(
                                          buttonKey:
                                              const ValueKey('chat_send'),
                                          icon: const Icon(
                                            Icons.send_rounded,
                                            size: 18,
                                          ),
                                          variant: SlButtonVariant.primary,
                                          onPressed: (_sending || _asking)
                                              ? null
                                              : _send,
                                          child: Text(
                                            context.t.common.actions.send,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
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

final class _TodoLinkSheet extends StatefulWidget {
  const _TodoLinkSheet({
    required this.initialRanked,
    required this.statusLabel,
    required this.todoStatusLabel,
    required this.showEnableCloudButton,
    this.requestImprovedRanked,
    this.ensureCloudEmbeddingsConsented,
    this.requestCloudRanked,
  });

  final List<TodoLinkCandidate> initialRanked;
  final String statusLabel;
  final String Function(String status) todoStatusLabel;
  final bool showEnableCloudButton;
  final Future<List<TodoLinkCandidate>>? requestImprovedRanked;
  final Future<bool> Function()? ensureCloudEmbeddingsConsented;
  final Future<List<TodoLinkCandidate>?> Function()? requestCloudRanked;

  @override
  State<_TodoLinkSheet> createState() => _TodoLinkSheetState();
}

final class _TodoLinkSheetState extends State<_TodoLinkSheet> {
  late List<TodoLinkCandidate> _ranked;
  bool _improving = false;
  late bool _showEnableCloudButton;

  @override
  void initState() {
    super.initState();
    _ranked = widget.initialRanked;
    _showEnableCloudButton = widget.showEnableCloudButton;

    final future = widget.requestImprovedRanked;
    if (future != null) {
      _improving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        List<TodoLinkCandidate> improved = _ranked;
        try {
          improved = await future;
        } catch (_) {
          improved = _ranked;
        }
        if (!mounted) return;
        setState(() {
          _ranked = improved;
          _improving = false;
        });
      });
    }
  }

  Future<void> _enableCloudEmbeddings() async {
    final ensureConsent = widget.ensureCloudEmbeddingsConsented;
    final requestCloudRanked = widget.requestCloudRanked;
    if (ensureConsent == null || requestCloudRanked == null) return;

    final consented = await ensureConsent();
    if (!consented || !mounted) return;

    setState(() {
      _showEnableCloudButton = false;
      _improving = true;
    });

    List<TodoLinkCandidate>? improved;
    try {
      improved = await requestCloudRanked();
    } catch (_) {
      improved = null;
    }
    if (!mounted) return;

    setState(() {
      if (improved != null) {
        _ranked = improved;
      }
      _improving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlSurface(
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
          Text(context.t.actions.todoLink.subtitle(status: widget.statusLabel)),
          if (_showEnableCloudButton) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('todo_link_sheet_enable_cloud'),
              onPressed: _improving ? null : _enableCloudEmbeddings,
              child: Text(context.t.chat.embeddingsConsent.actions.enableCloud),
            ),
          ],
          if (_improving) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  context.t.settings.byokUsage.loading,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _ranked.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final c = _ranked[index];
                return ListTile(
                  title: Text(c.target.title),
                  subtitle: Text(widget.todoStatusLabel(c.target.status)),
                  onTap: () => Navigator.of(context).pop(c.target.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _AttachmentEnrichment {
  const _AttachmentEnrichment({
    required this.placeDisplayName,
    required this.captionLong,
  });

  final String? placeDisplayName;
  final String? captionLong;
}

final class _TodoAgendaSummary {
  const _TodoAgendaSummary({
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.previewTodos,
  });

  const _TodoAgendaSummary.empty()
      : dueCount = 0,
        overdueCount = 0,
        upcomingCount = 0,
        previewTodos = const <Todo>[];

  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final List<Todo> previewTodos;
}

enum _MessageAction {
  copy,
  convertTodo,
  convertTodoToInfo,
  openTodo,
  edit,
  linkTodo,
  delete,
}

enum _AskAiSetupAction {
  subscribe,
  configureByok,
}
