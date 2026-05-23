part of 'agent_conversation_page.dart';

final class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.trailingIcon,
    this.count,
  });

  final String title;
  final Widget child;
  final String? trailing;
  final IconData? trailingIcon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: AgentOperatingSystemTokens.surfaceContainerLow,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: AgentOperatingSystemTokens.labelLg.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      _DesktopCountBadge(count: count!),
                    ],
                    const Spacer(),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: AgentOperatingSystemTokens.code.copyWith(
                          color: AgentOperatingSystemTokens.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      )
                    else if (trailingIcon != null)
                      Icon(
                        trailingIcon,
                        size: 16,
                        color: AgentOperatingSystemTokens.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const Divider(
              height: 1,
              color: AgentOperatingSystemTokens.outlineVariant,
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

final class _DesktopLabeledValue extends StatelessWidget {
  const _DesktopLabeledValue({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: AgentOperatingSystemTokens.bodySm.copyWith(
        color: AgentOperatingSystemTokens.onSurface,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: AgentOperatingSystemTokens.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (icon == null)
          valueWidget
        else
          Row(
            children: [
              Icon(icon, size: 14, color: AgentOperatingSystemTokens.secondary),
              const SizedBox(width: 8),
              Expanded(child: valueWidget),
            ],
          ),
      ],
    );
  }
}

final class _DesktopPanelDivider extends StatelessWidget {
  const _DesktopPanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        color: AgentOperatingSystemTokens.outlineVariant,
      ),
    );
  }
}

final class _DesktopFactRow extends StatelessWidget {
  const _DesktopFactRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
          Text(value, style: AgentOperatingSystemTokens.code),
        ],
      ),
    );
  }
}

final class _DesktopTraceRow extends StatelessWidget {
  const _DesktopTraceRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AgentOperatingSystemTokens.code.copyWith(
              color: AgentOperatingSystemTokens.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AgentOperatingSystemTokens.code.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

final class _DesktopDiffLine extends StatelessWidget {
  const _DesktopDiffLine({
    required this.prefix,
    required this.text,
    required this.color,
    required this.background,
  });

  final String prefix;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Text(
              prefix,
              style: AgentOperatingSystemTokens.code.copyWith(color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AgentOperatingSystemTokens.bodySm.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DesktopBadge extends StatelessWidget {
  const _DesktopBadge({
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
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

final class _DesktopCountBadge extends StatelessWidget {
  const _DesktopCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AgentOperatingSystemTokens.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$count',
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: AgentOperatingSystemTokens.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

final class _DesktopToolStatus extends StatelessWidget {
  const _DesktopToolStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(label, style: AgentOperatingSystemTokens.code),
        ),
      ),
    );
  }
}

Map<String, Object?> _latestToolTrace(RuntimeAgentState? state) {
  if (state == null) return const <String, Object?>{};
  for (final turn in state.conversationTurns.reversed) {
    final trace = turn.raw['tool_trace'];
    if (trace is Map) {
      return trace.map((key, value) => MapEntry('$key', value as Object?));
    }
  }
  return const <String, Object?>{};
}

bool _latestAssistantHasCitations(RuntimeAgentState? state) {
  if (state == null) return false;
  for (final turn in state.conversationTurns.reversed) {
    if (turn.role != 'assistant') continue;
    return parseChatAnswerEvidence(turn.citationsJson)?.hasEvidence ?? false;
  }
  return false;
}

String? _latestUserTurn(RuntimeAgentState? state) {
  if (state == null) return null;
  for (final turn in state.conversationTurns.reversed) {
    if (turn.role == 'user' && turn.content.trim().isNotEmpty) {
      return turn.content.trim();
    }
  }
  return null;
}

String _activeMemoryLabel(
  RuntimeAgentState? state,
  ConversationContextSnapshot contextSnapshot,
) {
  final memories = state?.memoryRecords ?? const <RuntimeWorkingSetRecord>[];
  if (memories.isEmpty) return 'none yet';
  if (memories.length == 1) return '${memories.first.title} (Pinned)';
  if (contextSnapshot.longTermMemory.isNotEmpty) {
    return contextSnapshot.longTermMemory.first.title;
  }
  return '${memories.length} active memories';
}

String _desktopDate(int ms) {
  if (ms <= 0) return 'not recorded';
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}
