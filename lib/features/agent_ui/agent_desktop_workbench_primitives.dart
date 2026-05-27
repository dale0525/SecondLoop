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
    final colors = AgentOperatingSystemTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.labelLg.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      _DesktopCountBadge(count: count!),
                    ],
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: AgentOperatingSystemTokens.code.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      )
                    else if (trailingIcon != null)
                      Icon(
                        trailingIcon,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              color: colors.outlineVariant,
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
    final colors = AgentOperatingSystemTokens.of(context);
    final valueWidget = Text(
      value,
      style: AgentOperatingSystemTokens.bodySm.copyWith(
        color: colors.onSurface,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AgentOperatingSystemTokens.labelMd.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (icon == null)
          valueWidget
        else
          Row(
            children: [
              Icon(icon, size: 14, color: colors.secondary),
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
    final colors = AgentOperatingSystemTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        color: colors.outlineVariant,
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
    final colors = AgentOperatingSystemTokens.of(context);
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AgentOperatingSystemTokens.code.copyWith(
              color: colors.onSurfaceVariant,
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
    final colors = AgentOperatingSystemTokens.of(context);
    return SizedBox(
      width: 20,
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$count',
            style: AgentOperatingSystemTokens.labelMd.copyWith(
              color: colors.onSecondaryContainer,
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
    final colors = AgentOperatingSystemTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusSm),
          border: Border.all(color: colors.outlineVariant),
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
  final snapshotTrace = state.latestContextSnapshot?.packet['tool_trace'] ??
      state.latestContextSnapshot?.packet['toolTrace'];
  if (snapshotTrace is Map) {
    return snapshotTrace.map(
      (key, value) => MapEntry('$key', value as Object?),
    );
  }
  return const <String, Object?>{};
}

String _desktopToolTraceTitle(Map<String, Object?> trace) {
  final skill = _firstOperatingString([
    trace['skill'],
    trace['skill_id'],
    trace['skillId'],
    trace['runtime_skill'],
    trace['runtimeSkill'],
    trace['tool'],
  ]);
  if (skill == null) return 'tool trace unavailable';
  final status = _firstOperatingString([
        trace['status'],
        trace['state'],
        trace['result'],
      ]) ??
      'reported';
  return '$skill: $status';
}

String? _desktopCitationBadgeLabel({
  required Map<String, Object?> trace,
  required bool hasCitations,
}) {
  if (hasCitations) return 'CITATIONS: PRESENT';
  final skill = _firstOperatingString([
        trace['skill'],
        trace['skill_id'],
        trace['runtime_skill'],
        trace['tool'],
      ]) ??
      '';
  final currentFacts = _firstOperatingString([
        trace['current_facts'],
        trace['currentFacts'],
      ]) ??
      '';
  final needsWebResearch =
      ('$skill $currentFacts').toLowerCase().contains('web-research');
  return needsWebResearch ? 'CITATIONS: MISSING' : null;
}

String? _desktopToolTraceFooter(
  RuntimeAgentState? state,
  Map<String, Object?> trace,
) {
  if (trace.isEmpty) return null;
  final parts = <String>[];
  final latencyMs = _firstOperatingInt([
    trace['latency_ms'],
    trace['latencyMs'],
    trace['duration_ms'],
    trace['durationMs'],
  ]);
  if (latencyMs != null) {
    parts.add('Latency: ${(latencyMs / 1000).toStringAsFixed(2)}s');
  }
  final createdAtMs = _firstOperatingInt([
        trace['created_at_ms'],
        trace['createdAtMs'],
        trace['completed_at_ms'],
        trace['completedAtMs'],
      ]) ??
      _latestTraceTurnCreatedAtMs(state);
  if (createdAtMs != null && createdAtMs > 0) {
    parts.add(_desktopDate(createdAtMs));
  }
  return parts.isEmpty ? null : parts.join(' • ');
}

int? _latestTraceTurnCreatedAtMs(RuntimeAgentState? state) {
  if (state == null) return null;
  for (final turn in state.conversationTurns.reversed) {
    if (turn.raw['tool_trace'] is Map) return turn.createdAtMs;
  }
  return null;
}

int? _firstOperatingInt(Iterable<Object?> values) {
  for (final value in values) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
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
