import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import '../actions/calendar/ics_generator.dart';
import '../agent_ui/agent_design_tokens.dart';
import '../agent_ui/agent_status_chip.dart';

final class CalendarEmailData {
  const CalendarEmailData({
    required this.availability,
    required this.invite,
    required this.email,
  });

  final CalendarAvailabilityData availability;
  final CalendarInviteDraft invite;
  final EmailDraftData email;

  static CalendarEmailData demo() {
    return CalendarEmailData(
      availability: const CalendarAvailabilityData(
        title: 'Evening admin window',
        detail: 'Today 19:30-20:00 remains open after school pickup.',
      ),
      invite: CalendarInviteDraft(
        uid: 'passport-renewal-prep',
        title: 'Passport renewal prep',
        timeLabel: 'Today 19:30-20:00',
        attendees: const ['Mina Park'],
        startUtc: DateTime.utc(2026, 5, 13, 11, 30),
        endUtc: DateTime.utc(2026, 5, 13, 12),
        dtStampUtc: DateTime.utc(2026, 5, 13),
      ),
      email: const EmailDraftData(
        subject: 'Draft: travel checklist follow-up',
        preview: 'Hi Mina, here is the checklist before the appointment.',
        sendState: EmailSendState.notConnected,
      ),
    );
  }
}

final class CalendarAvailabilityData {
  const CalendarAvailabilityData({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;
}

final class CalendarInviteDraft {
  const CalendarInviteDraft({
    required this.uid,
    required this.title,
    required this.timeLabel,
    required this.attendees,
    required this.startUtc,
    required this.endUtc,
    required this.dtStampUtc,
  });

  final String uid;
  final String title;
  final String timeLabel;
  final List<String> attendees;
  final DateTime startUtc;
  final DateTime endUtc;
  final DateTime dtStampUtc;

  String buildIcs() {
    return IcsGenerator.generateEvent(
      uid: uid,
      title: title,
      startUtc: startUtc,
      endUtc: endUtc,
      dtStampUtc: dtStampUtc,
    );
  }

  String get icsSummaryLine {
    return buildIcs().split('\r\n').firstWhere(
          (line) => line.startsWith('SUMMARY:'),
          orElse: () => 'SUMMARY:$title',
        );
  }
}

enum EmailSendState {
  notConnected,
  approvalRequired,
}

final class EmailDraftData {
  const EmailDraftData({
    required this.subject,
    required this.preview,
    required this.sendState,
  });

  final String subject;
  final String preview;
  final EmailSendState sendState;
}

final class CalendarEmailCard extends StatelessWidget {
  const CalendarEmailCard({
    required this.data,
    this.onSaveDraft,
    this.onReviewInvite,
    super.key,
  });

  final CalendarEmailData data;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onReviewInvite;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    return SlSurface(
      key: const ValueKey('calendar_email_card'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      padding: const EdgeInsets.all(AgentDesignTokens.gapLg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CalendarAvailabilitySection(availability: data.availability),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _CalendarInviteSection(
              invite: data.invite,
              onReviewInvite: onReviewInvite,
            ),
            const SizedBox(height: AgentDesignTokens.gapLg),
            _EmailDraftSection(email: data.email, onSaveDraft: onSaveDraft),
          ],
        ),
      ),
    );
  }
}

final class _CalendarAvailabilitySection extends StatelessWidget {
  const _CalendarAvailabilitySection({required this.availability});

  final CalendarAvailabilityData availability;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.calendarEmail;
    return _SectionBlock(
      icon: Icons.event_available_outlined,
      title: t.calendarTitle,
      trailing: AgentStatusChip.allowed(label: t.calendarReadSafe),
      children: [
        Text(
          availability.title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(availability.detail),
      ],
    );
  }
}

final class _CalendarInviteSection extends StatelessWidget {
  const _CalendarInviteSection({
    required this.invite,
    required this.onReviewInvite,
  });

  final CalendarInviteDraft invite;
  final VoidCallback? onReviewInvite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = context.t.chat.calendarEmail;
    return _SectionBlock(
      icon: Icons.outgoing_mail,
      title: t.inviteTitle,
      trailing: AgentStatusChip.needsApproval(
        label: t.inviteRequiresApproval,
      ),
      children: [
        Text(
          invite.title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(invite.timeLabel),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(t.attendees(names: invite.attendees.join(', '))),
        const SizedBox(height: AgentDesignTokens.gapMd),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AgentDesignTokens.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AgentDesignTokens.gapMd),
            child: Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 18),
                const SizedBox(width: AgentDesignTokens.gapSm),
                Expanded(
                  child: Text(
                    [t.icsPreview, invite.icsSummaryLine].join(': '),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AgentDesignTokens.gapMd),
        OutlinedButton.icon(
          onPressed: onReviewInvite,
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: Text(t.reviewInvite),
        ),
      ],
    );
  }
}

final class _EmailDraftSection extends StatelessWidget {
  const _EmailDraftSection({
    required this.email,
    required this.onSaveDraft,
  });

  final EmailDraftData email;
  final VoidCallback? onSaveDraft;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.calendarEmail;
    return _SectionBlock(
      icon: Icons.alternate_email_outlined,
      title: t.emailTitle,
      trailing: AgentStatusChip.allowed(label: t.draftCanBeSaved),
      children: [
        Text(
          email.subject,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AgentDesignTokens.gapXs),
        Text(email.preview),
        const SizedBox(height: AgentDesignTokens.gapMd),
        Wrap(
          spacing: AgentDesignTokens.gapSm,
          runSpacing: AgentDesignTokens.gapSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onSaveDraft,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(t.saveDraft),
            ),
            _EmailSendStatus(sendState: email.sendState),
          ],
        ),
        const SizedBox(height: AgentDesignTokens.gapSm),
        Text(t.approvalRequiredBeforeSend),
      ],
    );
  }
}

final class _EmailSendStatus extends StatelessWidget {
  const _EmailSendStatus({required this.sendState});

  final EmailSendState sendState;

  @override
  Widget build(BuildContext context) {
    final t = context.t.chat.calendarEmail;
    return switch (sendState) {
      EmailSendState.notConnected => AgentStatusChip.pending(
          label: t.emailNotConnected,
        ),
      EmailSendState.approvalRequired => AgentStatusChip.needsApproval(
          label: t.approvalRequiredBeforeSend,
        ),
    };
  }
}

final class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeader = constraints.maxWidth < 360;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compactHeader) ...[
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AgentDesignTokens.gapSm),
                  Expanded(child: Text(title, style: titleStyle)),
                ],
              ),
              const SizedBox(height: AgentDesignTokens.gapSm),
              trailing,
            ] else ...[
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AgentDesignTokens.gapSm),
                  Expanded(child: Text(title, style: titleStyle)),
                  trailing,
                ],
              ),
            ],
            const SizedBox(height: AgentDesignTokens.gapMd),
            ...children,
          ],
        );
      },
    );
  }
}
