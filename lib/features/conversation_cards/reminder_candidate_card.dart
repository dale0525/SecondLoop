import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';

final class ReminderCandidate {
  const ReminderCandidate({
    required this.title,
    required this.subtitle,
    required this.kindLabel,
  });

  final String title;
  final String subtitle;
  final String kindLabel;
}

final class ReminderCandidateCard extends StatelessWidget {
  const ReminderCandidateCard({
    required this.candidate,
    super.key,
  });

  final ReminderCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return SlSurface(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  candidate.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              AgentStatusChip.needsApproval(label: candidate.kindLabel),
            ],
          ),
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(candidate.subtitle),
        ],
      ),
    );
  }
}
