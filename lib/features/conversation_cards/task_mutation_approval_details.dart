import 'package:flutter/foundation.dart';

import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/secretary_runtime_client.dart';

@immutable
final class TaskMutationApprovalDetails {
  const TaskMutationApprovalDetails({
    required this.targetId,
    required this.currentTitle,
    required this.proposedTitle,
    required this.resolverDetail,
    required this.source,
    required this.auditId,
    required this.contextSnapshotId,
    required this.runtimeTool,
    required this.riskLabel,
    required this.notice,
    required this.currentStateLabel,
    required this.systemContext,
    required this.lastApprovedChange,
    required this.confidenceLabel,
  });

  final String targetId;
  final String currentTitle;
  final String proposedTitle;
  final String resolverDetail;
  final String source;
  final String auditId;
  final String contextSnapshotId;
  final String runtimeTool;
  final String riskLabel;
  final String notice;
  final String currentStateLabel;
  final String systemContext;
  final String lastApprovedChange;
  final String confidenceLabel;

  bool get hasFooterEvidence =>
      lastApprovedChange.isNotEmpty || confidenceLabel.isNotEmpty;

  factory TaskMutationApprovalDetails.fromRuntime({
    required SecretaryRuntimeApprovalItem item,
    required List<RuntimeWorkingSetRecord> taskRecords,
    RuntimeContextSnapshot? contextSnapshot,
    List<Map<String, Object?>> auditRefs = const <Map<String, Object?>>[],
    List<Map<String, Object?>> recentEntityRefs =
        const <Map<String, Object?>>[],
  }) {
    final record = item.record ?? const <String, Object?>{};
    final targetId = taskMutationApprovalFirstString([
          item.taskId,
          record['task_id'],
          record['taskId'],
          record['target_task_id'],
          record['targetTaskId'],
          record['target_entity_id'],
          record['targetEntityId'],
          record['id'],
          record['record_id'],
          record['recordId'],
        ]) ??
        '';
    final targetRecord = _taskRecordById(taskRecords, targetId);
    final currentTitle = taskMutationApprovalFirstString([
          record['current_title'],
          record['currentTitle'],
          record['previous_title'],
          record['previousTitle'],
          record['before_title'],
          record['beforeTitle'],
          record['old_title'],
          record['oldTitle'],
          targetRecord?.title,
          item.title,
        ]) ??
        'Target task unavailable';
    final proposedTitle = taskMutationApprovalFirstString([
          record['proposed_title'],
          record['proposedTitle'],
          record['new_title'],
          record['newTitle'],
          record['after_title'],
          record['afterTitle'],
          record['title_after'],
          record['titleAfter'],
          record['target_title'],
          record['targetTitle'],
          record['title'],
          item.title,
        ]) ??
        'Pending mutation';
    final matchingRef = _recentRefForTarget(recentEntityRefs, targetId);
    final contextId = taskMutationApprovalFirstString([
          record['context_snapshot_id'],
          record['contextSnapshotId'],
          contextSnapshot?.id,
        ]) ??
        '';
    final auditId = taskMutationApprovalFirstString([
          record['audit_id'],
          record['auditId'],
          record['transaction_id'],
          record['transactionId'],
          _firstAuditId(auditRefs),
        ]) ??
        '';
    final source = taskMutationApprovalFirstString([
          record['source'],
          record['source_label'],
          record['sourceLabel'],
          record['source_message'],
          record['sourceMessage'],
        ]) ??
        'Chat Message';
    final resolverDetail = taskMutationApprovalFirstString([
          record['resolver_detail'],
          record['resolverDetail'],
          record['resolution_detail'],
          record['resolutionDetail'],
          matchingRef?['resolver_detail'],
          matchingRef?['resolverDetail'],
          matchingRef?['reason'],
        ]) ??
        'Target resolution unavailable';
    final currentStateLabel = taskMutationApprovalFirstString([
          record['current_state_label'],
          record['currentStateLabel'],
          targetRecord?.raw['due_label'],
          targetRecord?.raw['dueLabel'],
          record['due_label'],
          record['dueLabel'],
        ]) ??
        'Awaiting approval';
    final runtimeTool = taskMutationApprovalFirstString([
          record['runtime_tool'],
          record['runtimeTool'],
          record['tool'],
          record['skill'],
        ]) ??
        'task-management';
    final riskLabel = taskMutationApprovalFirstString([
          record['risk_label'],
          record['riskLabel'],
          record['risk_assessment'],
          record['riskAssessment'],
        ]) ??
        'Low Risk';
    final notice = taskMutationApprovalFirstString([
          record['notice'],
          record['pending_notice'],
          record['pendingNotice'],
        ]) ??
        'Mutation is not applied until approved.';
    final threadLabel = taskMutationApprovalFirstString([
      record['thread_label'],
      record['threadLabel'],
      record['session_thread'],
      record['sessionThread'],
    ]);
    final systemContext = taskMutationApprovalFirstString([
          record['system_context'],
          record['systemContext'],
        ]) ??
        'Task "$currentTitle" was successfully initialized'
            '${threadLabel == null ? '' : ' in $threadLabel'}.';
    return TaskMutationApprovalDetails(
      targetId: targetId.isEmpty ? 'unknown-task' : targetId,
      currentTitle: currentTitle,
      proposedTitle: proposedTitle,
      resolverDetail: resolverDetail,
      source: source,
      auditId: auditId.isEmpty ? 'Unavailable' : auditId,
      contextSnapshotId: contextId.isEmpty ? 'Unavailable' : contextId,
      runtimeTool: runtimeTool,
      riskLabel: riskLabel,
      notice: notice,
      currentStateLabel: currentStateLabel,
      systemContext: systemContext,
      lastApprovedChange: taskMutationApprovalFirstString([
            record['last_approved_change'],
            record['lastApprovedChange'],
          ]) ??
          '',
      confidenceLabel: taskMutationApprovalFirstString([
            record['confidence_label'],
            record['confidenceLabel'],
            record['automation_confidence'],
            record['automationConfidence'],
          ]) ??
          '',
    );
  }
}

String? taskMutationApprovalFirstString(List<Object?> values) {
  for (final value in values) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    } else if (value is num) {
      return '$value';
    }
  }
  return null;
}

RuntimeWorkingSetRecord? _taskRecordById(
  List<RuntimeWorkingSetRecord> records,
  String id,
) {
  final needle = id.trim();
  if (needle.isEmpty) return null;
  for (final record in records) {
    if (record.id == needle) return record;
  }
  return null;
}

Map<String, Object?>? _recentRefForTarget(
  List<Map<String, Object?>> refs,
  String targetId,
) {
  final needle = targetId.trim();
  if (needle.isEmpty) return null;
  for (final ref in refs) {
    final id = taskMutationApprovalFirstString([
      ref['entity_id'],
      ref['entityId'],
      ref['task_id'],
      ref['taskId'],
      ref['id'],
    ]);
    if (id == needle) return ref;
  }
  return null;
}

String? _firstAuditId(List<Map<String, Object?>> refs) {
  for (final ref in refs) {
    final value = taskMutationApprovalFirstString([
      ref['id'],
      ref['audit_id'],
      ref['auditId'],
      ref['transaction_id'],
      ref['transactionId'],
    ]);
    if (value != null) return value;
  }
  return null;
}
