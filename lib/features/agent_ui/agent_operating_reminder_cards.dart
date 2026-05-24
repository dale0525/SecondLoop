part of 'agent_conversation_page.dart';

typedef _OperatingApprovalTitleChanged = void Function(
  SecretaryRuntimeApprovalItem item,
  String title,
);

final class _OperatingPendingIntent {
  const _OperatingPendingIntent({
    required this.id,
    required this.requirement,
    required this.reasoning,
    required this.statusLabel,
    required this.sourceIds,
  });

  final String id;
  final String requirement;
  final String reasoning;
  final String statusLabel;
  final Set<String> sourceIds;
}

final class _OperatingDateChip extends StatelessWidget {
  const _OperatingDateChip({required this.createdAtMs});

  final int createdAtMs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            _operatingDateLabel(createdAtMs),
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingTurnTimeLabel extends StatelessWidget {
  const _OperatingTurnTimeLabel({required this.createdAtMs});

  final int createdAtMs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        _operatingTimeLabel(createdAtMs),
        style: AgentOperatingSystemTokens.labelMd.copyWith(
          color: AgentOperatingSystemTokens.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _OperatingPendingIntentCard extends StatelessWidget {
  const _OperatingPendingIntentCard({required this.intent});

  final _OperatingPendingIntent intent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: KeyedSubtree(
          key: ValueKey('agent_operating_pending_intent_${intent.id}'),
          child: _OperatingCard(
            header: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pending Intent',
                    style: AgentOperatingSystemTokens.labelLg.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  intent.statusLabel.toUpperCase(),
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            child: Column(
              children: [
                _OperatingDetailRow(
                  label: 'Requirement:',
                  value: intent.requirement,
                  valueStyle: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _OperatingDetailRow(
                  label: 'Reasoning:',
                  value: intent.reasoning,
                  valueStyle: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingRecurringReminderCandidateCard extends StatelessWidget {
  const _OperatingRecurringReminderCandidateCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
    required this.onEditTitle,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final ValueChanged<String>? onEditTitle;

  @override
  Widget build(BuildContext context) {
    final record = item.record ?? const <String, Object?>{};
    final title = _firstOperatingString([
          record['title'],
          record['text'],
          record['content'],
          item.title,
        ]) ??
        item.title;
    final schedule = _firstOperatingString([
          record['schedule_label'],
          record['scheduleLabel'],
          record['rrule_label'],
          record['rruleLabel'],
          record['human_schedule'],
          record['humanSchedule'],
          record['schedule'],
        ]) ??
        'Schedule pending';
    final nextTrigger = _firstOperatingString([
          record['next_trigger_label'],
          record['nextTriggerLabel'],
          record['next_trigger'],
          record['nextTrigger'],
        ]) ??
        'Pending approval';
    final risk = _firstOperatingString([
          record['risk_assessment'],
          record['riskAssessment'],
          record['risk'],
          record['conflict_risk'],
          record['conflictRisk'],
        ]) ??
        'Unknown';
    final auditId = _firstOperatingString([
          record['audit_id'],
          record['auditId'],
        ]) ??
        item.id;

    return KeyedSubtree(
      key: ValueKey('agent_operating_recurring_reminder_${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OperatingCard(
            header: const Row(
              children: [
                Icon(
                  Icons.event_repeat_rounded,
                  color: AgentOperatingSystemTokens.muted,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recurring Reminder Candidate',
                    style: AgentOperatingSystemTokens.labelLg,
                  ),
                ),
                _OperatingStatusBadge(
                  label: 'Pending Approval',
                  background: AgentOperatingSystemTokens.surfaceContainerHigh,
                  foreground: AgentOperatingSystemTokens.onSurfaceVariant,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AgentOperatingSystemTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(
                      AgentOperatingSystemTokens.radiusSm,
                    ),
                    border: Border.all(
                      color: AgentOperatingSystemTokens.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AgentOperatingSystemTokens.bodyMd.copyWith(
                            color: AgentOperatingSystemTokens.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              color: AgentOperatingSystemTokens.secondary,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                schedule,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    AgentOperatingSystemTokens.labelLg.copyWith(
                                  color: AgentOperatingSystemTokens.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _OperatingDetailRow(label: 'Next trigger:', value: nextTrigger),
                const SizedBox(height: 5),
                _OperatingDetailRow(label: 'Risk Assessment:', value: risk),
                const SizedBox(height: 5),
                _OperatingDetailRow(label: 'Audit ID:', value: auditId),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _OperatingFooterTextButton(
                        key: ValueKey(
                          'agent_operating_recurring_approve_${item.id}',
                        ),
                        label: 'Approve',
                        primary: true,
                        onPressed: onApprove,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OperatingFooterTextButton(
                        key: ValueKey(
                          'agent_operating_recurring_edit_${item.id}',
                        ),
                        label: 'Edit',
                        onPressed: onEditTitle == null
                            ? null
                            : () => _showTitleEditor(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OperatingFooterTextButton(
                        key: ValueKey(
                          'agent_operating_recurring_dismiss_${item.id}',
                        ),
                        label: 'Dismiss',
                        onPressed: onReject,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No recurring reminder is active until approved.',
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTitleEditor(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RuntimeApprovalTitleDialog(item: item),
    );
    final nextTitle = title?.trim() ?? '';
    if (nextTitle.isEmpty) return;
    onEditTitle?.call(nextTitle);
  }
}

final class _OperatingFooterTextButton extends StatelessWidget {
  const _OperatingFooterTextButton({
    required super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary
        ? AgentOperatingSystemTokens.secondary
        : AgentOperatingSystemTokens.onSurfaceVariant;
    return SizedBox(
      height: 36,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor:
              AgentOperatingSystemTokens.onSurfaceVariant.withOpacity(0.45),
          textStyle: AgentOperatingSystemTokens.labelLg.copyWith(
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
          ),
        ),
        onPressed: onPressed,
        child: Text(label.toUpperCase()),
      ),
    );
  }
}

final class _OperatingDetailRow extends StatelessWidget {
  const _OperatingDetailRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: valueStyle ??
                AgentOperatingSystemTokens.bodySm.copyWith(
                  color: AgentOperatingSystemTokens.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}

List<Widget> _operatingPendingIntentCards({
  required RuntimeAgentState? state,
  required String? userMessageId,
  required String assistantMessageId,
  required Set<String> renderedIds,
}) {
  final sourceIds = <String>{
    assistantMessageId.trim(),
    if (userMessageId != null) userMessageId.trim(),
  }..removeWhere((id) => id.isEmpty);
  if (sourceIds.isEmpty) return const <Widget>[];

  final records = state?.workingSetRecords ?? const <RuntimeWorkingSetRecord>[];
  final cards = <Widget>[];
  for (final record in records) {
    final intent = _operatingPendingIntentFromRecord(record);
    if (intent == null || renderedIds.contains(intent.id)) continue;
    if (!intent.sourceIds.any(sourceIds.contains)) continue;
    renderedIds.add(intent.id);
    cards.add(_OperatingPendingIntentCard(intent: intent));
  }
  return cards;
}

_OperatingPendingIntent? _operatingPendingIntentFromRecord(
  RuntimeWorkingSetRecord record,
) {
  final raw = record.raw;
  final kind = record.kind.trim();
  final status = _firstOperatingString([
    raw['status'],
    raw['state'],
    raw['run_status'],
    raw['runStatus'],
  ]);
  final missingSlot = _operatingMissingSlotLabel(raw);
  final looksPending = kind == 'pending_intent' ||
      kind == 'pending_action_intent' ||
      kind == 'clarification_pending_intent' ||
      (missingSlot != null &&
          (status == 'action_halted' ||
              status == 'needs_clarification' ||
              status == 'pending_clarification'));
  if (!looksPending) return null;

  final id = record.id.isNotEmpty
      ? record.id
      : _firstOperatingString([raw['id'], raw['intent_id'], raw['intentId']]);
  if (id == null || id.isEmpty) return null;

  final sourceIds = _operatingSourceIds(raw);
  if (sourceIds.isEmpty) return null;

  final requirement = _firstOperatingString([
        raw['requirement'],
        raw['missing_slot_label'],
        raw['missingSlotLabel'],
      ]) ??
      (missingSlot == null ? 'Missing Slot' : 'Missing Slot: $missingSlot');
  final reasoning = _firstOperatingString([
        raw['reasoning'],
        raw['reason'],
        raw['explanation'],
      ]) ??
      'Action requires a missing value before runtime can continue.';
  final statusLabel = _firstOperatingString([
        raw['status_label'],
        raw['statusLabel'],
      ]) ??
      (status == 'needs_clarification' ? 'Action Halted' : 'Action Halted');

  return _OperatingPendingIntent(
    id: id,
    requirement: requirement,
    reasoning: reasoning,
    statusLabel: statusLabel,
    sourceIds: sourceIds,
  );
}

Set<String> _operatingSourceIds(Map<String, Object?> raw) {
  return <String>{
    ..._operatingStringList(raw['source_message_ids']),
    ..._operatingStringList(raw['sourceMessageIds']),
    ..._operatingStringList(raw['source_turn_ids']),
    ..._operatingStringList(raw['sourceTurnIds']),
    ..._operatingStringList(raw['source_ids']),
    ..._operatingStringList(raw['sourceIds']),
    for (final value in [
      raw['source_message_id'],
      raw['sourceMessageId'],
      raw['source_user_message_id'],
      raw['sourceUserMessageId'],
      raw['source_assistant_message_id'],
      raw['sourceAssistantMessageId'],
      raw['assistant_message_id'],
      raw['assistantMessageId'],
      raw['message_id'],
      raw['messageId'],
      raw['turn_id'],
      raw['turnId'],
    ])
      if (value is String && value.trim().isNotEmpty) value.trim(),
  };
}

String? _operatingMissingSlotLabel(Map<String, Object?> raw) {
  final direct = _firstOperatingString([
    raw['missing_slot'],
    raw['missingSlot'],
    raw['slot'],
    raw['slot_label'],
    raw['slotLabel'],
  ]);
  if (direct != null) return direct;

  final slots = raw['missing_slots'] ?? raw['missingSlots'];
  if (slots is List) {
    for (final slot in slots) {
      if (slot is String && slot.trim().isNotEmpty) return slot.trim();
      if (slot is Map) {
        final label = _firstOperatingString([
          slot['label'],
          slot['name'],
          slot['id'],
        ]);
        if (label != null) return label;
      }
    }
  }
  return null;
}

List<String> _operatingStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

String _operatingDateLabel(int createdAtMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _operatingTimeLabel(int createdAtMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
