import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../core/backend/attachments_backend.dart';
import '../../../core/session/session_scope.dart';
import '../../../i18n/strings.g.dart';
import '../../../src/rust/db.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';
import '../../attachments/attachment_card.dart';
import '../../attachments/attachment_viewer_page.dart';

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
    if (text.isEmpty) return;
    _noteController.clear();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    await backend.appendTodoNote(
      sessionKey,
      todoId: _todo.id,
      content: text,
    );
    if (!mounted) return;
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

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 6),
          Text(
            timeText,
            style: theme.textTheme.bodySmall,
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
                              builder: (_) =>
                                  AttachmentViewerPage(attachment: attachment),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _todo.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SlButton(
                            variant: SlButtonVariant.outline,
                            onPressed: () => unawaited(
                              _setStatus(_nextStatusForTap(_todo.status)),
                            ),
                            child: Text(_statusLabel(context, _todo.status)),
                          ),
                          SlButton(
                            variant: SlButtonVariant.outline,
                            onPressed: () => unawaited(_setStatus('dismissed')),
                            child: Text(context.t.actions.todoStatus.dismissed),
                          ),
                        ],
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
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: context.t.actions.todoDetail.noteHint,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => unawaited(_appendNote()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SlButton(
                      onPressed: () => unawaited(_appendNote()),
                      child: Text(context.t.actions.todoDetail.addNote),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
