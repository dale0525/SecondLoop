import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/backend/attachments_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_focus_ring.dart';
import '../../../ui/sl_icon_button.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';
import '../../attachments/attachment_card.dart';
import '../../attachments/attachment_viewer_page.dart';
import '../time/date_time_picker_dialog.dart';

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
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByMessageId =
      <String, Future<List<Attachment>>>{};
  final Map<String, Future<List<Attachment>>> _attachmentsFuturesByActivityId =
      <String, Future<List<Attachment>>>{};
  final List<Attachment> _pendingAttachments = <Attachment>[];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activitiesFuture ??= _loadActivities();
  }

  Future<List<TodoActivity>> _loadActivities() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return backend.listTodoActivities(sessionKey, _todo.id);
  }

  void _refreshActivities() {
    setState(() {
      _activitiesFuture = _loadActivities();
      _attachmentsFuturesByMessageId.clear();
      _attachmentsFuturesByActivityId.clear();
    });
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

  Future<void> _appendNote() async {
    final text = _noteController.text.trim();
    final pending = List<Attachment>.from(_pendingAttachments);
    if (text.isEmpty && pending.isEmpty) return;
    _noteController.clear();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final content = text.isNotEmpty
        ? text
        : context.t.actions.todoDetail.attachmentNoteDefault;
    final activity = await backend.appendTodoNote(
      sessionKey,
      todoId: _todo.id,
      content: content,
    );
    for (final attachment in pending) {
      await backend.linkAttachmentToTodoActivity(
        sessionKey,
        activityId: activity.id,
        attachmentSha256: attachment.sha256,
      );
    }
    if (!mounted) return;
    setState(_pendingAttachments.clear);
    _refreshActivities();
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
    final isMarkdown = activity.activityType == 'note' ||
        activity.activityType == 'summary' ||
        (activity.activityType != 'status_change' && title.contains('\n'));

    final icon = switch (activity.activityType) {
      'note' => Icons.notes_rounded,
      'summary' => Icons.auto_awesome_rounded,
      'status_change' => Icons.sync_rounded,
      _ => Icons.bolt_rounded,
    };

    return SlSurface(
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
              child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMarkdown)
                  MarkdownBody(
                    data: title,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyLarge,
                    ),
                  )
                else
                  Text(title, style: theme.textTheme.bodyLarge),
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
                      final attachments = snapshot.data ?? const <Attachment>[];
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _todo.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _TodoStatusButton(
                            label: _statusLabel(context, _todo.status),
                            onPressed: () => unawaited(
                              _setStatus(_nextStatusForTap(_todo.status)),
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
                            onPressed: () => unawaited(_setStatus('dismissed')),
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

                    final activities = snapshot.data ?? const <TodoActivity>[];
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
