import 'package:flutter/material.dart';

import '../../core/secretary/secretary_models.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'secretary_review_section.dart';

class MemoryReviewPage extends StatelessWidget {
  const MemoryReviewPage({
    this.pending = const <SecretaryMemoryProposal>[],
    this.current = const <SecretaryMemoryPage>[],
    this.needsReview = const <SecretaryMemoryPage>[],
    this.archived = const <SecretaryMemoryPage>[],
    this.onAcceptProposal,
    this.onDismissProposal,
    super.key,
  });

  final List<SecretaryMemoryProposal> pending;
  final List<SecretaryMemoryPage> current;
  final List<SecretaryMemoryPage> needsReview;
  final List<SecretaryMemoryPage> archived;
  final ValueChanged<SecretaryMemoryProposal>? onAcceptProposal;
  final ValueChanged<SecretaryMemoryProposal>? onDismissProposal;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.secretary.memory;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.pageTitle),
        actions: [
          IconButton(
            key: const ValueKey('secretary_memory_create'),
            tooltip: t.newMemoryTooltip,
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final content = <Widget>[
              SecretaryReviewSection(
                title: t.sections.pending,
                count: pending.length,
                children: [
                  for (final proposal in pending)
                    _PendingMemoryTile(
                      proposal: proposal,
                      onAccept: onAcceptProposal == null
                          ? null
                          : () => onAcceptProposal!(proposal),
                      onDismiss: onDismissProposal == null
                          ? null
                          : () => onDismissProposal!(proposal),
                    ),
                ],
              ),
              SecretaryReviewSection(
                title: t.sections.current,
                count: current.length,
                children: [
                  for (final memory in current) _MemoryTile(memory: memory),
                ],
              ),
              SecretaryReviewSection(
                title: t.sections.needsReview,
                count: needsReview.length,
                children: [
                  for (final memory in needsReview) _MemoryTile(memory: memory),
                ],
              ),
              SecretaryReviewSection(
                title: t.sections.archived,
                count: archived.length,
                children: [
                  for (final memory in archived) _MemoryTile(memory: memory),
                ],
              ),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final item in content)
                          SizedBox(
                            width: (constraints.maxWidth - 48) / 2,
                            child: item,
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        for (final item in content) ...[
                          item,
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _PendingMemoryTile extends StatelessWidget {
  const _PendingMemoryTile({
    required this.proposal,
    this.onAccept,
    this.onDismiss,
  });

  final SecretaryMemoryProposal proposal;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    final t = context.t;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SlSurface(
        color: colorScheme.surface,
        borderColor: Colors.orange.shade700.withOpacity(0.28),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proposal.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(proposal.body),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SlButton(
                  buttonKey: ValueKey(
                    'memory_review_accept_${proposal.sourceMessageId}',
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  onPressed: onAccept,
                  child: Text(t.common.actions.accept),
                ),
                SlButton(
                  buttonKey: ValueKey(
                    'memory_review_dismiss_${proposal.sourceMessageId}',
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  variant: SlButtonVariant.outline,
                  onPressed: onDismiss,
                  child: Text(t.common.actions.ignore),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.memory});

  final SecretaryMemoryPage memory;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SlSurface(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              memory.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              memory.body,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
