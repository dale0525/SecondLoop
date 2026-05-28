part of 'desktop_approvals_workbench_page.dart';

List<_ApprovalView> _approvalsFromState(
  RuntimeAgentState state,
  _ApprovalWorkbenchCopy copy,
) {
  return state.approvalItems
      .map((approval) => _ApprovalView.fromRuntime(approval, copy))
      .where((approval) => approval.id.isNotEmpty)
      .toList(growable: false);
}

enum _ApprovalRiskLevel { high, medium, low }

final class _ApprovalWorkbenchCopy {
  const _ApprovalWorkbenchCopy({
    required this.notReported,
    required this.previousValue,
    required this.proposedValue,
    required this.runtimeApproval,
    required this.runtimeTarget,
    required this.reason,
    required this.noSourceExcerpt,
    required this.traceChecking,
    required this.highRisk,
    required this.mediumRisk,
    required this.lowRisk,
    required this.taskMutationType,
    required this.memoryType,
    required this.emailDraftType,
    required this.paymentRefusalType,
    required this.runtimeApprovalType,
    required this.needsConfigNotice,
    required this.refusedNotice,
    required this.defaultNotice,
  });

  final String notReported;
  final String previousValue;
  final String proposedValue;
  final String runtimeApproval;
  final String runtimeTarget;
  final String reason;
  final String noSourceExcerpt;
  final String traceChecking;
  final String highRisk;
  final String mediumRisk;
  final String lowRisk;
  final String taskMutationType;
  final String memoryType;
  final String emailDraftType;
  final String paymentRefusalType;
  final String runtimeApprovalType;
  final String needsConfigNotice;
  final String refusedNotice;
  final String defaultNotice;
}

final class _ApprovalView {
  const _ApprovalView({
    required this.id,
    required this.kind,
    required this.typeLabel,
    required this.title,
    required this.status,
    required this.risk,
    required this.riskLevel,
    required this.targetId,
    required this.sourceId,
    required this.targetLabel,
    required this.before,
    required this.after,
    required this.reason,
    required this.sourceExcerpt,
    required this.traceText,
    required this.systemNotice,
    required this.guardrailLabels,
    required this.needsConfig,
    required this.refused,
  });

  final String id;
  final String kind;
  final String typeLabel;
  final String title;
  final String status;
  final String risk;
  final _ApprovalRiskLevel riskLevel;
  final String targetId;
  final String sourceId;
  final String targetLabel;
  final String before;
  final String after;
  final String reason;
  final String sourceExcerpt;
  final String traceText;
  final String systemNotice;
  final List<String> guardrailLabels;
  final bool needsConfig;
  final bool refused;

  bool canSubmitDecision(String decision) {
    if (refused) return false;
    if (decision == 'approve' && needsConfig) return false;
    return id.isNotEmpty && status.contains('pending');
  }

  factory _ApprovalView.fromRuntime(
    Map<String, Object?> item,
    _ApprovalWorkbenchCopy copy,
  ) {
    final record = desktopRuntimeMap(item['record']);
    final kind = desktopRuntimeString([item['kind'], record['kind']]) ??
        'approval_required';
    final status = desktopRuntimeString([
          record['status'],
          item['status'],
          record['state'],
        ]) ??
        'pending_approval';
    final refused = desktopRuntimeLooksLikeKind(
      item,
      const [
        'refused',
        'purchase',
        'payment',
        'local_computer',
        'local-computer',
        'local computer',
      ],
    );
    final needsConfig = desktopRuntimeLooksLikeKind(
      item,
      const ['needs_configuration', 'tool_unavailable', 'not authorized'],
    );
    final before = desktopRuntimeString([
          record['before'],
          record['old_value'],
          record['oldValue'],
          record['current_title'],
          record['currentTitle'],
          record['from'],
        ]) ??
        copy.previousValue;
    final after = desktopRuntimeString([
          record['after'],
          record['new_value'],
          record['newValue'],
          record['proposed_title'],
          record['proposedTitle'],
          record['target_title'],
          record['targetTitle'],
          record['to'],
          item['title'],
        ]) ??
        copy.proposedValue;
    final riskLevel = _riskLevel(item, record);
    return _ApprovalView(
      id: desktopRuntimeString([item['id'], item['approval_id']]) ?? '',
      kind: kind,
      typeLabel: _approvalTypeLabel(kind, copy),
      title: desktopRuntimeString([item['title'], record['title']]) ??
          copy.runtimeApproval,
      status: refused
          ? 'refused'
          : needsConfig
              ? 'needs_configuration'
              : status,
      risk: _riskLabel(riskLevel, copy),
      riskLevel: riskLevel,
      targetId: desktopRuntimeString([
            item['task_id'],
            record['target_id'],
            record['targetId'],
            record['task_id'],
            record['taskId'],
          ]) ??
          copy.notReported,
      sourceId: desktopRuntimeString([
            item['source_intent_id'],
            record['source_message_id'],
            record['sourceMessageId'],
            record['source'],
          ]) ??
          copy.notReported,
      targetLabel: desktopRuntimeString([
            record['target_label'],
            record['task_title'],
            record['taskTitle'],
            record['entity_title'],
            record['title'],
          ]) ??
          copy.runtimeTarget,
      before: before,
      after: after,
      reason: desktopRuntimeString([item['reason'], record['reason']]) ??
          copy.reason,
      sourceExcerpt: desktopRuntimeString([
            record['source_excerpt'],
            record['sourceExcerpt'],
            record['message_excerpt'],
            record['messageExcerpt'],
          ]) ??
          copy.noSourceExcerpt,
      traceText: desktopRuntimeString([
            record['tool_trace'],
            record['trace'],
            record['trace_text'],
            record['traceText'],
          ]) ??
          copy.traceChecking,
      systemNotice: needsConfig
          ? copy.needsConfigNotice
          : refused
              ? copy.refusedNotice
              : copy.defaultNotice,
      guardrailLabels: _guardrailLabels(record, needsConfig, refused),
      needsConfig: needsConfig,
      refused: refused,
    );
  }
}

_ApprovalRiskLevel _riskLevel(
  Map<String, Object?> item,
  Map<String, Object?> record,
) {
  final raw = desktopRuntimeString([
        record['risk'],
        record['risk_level'],
        record['riskLevel'],
        item['risk'],
      ]) ??
      '';
  if (raw.toLowerCase().contains('high')) return _ApprovalRiskLevel.high;
  if (raw.toLowerCase().contains('low')) return _ApprovalRiskLevel.low;
  return _ApprovalRiskLevel.medium;
}

String _riskLabel(_ApprovalRiskLevel riskLevel, _ApprovalWorkbenchCopy copy) {
  return switch (riskLevel) {
    _ApprovalRiskLevel.high => copy.highRisk,
    _ApprovalRiskLevel.medium => copy.mediumRisk,
    _ApprovalRiskLevel.low => copy.lowRisk,
  };
}

String _approvalTypeLabel(String kind, _ApprovalWorkbenchCopy copy) {
  final normalized = kind.toLowerCase();
  if (normalized.contains('task_mutation')) return copy.taskMutationType;
  if (normalized.contains('memory')) return copy.memoryType;
  if (normalized.contains('email')) return copy.emailDraftType;
  if (normalized.contains('purchase') || normalized.contains('payment')) {
    return copy.paymentRefusalType;
  }
  return copy.runtimeApprovalType;
}

_ApprovalWorkbenchCopy _approvalWorkbenchCopy(BuildContext context) {
  final t = context.t.chat.operating.desktopWorkbench.approvals;
  final root = context.t.chat.operating.desktopWorkbench;
  return _ApprovalWorkbenchCopy(
    notReported: root.notReported,
    previousValue: t.fallbacks.previousValue,
    proposedValue: t.fallbacks.proposedValue,
    runtimeApproval: t.fallbacks.runtimeApproval,
    runtimeTarget: t.fallbacks.runtimeTarget,
    reason: t.fallbacks.reason,
    noSourceExcerpt: t.noSourceExcerpt,
    traceChecking: t.traceChecking,
    highRisk: t.risk.high,
    mediumRisk: t.risk.medium,
    lowRisk: t.risk.low,
    taskMutationType: t.typeLabels.taskMutation,
    memoryType: t.typeLabels.memory,
    emailDraftType: t.typeLabels.emailDraft,
    paymentRefusalType: t.typeLabels.paymentRefusal,
    runtimeApprovalType: t.typeLabels.runtimeApproval,
    needsConfigNotice: t.systemNotice.needsConfig,
    refusedNotice: t.systemNotice.refused,
    defaultNotice: t.systemNotice.waitingDecision,
  );
}

List<String> _guardrailLabels(
  Map<String, Object?> record,
  bool needsConfig,
  bool refused,
) {
  if (refused) {
    return const [
      'side_effect_refused',
      'no_external_action',
      'audit_refs_present',
    ];
  }
  if (needsConfig) {
    return const [
      'needs_configuration',
      'tool_unavailable',
      'approval_blocked',
    ];
  }
  final raw = desktopRuntimeObjectList(record['guardrails'])
      .map((item) => desktopRuntimeString([item['label'], item['id']]))
      .whereType<String>()
      .toList(growable: false);
  if (raw.isNotEmpty) return raw;
  return const [
    'approval_required',
    'target_resolved',
    'audit_refs_present',
    'side_effect_guarded',
  ];
}
