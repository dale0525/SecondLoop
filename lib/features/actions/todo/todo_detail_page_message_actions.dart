part of 'todo_detail_page.dart';

extension _TodoDetailPageStateMessageActions on _TodoDetailPageState {
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

    try {
      final initialMode = shouldUseMarkdownEditorByDefault(message.content)
          ? ChatEditorMode.markdown
          : ChatEditorMode.plain;
      final newContent = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => ChatMarkdownEditorPage(
            initialText: message.content,
            title: context.t.chat.editMessageTitle,
            saveLabel: context.t.common.actions.save,
            inputFieldKey: const ValueKey('edit_message_content'),
            saveButtonKey: const ValueKey('edit_message_save'),
            allowPlainMode: true,
            initialMode: initialMode,
          ),
        ),
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
        final confirmed = await showSlDeleteConfirmDialog(
          context,
          title: t.actions.todoDelete.dialog.title,
          message: t.actions.todoDelete.dialog.message,
          confirmLabel: t.actions.todoDelete.dialog.confirm,
          confirmButtonKey: const ValueKey('chat_delete_todo_confirm'),
        );
        if (!mounted) return;
        if (!confirmed) return;

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

      final confirmed = await showSlDeleteConfirmDialog(
        context,
        title: t.chat.deleteMessageDialog.title,
        message: t.chat.deleteMessageDialog.message,
        confirmButtonKey: const ValueKey('todo_detail_delete_message_confirm'),
      );
      if (!mounted) return;
      if (!confirmed) return;

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
}
