part of 'desktop_approvals_workbench_page.dart';

List<_ApprovalView> _approvalsFromState(RuntimeAgentState state) {
  return state.approvalItems
      .map(_ApprovalView.fromRuntime)
      .where((approval) => approval.id.isNotEmpty)
      .toList(growable: false);
}

final class _ApprovalView {
  const _ApprovalView({
    required this.id,
    required this.kind,
    required this.typeLabel,
    required this.title,
    required this.status,
    required this.risk,
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

  factory _ApprovalView.fromRuntime(Map<String, Object?> item) {
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
        'previous value not reported';
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
        'proposed value not reported';
    return _ApprovalView(
      id: desktopRuntimeString([item['id'], item['approval_id']]) ?? '',
      kind: kind,
      typeLabel: desktopRuntimeTitleCase(kind),
      title: desktopRuntimeString([item['title'], record['title']]) ??
          'Runtime approval',
      status: refused
          ? 'refused'
          : needsConfig
              ? 'needs_configuration'
              : status,
      risk: _riskLabel(item, record),
      targetId: desktopRuntimeString([
            item['task_id'],
            record['target_id'],
            record['targetId'],
            record['task_id'],
            record['taskId'],
          ]) ??
          'not reported',
      sourceId: desktopRuntimeString([
            item['source_intent_id'],
            record['source_message_id'],
            record['sourceMessageId'],
            record['source'],
          ]) ??
          'not reported',
      targetLabel: desktopRuntimeString([
            record['target_label'],
            record['task_title'],
            record['taskTitle'],
            record['entity_title'],
            record['title'],
          ]) ??
          'Runtime target',
      before: before,
      after: after,
      reason: desktopRuntimeString([item['reason'], record['reason']]) ??
          'Agent insight was not reported by runtime.',
      sourceExcerpt: desktopRuntimeString([
            record['source_excerpt'],
            record['sourceExcerpt'],
            record['message_excerpt'],
            record['messageExcerpt'],
          ]) ??
          'No source excerpt reported.',
      traceText: desktopRuntimeString([
            record['tool_trace'],
            record['trace'],
            record['trace_text'],
            record['traceText'],
          ]) ??
          '> checking guardrails... approval_required',
      systemNotice: needsConfig
          ? 'tool_unavailable: Connector requires configuration before related mutations can be approved.'
          : refused
              ? 'refused: Purchase, payment, or local-computer side effects cannot be approved.'
              : 'approval_required: Runtime will not apply this mutation before a decision.',
      guardrailLabels: _guardrailLabels(record, needsConfig, refused),
      needsConfig: needsConfig,
      refused: refused,
    );
  }
}

String _riskLabel(Map<String, Object?> item, Map<String, Object?> record) {
  final raw = desktopRuntimeString([
        record['risk'],
        record['risk_level'],
        record['riskLevel'],
        item['risk'],
      ]) ??
      '';
  if (raw.toLowerCase().contains('high')) return 'High Risk';
  if (raw.toLowerCase().contains('low')) return 'Low Risk';
  return 'Medium Risk';
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
