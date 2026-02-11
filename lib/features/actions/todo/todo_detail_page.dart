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
import '../../../ui/sl_delete_confirm_dialog.dart';
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

part 'todo_detail_page_message_actions.dart';

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
  static const List<String> _kSelectableStatuses = <String>[
    'open',
    'in_progress',
    'done',
  ];

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
    final confirmed = await showSlDeleteConfirmDialog(
      context,
      title: t.actions.todoDelete.dialog.title,
      message: t.actions.todoDelete.dialog.message,
      confirmLabel: t.actions.todoDelete.dialog.confirm,
      confirmButtonKey: const ValueKey('todo_delete_confirm'),
    );
    if (!mounted) return;
    if (!confirmed) return;

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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _TodoStatusSelector(
                              statuses: _kSelectableStatuses,
                              selectedStatus: _todo.status,
                              statusLabelBuilder: (status) =>
                                  _statusLabel(context, status),
                              buttonKeyBuilder: (status) =>
                                  ValueKey('todo_detail_set_status_$status'),
                              onSelected: (status) =>
                                  unawaited(_setStatus(status)),
                            ),
                          ),
                          const SizedBox(width: 8),
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
    required this.selected,
    this.buttonKey,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      final base = selected ? colorScheme.primary : colorScheme.onSurface;
      if (states.contains(MaterialState.pressed)) {
        return base.withOpacity(0.16);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return base.withOpacity(0.1);
      }
      return null;
    });

    final foreground =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final border = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.58 : 0.4,
          )
        : tokens.borderSubtle;
    final background = selected
        ? colorScheme.primary.withOpacity(
            theme.brightness == Brightness.dark ? 0.2 : 0.08,
          )
        : tokens.surface2;

    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        side: BorderSide(color: border),
      ).copyWith(overlayColor: overlay),
      icon: Icon(
        selected ? Icons.check_rounded : Icons.circle_outlined,
        size: 16,
        color: foreground,
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

final class _TodoStatusSelector extends StatelessWidget {
  const _TodoStatusSelector({
    required this.statuses,
    required this.selectedStatus,
    required this.statusLabelBuilder,
    required this.onSelected,
    this.buttonKeyBuilder,
  });

  final List<String> statuses;
  final String selectedStatus;
  final String Function(String status) statusLabelBuilder;
  final ValueChanged<String> onSelected;
  final Key? Function(String status)? buttonKeyBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in statuses)
          _TodoStatusButton(
            buttonKey: buttonKeyBuilder?.call(status),
            label: statusLabelBuilder(status),
            selected: status == selectedStatus,
            onPressed: () {
              if (status == selectedStatus) return;
              onSelected(status);
            },
          ),
      ],
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
