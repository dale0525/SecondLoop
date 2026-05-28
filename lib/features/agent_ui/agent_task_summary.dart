import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/runtime_agent_state_repository.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';
import '../conversation_context/conversation_context_rail.dart';
import 'agent_design_tokens.dart';
import 'agent_runtime_file_context.dart';

const _ink = Color(0xFF101936);
const _muted = Color(0xFF63708A);
const _line = Color(0xFFE1E7F0);
const _soft = Color(0xFFF7F9FC);

List<Todo> agentOpenTasks(List<Todo> todos) {
  final open = todos.where(_isOpenTask).toList(growable: false);
  return List<Todo>.from(open)..sort(_compareTasks);
}

List<Todo> agentTodosFromRuntimeTasks(List<RuntimeWorkingSetRecord> tasks) {
  return tasks.map(agentTodoFromRuntimeTask).toList(growable: false);
}

List<Todo> agentTodosFromRuntimeState(RuntimeAgentState state) {
  return _mergeTodosById([
    ...agentTodosFromRuntimeTasks(state.tasks),
    ...agentTodosFromRuntimeRecurringRules(state.recurringReminderRules),
  ]);
}

Todo agentTodoFromRuntimeTask(RuntimeWorkingSetRecord record) {
  final createdAtMs =
      _runtimeInt(record.raw['created_at_ms'] ?? record.raw['createdAtMs']) ??
          record.updatedAtMs;
  return Todo(
    id: record.id,
    title: record.title,
    dueAtMs: _runtimeDueAtMs(record.raw),
    status: _runtimeTaskStatus(record.status),
    sourceEntryId: _runtimeString(record.raw['source_message_id']) ??
        _runtimeString(record.raw['sourceMessageId']) ??
        _runtimeString(record.raw['source_entry_id']) ??
        _runtimeString(record.raw['sourceEntryId']),
    createdAtMs: createdAtMs,
    updatedAtMs: record.updatedAtMs == 0 ? createdAtMs : record.updatedAtMs,
    reviewStage: _runtimeInt(record.raw['review_stage']) ??
        _runtimeInt(record.raw['reviewStage']),
    nextReviewAtMs: _runtimeInt(record.raw['next_review_at_ms']) ??
        _runtimeInt(record.raw['nextReviewAtMs']),
    lastReviewAtMs: _runtimeInt(record.raw['last_review_at_ms']) ??
        _runtimeInt(record.raw['lastReviewAtMs']),
    manualImportanceNudgeScore:
        _runtimeInt(record.raw['manual_importance_nudge_score']) ??
            _runtimeInt(record.raw['manualImportanceNudgeScore']),
    manualUrgencyNudgeScore:
        _runtimeInt(record.raw['manual_urgency_nudge_score']) ??
            _runtimeInt(record.raw['manualUrgencyNudgeScore']),
  );
}

List<Todo> agentTodosFromRuntimeRecurringRules(
  List<Map<String, Object?>> rules,
) {
  return rules
      .where(_isVisibleRuntimeRecurringRule)
      .map(agentTodoFromRuntimeRecurringRule)
      .where(
          (todo) => todo.id.trim().isNotEmpty && todo.title.trim().isNotEmpty)
      .toList(growable: false);
}

Todo agentTodoFromRuntimeRecurringRule(Map<String, Object?> rule) {
  final title = _firstRuntimeString([
        rule['title'],
        rule['text'],
        rule['content'],
        rule['summary'],
      ]) ??
      '';
  final id = _firstRuntimeString([
        rule['id'],
        rule['record_id'],
        rule['recordId'],
        rule['recurring_rule_id'],
        rule['recurringRuleId'],
      ]) ??
      '';
  final dueAtMs = _runtimeDueAtMs(rule);
  final createdAtMs = _runtimeInt(rule['created_at_ms']) ??
      _runtimeInt(rule['createdAtMs']) ??
      _runtimeInt(rule['updated_at_ms']) ??
      _runtimeInt(rule['updatedAtMs']) ??
      dueAtMs ??
      0;
  final updatedAtMs = _runtimeInt(rule['updated_at_ms']) ??
      _runtimeInt(rule['updatedAtMs']) ??
      createdAtMs;
  return Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs,
    status: 'open',
    sourceEntryId: _runtimeString(rule['source_intent_id']) ??
        _runtimeString(rule['sourceIntentId']),
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs,
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
    manualImportanceNudgeScore: null,
    manualUrgencyNudgeScore: null,
  );
}

List<MemoryPageRecord> agentMemoryPagesFromRuntimeRecords(
  List<RuntimeWorkingSetRecord> records,
) {
  return records.map(agentMemoryPageFromRuntimeRecord).toList(growable: false);
}

List<MemoryPageRecord> agentMemoryPagesFromRuntimeState(
  RuntimeAgentState state,
) {
  final latest = state.latestContextSnapshot;
  final snapshotRecords = latest == null
      ? const <RuntimeWorkingSetRecord>[]
      : <RuntimeWorkingSetRecord>[
          ..._runtimeRecordList(latest.packet['memory_records']),
          ..._runtimeRecordsFromWorkingSet(latest.packet['working_set'])
              .where((record) => record.kind == 'memory'),
        ];
  final records = _mergeRuntimeRecordsById([
    ...state.memoryRecords,
    ...state.workingSetRecords.where((record) => record.kind == 'memory'),
    ...snapshotRecords,
  ]);
  return agentMemoryPagesFromRuntimeRecords(records);
}

MemoryPageRecord agentMemoryPageFromRuntimeRecord(
  RuntimeWorkingSetRecord record,
) {
  final title = _runtimeMemoryTitle(record);
  final body = _runtimeMemoryBody(record, fallback: title);
  final updatedAtMs = record.updatedAtMs;
  final createdAtMs =
      _runtimeInt(record.raw['created_at_ms'] ?? record.raw['createdAtMs']) ??
          updatedAtMs;
  return MemoryPageRecord(
    pageId: record.id,
    pageType: _runtimeString(record.raw['memory_kind']) ??
        _runtimeString(record.raw['memoryKind']) ??
        _runtimeString(record.raw['page_type']) ??
        _runtimeString(record.raw['pageType']) ??
        'preference',
    state: _runtimeString(record.raw['state']) ?? 'active',
    sourceCount: 0,
    title: title,
    summary: _runtimeString(record.raw['summary']) ?? body,
    body: body,
    primaryEvidenceJson: '{}',
    sourceDocumentIdsJson: '[]',
    confidenceLevel: _runtimeDouble(record.raw['confidence']) ?? 0.9,
    humanCorrected: record.raw['human_corrected'] == true ||
        record.raw['humanCorrected'] == true,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs == 0 ? createdAtMs : updatedAtMs,
  );
}

ConversationContextSnapshot agentRuntimeContextSnapshot(
  RuntimeAgentState state,
) {
  final latest = state.latestContextSnapshot;
  final recentFiles = agentRuntimeRecentFileItems(state, latest?.packet);
  if (latest != null) {
    final records = _runtimeRecordsFromWorkingSet(latest.packet['working_set']);
    final tasks = _mergeTodosById([
      ...agentTodosFromRuntimeTasks(state.tasks),
      ...records
          .where((record) => record.kind == 'task')
          .map(agentTodoFromRuntimeTask),
      ...agentTodosFromRuntimeRecurringRules([
        ...state.recurringReminderRules,
        ..._runtimeObjectList(latest.packet['recurring_reminder_rules']),
      ]),
    ]);
    return agentTaskContextSnapshot(
      tasks,
      memories: agentMemoryPagesFromRuntimeState(state),
      recentFiles: recentFiles,
    );
  }
  return agentTaskContextSnapshot(
    agentTodosFromRuntimeState(state),
    memories: agentMemoryPagesFromRuntimeState(state),
    recentFiles: recentFiles,
  );
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
  List<ConversationContextItem> recentFiles = const <ConversationContextItem>[],
}) {
  final openTasks = agentOpenTasks(todos);
  final memoryItems = agentMemoryContextItems(memories);
  if (openTasks.isEmpty && memoryItems.isEmpty && recentFiles.isEmpty) {
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
    recentFiles: recentFiles.take(3).toList(growable: false),
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

List<RuntimeWorkingSetRecord> _runtimeRecordsFromWorkingSet(Object? raw) {
  if (raw is! Map) return const <RuntimeWorkingSetRecord>[];
  return _runtimeRecordList(raw['records']);
}

List<RuntimeWorkingSetRecord> _runtimeRecordList(Object? raw) {
  if (raw is! List) return const <RuntimeWorkingSetRecord>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => RuntimeWorkingSetRecord.fromJson(
          item.map((key, value) => MapEntry('$key', value as Object?)),
        ),
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _runtimeObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => item.map((key, value) => MapEntry('$key', value as Object?)),
      )
      .toList(growable: false);
}

List<Todo> _mergeTodosById(Iterable<Todo> todos) {
  final byId = <String, Todo>{};
  for (final todo in todos) {
    final id = todo.id.trim();
    if (id.isEmpty || byId.containsKey(id)) continue;
    byId[id] = todo;
  }
  return byId.values.toList(growable: false);
}

List<RuntimeWorkingSetRecord> _mergeRuntimeRecordsById(
  Iterable<RuntimeWorkingSetRecord> records,
) {
  final byId = <String, RuntimeWorkingSetRecord>{};
  for (final record in records) {
    final id = record.id.trim();
    if (id.isEmpty || byId.containsKey(id)) continue;
    byId[id] = record;
  }
  return byId.values.toList(growable: false);
}

String _runtimeTaskStatus(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized == 'todo' ||
      normalized == 'to_do' ||
      normalized == 'pending' ||
      normalized == 'not_started') {
    return 'open';
  }
  return normalized;
}

String _runtimeMemoryTitle(RuntimeWorkingSetRecord record) {
  return _firstRuntimeString([
        record.raw['title'],
        record.raw['text'],
        record.raw['content'],
        record.raw['summary'],
        record.raw['body'],
      ]) ??
      record.title;
}

String _runtimeMemoryBody(
  RuntimeWorkingSetRecord record, {
  required String fallback,
}) {
  return _firstRuntimeString([
        record.raw['body'],
        record.raw['summary'],
        record.raw['detail'],
        record.raw['description'],
        record.raw['text'],
        record.raw['content'],
      ]) ??
      fallback;
}

String? _firstRuntimeString(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = _runtimeString(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _runtimeString(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

int? _runtimeInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

bool _isVisibleRuntimeRecurringRule(Map<String, Object?> rule) {
  final kind = _runtimeString(rule['kind']);
  if (kind != null && kind != 'recurring_reminder_rule') return false;
  final approvalStatus = _runtimeString(rule['approval_status']) ??
      _runtimeString(rule['approvalStatus']);
  if (approvalStatus != null && approvalStatus != 'approved') return false;
  final status = _runtimeString(rule['status']) ?? 'active';
  return status != 'pending_approval' &&
      status != 'rejected' &&
      status != 'archived' &&
      status != 'deleted' &&
      status != 'dismissed';
}

double? _runtimeDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

int? _runtimeDueAtMs(Map<String, Object?> raw) {
  return _runtimeInt(raw['due_at_ms']) ??
      _runtimeInt(raw['dueAtMs']) ??
      _runtimeInt(raw['new_due_at_ms']) ??
      _runtimeInt(raw['newDueAtMs']) ??
      _runtimeInt(raw['next_fire_at_ms']) ??
      _runtimeInt(raw['nextFireAtMs']) ??
      _runtimeIsoDateTimeMs(raw['due_local_iso']) ??
      _runtimeIsoDateTimeMs(raw['dueLocalIso']);
}

int? _runtimeIsoDateTimeMs(Object? raw) {
  final value = _runtimeString(raw);
  if (value == null) return null;
  return DateTime.tryParse(value)?.millisecondsSinceEpoch;
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
  const AgentTasksPage({
    this.runtimeAgentStateRepository,
    this.conversationId = 'loop_home',
    super.key,
  });

  final RuntimeAgentStateRepository? runtimeAgentStateRepository;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final text = context.t;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    return FutureBuilder<CloudRuntimeConnection?>(
      future: _loadTaskRuntimeConnection(),
      initialData: RuntimeConnectionStore.cachedConnection,
      builder: (context, connectionSnapshot) {
        final cloudAuthScope = CloudAuthScope.maybeOf(context);
        final selfManagedConnection =
            connectionSnapshot.data?.profile.runtimeMode ==
                    CloudRuntimeMode.selfManaged
                ? connectionSnapshot.data
                : null;
        final vaultId = selfManagedConnection?.profile.vaultId.trim() ??
            cloudAuthScope?.controller.uid?.trim() ??
            '';
        final repository = runtimeAgentStateRepository ??
            (selfManagedConnection != null
                ? SecretaryRuntimeAgentStateRepository()
                : cloudAuthScope == null || vaultId.isEmpty
                    ? null
                    : SecretaryRuntimeAgentStateRepository.hostedManagedPro(
                        apiBaseUrl: cloudAuthScope.gatewayConfig.baseUrl,
                        hostedSessionTokenGetter:
                            cloudAuthScope.controller.getIdToken,
                      ));
        final Future<List<Todo>> tasksFuture =
            repository == null || vaultId.isEmpty
                ? backend.listTodos(sessionKey)
                : repository
                    .fetchAgentState(
                      vaultId: vaultId,
                      conversationId: conversationId,
                    )
                    .then(agentTodosFromRuntimeState);
        return Scaffold(
          appBar: AppBar(title: Text(text.chat.agentTasks.allTasks)),
          body: FutureBuilder<List<Todo>>(
            future: tasksFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    text.errors.loadFailed(error: '${snapshot.error}'),
                  ),
                );
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
      },
    );
  }
}

Future<CloudRuntimeConnection?> _loadTaskRuntimeConnection() async {
  try {
    return await RuntimeConnectionStore().loadConnection();
  } catch (_) {
    return RuntimeConnectionStore.cachedConnection;
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
      final text = context.t;
      return FractionallySizedBox(
        key: const ValueKey('agent_tasks_sheet'),
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text.chat.agentTasks.allTasks,
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
    final text = context.t;
    final openTasks = agentOpenTasks(todos);
    if (openTasks.isEmpty) {
      return Center(child: Text(text.chat.agentTasks.empty));
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
