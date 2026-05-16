import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../src/rust/platform_int.dart';
import '../conversation_context/conversation_context_rail.dart';
import 'agent_design_tokens.dart';

const _ink = Color(0xFF101936);
const _muted = Color(0xFF63708A);
const _line = Color(0xFFE1E7F0);
const _soft = Color(0xFFF7F9FC);

List<Todo> agentOpenTasks(List<Todo> todos) {
  final open = todos.where(_isOpenTask).toList(growable: false);
  return List<Todo>.from(open)..sort(_compareTasks);
}

List<Todo> agentTasksCreatedFromSources(
  List<Todo> todos,
  Set<String> sourceIds,
) {
  if (sourceIds.isEmpty) return const <Todo>[];
  final matching = todos.where((todo) {
    final sourceEntryId = todo.sourceEntryId?.trim();
    if (sourceEntryId == null || sourceEntryId.isEmpty) return false;
    return sourceIds.contains(sourceEntryId) && !_isRemovedTask(todo);
  }).toList(growable: false);
  return List<Todo>.from(matching)..sort(_compareTasks);
}

ConversationContextSnapshot agentTaskContextSnapshot(
  List<Todo> todos, {
  List<MemoryPageRecord> memories = const <MemoryPageRecord>[],
}) {
  final openTasks = agentOpenTasks(todos);
  final memoryItems = agentMemoryContextItems(memories);
  if (openTasks.isEmpty && memoryItems.isEmpty) {
    return const ConversationContextSnapshot.empty();
  }
  final count = openTasks.length;
  final preview = openTasks.take(3).map((todo) {
    return ConversationContextItem(
      title: todo.title,
      subtitle: _taskSubtitle(todo),
    );
  }).toList(growable: false);
  return ConversationContextSnapshot(
    todayAtAGlance: openTasks.isEmpty
        ? const <ConversationContextItem>[]
        : <ConversationContextItem>[
            ConversationContextItem(
              title: t.chat.agentTasks.topPrioritiesCount(count: count),
              subtitle: preview.map((item) => item.title).join(' · '),
            ),
          ],
    longTermMemory: memoryItems,
    people: const <ConversationContextItem>[],
    recentFiles: const <ConversationContextItem>[],
    pendingReview: const <ConversationContextItem>[],
    privacyNote: t.chat.agentContext.defaultPrivacyNote,
  );
}

List<ConversationContextItem> agentMemoryContextItems(
  List<MemoryPageRecord> memories,
) {
  final active = memories
      .where((memory) => memory.state.toLowerCase() == 'active')
      .toList(growable: false)
    ..sort((a, b) {
      return platformIntToInt(b.updatedAtMs).compareTo(
        platformIntToInt(a.updatedAtMs),
      );
    });
  return active.take(3).map((memory) {
    return ConversationContextItem(
      title: memory.title,
      subtitle: _memorySubtitle(memory),
    );
  }).toList(growable: false);
}

final class AgentCreatedTaskCard extends StatelessWidget {
  const AgentCreatedTaskCard({
    required this.todo,
    required this.onOpenTask,
    super.key,
  });

  final Todo todo;
  final VoidCallback onOpenTask;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('agent_created_task_card_${todo.id}'),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
        border: Border.all(color: const Color(0xFFBFD2FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF08A86B),
              size: 22,
            ),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.chat.agentTasks.created,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapXs),
                  Text(
                    todo.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AgentDesignTokens.gapXs),
                  Text(
                    _taskSubtitle(todo),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AgentDesignTokens.gapSm),
            TextButton.icon(
              key: ValueKey('agent_open_task_${todo.id}'),
              onPressed: onOpenTask,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(t.chat.agentTasks.openTask),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAgentTaskDetailSheet({
  required BuildContext context,
  required Todo todo,
  Future<void> Function(Todo todo)? onTaskViewed,
}) {
  if (onTaskViewed != null) {
    unawaited(onTaskViewed(todo).catchError((_) {}));
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) {
      return Padding(
        key: const ValueKey('agent_task_detail_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              todo.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _AgentTaskFactRow(
              icon: Icons.flag_outlined,
              label: t.chat.agentTasks.status,
              value: _taskStatusLabel(todo),
            ),
            const SizedBox(height: AgentDesignTokens.gapMd),
            _AgentTaskFactRow(
              icon: Icons.schedule_rounded,
              label: t.chat.agentTasks.dueLabel,
              value: _taskSubtitle(todo),
            ),
          ],
        ),
      );
    },
  );
}

final class _AgentTaskFactRow extends StatelessWidget {
  const _AgentTaskFactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          children: [
            Icon(icon, color: _muted, size: 20),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class AgentTasksPage extends StatelessWidget {
  const AgentTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return Scaffold(
      appBar: AppBar(title: Text(t.chat.agentTasks.allTasks)),
      body: FutureBuilder<List<Todo>>(
        future: backend.listTodos(sessionKey),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text(t.errors.loadFailed(error: '${snapshot.error}')));
          }
          return _AgentTasksList(
            todos: snapshot.data ?? const <Todo>[],
            onOpenTask: (todo) => showAgentTaskDetailSheet(
              context: context,
              todo: todo,
            ),
          );
        },
      ),
    );
  }
}

void showAgentTasksSheet({
  required BuildContext context,
  required List<Todo> todos,
  Future<void> Function(Todo todo)? onTaskViewed,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      return FractionallySizedBox(
        key: const ValueKey('agent_tasks_sheet'),
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.chat.agentTasks.allTasks,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AgentDesignTokens.gapLg),
              Expanded(
                child: _AgentTasksList(
                  todos: todos,
                  onOpenTask: (todo) => showAgentTaskDetailSheet(
                    context: context,
                    todo: todo,
                    onTaskViewed: onTaskViewed,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

final class _AgentTasksList extends StatelessWidget {
  const _AgentTasksList({
    required this.todos,
    required this.onOpenTask,
  });

  final List<Todo> todos;
  final ValueChanged<Todo> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final openTasks = agentOpenTasks(todos);
    if (openTasks.isEmpty) {
      return Center(child: Text(t.chat.agentTasks.empty));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      itemCount: openTasks.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AgentDesignTokens.gapSm),
      itemBuilder: (context, index) {
        return _TaskListTile(
          index: index,
          todo: openTasks[index],
          onOpenTask: () => onOpenTask(openTasks[index]),
        );
      },
    );
  }
}

final class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    required this.index,
    required this.todo,
    required this.onOpenTask,
  });

  final int index;
  final Todo todo;
  final VoidCallback onOpenTask;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AgentDesignTokens.radiusMd);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('agent_task_list_item_${todo.id}'),
        onTap: onOpenTask,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: radius,
            border: Border.all(color: _line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TaskNumber(index: index),
                const SizedBox(width: AgentDesignTokens.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AgentDesignTokens.gapXs),
                      Text(
                        _taskSubtitle(todo),
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AgentDesignTokens.gapMd),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _muted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String agentTaskSubtitle(Todo todo) => _taskSubtitle(todo);

String agentTaskStatusLabel(Todo todo) => _taskStatusLabel(todo);

String agentTaskDueLabelFromMs(int? dueAtMs) {
  if (dueAtMs == null) return t.chat.agentTasks.notScheduled;
  final dueAt = DateTime.fromMillisecondsSinceEpoch(dueAtMs);
  final month = dueAt.month.toString().padLeft(2, '0');
  final day = dueAt.day.toString().padLeft(2, '0');
  final hour = dueAt.hour.toString().padLeft(2, '0');
  final minute = dueAt.minute.toString().padLeft(2, '0');
  return t.chat.agentTasks.due(value: '$month-$day $hour:$minute');
}

final class _TaskNumber extends StatelessWidget {
  const _TaskNumber({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(
          child: Text(
            t.chat.agentTasks.itemIndex(value: index + 1),
            style: const TextStyle(
              color: Color(0xFFE53935),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

bool _isOpenTask(Todo todo) {
  return !_isCompletedTask(todo) && !_isRemovedTask(todo);
}

bool _isCompletedTask(Todo todo) {
  final status = todo.status.toLowerCase();
  return status == 'done' || status == 'completed';
}

bool _isRemovedTask(Todo todo) {
  final status = todo.status.toLowerCase();
  return status == 'archived' || status == 'deleted';
}

int _compareTasks(Todo a, Todo b) {
  const farFutureMs = 1 << 62;
  final dueA = platformIntToNullableInt(a.dueAtMs) ?? farFutureMs;
  final dueB = platformIntToNullableInt(b.dueAtMs) ?? farFutureMs;
  final dueCompare = dueA.compareTo(dueB);
  if (dueCompare != 0) return dueCompare;
  final updatedA = platformIntToInt(a.updatedAtMs);
  final updatedB = platformIntToInt(b.updatedAtMs);
  final updatedCompare = updatedB.compareTo(updatedA);
  if (updatedCompare != 0) return updatedCompare;
  return a.title.compareTo(b.title);
}

String _taskSubtitle(Todo todo) {
  final dueAtMs = platformIntToNullableInt(todo.dueAtMs);
  return agentTaskDueLabelFromMs(dueAtMs);
}

String _memorySubtitle(MemoryPageRecord memory) {
  final summary = memory.summary.trim();
  if (summary.isNotEmpty && summary != memory.title.trim()) return summary;
  final body = memory.body.trim();
  if (body.isNotEmpty) return body;
  return memory.title;
}

String _taskStatusLabel(Todo todo) {
  final status = todo.status.toLowerCase();
  if (status == 'done' || status == 'completed') {
    return t.chat.agentTasks.statusDone;
  }
  if (status == 'inbox') return t.chat.agentTasks.statusInbox;
  return t.chat.agentTasks.statusOpen;
}
