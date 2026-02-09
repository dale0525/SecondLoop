part of 'chat_page.dart';

final class _TodoMessageBadgeMeta {
  const _TodoMessageBadgeMeta({
    required this.todoId,
    required this.todoTitle,
    required this.isRelated,
  });

  final String todoId;
  final String todoTitle;
  final bool isRelated;
}

extension _ChatPageStateTodoMessageBadge on _ChatPageState {
  _TodoMessageBadgeMeta? _todoMessageBadgeMetaForMessage({
    required Message message,
    required Map<String, SemanticParseJob> jobsByMessageId,
    required String displayText,
  }) {
    final job = jobsByMessageId[message.id];
    if (job == null) return null;
    if (job.status != 'succeeded') return null;
    if (job.undoneAtMs != null) return null;

    final kind = job.appliedActionKind?.trim();
    final todoId = job.appliedTodoId?.trim();
    if (todoId == null || todoId.isEmpty) return null;
    if (kind != 'create' && kind != 'followup') return null;

    final title = (job.appliedTodoTitle ?? '').trim().isNotEmpty
        ? job.appliedTodoTitle!.trim()
        : displayText.trim();
    return _TodoMessageBadgeMeta(
      todoId: todoId,
      todoTitle: title,
      isRelated: kind == 'followup',
    );
  }

  String _todoMessageBadgeLabel(
    BuildContext context,
    _TodoMessageBadgeMeta meta,
  ) {
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
    if (isZh) return meta.isRelated ? '关联事项' : '事项';
    return meta.isRelated ? 'Related task' : 'Task';
  }

  Future<void> _openTodoFromBadge(_TodoMessageBadgeMeta meta) async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    Todo? todo;
    try {
      final todos = await backend.listTodos(sessionKey);
      for (final item in todos) {
        if (item.id == meta.todoId) {
          todo = item;
          break;
        }
      }
    } catch (_) {
      todo = null;
    }

    if (!mounted || todo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TodoDetailPage(initialTodo: todo!),
      ),
    );
  }

  Widget _buildTodoTypeBadge({
    required Message message,
    required _TodoMessageBadgeMeta meta,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      key: ValueKey('message_todo_type_badge_${message.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => unawaited(_openTodoFromBadge(meta)),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                meta.isRelated ? Icons.link_rounded : Icons.task_alt_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _todoMessageBadgeLabel(context, meta),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedTodoRootQuote({
    required Message message,
    required _TodoMessageBadgeMeta meta,
    required ColorScheme colorScheme,
  }) {
    final trimmedTitle = meta.todoTitle.trim();
    if (!meta.isRelated || trimmedTitle.isEmpty) return const SizedBox.shrink();
    final quoteText = '「$trimmedTitle」';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: ValueKey('message_related_todo_root_${message.id}'),
        onTap: () => unawaited(_openTodoFromBadge(meta)),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: colorScheme.outline.withOpacity(0.75),
                width: 2,
              ),
            ),
            color: colorScheme.surface.withOpacity(0.28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            quoteText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
