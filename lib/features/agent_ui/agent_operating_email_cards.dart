part of 'agent_conversation_page.dart';

List<Widget> _operatingEmailRuntimeCards({
  required RuntimeAgentState state,
  required Set<String> sourceIds,
  required VoidCallback onSaveDraft,
  required VoidCallback onConnectEmail,
}) {
  final emailRecords = state.workingSetRecords.where((record) {
    return _operatingEmailRecordMatchesSource(record, sourceIds);
  }).toList(growable: false);
  return [
    for (final record in emailRecords)
      if (_isOperatingEmailDraftRecord(record))
        _OperatingEmailDraftCard(
          record: record,
          onSaveDraft: onSaveDraft,
          onConnectEmail: onConnectEmail,
        )
      else if (_isOperatingEmailGuardrailRecord(record))
        _OperatingEmailGuardrailCard(record: record),
  ];
}

bool _hasOperatingEmailUnavailableState(RuntimeAgentState? state) {
  if (state == null) return false;
  return state.workingSetRecords.any(
    (record) =>
        _isOperatingEmailDraftRecord(record) ||
        _isOperatingEmailGuardrailRecord(record),
  );
}

bool _isOperatingEmailOnlyDegradedState(RuntimeAgentState state) {
  if (!_hasOperatingEmailUnavailableState(state)) return false;
  if (state.tasks.isNotEmpty || state.memoryRecords.isNotEmpty) return false;
  return state.workingSetRecords.every(
    (record) =>
        _isOperatingEmailDraftRecord(record) ||
        _isOperatingEmailGuardrailRecord(record),
  );
}

bool _operatingEmailRecordMatchesSource(
  RuntimeWorkingSetRecord record,
  Set<String> sourceIds,
) {
  final sourceId = _firstOperatingString([
    record.raw['source_message_id'],
    record.raw['sourceMessageId'],
    record.raw['source_entry_id'],
    record.raw['sourceEntryId'],
    record.raw['assistant_turn_id'],
    record.raw['assistantTurnId'],
  ]);
  return sourceId == null || sourceIds.contains(sourceId);
}

final class _OperatingEmailUnavailableModeChip extends StatelessWidget {
  const _OperatingEmailUnavailableModeChip();

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.email;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDEC),
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: const Color(0xFFFFB4AB)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 13,
              color: Color(0xFFBA1A1A),
            ),
            const SizedBox(width: 4),
            Text(
              t.notConnected,
              style: const TextStyle(
                color: Color(0xFFBA1A1A),
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isOperatingEmailDraftRecord(RuntimeWorkingSetRecord record) {
  final kind = record.kind.trim().toLowerCase();
  if (kind == 'email_draft' ||
      kind == 'email_draft_candidate' ||
      kind == 'email_draft_only') {
    return true;
  }
  final rawKind = _firstOperatingString([
    record.raw['kind'],
    record.raw['type'],
    record.raw['record_kind'],
    record.raw['recordKind'],
  ])?.toLowerCase();
  if (rawKind == 'email_draft' ||
      rawKind == 'email_draft_candidate' ||
      rawKind == 'email_draft_only') {
    return true;
  }
  final tool = _firstOperatingString([
    record.raw['tool'],
    record.raw['tool_id'],
    record.raw['toolId'],
  ])?.toLowerCase();
  return tool == 'email.draft' || tool == 'email_draft';
}

bool _isOperatingEmailGuardrailRecord(RuntimeWorkingSetRecord record) {
  final kind = record.kind.trim().toLowerCase();
  if (kind == 'email_authorization_block' || kind == 'email_guardrail') {
    return true;
  }
  final tool = _firstOperatingString([
    record.raw['tool'],
    record.raw['tool_id'],
    record.raw['toolId'],
  ])?.toLowerCase();
  final action = _firstOperatingString([
    record.raw['action'],
    record.raw['blocked_action'],
    record.raw['blockedAction'],
  ])?.toLowerCase();
  final status = _firstOperatingString([
    record.raw['status'],
    record.raw['runtime_status'],
    record.raw['runtimeStatus'],
  ])?.toLowerCase();
  final blocksEmail = (tool != null && tool.startsWith('email.')) ||
      (action != null && action.contains('email'));
  if (!blocksEmail) return false;
  if (kind == 'external_tool_block' ||
      kind == 'external_side_effect_blocked' ||
      kind == 'tool_blocked') {
    return true;
  }
  final isBlocked = status == 'tool_unavailable' ||
      status == 'needs_configuration' ||
      status == 'external_side_effect_blocked' ||
      status == 'fail_closed' ||
      status == 'blocked' ||
      status == 'not_executed';
  return isBlocked;
}

final class _OperatingEmailDraftCard extends StatelessWidget {
  const _OperatingEmailDraftCard({
    required this.record,
    required this.onSaveDraft,
    required this.onConnectEmail,
  });

  final RuntimeWorkingSetRecord record;
  final VoidCallback onSaveDraft;
  final VoidCallback onConnectEmail;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.email;
    final raw = record.raw;
    final title = _firstOperatingString([
          raw['display_title'],
          raw['displayTitle'],
          raw['title'],
          record.title,
        ]) ??
        t.draftFallback;
    final recipients = _operatingEmailRecipients(raw);
    final subject = _firstOperatingString([
          raw['subject'],
          raw['email_subject'],
          raw['emailSubject'],
        ]) ??
        t.noSubject;
    final body = _firstOperatingString([
          raw['body'],
          raw['preview'],
          raw['content'],
          record.body,
          record.summary,
        ]) ??
        t.bodyUnavailable;
    final source = _firstOperatingString([
          raw['source'],
          raw['source_label'],
          raw['sourceLabel'],
        ]) ??
        t.runtimeDraft;
    final auditId = _firstOperatingString([
          raw['audit_id'],
          raw['auditId'],
          raw['draft_id'],
          raw['draftId'],
          record.id,
        ]) ??
        record.id;

    return KeyedSubtree(
      key: ValueKey('agent_operating_email_draft_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            const Icon(
              Icons.drafts_outlined,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.draftTitle,
                style: AgentOperatingSystemTokens.labelLg,
              ),
            ),
            const _OperatingStatusBadge(
              label: 'Draft Only',
              background: AgentOperatingSystemTokens.surfaceContainerHigh,
              foreground: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AgentOperatingSystemTokens.headlineSm.copyWith(
                color: AgentOperatingSystemTokens.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _OperatingEmailField(label: 'To:', value: recipients),
            const SizedBox(height: 8),
            _OperatingEmailField(label: 'Subject:', value: subject),
            const SizedBox(height: 8),
            _OperatingEmailBody(value: body),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OperatingEmailMetadataChip(label: 'Source: $source'),
                _OperatingEmailMetadataChip(label: 'Audit: $auditId'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey('agent_operating_email_save_${record.id}'),
                    label: 'Save Draft',
                    primary: true,
                    onPressed: onSaveDraft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey('agent_operating_email_connect_${record.id}'),
                    label: 'Connect Email',
                    onPressed: onConnectEmail,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingEmailGuardrailCard extends StatelessWidget {
  const _OperatingEmailGuardrailCard({required this.record});

  final RuntimeWorkingSetRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.email;
    final raw = record.raw;
    final reason = _firstOperatingString([
          raw['reason'],
          raw['runtime_status'],
          raw['runtimeStatus'],
          raw['status'],
        ]) ??
        'Needs Configuration';
    final connector = _firstOperatingString([
          raw['connector'],
          raw['connector_label'],
          raw['connectorLabel'],
        ]) ??
        'Email (Disconnected)';
    final action = _firstOperatingString([
          raw['blocked_action'],
          raw['blockedAction'],
          raw['action'],
        ]) ??
        'Send Email (Blocked)';
    final status = _firstOperatingString([
          raw['status_label'],
          raw['statusLabel'],
          raw['execution_status'],
          raw['executionStatus'],
        ]) ??
        'Not Executed (Fail Closed)';
    final risk = _firstOperatingString([
          raw['risk'],
          raw['risk_label'],
          raw['riskLabel'],
        ]) ??
        'Low';
    final auditId = _firstOperatingString([
          raw['audit_id'],
          raw['auditId'],
          record.id,
        ]) ??
        record.id;
    final tool = _firstOperatingString([
          raw['tool'],
          raw['tool_id'],
          raw['toolId'],
        ]) ??
        'email.send';

    return KeyedSubtree(
      key: ValueKey('agent_operating_email_guardrail_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            const Icon(
              Icons.security_rounded,
              color: Color(0xFFBA1A1A),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.guardrailTitle,
                style: AgentOperatingSystemTokens.labelLg,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OperatingDetailRow(label: 'Reason:', value: reason),
            const SizedBox(height: 5),
            _OperatingDetailRow(label: 'Connector:', value: connector),
            const SizedBox(height: 5),
            _OperatingDetailRow(
              label: 'Action:',
              value: action,
              valueStyle: AgentOperatingSystemTokens.bodySm.copyWith(
                color: const Color(0xFFBA1A1A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            _OperatingDetailRow(label: 'Status:', value: status),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OperatingEmailMetadataChip(label: 'Risk: $risk'),
                _OperatingEmailMetadataChip(label: 'Audit: $auditId'),
                _OperatingEmailMetadataChip(
                  label: 'tool: $tool',
                  icon: Icons.code_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingEmailField extends StatelessWidget {
  const _OperatingEmailField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainerLow,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: AgentOperatingSystemTokens.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _OperatingEmailBody extends StatelessWidget {
  const _OperatingEmailBody({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.bodyLabel,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AgentOperatingSystemTokens.surfaceContainerLow,
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _OperatingEmailMetadataChip extends StatelessWidget {
  const _OperatingEmailMetadataChip({
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: AgentOperatingSystemTokens.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _operatingEmailRecipients(Map<String, Object?> raw) {
  final direct = _firstOperatingString([
    raw['to'],
    raw['recipient'],
    raw['recipient_label'],
    raw['recipientLabel'],
  ]);
  if (direct != null) return direct;
  final rawRecipients = raw['recipients'];
  if (rawRecipients is List) {
    final recipients = rawRecipients
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (recipients.isNotEmpty) return recipients.join(', ');
  }
  return 'Recipient unavailable';
}
