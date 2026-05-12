import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';
import 'review_models.dart';

final class ReviewQueueList extends StatelessWidget {
  const ReviewQueueList({
    required this.items,
    required this.selectedItem,
    required this.onSelect,
    super.key,
  });

  final List<ReviewItem> items;
  final ReviewItem selectedItem;
  final ValueChanged<ReviewItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t.actions.reviewQueue.agentUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapMd),
        Wrap(
          spacing: AgentDesignTokens.gapSm,
          runSpacing: AgentDesignTokens.gapSm,
          children: [
            FilterChip(
              label: Text(t.filters.all),
              selected: true,
              onSelected: (_) {},
            ),
            FilterChip(
              label: Text(t.filters.highRisk),
              selected: false,
              onSelected: (_) {},
            ),
            FilterChip(
              label: Text(t.filters.drafts),
              selected: false,
              onSelected: (_) {},
            ),
          ],
        ),
        const SizedBox(height: AgentDesignTokens.gapLg),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AgentDesignTokens.gapSm),
            itemBuilder: (context, index) {
              final item = items[index];
              return ReviewQueueItem(
                item: item,
                selected: item.id == selectedItem.id,
                onTap: () => onSelect(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class ReviewQueueItem extends StatelessWidget {
  const ReviewQueueItem({
    required this.item,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ReviewItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SlSurface(
      color: selected ? scheme.primaryContainer.withOpacity(0.36) : null,
      borderColor: selected ? scheme.primary.withOpacity(0.32) : null,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('review_queue_item_${item.id}'),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  _RiskChip(risk: item.risk),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              Text(
                item.summary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              Row(
                children: [
                  _StatusChip(status: item.status),
                  const Spacer(),
                  Text(
                    item.timeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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

final class ReviewDetail extends StatelessWidget {
  const ReviewDetail({
    required this.item,
    super.key,
  });

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final t = context.t.actions.reviewQueue.agentUi;
    return SlSurface(
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.detailTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapMd),
          Text(item.source),
          const SizedBox(height: AgentDesignTokens.gapLg),
          _ReviewDiffTable(rows: item.diffRows),
          const SizedBox(height: AgentDesignTokens.gapLg),
          ReviewActionFooter(item: item),
        ],
      ),
    );
  }
}

final class ReviewActionFooter extends StatelessWidget {
  const ReviewActionFooter({required this.item, super.key});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.t.actions.reviewQueue.agentUi;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AgentDesignTokens.gapSm,
      runSpacing: AgentDesignTokens.gapSm,
      children: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: Text(t.actions.approve),
        ),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(t.actions.edit),
        ),
        TextButton.icon(
          onPressed: () {},
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: Text(t.actions.reject),
        ),
      ],
    );
  }
}

final class _ReviewDiffTable extends StatelessWidget {
  const _ReviewDiffTable({required this.rows});

  final List<ReviewDiffRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ReviewDiffRowView(row: rows[i]),
            if (i != rows.length - 1)
              Divider(height: 1, color: scheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

final class _ReviewDiffRowView extends StatelessWidget {
  const _ReviewDiffRowView({required this.row});

  final ReviewDiffRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        );
    return Padding(
      key: ValueKey('review_diff_${row.id}'),
      padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(row.field, style: labelStyle)),
          Expanded(child: Text(row.before)),
          const SizedBox(width: AgentDesignTokens.gapMd),
          const Icon(Icons.arrow_forward_rounded, size: 16),
          const SizedBox(width: AgentDesignTokens.gapMd),
          Expanded(child: Text(row.after)),
        ],
      ),
    );
  }
}

final class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.risk});

  final ReviewRisk risk;

  @override
  Widget build(BuildContext context) {
    return switch (risk) {
      ReviewRisk.high => AgentStatusChip.high(
          label: context.t.actions.reviewQueue.agentUi.risk.high,
        ),
      ReviewRisk.medium => AgentStatusChip.medium(
          label: context.t.actions.reviewQueue.agentUi.risk.medium,
        ),
      ReviewRisk.low => AgentStatusChip.low(
          label: context.t.actions.reviewQueue.agentUi.risk.low,
        ),
    };
  }
}

final class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReviewStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ReviewStatus.needsApproval => AgentStatusChip.needsApproval(
          label: context.t.actions.reviewQueue.agentUi.status.needsApproval,
        ),
      ReviewStatus.draft => AgentStatusChip.pending(
          label: context.t.actions.reviewQueue.agentUi.status.draft,
        ),
    };
  }
}
