import 'package:flutter/material.dart';

import '../../core/secretary/secretary_models.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'secretary_review_section.dart';

class PlanningReviewPage extends StatelessWidget {
  const PlanningReviewPage({
    required this.plan,
    this.onAcceptSuggestion,
    this.onDismissSuggestion,
    super.key,
  });

  final SecretaryPlan plan;
  final ValueChanged<String>? onAcceptSuggestion;
  final ValueChanged<String>? onDismissSuggestion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning Review'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlSurface(
                color: Colors.orange.shade700.withOpacity(0.08),
                borderColor: Colors.orange.shade700.withOpacity(0.24),
                padding: const EdgeInsets.all(12),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Suggestions need confirmation before changes are written.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final sections = [
                    _section('Focus', plan.sections.focus),
                    _section('Due soon', plan.sections.dueSoon),
                    _section('Needs decision', plan.sections.needsDecision),
                    _section(
                      'Missing next action',
                      plan.sections.missingNextAction,
                    ),
                  ];
                  if (!wide) {
                    return Column(
                      children: [
                        for (final section in sections) ...[
                          section,
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final section in sections)
                        SizedBox(
                          width: (constraints.maxWidth - 28) / 3,
                          child: section,
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<SecretaryPlanItem> items) {
    return SecretaryReviewSection(
      title: title,
      count: items.length,
      children: [
        for (final item in items)
          _PlanItemTile(
            item: item,
            onAccept: onAcceptSuggestion == null
                ? null
                : () => onAcceptSuggestion!(item.id),
            onDismiss: onDismissSuggestion == null
                ? null
                : () => onDismissSuggestion!(item.id),
          ),
      ],
    );
  }
}

class _PlanItemTile extends StatelessWidget {
  const _PlanItemTile({
    required this.item,
    this.onAccept,
    this.onDismiss,
  });

  final SecretaryPlanItem item;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SlSurface(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (item.dueAtMs != null)
                  Text(
                    _timeLabel(item.dueAtMs!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.reason,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SlButton(
                  buttonKey: ValueKey('secretary_plan_accept_${item.id}'),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
                SlButton(
                  buttonKey: ValueKey('secretary_plan_dismiss_${item.id}'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  variant: SlButtonVariant.outline,
                  onPressed: onDismiss,
                  child: const Text('Ignore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(int ms) {
    final value = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
