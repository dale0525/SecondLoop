part of 'agent_home_storyboard.dart';

final class AgentDailyBriefStoryboard extends StatelessWidget {
  const AgentDailyBriefStoryboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: AgentHomeStoryboard.ink,
        fontFamily: 'Inter',
        fontSize: 14,
        decoration: TextDecoration.none,
      ),
      child: const ColoredBox(
        color: AgentHomeStoryboard.soft,
        child: FittedBox(
          alignment: Alignment.topLeft,
          fit: BoxFit.contain,
          child: SizedBox(
            width: AgentHomeStoryboard.canvasWidth,
            height: AgentHomeStoryboard.canvasHeight,
            child: _DailyBriefCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _DailyBriefCanvas extends StatelessWidget {
  const _DailyBriefCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1115,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DailyBriefWorkspace(),
                SizedBox(width: 56),
                _DailyBriefPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _DailyBriefNotesStrip(),
        ],
      ),
    );
  }
}

final class _DailyBriefWorkspace extends StatelessWidget {
  const _DailyBriefWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_daily_brief_workspace'),
      width: 1552,
      height: 1115,
      decoration: _box(radius: 16),
      child: const Row(
        children: [
          _Sidebar(),
          _VLine(),
          Expanded(child: _DailyBriefConversation()),
          _VLine(),
          SizedBox(width: 395, child: _ContextRail()),
        ],
      ),
    );
  }
}

final class _DailyBriefConversation extends StatelessWidget {
  const _DailyBriefConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DailyBriefHeader(),
          SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DailyBriefUserMessage(),
                  SizedBox(height: 14),
                  _DailyBriefAssistantMessage(),
                  SizedBox(height: 14),
                  _DailyBriefFollowUpUser(),
                  SizedBox(height: 12),
                  _DailyBriefQuestionMessage(),
                  SizedBox(height: 12),
                  _DailyBriefBirthdayAnswer(),
                  SizedBox(height: 12),
                  _DailyBriefCandidateMessage(),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          _Composer(fullText: true),
        ],
      ),
    );
  }
}

final class _DailyBriefHeader extends StatelessWidget {
  const _DailyBriefHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('Conversation',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        SizedBox(width: 22),
        _PresenceDot(),
        SizedBox(width: 8),
        Text('Ready',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

final class _DailyBriefUserMessage extends StatelessWidget {
  const _DailyBriefUserMessage();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:01',
      text: 'What should I focus on today?',
      bubble: true,
    );
  }
}

final class _DailyBriefAssistantMessage extends StatelessWidget {
  const _DailyBriefAssistantMessage();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 44),
        SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:01'),
              SizedBox(height: 8),
              Text(
                "Good morning. Here's your daily brief.",
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 14),
              _DailyBriefSummaryCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefFollowUpUser extends StatelessWidget {
  const _DailyBriefFollowUpUser();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:05',
      text: "Remind me one day before my child's birthday to buy a gift.",
      bubble: true,
    );
  }
}

final class _DailyBriefQuestionMessage extends StatelessWidget {
  const _DailyBriefQuestionMessage();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefTextMessage(
      avatar: _LoopAvatar(size: 44),
      name: 'SecondLoop',
      time: '09:05',
      text: "Sure. What date is your child's birthday?",
    );
  }
}

final class _DailyBriefBirthdayAnswer extends StatelessWidget {
  const _DailyBriefBirthdayAnswer();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:06',
      text: "My child's birthday is June 20.",
      bubble: true,
    );
  }
}

final class _DailyBriefCandidateMessage extends StatelessWidget {
  const _DailyBriefCandidateMessage();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 44),
        SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:06'),
              SizedBox(height: 8),
              Text(
                'Got it. I prepared these items for Review before enabling them.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 14),
              _DailyBriefCandidateCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefTextMessage extends StatelessWidget {
  const _DailyBriefTextMessage({
    required this.avatar,
    required this.name,
    required this.time,
    required this.text,
    this.bubble = false,
  });

  final Widget avatar;
  final String name;
  final String time;
  final String text;
  final bool bubble;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      style: TextStyle(
        color: bubble ? AgentHomeStoryboard.ink : AgentHomeStoryboard.muted,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w800,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: name, time: time),
              const SizedBox(height: 8),
              if (bubble)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: _box(
                    radius: 8,
                    color: const Color(0xFFF0F3F8),
                    border: const Color(0xFFF0F3F8),
                  ),
                  child: textWidget,
                )
              else
                textWidget,
            ],
          ),
        ),
      ],
    );
  }
}

final class _DailyBriefSummaryCard extends StatelessWidget {
  const _DailyBriefSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PriorityColumn()),
                _VLine(),
                Expanded(child: _CalendarColumn()),
                _VLine(),
                Expanded(child: _ReminderColumn()),
                _VLine(),
                Expanded(child: _CommitmentColumn()),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          _PendingReviewsRow(),
        ],
      ),
    );
  }
}

final class _PriorityColumn extends StatelessWidget {
  const _PriorityColumn();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefPanel(
      title: 'Top priorities',
      rows: [
        _DailyPanelRow('1', 'Weekly report', chip: 'High'),
        _DailyPanelRow('2', 'Q2 budget report', chip: 'High'),
        _DailyPanelRow('3', 'Client demo prep',
            chip: 'Medium', tone: _Tone.orange),
      ],
      link: 'See all tasks (6)',
    );
  }
}

final class _CalendarColumn extends StatelessWidget {
  const _CalendarColumn();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefPanel(
      title: 'Calendar windows',
      rows: [
        _DailyPanelRow('', '09:00 - 10:00', chip: 'Free', tone: _Tone.green),
        _DailyPanelRow('', '14:00 - 15:00', chip: 'Focus time'),
        _DailyPanelRow('', '16:00 - 17:00', chip: 'Busy'),
      ],
      link: "See today's calendar",
    );
  }
}

final class _ReminderColumn extends StatelessWidget {
  const _ReminderColumn();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefPanel(
      title: 'Reminders',
      rows: [
        _DailyPanelRow('!', '09:00  Standup', chip: 'Scheduled'),
        _DailyPanelRow('o', '17:00  Buy gift', chip: 'Scheduled'),
        _DailyPanelRow('!', 'Birthday reminder',
            chip: 'Needs OK', tone: _Tone.orange),
      ],
      link: 'See all reminders',
    );
  }
}

final class _CommitmentColumn extends StatelessWidget {
  const _CommitmentColumn();

  @override
  Widget build(BuildContext context) {
    return const _DailyBriefPanel(
      title: 'Commitments owed',
      rows: [
        _DailyPanelRow('>', 'Follow up with Alex\nToday 10:00'),
        _DailyPanelRow('!', 'Product review feedback\nToday 14:00'),
        _DailyPanelRow('[]', 'Submit reimbursement\nMay 23, 17:00'),
      ],
      link: 'See all commitments',
    );
  }
}

final class _DailyBriefPanel extends StatelessWidget {
  const _DailyBriefPanel({
    required this.title,
    required this.rows,
    required this.link,
  });

  final String title;
  final List<_DailyPanelRow> rows;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          for (final row in rows) row,
          const SizedBox(height: 2),
          Text(link,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _DailyPanelRow extends StatelessWidget {
  const _DailyPanelRow(
    this.marker,
    this.text, {
    this.chip,
    this.tone = _Tone.blue,
  });

  final String marker;
  final String text;
  final String? chip;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: const TextStyle(
                  color: Color(0xFFFF2E2E),
                  fontSize: 13,
                  fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, height: 1.2, fontWeight: FontWeight.w800),
            ),
          ),
          if (chip != null) ...[
            const SizedBox(width: 8),
            _Chip(chip!, tone: tone),
          ],
        ],
      ),
    );
  }
}

final class _PendingReviewsRow extends StatelessWidget {
  const _PendingReviewsRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 76,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text('Pending reviews',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            SizedBox(width: 8),
            _Chip('3', tone: _Tone.blue),
            SizedBox(width: 28),
            Expanded(
              child: _DailyReviewInlineItem(
                glyph: 'T',
                color: Color(0xFFFF2E2E),
                text: 'Task change: weekly report',
                chip: 'High',
                tone: _Tone.red,
              ),
            ),
            Expanded(
              child: _DailyReviewInlineItem(
                glyph: 'E',
                color: AgentHomeStoryboard.blue,
                text: 'Email draft to client',
                chip: 'Medium',
                tone: _Tone.orange,
              ),
            ),
            Expanded(
              child: _DailyReviewInlineItem(
                glyph: 'R',
                color: Color(0xFF159364),
                text: 'Recurring reminder rule',
                chip: 'Low',
                tone: _Tone.green,
              ),
            ),
            SizedBox(width: 18),
            Text('Go to Review',
                style: TextStyle(
                    color: AgentHomeStoryboard.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

final class _DailyReviewInlineItem extends StatelessWidget {
  const _DailyReviewInlineItem({
    required this.glyph,
    required this.color,
    required this.text,
    required this.chip,
    required this.tone,
  });

  final String glyph;
  final Color color;
  final String text;
  final String chip;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Glyph(glyph, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        _Chip(chip, tone: tone),
      ],
    );
  }
}

final class _DailyBriefCandidateCard extends StatelessWidget {
  const _DailyBriefCandidateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Needs confirmation (2)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 10),
          _DailyCandidateRow(
            glyph: 'M',
            color: Color(0xFFFF8A00),
            title: 'Memory candidate: child birthday',
            detail: 'Personal  -  High confidence',
          ),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          _DailyCandidateRow(
            glyph: 'R',
            color: Color(0xFF8D57FF),
            title: 'Recurring reminder candidate: buy gift before birthday',
            detail: 'Reminder  -  High confidence',
          ),
        ],
      ),
    );
  }
}

final class _DailyCandidateRow extends StatelessWidget {
  const _DailyCandidateRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.detail,
  });

  final String glyph;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _Glyph(glyph, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(detail, style: _mutedBold(12)),
              ],
            ),
          ),
          Text('High confidence', style: _mutedBold(12)),
          const SizedBox(width: 22),
          const SizedBox(
              width: 74, child: _TinyActionButton('Review', primary: true)),
          const SizedBox(width: 8),
          const SizedBox(width: 72, child: _TinyActionButton('Edit')),
          const SizedBox(width: 8),
          const SizedBox(width: 72, child: _TinyActionButton('Ignore')),
        ],
      ),
    );
  }
}

final class _DailyBriefNotesStrip extends StatelessWidget {
  const _DailyBriefNotesStrip();

  static const _notes = [
    (
      title: 'Daily brief is a conversation response.',
      body:
          'The brief combines tasks, reminders, commitments, calendar, and recent context.',
    ),
    (
      title: 'Simple, low-risk new tasks may be added automatically.',
      body: 'New items can be applied automatically when safe.',
    ),
    (
      title: 'Existing task changes wait for approval.',
      body: 'Formal mutations open a review item before applying.',
    ),
    (
      title: 'Missing facts trigger follow-up questions.',
      body: 'SecondLoop asks clarifying questions before creating items.',
    ),
    (
      title: 'Right context rail remains stable.',
      body: 'Your context is consistent across the conversation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_daily_brief_interaction_notes'),
      height: 220,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(28, 24, 26, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Text('Interaction Notes',
                style: TextStyle(
                    fontSize: 21, height: 1.25, fontWeight: FontWeight.w900)),
          ),
          const _NoteDivider(),
          for (var i = 0; i < _notes.length; i++) ...[
            Expanded(
              child: _NoteItem(
                number: '${i + 1}',
                title: _notes[i].title,
                body: _notes[i].body,
              ),
            ),
            if (i < _notes.length - 1) const _NoteDivider(),
          ],
        ],
      ),
    );
  }
}
