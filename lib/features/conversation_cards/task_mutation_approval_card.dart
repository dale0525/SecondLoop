import 'package:flutter/material.dart';

import '../../core/cloud/runtime_agent_state_models.dart';
import '../../core/cloud/secretary_runtime_client.dart';
import '../../i18n/strings.g.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_operating_system_tokens.dart';
import 'task_mutation_approval_details.dart';

bool isTaskTitleMutationApproval(SecretaryRuntimeApprovalItem item) {
  if (item.editableFields.contains('title')) return true;
  final record = item.record ?? const <String, Object?>{};
  return taskMutationApprovalFirstString([
        record['current_title'],
        record['currentTitle'],
        record['previous_title'],
        record['previousTitle'],
        record['before_title'],
        record['beforeTitle'],
        record['old_title'],
        record['oldTitle'],
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
      ]) !=
      null;
}

final class TaskMutationApprovalCard extends StatelessWidget {
  const TaskMutationApprovalCard({
    required this.item,
    required this.taskRecords,
    required this.onApprove,
    required this.onReject,
    this.contextSnapshot,
    this.auditRefs = const <Map<String, Object?>>[],
    this.recentEntityRefs = const <Map<String, Object?>>[],
    this.onEditTitle,
    this.busy = false,
    super.key,
  });

  final SecretaryRuntimeApprovalItem item;
  final List<RuntimeWorkingSetRecord> taskRecords;
  final RuntimeContextSnapshot? contextSnapshot;
  final List<Map<String, Object?>> auditRefs;
  final List<Map<String, Object?>> recentEntityRefs;
  final VoidCallback? onApprove;
  final ValueChanged<String>? onEditTitle;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final details = TaskMutationApprovalDetails.fromRuntime(
      item: item,
      taskRecords: taskRecords,
      contextSnapshot: contextSnapshot,
      auditRefs: auditRefs,
      recentEntityRefs: recentEntityRefs,
    );
    return KeyedSubtree(
      key: ValueKey('approval_preview_card_${item.id}'),
      child: DecoratedBox(
        key: ValueKey('task_mutation_approval_card_${item.id}'),
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surface,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _TaskMutationHeader(details: details),
            Padding(
              padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SystemContext(details: details),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _CurrentStatePreview(details: details),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _TargetAndResolver(details: details),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _ProposedTitleDiff(details: details, itemId: item.id),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _TaskMutationMetadataGrid(details: details),
                  const SizedBox(height: AgentDesignTokens.gapMd),
                  _PendingNotice(notice: details.notice),
                  const SizedBox(height: AgentDesignTokens.gapLg),
                  _TaskMutationActions(
                    item: item,
                    busy: busy,
                    onApprove: onApprove,
                    onEditTitle: onEditTitle,
                    onReject: onReject,
                  ),
                  if (details.hasFooterEvidence) ...[
                    const SizedBox(height: AgentDesignTokens.gapLg),
                    _FooterEvidence(details: details),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _TaskMutationHeader extends StatelessWidget {
  const _TaskMutationHeader({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AgentOperatingSystemTokens.radiusLg),
        ),
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(
              Icons.fact_check_outlined,
              color: AgentOperatingSystemTokens.onSurface,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.headlineSm.copyWith(
                  color: AgentOperatingSystemTokens.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RiskChip(label: details.riskLabel),
          ],
        ),
      ),
    );
  }
}

final class _SystemContext extends StatelessWidget {
  const _SystemContext({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return _LabeledSurface(
      label: t.systemContext,
      child: Text(
        details.systemContext,
        style: AgentOperatingSystemTokens.bodySm.copyWith(
          color: AgentOperatingSystemTokens.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _CurrentStatePreview extends StatelessWidget {
  const _CurrentStatePreview({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return _LabeledSurface(
      label: t.currentStateAwaitingApproval,
      trailing: const Icon(
        Icons.lock_outline_rounded,
        size: 16,
        color: AgentOperatingSystemTokens.onSurfaceVariant,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_box_outline_blank_rounded,
            size: 20,
            color: AgentOperatingSystemTokens.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  details.currentTitle,
                  key: ValueKey(
                    'task_mutation_current_title_${details.targetId}',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgentOperatingSystemTokens.bodySm.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details.currentStateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgentOperatingSystemTokens.labelMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _TargetAndResolver extends StatelessWidget {
  const _TargetAndResolver({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 520;
        final children = [
          _InfoBlock(
            label: t.targetEntity,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CodePill(details.targetId),
                Text(
                  details.currentTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgentOperatingSystemTokens.bodyMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _InfoBlock(
            label: t.resolverDetail,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 16,
                  color: AgentOperatingSystemTokens.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    details.resolverDetail,
                    style: AgentOperatingSystemTokens.bodySm.copyWith(
                      color: AgentOperatingSystemTokens.secondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
        if (!useColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              children[0],
              const SizedBox(height: AgentDesignTokens.gapMd),
              children[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: AgentDesignTokens.gapLg),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

final class _ProposedTitleDiff extends StatelessWidget {
  const _ProposedTitleDiff({
    required this.details,
    required this.itemId,
  });

  final TaskMutationApprovalDetails details;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return _LabeledSurface(
      label: t.proposedChange,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.edit_note_rounded,
            size: 22,
            color: AgentOperatingSystemTokens.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  t.changeTitleFrom,
                  style: AgentOperatingSystemTokens.bodyMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                  ),
                ),
                _DiffPill(
                  key: ValueKey('task_mutation_current_diff_$itemId'),
                  text: details.currentTitle,
                  tone: _DiffTone.remove,
                ),
                Text(
                  t.to,
                  style: AgentOperatingSystemTokens.bodyMd.copyWith(
                    color: AgentOperatingSystemTokens.onSurface,
                  ),
                ),
                _DiffPill(
                  key: ValueKey('task_mutation_proposed_title_$itemId'),
                  text: details.proposedTitle,
                  tone: _DiffTone.add,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _TaskMutationMetadataGrid extends StatelessWidget {
  const _TaskMutationMetadataGrid({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    final items = [
      (t.source, details.source),
      (t.auditId, details.auditId),
      (t.contextSnapshot, details.contextSnapshotId),
      (t.runtimeTool, details.runtimeTool),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth >= 520
                ? (constraints.maxWidth - AgentDesignTokens.gapMd * 3) / 4
                : (constraints.maxWidth - AgentDesignTokens.gapMd) / 2;
            return Wrap(
              spacing: AgentDesignTokens.gapMd,
              runSpacing: AgentDesignTokens.gapMd,
              children: [
                for (final item in items)
                  SizedBox(
                    width:
                        tileWidth.clamp(120.0, constraints.maxWidth).toDouble(),
                    child: _MetadataTile(label: item.$1, value: item.$2),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AgentOperatingSystemTokens.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            notice,
            style: AgentOperatingSystemTokens.labelLg.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _TaskMutationActions extends StatelessWidget {
  const _TaskMutationActions({
    required this.item,
    required this.busy,
    required this.onApprove,
    required this.onEditTitle,
    required this.onReject,
  });

  final SecretaryRuntimeApprovalItem item;
  final bool busy;
  final VoidCallback? onApprove;
  final ValueChanged<String>? onEditTitle;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    final commonActions = context.t.common.actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: 1,
          color: AgentOperatingSystemTokens.outlineVariant,
        ),
        const SizedBox(height: AgentDesignTokens.gapLg),
        FilledButton.icon(
          key: ValueKey('task_mutation_approve_${item.id}'),
          onPressed: busy ? null : onApprove,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(busy ? t.processing : t.approveChange),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        OutlinedButton.icon(
          key: ValueKey('task_mutation_edit_${item.id}'),
          onPressed:
              busy || onEditTitle == null ? null : () => _showEditor(context),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(
            onEditTitle == null ? t.editUnavailable : commonActions.edit,
          ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        OutlinedButton.icon(
          key: ValueKey('task_mutation_reject_${item.id}'),
          onPressed: busy ? null : onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
          ),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: Text(commonActions.reject),
        ),
      ],
    );
  }

  Future<void> _showEditor(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TaskMutationTitleDialog(item: item),
    );
    final nextTitle = title?.trim() ?? '';
    if (nextTitle.isEmpty) return;
    onEditTitle?.call(nextTitle);
  }
}

final class _FooterEvidence extends StatelessWidget {
  const _FooterEvidence({required this.details});

  final TaskMutationApprovalDetails details;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = <Widget>[
          if (details.lastApprovedChange.isNotEmpty)
            _EvidenceCard(
              icon: Icons.history_rounded,
              label: t.lastApprovedChange,
              value: details.lastApprovedChange,
            ),
          if (details.confidenceLabel.isNotEmpty)
            _EvidenceCard(
              icon: Icons.bolt_rounded,
              label: t.automationConfidence,
              value: details.confidenceLabel,
            ),
        ];
        if (cards.length <= 1 || constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(height: AgentDesignTokens.gapMd),
                cards[index],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

final class _TaskMutationTitleDialog extends StatefulWidget {
  const _TaskMutationTitleDialog({required this.item});

  final SecretaryRuntimeApprovalItem item;

  @override
  State<_TaskMutationTitleDialog> createState() =>
      _TaskMutationTitleDialogState();
}

final class _TaskMutationTitleDialogState
    extends State<_TaskMutationTitleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final record = widget.item.record ?? const <String, Object?>{};
    _controller = TextEditingController(
      text: taskMutationApprovalFirstString([
            record['proposed_title'],
            record['proposedTitle'],
            record['new_title'],
            record['newTitle'],
            record['title'],
            widget.item.title,
          ]) ??
          '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.operating.taskMutationApproval;
    final commonActions = context.t.common.actions;
    return AlertDialog(
      title: Text(t.editProposedTitle),
      content: TextField(
        key: ValueKey('task_mutation_title_field_${widget.item.id}'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(commonActions.cancel),
        ),
        FilledButton(
          key: ValueKey('task_mutation_save_title_${widget.item.id}'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(commonActions.save),
        ),
      ],
    );
  }
}

final class _LabeledSurface extends StatelessWidget {
  const _LabeledSurface({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _SectionLabel(label)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AgentDesignTokens.gapSm),
            child,
          ],
        ),
      ),
    );
  }
}

final class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionLabel(label),
        const SizedBox(height: AgentDesignTokens.gapSm),
        child,
      ],
    );
  }
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AgentOperatingSystemTokens.labelLg.copyWith(
        color: AgentOperatingSystemTokens.onSurfaceVariant,
      ),
    );
  }
}

final class _CodePill extends StatelessWidget {
  const _CodePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainer,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.code.copyWith(
            color: AgentOperatingSystemTokens.onSurface,
          ),
        ),
      ),
    );
  }
}

enum _DiffTone { add, remove }

final class _DiffPill extends StatelessWidget {
  const _DiffPill({
    required this.text,
    required this.tone,
    super.key,
  });

  final String text;
  final _DiffTone tone;

  @override
  Widget build(BuildContext context) {
    final isAdd = tone == _DiffTone.add;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isAdd ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: AgentOperatingSystemTokens.bodyMd.copyWith(
            color: isAdd ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
            fontWeight: isAdd ? FontWeight.w700 : FontWeight.w500,
            decoration: isAdd ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

final class _MetadataTile extends StatelessWidget {
  const _MetadataTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AgentOperatingSystemTokens.bodySm.copyWith(
            color: AgentOperatingSystemTokens.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

final class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE7F7EC),
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 14,
              color: Color(0xFF15803D),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AgentOperatingSystemTokens.labelLg.copyWith(
                color: const Color(0xFF15803D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFFEAF1FF),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  icon,
                  size: 20,
                  color: AgentOperatingSystemTokens.secondary,
                ),
              ),
            ),
            const SizedBox(width: AgentDesignTokens.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgentOperatingSystemTokens.labelLg.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AgentOperatingSystemTokens.bodySm.copyWith(
                      color: AgentOperatingSystemTokens.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
