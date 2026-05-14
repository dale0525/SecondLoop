import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';

final class ApprovalPreviewChange {
  const ApprovalPreviewChange({
    required this.sourceSentence,
    required this.dueTimeBefore,
    required this.dueTimeAfter,
    required this.statusLabel,
  });

  final String sourceSentence;
  final String dueTimeBefore;
  final String dueTimeAfter;
  final String statusLabel;

  static ApprovalPreviewChange demo() {
    return const ApprovalPreviewChange(
      sourceSentence:
          "Move the passport renewal task to today at 20:00, but don't mark it done.",
      dueTimeBefore: 'Tomorrow 09:00',
      dueTimeAfter: 'Today 20:00',
      statusLabel: 'Not started',
    );
  }
}

final class ApprovalPreviewCard extends StatelessWidget {
  const ApprovalPreviewCard({
    required this.change,
    this.onApprove,
    this.onEdit,
    this.onReject,
    super.key,
  });

  final ApprovalPreviewChange change;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = context.t.chat.approvalPreview;

    return SlSurface(
      key: const ValueKey('approval_preview_card'),
      color: tokens.surface,
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              AgentStatusChip.needsApproval(label: t.needsApproval),
            ],
          ),
          const SizedBox(height: AgentDesignTokens.gapMd),
          Text(
            change.sourceSentence,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AgentDesignTokens.gapLg),
          _DiffTable(change: change),
          const SizedBox(height: AgentDesignTokens.gapLg),
          Wrap(
            spacing: AgentDesignTokens.gapSm,
            runSpacing: AgentDesignTokens.gapSm,
            children: [
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: Text(t.reviewApprove),
              ),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(t.edit),
              ),
              TextButton.icon(
                onPressed: onReject,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(t.reject),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.change});

  final ApprovalPreviewChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = context.t.chat.approvalPreview;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
      ),
      child: Column(
        children: [
          _DiffRow(
            label: t.dueTime,
            beforeLabel: t.before,
            beforeValue: change.dueTimeBefore,
            afterLabel: t.after,
            afterValue: change.dueTimeAfter,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
            child: Row(
              children: [
                Expanded(child: Text(t.statusUnchanged, style: labelStyle)),
                Text(change.statusLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.label,
    required this.beforeLabel,
    required this.beforeValue,
    required this.afterLabel,
    required this.afterValue,
  });

  final String label;
  final String beforeLabel;
  final String beforeValue;
  final String afterLabel;
  final String afterValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: labelStyle)),
          Expanded(
            child: _DiffValue(label: beforeLabel, value: beforeValue),
          ),
          const SizedBox(width: AgentDesignTokens.gapMd),
          Expanded(
            child: _DiffValue(label: afterLabel, value: afterValue),
          ),
        ],
      ),
    );
  }
}

final class _DiffValue extends StatelessWidget {
  const _DiffValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
