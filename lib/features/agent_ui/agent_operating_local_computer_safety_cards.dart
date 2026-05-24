part of 'agent_conversation_page.dart';

List<Widget> _operatingLocalComputerSafetyRuntimeCards({
  required RuntimeAgentState state,
  required Set<String> sourceIds,
  required ValueChanged<String> onSafeFollowUpSelected,
}) {
  final record = _operatingLocalComputerSafetyRecordForTurn(
    state: state,
    sourceIds: sourceIds,
  );
  if (record == null) return const <Widget>[];
  return [
    _OperatingLocalComputerSafetyProtocolCard(record: record),
    _OperatingLocalComputerSafetyAlternativeCard(
      record: record,
      onSaveToVault: () => onSafeFollowUpSelected(
        'Create a vault note draft with this manual Downloads cleanup '
        'checklist. Do not execute terminal commands, open Finder, or modify '
        'local files.',
      ),
    ),
    _OperatingLocalComputerSafetyMetadataCard(record: record),
  ];
}

final class _OperatingLocalComputerSafetyModeChip extends StatelessWidget {
  const _OperatingLocalComputerSafetyModeChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9EB),
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: const Color(0xFFFEE2B3)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 13,
              color: Color(0xFF854D0E),
            ),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Local Operation Blocked',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF854D0E),
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

final class _OperatingLocalComputerSafetyAssistantBubble
    extends StatelessWidget {
  const _OperatingLocalComputerSafetyAssistantBubble({
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
        ? 'I cannot execute terminal commands or modify local files. No '
            'action was taken.'
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
              key: ValueKey(
                'agent_operating_local_safety_refusal_${record.id}',
              ),
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
                              Text(
                                body,
                                style:
                                    AgentOperatingSystemTokens.bodyMd.copyWith(
                                  color: AgentOperatingSystemTokens.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Security Protocol: Local Computer Operation '
                                'Refusal (Approved)',
                                style:
                                    AgentOperatingSystemTokens.bodySm.copyWith(
                                  color: AgentOperatingSystemTokens
                                      .onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
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

final class _OperatingLocalComputerSafetyProtocolCard extends StatelessWidget {
  const _OperatingLocalComputerSafetyProtocolCard({required this.record});

  final RuntimeWorkingSetRecord record;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('agent_operating_local_safety_protocol_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            Expanded(
              child: Text(
                'Safety Protocol'.toUpperCase(),
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: AgentOperatingSystemTokens.secondary,
            ),
          ],
        ),
        child: const Column(
          children: [
            _OperatingLocalComputerSafetyProtocolRow(
              icon: Icons.check_circle_outline_rounded,
              text: 'No command executed',
              verified: true,
            ),
            SizedBox(height: 12),
            _OperatingLocalComputerSafetyProtocolRow(
              icon: Icons.check_circle_outline_rounded,
              text: 'No local file access',
              verified: true,
            ),
            SizedBox(height: 12),
            _OperatingLocalComputerSafetyProtocolRow(
              icon: Icons.check_circle_outline_rounded,
              text: 'No terminal automation',
              verified: true,
            ),
            SizedBox(height: 12),
            _OperatingLocalComputerSafetyProtocolRow(
              icon: Icons.info_outline_rounded,
              text: 'Manual review recommended',
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingLocalComputerSafetyProtocolRow extends StatelessWidget {
  const _OperatingLocalComputerSafetyProtocolRow({
    required this.icon,
    required this.text,
    this.verified = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String text;
  final bool verified;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: verified
              ? AgentOperatingSystemTokens.secondary
              : AgentOperatingSystemTokens.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AgentOperatingSystemTokens.bodyMd.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

final class _OperatingLocalComputerSafetyAlternativeCard
    extends StatelessWidget {
  const _OperatingLocalComputerSafetyAlternativeCard({
    required this.record,
    required this.onSaveToVault,
  });

  final RuntimeWorkingSetRecord record;
  final VoidCallback onSaveToVault;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('agent_operating_local_safety_alternative_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            const Icon(
              Icons.sticky_note_2_outlined,
              size: 16,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Alternative Action'.toUpperCase(),
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Downloads cleanup checklist',
              style: AgentOperatingSystemTokens.headlineSm,
            ),
            const SizedBox(height: 12),
            const _OperatingLocalComputerChecklistItem(
              text: 'Open Finder and navigate to Downloads',
            ),
            const SizedBox(height: 10),
            const _OperatingLocalComputerChecklistItem(
              text: "Locate the folder named 'test'",
            ),
            const SizedBox(height: 10),
            const _OperatingLocalComputerChecklistItem(
              text: 'Review contents before deletion',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: ValueKey('agent_operating_local_safety_save_${record.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AgentOperatingSystemTokens.onSurface,
                side: const BorderSide(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
                textStyle: AgentOperatingSystemTokens.labelLg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusSm,
                  ),
                ),
                minimumSize: const Size.fromHeight(36),
              ),
              onPressed: onSaveToVault,
              child: const Text('Save to Vault'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingLocalComputerChecklistItem extends StatelessWidget {
  const _OperatingLocalComputerChecklistItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AgentOperatingSystemTokens.outline),
              borderRadius: BorderRadius.circular(
                AgentOperatingSystemTokens.radiusSm,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AgentOperatingSystemTokens.bodySm.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

final class _OperatingLocalComputerSafetyMetadataCard extends StatelessWidget {
  const _OperatingLocalComputerSafetyMetadataCard({required this.record});

  final RuntimeWorkingSetRecord record;

  @override
  Widget build(BuildContext context) {
    final raw = record.raw;
    final skill = _operatingSafetySkill(
      raw,
      fallback: 'local-computer-safety',
    );
    final blockedAction = _operatingSafetyBlockedAction(
      raw,
      fallback: 'shell execution',
    );
    final status = _operatingSafetyStatusLabel(
      raw,
      fallback: 'Refused / No side effect',
    );
    final auditId = _operatingSafetyAuditId(record);
    final sourceId = _operatingSafetySourceId(record);
    final toolTrace = _operatingSafetyToolTrace(
      raw,
      fallback: 'safety-check-v2',
    );

    return KeyedSubtree(
      key: ValueKey('agent_operating_local_safety_metadata_${record.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            Expanded(
              child: Text(
                'Audit & Safety'.toUpperCase(),
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              auditId,
              style: AgentOperatingSystemTokens.code.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 18) / 2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OperatingSafetyMetadataItem(
                      width: itemWidth,
                      label: 'Skill',
                      value: skill,
                      code: true,
                    ),
                    const SizedBox(width: 18),
                    _OperatingSafetyMetadataItem(
                      width: itemWidth,
                      label: 'Status',
                      value: status,
                      valueColor: _operatingSafetyError,
                      valueWeight: FontWeight.w800,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _OperatingLocalComputerMetadataRow(
              label: 'Blocked Action',
              value: blockedAction,
            ),
            const SizedBox(height: 10),
            _OperatingLocalComputerMetadataRow(
              label: 'Source ID',
              value: sourceId,
            ),
            const SizedBox(height: 10),
            _OperatingLocalComputerMetadataRow(
              label: 'Tool Trace',
              value: toolTrace,
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingLocalComputerMetadataRow extends StatelessWidget {
  const _OperatingLocalComputerMetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            softWrap: true,
            style: AgentOperatingSystemTokens.code.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
