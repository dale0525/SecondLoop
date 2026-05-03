export 'todo_command_review_card.dart';

import 'package:flutter/material.dart';

import '../../core/secretary/secretary_models.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class ChatSecretaryMemoryCard extends StatelessWidget {
  const ChatSecretaryMemoryCard({
    required this.proposal,
    required this.onAccept,
    required this.onEdit,
    required this.onIgnore,
    super.key,
  });

  final SecretaryMemoryProposal proposal;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final warningColor = Colors.orange.shade700;
    final t = context.t;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SlSurface(
          color: colorScheme.surface,
          borderColor: warningColor.withOpacity(0.32),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          padding: const EdgeInsets.all(14),
          child: Column(
            key: ValueKey('secretary_memory_card_${proposal.sourceMessageId}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: warningColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.chat.secretary.memory.cardTitle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: warningColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Text(
                    _confidenceLabel(proposal.confidence),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t.chat.secretary.memory.suggestedMemoryLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                proposal.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                proposal.body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SourceChip(label: t.chat.secretary.memory.sourceYou),
                  if (proposal.actionHint == 'update') ...[
                    const SizedBox(width: 8),
                    _SourceChip(label: t.chat.secretary.memory.update),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SlButton(
                    buttonKey: ValueKey(
                      'secretary_memory_accept_${proposal.sourceMessageId}',
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    onPressed: onAccept,
                    child: Text(t.common.actions.accept),
                  ),
                  SlButton(
                    buttonKey: ValueKey(
                      'secretary_memory_edit_${proposal.sourceMessageId}',
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onEdit,
                    child: Text(t.common.actions.edit),
                  ),
                  SlButton(
                    buttonKey: ValueKey(
                      'secretary_memory_ignore_${proposal.sourceMessageId}',
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onIgnore,
                    child: Text(t.common.actions.ignore),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _confidenceLabel(double confidence) {
    return '${(confidence * 100).round()}%';
  }
}

class ChatSecretaryPlanningCard extends StatelessWidget {
  const ChatSecretaryPlanningCard({
    required this.plan,
    required this.onViewPlan,
    required this.onRemindLater,
    required this.onIgnore,
    super.key,
  });

  final SecretaryPlan plan;
  final VoidCallback onViewPlan;
  final VoidCallback onRemindLater;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final t = context.t;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SlSurface(
          color: colorScheme.primary.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.06,
          ),
          borderColor: accent.withOpacity(0.24),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          padding: const EdgeInsets.all(14),
          child: Column(
            key: const ValueKey('secretary_planning_card'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.chat.secretary.planning.cardTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _summaryText(context, plan),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                t.chat.secretary.planning.cardSubtitle,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SlButton(
                    buttonKey: const ValueKey('secretary_plan_view'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: onViewPlan,
                    child: Text(t.chat.secretary.planning.viewPlan),
                  ),
                  SlButton(
                    buttonKey: const ValueKey('secretary_plan_remind_later'),
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onRemindLater,
                    child: Text(t.chat.secretary.planning.remindLater),
                  ),
                  SlButton(
                    buttonKey: const ValueKey('secretary_plan_ignore'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    variant: SlButtonVariant.outline,
                    onPressed: onIgnore,
                    child: Text(t.common.actions.ignore),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summaryText(BuildContext context, SecretaryPlan plan) {
    final t = context.t.chat.secretary.planning;
    final suggestions = plan.itemCount == 1
        ? t.oneSuggestion
        : t.manySuggestions(count: plan.itemCount);
    final confirmations = plan.requiresConfirmationCount == 1
        ? t.oneNeedsConfirmation
        : t.manyNeedConfirmation(count: plan.requiresConfirmationCount);
    return t.summary(
      suggestions: suggestions,
      confirmations: confirmations,
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
