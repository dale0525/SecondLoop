import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';
import '../agent_ui/agent_tab_bar.dart';
import 'research_models.dart';

final class ResearchBudgetConfirmationCard extends StatelessWidget {
  const ResearchBudgetConfirmationCard({
    required this.estimate,
    this.onStart,
    this.onReduceScope,
    this.onCancel,
    super.key,
  });

  final ResearchBudgetEstimate estimate;
  final VoidCallback? onStart;
  final VoidCallback? onReduceScope;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final t = context.t.chat.research;
    return SlSurface(
      key: const ValueKey('research_budget_confirmation_card'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.budgetTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                AgentStatusChip.needsApproval(label: t.requiresConfirmation),
              ],
            ),
            const SizedBox(height: AgentDesignTokens.gapMd),
            Text(
              estimate.topic,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AgentDesignTokens.gapXs),
            Text(estimate.scopeSummary),
            const SizedBox(height: AgentDesignTokens.gapLg),
            Wrap(
              spacing: AgentDesignTokens.gapSm,
              runSpacing: AgentDesignTokens.gapSm,
              children: [
                _ResearchMetric(
                  icon: Icons.article_outlined,
                  label: t.pages,
                  value: estimate.pagesLabel,
                ),
                _ResearchMetric(
                  icon: Icons.memory_outlined,
                  label: t.tokens,
                  value: estimate.tokensLabel,
                ),
                _ResearchMetric(
                  icon: Icons.payments_outlined,
                  label: t.cost,
                  value: estimate.costLabel,
                ),
              ],
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            Wrap(
              spacing: AgentDesignTokens.gapSm,
              runSpacing: AgentDesignTokens.gapSm,
              children: [
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(t.startResearch),
                ),
                OutlinedButton.icon(
                  onPressed: onReduceScope,
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: Text(t.reduceScope),
                ),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(t.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class ResearchResultCard extends StatelessWidget {
  const ResearchResultCard({
    required this.result,
    super.key,
  });

  final ResearchResult result;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final t = context.t.chat.research;
    return SlSurface(
      key: const ValueKey('research_result_card'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              result.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AgentDesignTokens.gapMd),
            AgentTabBar(
              tabs: [
                AgentTabItem(id: 'brief', label: t.tabs.brief),
                AgentTabItem(id: 'key_points', label: t.tabs.keyPoints),
                AgentTabItem(id: 'sources', label: t.tabs.sources),
                AgentTabItem(id: 'draft_note', label: t.tabs.draftNote),
              ],
              selectedId: 'brief',
              onSelected: (_) {},
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _ResearchSection(
                title: t.sections.brief, child: Text(result.brief)),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _ResearchSection(
              title: t.sections.keyPoints,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final point in result.keyPoints)
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AgentDesignTokens.gapXs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('- '),
                          Expanded(child: Text(point)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _ResearchSection(
              title: t.sections.sources,
              child: Column(
                children: [
                  for (final source in result.sources)
                    _ResearchCitationRow(citation: source),
                ],
              ),
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _ResearchSection(
              title: t.sections.draftNote,
              child: Text(result.draftNote),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResearchMetric extends StatelessWidget {
  const _ResearchMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AgentDesignTokens.gapSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(value),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResearchSection extends StatelessWidget {
  const _ResearchSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        child,
      ],
    );
  }
}

final class _ResearchCitationRow extends StatelessWidget {
  const _ResearchCitationRow({required this.citation});

  final ResearchCitation citation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = context.t.chat.research;
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgentStatusChip.allowed(label: '[${citation.number}]'),
              const SizedBox(width: AgentDesignTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      citation.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AgentDesignTokens.gapXs),
                    Text(citation.domain),
                    const SizedBox(height: AgentDesignTokens.gapXs),
                    Text(t.fetched(time: citation.fetchedLabel)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
