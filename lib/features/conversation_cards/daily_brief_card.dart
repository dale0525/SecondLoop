import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../agent_ui/agent_design_tokens.dart';
import 'reminder_candidate_card.dart';

final class DailyBriefData {
  const DailyBriefData({
    required this.topPriorities,
    required this.calendarWindows,
    required this.reminders,
    required this.commitmentsOwed,
    required this.pendingReviews,
    required this.candidates,
  });

  final List<String> topPriorities;
  final List<String> calendarWindows;
  final List<String> reminders;
  final List<String> commitmentsOwed;
  final List<String> pendingReviews;
  final List<ReminderCandidate> candidates;

  static DailyBriefData demo() {
    return const DailyBriefData(
      topPriorities: [
        'Renew passport before the application window closes.',
        'Finish the weekly report draft.',
      ],
      calendarWindows: [
        '19:30-20:30 is open for focused admin work.',
      ],
      reminders: [
        'Review one task change before it writes to the vault.',
      ],
      commitmentsOwed: [
        'Send Mina the travel checklist.',
      ],
      pendingReviews: [
        'Task due-time change needs approval.',
      ],
      candidates: [
        ReminderCandidate(
          title: 'Memory candidate: child birthday',
          subtitle: 'Store the birthday as long-term family context.',
          kindLabel: 'Memory',
        ),
        ReminderCandidate(
          title: 'Recurring reminder candidate: buy gift before birthday',
          subtitle:
              'Create an annual reminder one day before the birthday date.',
          kindLabel: 'Reminder',
        ),
      ],
    );
  }
}

final class DailyBriefCard extends StatelessWidget {
  const DailyBriefCard({
    required this.data,
    super.key,
  });

  final DailyBriefData data;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final t = context.t.chat.dailyBrief;
    return SlSurface(
      key: const ValueKey('daily_brief_card'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _BriefSection(title: t.topPriorities, items: data.topPriorities),
            _BriefSection(
                title: t.calendarWindows, items: data.calendarWindows),
            _BriefSection(title: t.reminders, items: data.reminders),
            _BriefSection(
                title: t.commitmentsOwed, items: data.commitmentsOwed),
            _BriefSection(title: t.pendingReviews, items: data.pendingReviews),
            const SizedBox(height: AgentDesignTokens.gapSm),
            for (final candidate in data.candidates) ...[
              ReminderCandidateCard(candidate: candidate),
              const SizedBox(height: AgentDesignTokens.gapSm),
            ],
          ],
        ),
      ),
    );
  }
}

final class _BriefSection extends StatelessWidget {
  const _BriefSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AgentDesignTokens.gapXs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AgentDesignTokens.gapXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('- '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
