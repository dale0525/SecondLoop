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
    final t = context.t.chat.operating.operatingSystem;
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
      header: Row(
        children: [
          const Icon(
            Icons.task_alt_rounded,
            color: AgentOperatingSystemTokens.secondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.taskCreated,
              style: AgentOperatingSystemTokens.labelLg,
            ),
          ),
          const _OperatingStatusBadge(
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
          _OperatingFactRow(
            label: 'Mutation ID',
            value: mutationId,
            valueColor: AgentOperatingSystemTokens.secondary,
            valueWeight: FontWeight.w800,
          ),
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
              label: Text(t.openTask),
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
    final t = context.t.chat.operating.operatingSystem;
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

    return KeyedSubtree(
      key: ValueKey('agent_operating_memory_candidate_${item.id}'),
      child: _OperatingCard(
        header: Row(
          children: [
            const Icon(
              Icons.psychology_alt_outlined,
              color: AgentOperatingSystemTokens.muted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.memoryCandidate,
                style: AgentOperatingSystemTokens.labelLg,
              ),
            ),
            const _OperatingStatusBadge(
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
                borderRadius:
                    BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
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
                      t.factToBeCommitted,
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: AgentOperatingSystemTokens.bodyMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OperatingDetailRow(
                    label: 'Risk Score:',
                    value: risk,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OperatingDetailRow(
                    label: 'Audit ID:',
                    value: auditId,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey('agent_operating_memory_approve_${item.id}'),
                    label: 'Approve',
                    primary: true,
                    onPressed: onApprove,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OperatingFooterTextButton(
                    key: ValueKey('agent_operating_memory_dismiss_${item.id}'),
                    label: 'Dismiss',
                    onPressed: onReject,
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
    required this.placeholder,
    required this.followUpMode,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final String? placeholder;
  final bool followUpMode;
  final List<AttachmentDraftPayload> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    if (followUpMode) {
      return _OperatingFollowUpComposer(
        controller: controller,
        focusNode: focusNode,
        busy: busy,
        placeholder: placeholder ??
            context.t.chat.agentConversation.followUpComposerHint,
        attachments: attachments,
        onAttach: onAttach,
        onRemoveAttachment: onRemoveAttachment,
        onSend: onSend,
      );
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: DecoratedBox(
        key: const ValueKey('operating_composer_box'),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0x66000000)
                  : const Color(0x22000000),
              blurRadius: 18,
              offset: const Offset(0, 8),
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
                    tooltip: context.t.chat.operating.desktopWorkbench.attach,
                    onPressed: busy ? null : onAttach,
                    style: IconButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      disabledForegroundColor: colors.muted.withOpacity(0.5),
                    ),
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
                      decoration: InputDecoration(
                        hintText: placeholder ??
                            context.t.chat.agentConversation.composerHint,
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: AgentOperatingSystemTokens.bodyMd.copyWith(
                          color: colors.muted,
                        ),
                      ),
                      style: AgentOperatingSystemTokens.bodyMd.copyWith(
                        color: colors.onSurface,
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
                            backgroundColor: colors.primaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                            disabledBackgroundColor:
                                colors.surfaceContainerHigh,
                            disabledForegroundColor:
                                colors.onSurfaceVariant.withOpacity(0.45),
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

final class _OperatingFollowUpComposer extends StatelessWidget {
  const _OperatingFollowUpComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.placeholder,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final String placeholder;
  final List<AttachmentDraftPayload> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return DecoratedBox(
      key: const ValueKey('operating_follow_up_composer_box'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                  tooltip: context.t.chat.operating.desktopWorkbench.attach,
                  onPressed: busy ? null : onAttach,
                  style: IconButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    disabledForegroundColor: colors.muted.withOpacity(0.5),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(
                        AgentOperatingSystemTokens.radiusLg,
                      ),
                      border: Border.all(
                        color: colors.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat_input'),
                            controller: controller,
                            focusNode: focusNode,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: placeholder,
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              hintStyle:
                                  AgentOperatingSystemTokens.bodyMd.copyWith(
                                color: colors.muted,
                              ),
                            ),
                            style: AgentOperatingSystemTokens.bodyMd.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, child) {
                            final enabled = !busy &&
                                (value.text.trim().isNotEmpty ||
                                    attachments.isNotEmpty);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: SizedBox.square(
                                dimension: 32,
                                child: FilledButton(
                                  key: const ValueKey('chat_send'),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: colors.secondary,
                                    foregroundColor: colors.background,
                                    disabledBackgroundColor:
                                        colors.surfaceContainerHigh,
                                    disabledForegroundColor: colors
                                        .onSurfaceVariant
                                        .withOpacity(0.45),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AgentOperatingSystemTokens.radiusLg,
                                      ),
                                    ),
                                  ),
                                  onPressed: enabled ? onSend : null,
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
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
