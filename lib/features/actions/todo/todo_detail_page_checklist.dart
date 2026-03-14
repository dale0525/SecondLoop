part of 'todo_detail_page.dart';

final class _TodoChecklistEditDialog extends StatefulWidget {
  const _TodoChecklistEditDialog({required this.initialContent});

  final String initialContent;

  @override
  State<_TodoChecklistEditDialog> createState() =>
      _TodoChecklistEditDialogState();
}

final class _TodoChecklistEditDialogState
    extends State<_TodoChecklistEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialContent);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('todo_detail_checklist_edit_dialog'),
      title: Text(context.t.actions.todoDetail.checklistEditTitle),
      content: TextField(
        key: const ValueKey('todo_detail_checklist_edit_input'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: context.t.actions.todoDetail.checklistHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.actions.cancel),
        ),
        FilledButton(
          key: const ValueKey('todo_detail_checklist_edit_save'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.t.common.actions.save),
        ),
      ],
    );
  }
}

extension _TodoDetailPageStateChecklist on _TodoDetailPageState {
  Future<bool> _confirmDoneWithIncompleteChecklist() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null) return true;

    List<TodoChecklistItem> items;
    try {
      items =
          await backend.listTodoChecklistItems(session.sessionKey, _todo.id);
    } catch (_) {
      return true;
    }
    final hasIncomplete = items.any((item) => !item.isDone);
    if (!hasIncomplete) return true;
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('todo_detail_incomplete_checklist_dialog'),
        title: Text(context.t.actions.todoDetail.incompleteChecklistDoneTitle),
        content:
            Text(context.t.actions.todoDetail.incompleteChecklistDoneMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t.common.actions.cancel),
          ),
          FilledButton(
            key: const ValueKey('todo_detail_incomplete_checklist_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t.common.actions.continueLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  void _refreshChecklistItems() {
    if (!mounted) return;
    _setState(() {
      _checklistFuture = _loadChecklistItems();
    });
  }

  void _showChecklistMutationError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.errors.loadFailed(error: '$error')),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _addChecklistItem() async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    final content = _checklistController.text.trim();
    if (backend == null ||
        session == null ||
        content.isEmpty ||
        _creatingChecklistItem) {
      return;
    }

    _setState(() => _creatingChecklistItem = true);
    try {
      await backend.createTodoChecklistItem(
        session.sessionKey,
        todoId: _todo.id,
        content: content,
      );
      if (mounted) _checklistController.clear();
      _refreshChecklistItems();
    } catch (error) {
      _showChecklistMutationError(error);
    } finally {
      if (mounted) {
        _setState(() => _creatingChecklistItem = false);
      }
    }
  }

  Future<void> _toggleChecklistItem(
    TodoChecklistItem item,
    bool nextValue,
  ) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null) return;

    try {
      await backend.setTodoChecklistItemDone(
        session.sessionKey,
        itemId: item.id,
        isDone: nextValue,
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    _refreshChecklistItems();
  }

  Future<void> _editChecklistItem(TodoChecklistItem item) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null) return;

    final nextContent = await showDialog<String>(
      context: context,
      builder: (context) => _TodoChecklistEditDialog(
        initialContent: item.content,
      ),
    );
    final trimmed = nextContent?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == item.content) return;
    try {
      await backend.updateTodoChecklistItemContent(
        session.sessionKey,
        itemId: item.id,
        content: trimmed,
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    _refreshChecklistItems();
  }

  Future<void> _deleteChecklistItem(TodoChecklistItem item) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null) return;

    try {
      await backend.deleteTodoChecklistItem(
        session.sessionKey,
        itemId: item.id,
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    _refreshChecklistItems();
    if (mounted) {
      _setState(() {
        _checklistSuggestionsFuture = _loadChecklistSuggestions();
      });
    }
  }

  Future<void> _moveChecklistItem(
    List<TodoChecklistItem> items,
    TodoChecklistItem item,
    int delta,
  ) async {
    final backend = AppBackendScope.maybeOf(context);
    final session = SessionScope.maybeOf(context);
    if (backend == null || session == null || items.length < 2) return;

    final currentIndex = items.indexWhere((entry) => entry.id == item.id);
    if (currentIndex == -1) return;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= items.length) return;

    final reordered = List<TodoChecklistItem>.from(items);
    final moving = reordered.removeAt(currentIndex);
    reordered.insert(nextIndex, moving);
    try {
      await backend.reorderTodoChecklistItems(
        session.sessionKey,
        todoId: _todo.id,
        orderedItemIds:
            reordered.map((entry) => entry.id).toList(growable: false),
      );
    } catch (error) {
      _showChecklistMutationError(error);
      return;
    }
    _refreshChecklistItems();
  }

  Widget _buildChecklistSection(BuildContext context) {
    final tokens = SlTokens.of(context);
    return SlSurface(
      key: const ValueKey('todo_detail_checklist_section'),
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<List<TodoChecklistItem>>(
        future: _checklistFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <TodoChecklistItem>[];
          final doneCount = items.where((item) => item.isDone).length;
          final progressText =
              items.isEmpty ? null : '$doneCount/${items.length}';
          return FutureBuilder<List<TodoChecklistSuggestion>>(
            future: _checklistSuggestionsFuture,
            builder: (context, suggestionsSnapshot) {
              final suggestions =
                  suggestionsSnapshot.data ?? const <TodoChecklistSuggestion>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t.actions.todoDetail.checklistTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (progressText != null)
                        Text(
                          progressText,
                          key: const ValueKey('todo_detail_checklist_progress'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('todo_detail_checklist_input'),
                          controller: _checklistController,
                          decoration: InputDecoration(
                            hintText:
                                context.t.actions.todoDetail.checklistHint,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => unawaited(_addChecklistItem()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SlButton(
                        buttonKey: const ValueKey('todo_detail_checklist_add'),
                        onPressed: _creatingChecklistItem
                            ? null
                            : () => unawaited(_addChecklistItem()),
                        child: Text(context.t.actions.todoDetail.checklistAdd),
                      ),
                    ],
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        for (var index = 0; index < items.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DecoratedBox(
                              key: ValueKey(
                                'todo_detail_checklist_item_${items[index].id}',
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withOpacity(0.35),
                                borderRadius:
                                    BorderRadius.circular(tokens.radiusLg),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      key: ValueKey(
                                        'todo_detail_checklist_toggle_${items[index].id}',
                                      ),
                                      value: items[index].isDone,
                                      onChanged: (value) => unawaited(
                                        _toggleChecklistItem(
                                          items[index],
                                          value ?? false,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusSm,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        items[index].content,
                                        style: items[index].isDone
                                            ? Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                )
                                            : Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'todo_detail_checklist_move_up_${items[index].id}',
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_upward_rounded,
                                      ),
                                      tooltip: context
                                          .t.actions.todoDetail.checklistMoveUp,
                                      onPressed: index == 0
                                          ? null
                                          : () => unawaited(
                                                _moveChecklistItem(
                                                  items,
                                                  items[index],
                                                  -1,
                                                ),
                                              ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'todo_detail_checklist_move_down_${items[index].id}',
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_downward_rounded,
                                      ),
                                      tooltip: context.t.actions.todoDetail
                                          .checklistMoveDown,
                                      onPressed: index == items.length - 1
                                          ? null
                                          : () => unawaited(
                                                _moveChecklistItem(
                                                  items,
                                                  items[index],
                                                  1,
                                                ),
                                              ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'todo_detail_checklist_edit_${items[index].id}',
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: context
                                          .t.actions.todoDetail.checklistEdit,
                                      onPressed: () => unawaited(
                                        _editChecklistItem(items[index]),
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'todo_detail_checklist_delete_${items[index].id}',
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      tooltip: context
                                          .t.actions.todoDetail.checklistDelete,
                                      onPressed: () => unawaited(
                                        _deleteChecklistItem(items[index]),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  _buildChecklistSuggestionsSection(context, suggestions),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
