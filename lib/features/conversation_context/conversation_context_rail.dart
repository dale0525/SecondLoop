import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'conversation_context_models.dart';

export 'conversation_context_models.dart';

final class ConversationContextRail extends StatelessWidget {
  const ConversationContextRail({
    required this.snapshot,
    this.compact = false,
    super.key,
  });

  final ConversationContextSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final content = SingleChildScrollView(
      key: const ValueKey('conversation_context_rail'),
      padding: EdgeInsets.all(compact ? 16 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.isEmpty)
            _ContextEmptyState(text: context.t.chat.agentContext.empty)
          else ...[
            _ContextSection(
              title: context.t.chat.agentContext.todayAtGlance,
              items: snapshot.todayAtAGlance,
            ),
            _ContextSection(
              title: context.t.chat.agentContext.longTermMemory,
              items: snapshot.longTermMemory,
            ),
            _ContextSection(
              title: context.t.chat.agentContext.people,
              items: snapshot.people,
            ),
            _ContextSection(
              title: context.t.chat.agentContext.recentFiles,
              items: snapshot.recentFiles,
            ),
            _ContextSection(
              title: context.t.chat.agentContext.pendingReview,
              items: snapshot.pendingReview,
            ),
            if (snapshot.privacyNote.trim().isNotEmpty)
              _PrivacyNote(text: snapshot.privacyNote),
          ],
        ],
      ),
    );

    if (compact) return content;

    return SlSurface(
      color: tokens.surface2,
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: EdgeInsets.zero,
      child: content,
    );
  }
}

final class ConversationContextSheetButton extends StatelessWidget {
  const ConversationContextSheetButton({
    required this.snapshot,
    super.key,
  });

  final ConversationContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('conversation_context_open'),
      tooltip: context.t.chat.agentContext.open,
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (context) {
            return FractionallySizedBox(
              key: const ValueKey('conversation_context_sheet'),
              heightFactor: 0.86,
              child: ConversationContextRail(
                snapshot: snapshot,
                compact: true,
              ),
            );
          },
        );
      },
      icon: const Icon(Icons.view_sidebar_outlined),
    );
  }
}

final class _ContextEmptyState extends StatelessWidget {
  const _ContextEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AgentDesignTokens.gapLg,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _ContextSection extends StatelessWidget {
  const _ContextSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<ConversationContextItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AgentDesignTokens.gapSm),
          for (final item in items) _ContextItemView(item: item),
        ],
      ),
    );
  }
}

final class _ContextItemView extends StatelessWidget {
  const _ContextItemView({required this.item});

  final ConversationContextItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withOpacity(0.68),
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.68)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AgentDesignTokens.gapXs),
              Text(
                item.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.42),
        borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
        border: Border.all(color: scheme.primary.withOpacity(0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.chat.agentContext.privacyNote,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AgentDesignTokens.gapXs),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
