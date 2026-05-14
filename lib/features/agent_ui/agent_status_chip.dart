import 'package:flutter/material.dart';

import 'agent_design_tokens.dart';

enum AgentStatusTone {
  pending,
  high,
  medium,
  low,
  allowed,
  needsApproval,
  completed,
}

final class AgentStatusChip extends StatelessWidget {
  const AgentStatusChip({
    required this.label,
    required this.tone,
    super.key,
  });

  const AgentStatusChip.pending({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.pending,
        super(key: key ?? const ValueKey('agent_status_chip_pending'));

  const AgentStatusChip.high({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.high,
        super(key: key ?? const ValueKey('agent_status_chip_high'));

  const AgentStatusChip.medium({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.medium,
        super(key: key ?? const ValueKey('agent_status_chip_medium'));

  const AgentStatusChip.low({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.low,
        super(key: key ?? const ValueKey('agent_status_chip_low'));

  const AgentStatusChip.allowed({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.allowed,
        super(key: key ?? const ValueKey('agent_status_chip_allowed'));

  const AgentStatusChip.needsApproval({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.needsApproval,
        super(key: key ?? const ValueKey('agent_status_chip_needs_approval'));

  const AgentStatusChip.completed({
    required this.label,
    Key? key,
  })  : tone = AgentStatusTone.completed,
        super(key: key ?? const ValueKey('agent_status_chip_completed'));

  final String label;
  final AgentStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _AgentStatusChipColors.from(context, tone);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        );

    return Semantics(
      label: label,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(AgentDesignTokens.radiusSm),
        ),
        child: Padding(
          padding: AgentDesignTokens.chipPadding,
          child: Text(label, style: textStyle),
        ),
      ),
    );
  }
}

final class _AgentStatusChipColors {
  const _AgentStatusChipColors({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;

  static _AgentStatusChipColors from(
    BuildContext context,
    AgentStatusTone tone,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final base = switch (tone) {
      AgentStatusTone.pending => scheme.tertiary,
      AgentStatusTone.high => scheme.error,
      AgentStatusTone.medium => Colors.orange,
      AgentStatusTone.low => scheme.primary,
      AgentStatusTone.allowed => Colors.teal,
      AgentStatusTone.needsApproval => scheme.secondary,
      AgentStatusTone.completed => Colors.green,
    };
    final opacity = isDark ? 0.20 : 0.12;
    return _AgentStatusChipColors(
      background: base.withOpacity(opacity),
      border: base.withOpacity(isDark ? 0.45 : 0.35),
      foreground: isDark ? Color.lerp(base, Colors.white, 0.35)! : base,
    );
  }
}
