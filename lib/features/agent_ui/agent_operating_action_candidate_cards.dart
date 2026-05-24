part of 'agent_conversation_page.dart';

bool _isOperatingActionItemCandidate(SecretaryRuntimeApprovalItem item) {
  final kind = item.kind.trim().toLowerCase();
  if (kind == 'action_item_candidate' ||
      kind == 'action_item_confirmation' ||
      kind == 'meeting_action_candidate') {
    return true;
  }
  final record = item.record ?? const <String, Object?>{};
  final recordKind = _firstOperatingString([
    record['kind'],
    record['type'],
    record['candidate_kind'],
    record['candidateKind'],
  ])?.toLowerCase();
  return recordKind == 'action_item_candidate' ||
      recordKind == 'meeting_action_candidate' ||
      recordKind == 'action_item';
}

final class _OperatingActionItemCandidateCard extends StatelessWidget {
  const _OperatingActionItemCandidateCard({
    required this.item,
    required this.onCreate,
    required this.onDismiss,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback? onCreate;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final record = item.record ?? const <String, Object?>{};
    final title = _firstOperatingString([
          record['title'],
          record['text'],
          record['summary'],
          item.title,
        ]) ??
        item.title;
    final description = _firstOperatingString([
      record['description'],
      record['body'],
      record['reason'],
      item.reason,
    ]);
    final candidateId = _firstOperatingString([
          record['candidate_id'],
          record['candidateId'],
          record['action_id'],
          record['actionId'],
          record['id'],
          item.sourceIntentId,
        ]) ??
        item.id;
    final due = _firstOperatingString([
      record['due_label'],
      record['dueLabel'],
      record['due'],
      record['due_at_label'],
      record['dueAtLabel'],
    ]);
    final sourceTime = _firstOperatingString([
      record['source_timestamp'],
      record['sourceTimestamp'],
      record['timestamp_label'],
      record['timestampLabel'],
      record['timecode'],
      record['timecode_label'],
      record['timecodeLabel'],
    ]);
    final risk = _firstOperatingString([
      record['risk_label'],
      record['riskLabel'],
      record['risk'],
    ]);
    final source = _firstOperatingString([
      record['source_id'],
      record['sourceId'],
      record['source'],
      record['meeting_id'],
      record['meetingId'],
    ]);

    return KeyedSubtree(
      key: ValueKey('agent_operating_action_candidate_${item.id}'),
      child: _OperatingCard(
        header: const Row(
          children: [
            Icon(
              Icons.add_task_rounded,
              color: AgentOperatingSystemTokens.secondary,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Action Item Candidate',
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AgentOperatingSystemTokens.headlineSm.copyWith(
                      color: AgentOperatingSystemTokens.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ActionCandidateIdBadge(label: candidateId),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (due != null) _OperatingDetailRow(label: 'Due:', value: due),
            if (due != null && sourceTime != null) const SizedBox(height: 5),
            if (sourceTime != null)
              _OperatingDetailRow(label: 'Source time:', value: sourceTime),
            if ((due != null || sourceTime != null) && source != null)
              const SizedBox(height: 5),
            if (source != null)
              _OperatingDetailRow(label: 'Source:', value: source),
            if (due == null && sourceTime == null && source == null)
              Text(
                'Runtime metadata incomplete',
                style: AgentOperatingSystemTokens.bodySm.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            if (risk != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _ActionCandidateRiskBadge(label: 'Risk: $risk'),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey(
                      'agent_operating_action_candidate_create_${item.id}',
                    ),
                    label: 'Create',
                    primary: true,
                    onPressed: onCreate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey(
                      'agent_operating_action_candidate_dismiss_${item.id}',
                    ),
                    label: 'Dismiss',
                    onPressed: onDismiss,
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

final class _ActionCandidateIdBadge extends StatelessWidget {
  const _ActionCandidateIdBadge({required this.label});

  final String label;

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _ActionCandidateRiskBadge extends StatelessWidget {
  const _ActionCandidateRiskBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final color = normalized.contains('low')
        ? const Color(0xFF15803D)
        : normalized.contains('high')
            ? const Color(0xFFB91C1C)
            : AgentOperatingSystemTokens.onSurfaceVariant;
    final background = normalized.contains('low')
        ? const Color(0xFFEFFDF4)
        : normalized.contains('high')
            ? const Color(0xFFFFF1F2)
            : AgentOperatingSystemTokens.surfaceContainerLow;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
