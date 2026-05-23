part of 'agent_conversation_page.dart';

final class _OperatingTaskCreatedCard extends StatelessWidget {
  const _OperatingTaskCreatedCard({
    required this.record,
    required this.onOpen,
  });

  final RuntimeWorkingSetRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final mutationId = _firstOperatingString([
          record.raw['mutation_id'],
          record.raw['mutationId'],
        ]) ??
        record.id;
    final auditId = _firstOperatingString([
          record.raw['audit_id'],
          record.raw['auditId'],
        ]) ??
        'not recorded';
    return _OperatingCard(
      header: const Row(
        children: [
          Icon(
            Icons.task_alt_rounded,
            color: AgentOperatingSystemTokens.secondary,
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Task Created',
              style: AgentOperatingSystemTokens.labelLg,
            ),
          ),
          _OperatingStatusBadge(
            label: 'Applied',
            background: AgentOperatingSystemTokens.secondaryContainer,
            foreground: AgentOperatingSystemTokens.onSecondaryContainer,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            record.title,
            style: AgentOperatingSystemTokens.headlineSm.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          const _OperatingFactRow(label: 'Source', value: 'User message'),
          _OperatingFactRow(label: 'Mutation ID', value: mutationId),
          _OperatingFactRow(label: 'Audit ID', value: auditId, last: true),
          const SizedBox(height: 14),
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              key: ValueKey('agent_operating_open_task_${record.id}'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C839B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusSm,
                  ),
                ),
              ),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open Task'),
            ),
          ),
        ],
      ),
    );
  }
}

final class _OperatingMemoryCandidateCard extends StatelessWidget {
  const _OperatingMemoryCandidateCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  final SecretaryRuntimeApprovalItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final record = item.record ?? const <String, Object?>{};
    final text = _firstOperatingString([
          record['text'],
          record['content'],
          record['title'],
          item.title,
        ]) ??
        item.title;
    final risk = _firstOperatingString([
          record['conflict_risk'],
          record['conflictRisk'],
        ]) ??
        'Unknown';
    final auditId = _firstOperatingString([
          record['audit_id'],
          record['auditId'],
        ]) ??
        item.id;

    return _OperatingCard(
      header: const Row(
        children: [
          Icon(
            Icons.psychology_alt_outlined,
            color: AgentOperatingSystemTokens.muted,
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Memory Candidate',
              style: AgentOperatingSystemTokens.labelLg,
            ),
          ),
          _OperatingStatusBadge(
            label: 'Pending approval',
            background: AgentOperatingSystemTokens.surfaceContainerHigh,
            foreground: AgentOperatingSystemTokens.onSurfaceVariant,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '"$text"',
            style: AgentOperatingSystemTokens.bodyMd.copyWith(
              color: AgentOperatingSystemTokens.onSurface,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          _OperatingFactRow(
            label: 'Conflict Risk',
            value: risk,
            valueColor: AgentOperatingSystemTokens.secondary,
            valueWeight: FontWeight.w800,
          ),
          _OperatingFactRow(label: 'Audit ID', value: auditId, last: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: ValueKey('agent_operating_memory_approve_${item.id}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AgentOperatingSystemTokens.secondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AgentOperatingSystemTokens.radiusSm,
                      ),
                    ),
                  ),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _OperatingCard extends StatelessWidget {
  const _OperatingCard({
    required this.header,
    required this.child,
  });

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ColoredBox(
              color: AgentOperatingSystemTokens.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: header,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingStatusBadge extends StatelessWidget {
  const _OperatingStatusBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: foreground,
          ),
        ),
      ),
    );
  }
}

final class _OperatingFactRow extends StatelessWidget {
  const _OperatingFactRow({
    required this.label,
    required this.value,
    this.valueColor = AgentOperatingSystemTokens.onSurfaceVariant,
    this.valueWeight = FontWeight.w500,
    this.last = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final FontWeight valueWeight;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x55C6C6CD)),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AgentOperatingSystemTokens.labelMd.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AgentOperatingSystemTokens.code.copyWith(
                  color: valueColor,
                  fontWeight: valueWeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingContextStrip extends StatelessWidget {
  const _OperatingContextStrip({required this.state});

  final RuntimeAgentState? state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surfaceContainer.withOpacity(0.3),
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OperatingContextItem(
                icon: Icons.storage_rounded,
                label: 'Entity Ref:',
                value: _entityRefLabel(),
                chip: true,
              ),
              const _OperatingContextDivider(),
              _OperatingContextItem(
                icon: Icons.memory_rounded,
                label: 'Active Memory:',
                value: _activeMemoryLabel(),
              ),
              const _OperatingContextDivider(),
              _OperatingContextItem(
                icon: Icons.folder_open_rounded,
                label: 'Working set:',
                value: '${_fileCount()} files',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _entityRefLabel() {
    final refs = state?.recentEntityRefs ?? const <Map<String, Object?>>[];
    for (final ref in refs) {
      final type = _firstOperatingString([
            ref['entity_type'],
            ref['entityType'],
            ref['type'],
          ]) ??
          'entity';
      final title = _firstOperatingString([ref['title'], ref['name']]);
      if (title != null) return '$type:"$title"';
    }
    final task = state?.tasks.firstOrNull;
    if (task != null) return 'task:"${task.title}"';
    return 'none';
  }

  String _activeMemoryLabel() {
    final memories = state?.memoryRecords ?? const <RuntimeWorkingSetRecord>[];
    if (memories.isEmpty) return 'none yet';
    if (memories.length == 1) return memories.first.title;
    return '${memories.length} active';
  }

  int _fileCount() {
    final records =
        state?.workingSetRecords ?? const <RuntimeWorkingSetRecord>[];
    return records
        .where((record) =>
            record.kind == 'file' ||
            record.kind == 'attachment' ||
            record.kind == 'media_result')
        .length;
  }
}

final class _OperatingContextItem extends StatelessWidget {
  const _OperatingContextItem({
    required this.icon,
    required this.label,
    required this.value,
    this.chip = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      style: AgentOperatingSystemTokens.labelMd.copyWith(
        color: AgentOperatingSystemTokens.onSurface,
        fontStyle: value == 'none yet' ? FontStyle.italic : FontStyle.normal,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 16, color: AgentOperatingSystemTokens.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        if (chip)
          DecoratedBox(
            decoration: BoxDecoration(
              color: AgentOperatingSystemTokens.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(
                AgentOperatingSystemTokens.radiusSm,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: valueText,
            ),
          )
        else
          valueText,
      ],
    );
  }
}

final class _OperatingContextDivider extends StatelessWidget {
  const _OperatingContextDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: AgentOperatingSystemTokens.outlineVariant,
    );
  }
}

final class _OperatingComposer extends StatelessWidget {
  const _OperatingComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final List<AttachmentDraftPayload> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surface,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachments.isNotEmpty) ...[
                _AttachmentDraftStrip(
                  attachments: attachments,
                  onRemoveAttachment: onRemoveAttachment,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('chat_attach'),
                    tooltip: 'Attach',
                    onPressed: busy ? null : onAttach,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat_input'),
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Type instructions or data...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: AgentOperatingSystemTokens.bodyMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurface,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      final enabled = !busy &&
                          (value.text.trim().isNotEmpty ||
                              attachments.isNotEmpty);
                      return SizedBox.square(
                        dimension: 40,
                        child: FilledButton(
                          key: const ValueKey('chat_send'),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                AgentOperatingSystemTokens.primaryContainer,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                AgentOperatingSystemTokens.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AgentOperatingSystemTokens.radiusMd,
                              ),
                            ),
                          ),
                          onPressed: enabled ? onSend : null,
                          child: const Icon(Icons.send_rounded, size: 20),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _firstOperatingString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is! String) continue;
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

extension _OperatingIterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
