part of 'agent_conversation_page.dart';

extension _OperatingApprovalPreview on _OperatingMessageList {
  ApprovalPreviewChange _approvalPreviewChange(
    BuildContext context,
    SecretaryRuntimeApprovalItem item,
  ) {
    final record = item.record ?? const <String, Object?>{};
    final todo = _todoById(item.taskId);
    final reason = item.reason.trim();
    return ApprovalPreviewChange(
      sourceSentence: reason.isEmpty ? item.title : reason,
      dueTimeBefore: todo == null
          ? context.t.chat.agentTasks.notScheduled
          : agentTaskSubtitle(todo),
      dueTimeAfter: agentTaskDueLabelFromMs(_runtimeDueAtMs(record)),
      statusLabel: todo == null
          ? context.t.chat.agentTasks.statusOpen
          : agentTaskStatusLabel(todo),
    );
  }

  Todo? _todoById(String todoId) {
    final id = todoId.trim();
    if (id.isEmpty) return null;
    for (final todo in todos) {
      if (todo.id == id) return todo;
    }
    return null;
  }
}
