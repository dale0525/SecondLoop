part of 'agent_conversation_page.dart';

const _operatingSafetyError = Color(0xFFBA1A1A);
const _operatingSafetyErrorContainer = Color(0xFFFFEDEC);
const _operatingSafetyErrorOutline = Color(0xFFFFB4AB);

List<Widget> _operatingPurchasePaymentSafetyRuntimeCards({
  required RuntimeAgentState state,
  required Set<String> sourceIds,
  required ValueChanged<String> onSafeFollowUpSelected,
}) {
  final record = _operatingPurchasePaymentSafetyRecordForTurn(
    state: state,
    sourceIds: sourceIds,
  );
  if (record == null) return const <Widget>[];
  return [
    _OperatingPurchasePaymentSafetyAlternativesCard(
      record: record,
      onSafeFollowUpSelected: onSafeFollowUpSelected,
    ),
    _OperatingPurchasePaymentSafetyMetadataCard(record: record),
  ];
}

bool _hasOperatingPurchasePaymentSafetyState(RuntimeAgentState? state) {
  if (state == null) return false;
  return state.workingSetRecords.any(_isOperatingPurchasePaymentSafetyRecord);
}

bool _hasOperatingLocalComputerSafetyState(RuntimeAgentState? state) {
  if (state == null) return false;
  return state.workingSetRecords.any(_isOperatingLocalComputerSafetyRecord);
}

RuntimeWorkingSetRecord? _operatingPurchasePaymentSafetyRecordForTurn({
  required RuntimeAgentState? state,
  required Set<String> sourceIds,
}) {
  if (state == null) return null;
  final normalizedSourceIds =
      sourceIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  for (final record in state.workingSetRecords) {
    if (!_isOperatingPurchasePaymentSafetyRecord(record)) continue;
    if (_operatingSafetyRecordMatchesSource(record, normalizedSourceIds)) {
      return record;
    }
  }
  return null;
}

RuntimeWorkingSetRecord? _operatingLocalComputerSafetyRecordForTurn({
  required RuntimeAgentState? state,
  required Set<String> sourceIds,
}) {
  if (state == null) return null;
  final normalizedSourceIds =
      sourceIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  for (final record in state.workingSetRecords) {
    if (!_isOperatingLocalComputerSafetyRecord(record)) continue;
    if (_operatingSafetyRecordMatchesSource(record, normalizedSourceIds)) {
      return record;
    }
  }
  return null;
}

bool _operatingSafetyRecordMatchesSource(
  RuntimeWorkingSetRecord record,
  Set<String> sourceIds,
) {
  if (sourceIds.isEmpty) return true;
  final raw = record.raw;
  final recordSourceIds = <String>{
    ..._operatingStringList(raw['source_message_ids']),
    ..._operatingStringList(raw['sourceMessageIds']),
    ..._operatingStringList(raw['source_turn_ids']),
    ..._operatingStringList(raw['sourceTurnIds']),
    _firstOperatingString([
          raw['source_message_id'],
          raw['sourceMessageId'],
          raw['source_entry_id'],
          raw['sourceEntryId'],
          raw['assistant_turn_id'],
          raw['assistantTurnId'],
        ]) ??
        '',
  }..removeWhere((id) => id.trim().isEmpty);
  return recordSourceIds.isEmpty ||
      recordSourceIds.any((id) => sourceIds.contains(id.trim()));
}

bool _isOperatingPurchasePaymentSafetyRecord(RuntimeWorkingSetRecord record) {
  final kind = record.kind.trim().toLowerCase();
  final raw = record.raw;
  final rawKind = _firstOperatingString([
    raw['kind'],
    raw['type'],
    raw['record_kind'],
    raw['recordKind'],
  ])?.toLowerCase();
  final skill = (_operatingSafetyExplicitSkill(raw) ?? '').toLowerCase();
  final status = _operatingSafetyStatus(raw).toLowerCase();
  final blockedAction = _operatingSafetyExplicitBlockedAction(
        raw,
      )?.toLowerCase() ??
      '';
  final tool = _firstOperatingString([
    raw['tool'],
    raw['tool_id'],
    raw['toolId'],
  ])?.toLowerCase();

  final explicitlyPurchaseSafety =
      skill == 'purchase-payment-safety' || tool == 'purchase-payment-safety';
  final isBlockedKind = kind == 'external_side_effect_blocked' ||
      kind == 'external_tool_block' ||
      kind == 'tool_blocked' ||
      rawKind == 'external_side_effect_blocked' ||
      rawKind == 'external_tool_block' ||
      rawKind == 'tool_blocked';
  final isBlockedStatus = status == 'external_side_effect_blocked' ||
      status == 'refused' ||
      status == 'blocked' ||
      status == 'fail_closed' ||
      status == 'not_executed';
  final mentionsTransaction = blockedAction.contains('purchase') ||
      blockedAction.contains('payment') ||
      blockedAction.contains('ticket') ||
      blockedAction.contains('booking') ||
      blockedAction.contains('transfer') ||
      blockedAction.contains('signing');

  return explicitlyPurchaseSafety ||
      (isBlockedKind && isBlockedStatus && mentionsTransaction);
}

bool _isOperatingLocalComputerSafetyRecord(RuntimeWorkingSetRecord record) {
  final kind = record.kind.trim().toLowerCase();
  final raw = record.raw;
  final rawKind = _firstOperatingString([
    raw['kind'],
    raw['type'],
    raw['record_kind'],
    raw['recordKind'],
  ])?.toLowerCase();
  final skill = (_operatingSafetyExplicitSkill(raw) ?? '').toLowerCase();
  final status = _operatingSafetyStatus(raw).toLowerCase();
  final blockedAction = _operatingSafetyExplicitBlockedAction(
        raw,
      )?.toLowerCase() ??
      '';
  final tool = _firstOperatingString([
    raw['tool'],
    raw['tool_id'],
    raw['toolId'],
  ])?.toLowerCase();

  final explicitlyLocalComputerSafety =
      skill == 'local-computer-safety' || tool == 'local-computer-safety';
  final isBlockedKind = kind == 'external_side_effect_blocked' ||
      kind == 'external_tool_block' ||
      kind == 'tool_blocked' ||
      rawKind == 'external_side_effect_blocked' ||
      rawKind == 'external_tool_block' ||
      rawKind == 'tool_blocked';
  final isBlockedStatus = status == 'external_side_effect_blocked' ||
      status == 'refused' ||
      status == 'blocked' ||
      status == 'fail_closed' ||
      status == 'not_executed';
  final mentionsLocalComputer = blockedAction.contains('shell') ||
      blockedAction.contains('terminal') ||
      blockedAction.contains('local file') ||
      blockedAction.contains('local computer') ||
      blockedAction.contains('finder') ||
      blockedAction.contains('desktop') ||
      blockedAction.contains('computer operation');

  return explicitlyLocalComputerSafety ||
      (isBlockedKind && isBlockedStatus && mentionsLocalComputer);
}

final class _OperatingPurchasePaymentSafetyModeChip extends StatelessWidget {
  const _OperatingPurchasePaymentSafetyModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _operatingSafetyErrorContainer,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: _operatingSafetyErrorOutline),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              Icons.block_rounded,
              size: 13,
              color: _operatingSafetyError,
            ),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Blocked External Transaction',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _operatingSafetyError,
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingPurchasePaymentSafetyAssistantBubble
    extends StatelessWidget {
  const _OperatingPurchasePaymentSafetyAssistantBubble({
    required this.record,
    required this.content,
    required this.messageId,
    required this.createdAtMs,
    this.mediaResults = const <_AgentMessageMediaResultView>[],
  });

  final RuntimeWorkingSetRecord record;
  final String content;
  final String messageId;
  final int? createdAtMs;
  final List<_AgentMessageMediaResultView> mediaResults;

  @override
  Widget build(BuildContext context) {
    final body = content.trim().isEmpty
        ? 'I cannot execute direct purchases or financial payments on your '
            'behalf. No transaction has been initiated.'
        : content.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: KeyedSubtree(
              key: ValueKey('agent_operating_safety_refusal_${record.id}'),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AgentOperatingSystemTokens.surface,
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusLg,
                  ),
                  border: Border.all(
                    color: AgentOperatingSystemTokens.outlineVariant,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(
                        width: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AgentOperatingSystemTokens.secondary,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(
                                AgentOperatingSystemTokens.radiusLg,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    color: AgentOperatingSystemTokens.secondary,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Security Protocol Active',
                                      style: TextStyle(
                                        color: AgentOperatingSystemTokens
                                            .secondary,
                                        fontSize: 12,
                                        height: 16 / 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                body,
                                style:
                                    AgentOperatingSystemTokens.bodyMd.copyWith(
                                  color: AgentOperatingSystemTokens.onSurface,
                                ),
                              ),
                              if (mediaResults.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                KeyedSubtree(
                                  key: ValueKey(
                                    'agent_assistant_media_results_$messageId',
                                  ),
                                  child: _AssistantRuntimeMediaResults(
                                    results: mediaResults,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (createdAtMs != null && createdAtMs! > 0) ...[
            const SizedBox(height: 4),
            _OperatingTurnTimeLabel(createdAtMs: createdAtMs!),
          ],
        ],
      ),
    );
  }
}

final class _OperatingPurchasePaymentSafetyAlternativesCard
    extends StatelessWidget {
  const _OperatingPurchasePaymentSafetyAlternativesCard({
    required this.record,
    required this.onSafeFollowUpSelected,
  });

  final RuntimeWorkingSetRecord record;
  final ValueChanged<String> onSafeFollowUpSelected;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('agent_operating_safety_alternatives_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            const Expanded(
              child: Text(
                'Safe Alternatives',
                style: AgentOperatingSystemTokens.headlineSm,
              ),
            ),
            Text(
              '3 Actions Available',
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
              ),
            ),
          ],
        ),
        child: Column(
          children: [
            _OperatingSafetyAlternativeRow(
              icon: Icons.search_rounded,
              title: 'Research train options',
              subtitle: 'Find schedule and availability',
              actionLabel: 'Research',
              onPressed: () => onSafeFollowUpSelected(
                'Research tomorrow train options to Shanghai with schedule, '
                'availability, and citations. Do not book or pay.',
              ),
              keySuffix: 'research_${record.id}',
            ),
            const Divider(height: 1),
            _OperatingSafetyAlternativeRow(
              icon: Icons.checklist_rounded,
              title: 'Create booking checklist',
              subtitle: 'Prepare required passenger details',
              actionLabel: 'Create',
              onPressed: () => onSafeFollowUpSelected(
                'Create a manual booking checklist for two train tickets to '
                'Shanghai. Do not book, purchase, or pay.',
              ),
              keySuffix: 'checklist_${record.id}',
            ),
            const Divider(height: 1),
            _OperatingSafetyAlternativeRow(
              icon: Icons.notification_add_outlined,
              title: 'Set reminder for manual booking',
              subtitle: 'Alert for manual ticket release',
              actionLabel: 'Set',
              onPressed: () => onSafeFollowUpSelected(
                'Draft a reminder for me to manually book the Shanghai train '
                'tickets. Do not book or pay.',
              ),
              keySuffix: 'reminder_${record.id}',
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingSafetyAlternativeRow extends StatelessWidget {
  const _OperatingSafetyAlternativeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    required this.keySuffix,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;
  final String keySuffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AgentOperatingSystemTokens.surfaceContainerLow,
                border: Border.all(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(
                  AgentOperatingSystemTokens.radiusSm,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: AgentOperatingSystemTokens.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AgentOperatingSystemTokens.labelLg.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            key: ValueKey('agent_operating_safety_$keySuffix'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AgentOperatingSystemTokens.secondary,
              side: const BorderSide(
                color: AgentOperatingSystemTokens.secondary,
              ),
              textStyle: AgentOperatingSystemTokens.labelLg.copyWith(
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AgentOperatingSystemTokens.radiusSm,
                ),
              ),
              minimumSize: const Size(78, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

final class _OperatingPurchasePaymentSafetyMetadataCard
    extends StatelessWidget {
  const _OperatingPurchasePaymentSafetyMetadataCard({required this.record});

  final RuntimeWorkingSetRecord record;

  @override
  Widget build(BuildContext context) {
    final raw = record.raw;
    final skill = _operatingSafetySkill(raw);
    final blockedAction = _operatingSafetyBlockedAction(raw);
    final status = _operatingSafetyStatusLabel(raw);
    final auditId = _operatingSafetyAuditId(record);
    final sourceId = _operatingSafetySourceId(record);
    final toolTrace = _operatingSafetyToolTrace(raw);

    return KeyedSubtree(
      key: ValueKey('agent_operating_safety_metadata_${record.id}'),
      child: _OperatingCard(
        header: Text(
          'Transaction Safety Protocol'.toUpperCase(),
          style: AgentOperatingSystemTokens.labelLg.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 500;
            final itemWidth = twoColumn
                ? (constraints.maxWidth - 18) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 18,
              runSpacing: 16,
              children: [
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Skill',
                  value: skill,
                  code: true,
                  valueColor: AgentOperatingSystemTokens.secondary,
                ),
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Blocked Action',
                  value: blockedAction,
                ),
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Status',
                  value: status,
                  valueColor: _operatingSafetyError,
                  valueWeight: FontWeight.w800,
                ),
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Audit ID',
                  value: auditId,
                  code: true,
                ),
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Source ID',
                  value: sourceId,
                  code: true,
                ),
                _OperatingSafetyMetadataItem(
                  width: itemWidth,
                  label: 'Tool Trace',
                  value: toolTrace,
                  code: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _OperatingSafetyMetadataItem extends StatelessWidget {
  const _OperatingSafetyMetadataItem({
    required this.width,
    required this.label,
    required this.value,
    this.code = false,
    this.valueColor,
    this.valueWeight,
  });

  final double width;
  final String label;
  final String value;
  final bool code;
  final Color? valueColor;
  final FontWeight? valueWeight;

  @override
  Widget build(BuildContext context) {
    final valueStyle = (code
            ? AgentOperatingSystemTokens.code
            : AgentOperatingSystemTokens.bodySm)
        .copyWith(
      color: valueColor ?? AgentOperatingSystemTokens.onSurface,
      fontWeight: valueWeight ?? (code ? FontWeight.w600 : FontWeight.w400),
    );
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          if (code)
            DecoratedBox(
              decoration: BoxDecoration(
                color: AgentOperatingSystemTokens.surfaceContainerLow,
                borderRadius: BorderRadius.circular(
                  AgentOperatingSystemTokens.radiusSm,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                child: Text(
                  value,
                  softWrap: true,
                  style: valueStyle,
                ),
              ),
            )
          else
            Text(
              value,
              softWrap: true,
              style: valueStyle,
            ),
        ],
      ),
    );
  }
}

String _operatingSafetySkill(
  Map<String, Object?> raw, {
  String fallback = 'purchase-payment-safety',
}) {
  return _operatingSafetyExplicitSkill(raw) ?? fallback;
}

String? _operatingSafetyExplicitSkill(Map<String, Object?> raw) {
  return _firstOperatingString([
    raw['skill'],
    raw['skill_id'],
    raw['skillId'],
    raw['runtime_skill'],
    raw['runtimeSkill'],
  ]);
}

String _operatingSafetyBlockedAction(
  Map<String, Object?> raw, {
  String fallback = 'ticket purchase + payment',
}) {
  return _operatingSafetyExplicitBlockedAction(raw) ?? fallback;
}

String? _operatingSafetyExplicitBlockedAction(Map<String, Object?> raw) {
  return _firstOperatingString([
    raw['blocked_action'],
    raw['blockedAction'],
    raw['action'],
    raw['external_action'],
    raw['externalAction'],
  ]);
}

String _operatingSafetyStatus(Map<String, Object?> raw) {
  return _firstOperatingString([
        raw['status'],
        raw['runtime_status'],
        raw['runtimeStatus'],
        raw['execution_status'],
        raw['executionStatus'],
      ]) ??
      'external_side_effect_blocked';
}

String _operatingSafetyStatusLabel(
  Map<String, Object?> raw, {
  String fallback = 'Refused / No external action',
}) {
  return _firstOperatingString([
        raw['status_label'],
        raw['statusLabel'],
        raw['execution_status_label'],
        raw['executionStatusLabel'],
      ]) ??
      fallback;
}

String _operatingSafetyAuditId(RuntimeWorkingSetRecord record) {
  return _firstOperatingString([
        record.raw['audit_id'],
        record.raw['auditId'],
        record.raw['audit_ref'],
        record.raw['auditRef'],
        record.id,
      ]) ??
      record.id;
}

String _operatingSafetySourceId(RuntimeWorkingSetRecord record) {
  return _firstOperatingString([
        record.raw['source_id'],
        record.raw['sourceId'],
        record.raw['source_message_id'],
        record.raw['sourceMessageId'],
        record.raw['source_entry_id'],
        record.raw['sourceEntryId'],
      ]) ??
      'runtime';
}

String _operatingSafetyToolTrace(
  Map<String, Object?> raw, {
  String fallback = 'safe-check-v2',
}) {
  final trace = raw['tool_trace'] ?? raw['toolTrace'];
  if (trace is Map) {
    return _firstOperatingString([
          trace['id'],
          trace['trace_id'],
          trace['traceId'],
          trace['tool'],
          trace['tool_id'],
          trace['toolId'],
          trace['name'],
        ]) ??
        fallback;
  }
  return _firstOperatingString([
        trace,
        raw['tool_trace_id'],
        raw['toolTraceId'],
        raw['tool'],
        raw['tool_id'],
        raw['toolId'],
      ]) ??
      fallback;
}
