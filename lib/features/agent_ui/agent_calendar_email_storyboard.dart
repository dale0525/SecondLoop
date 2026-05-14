part of 'agent_home_storyboard.dart';

final class AgentCalendarEmailStoryboard extends StatelessWidget {
  const AgentCalendarEmailStoryboard({super.key});

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
            child: _CalendarEmailCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _CalendarEmailCanvas extends StatelessWidget {
  const _CalendarEmailCanvas();

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
                _CalendarEmailWorkspace(),
                SizedBox(width: 56),
                _CalendarEmailPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _CalendarEmailNotesStrip(),
        ],
      ),
    );
  }
}

final class _CalendarEmailWorkspace extends StatelessWidget {
  const _CalendarEmailWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_calendar_email_workspace'),
      width: 1552,
      height: 1115,
      decoration: _box(radius: 16),
      child: const Row(
        children: [
          _Sidebar(),
          _VLine(),
          Expanded(child: _CalendarEmailConversation()),
          _VLine(),
          SizedBox(width: 395, child: _ContextRail()),
        ],
      ),
    );
  }
}

final class _CalendarEmailConversation extends StatelessWidget {
  const _CalendarEmailConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalendarEmailHeader(),
          SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CalendarEmailDinnerRequest(),
                  SizedBox(height: 18),
                  _CalendarEmailInviteReply(),
                  SizedBox(height: 18),
                  _CalendarEmailFollowUpRequest(),
                  SizedBox(height: 18),
                  _CalendarEmailDraftReply(),
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

final class _CalendarEmailHeader extends StatelessWidget {
  const _CalendarEmailHeader();

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

final class _CalendarEmailDinnerRequest extends StatelessWidget {
  const _CalendarEmailDinnerRequest();

  @override
  Widget build(BuildContext context) {
    return const _CalendarEmailTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '09:01',
      text: 'Find two next-week evening times when friends can have dinner.',
      bubble: true,
    );
  }
}

final class _CalendarEmailInviteReply extends StatelessWidget {
  const _CalendarEmailInviteReply();

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
              _MessageMeta(name: 'SecondLoop', time: '09:02'),
              SizedBox(height: 8),
              Text(
                'Here are recommended evening times and an invite draft. Sending needs your approval.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              _CalendarInviteCard(),
              SizedBox(height: 8),
              _CalendarSafetyNote(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CalendarEmailFollowUpRequest extends StatelessWidget {
  const _CalendarEmailFollowUpRequest();

  @override
  Widget build(BuildContext context) {
    return const _CalendarEmailTextMessage(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 44),
      name: 'You',
      time: '10:15',
      text: "Draft a follow-up email to the team based on today's meeting.",
      bubble: true,
    );
  }
}

final class _CalendarEmailDraftReply extends StatelessWidget {
  const _CalendarEmailDraftReply();

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
              _MessageMeta(name: 'SecondLoop', time: '10:16'),
              SizedBox(height: 8),
              Text(
                'I drafted the follow-up, summarized key points, and kept sending behind approval.',
                style: TextStyle(
                    color: AgentHomeStoryboard.muted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              _EmailDraftCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CalendarEmailTextMessage extends StatelessWidget {
  const _CalendarEmailTextMessage({
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

final class _CalendarInviteCard extends StatelessWidget {
  const _CalendarInviteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const SizedBox(
        height: 260,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _AvailabilityPanel()),
            _VLine(),
            Expanded(child: _InviteDraftPanel()),
          ],
        ),
      ),
    );
  }
}

final class _AvailabilityPanel extends StatelessWidget {
  const _AvailabilityPanel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Recommended evening times',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              _Chip('Calendar read is safe', tone: _Tone.green),
            ],
          ),
          SizedBox(height: 18),
          _TimeSlot('Tue 5/20', '19:30 - 21:00'),
          SizedBox(height: 10),
          _TimeSlot('Thu 5/22', '19:00 - 20:30'),
          SizedBox(height: 18),
          Text('See more available times',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _TimeSlot extends StatelessWidget {
  const _TimeSlot(this.day, this.time);

  final String day;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(radius: 8, color: const Color(0xFFFBFCFE)),
      child: Row(
        children: [
          const _Glyph('C', color: AgentHomeStoryboard.blue),
          const SizedBox(width: 14),
          Expanded(
            child: Text(day,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Text(time,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _InviteDraftPanel extends StatelessWidget {
  const _InviteDraftPanel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Dinner invite draft',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              _Chip('Needs your approval to send', tone: _Tone.orange),
            ],
          ),
          SizedBox(height: 16),
          _DraftField('Title', 'Dinner with friends'),
          _DraftField('Time', 'Tue 5/20 19:30 - 21:00'),
          _DraftField('Place', 'Harbor Bistro'),
          _DraftField('Guests', 'Alex, Li Wei, Ethan'),
          _DraftField('Notes', 'Casual catch-up and dinner'),
          Spacer(),
          Row(
            children: [
              Expanded(child: _TinyActionButton('View details')),
              SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: _TinyActionButton('Needs your approval to send',
                    primary: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _DraftField extends StatelessWidget {
  const _DraftField(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 62, child: Text(label, style: _mutedBold(12))),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _CalendarSafetyNote extends StatelessWidget {
  const _CalendarSafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: _box(
        radius: 8,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: const Row(
        children: [
          _Glyph('S', color: Color(0xFF159364)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Calendar access only reads availability. Invites and emails wait for explicit approval.',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Color(0xFF1B5C47),
                  fontSize: 13,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _EmailDraftCard extends StatelessWidget {
  const _EmailDraftCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      padding: const EdgeInsets.all(14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _MeetingSummaryPanel()),
          SizedBox(width: 12),
          Expanded(flex: 2, child: _FollowUpDraftPanel()),
          SizedBox(width: 12),
          SizedBox(width: 230, child: _EmailStatusPanel()),
        ],
      ),
    );
  }
}

final class _MeetingSummaryPanel extends StatelessWidget {
  const _MeetingSummaryPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Meeting notes summary',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          Text(
            '- Q2 plan is on track; key budget decisions are ready.\n- Product launch timing moved to 6/15.\n- Owner updates are due 5/26.\n- Next sync: Fri 5/23 10:00.',
            style: TextStyle(
                fontSize: 12, height: 1.55, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

final class _FollowUpDraftPanel extends StatelessWidget {
  const _FollowUpDraftPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow-up email draft',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          _DraftField('To', 'Team members (8)'),
          _DraftField('Subject', 'Follow-up: Q2 plan and next steps'),
          SizedBox(height: 8),
          Expanded(
            child: Text(
              'Hi team,\n\nThanks for the discussion today. Here are the key points and next steps from the meeting:\n- Q2 plan remains on track.\n- Confirm launch timing and budget.\n- Share owner updates by 5/26.\n- Next sync is Fri 5/23 at 10:00.\n\nThanks,\nLi Wei',
              overflow: TextOverflow.fade,
              style: TextStyle(
                  fontSize: 12, height: 1.35, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _TinyActionButton('Save draft')),
              SizedBox(width: 10),
              Expanded(
                child:
                    _TinyActionButton('Needs approval to send', primary: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _EmailStatusPanel extends StatelessWidget {
  const _EmailStatusPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(14),
      decoration: _box(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Email send status',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _box(
              radius: 8,
              color: const Color(0xFFFFF7ED),
              border: const Color(0xFFFFE0B8),
            ),
            child: const Column(
              children: [
                _Glyph('E', color: Color(0xFFFF8A00)),
                SizedBox(height: 8),
                Text('Email not connected',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('Sending drafts requires account connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Spacer(),
          const _TinyActionButton('Configure Email'),
          const SizedBox(height: 8),
          Text(
            'After connection, sending still enters approval.',
            textAlign: TextAlign.center,
            style: _mutedBold(11),
          ),
        ],
      ),
    );
  }
}

final class _CalendarEmailNotesStrip extends StatelessWidget {
  const _CalendarEmailNotesStrip();

  static const _notes = [
    (
      title: 'Calendar and email reads are safe.',
      body: 'Reading available time or draft context does not affect anything.',
    ),
    (
      title: 'Sending email or invites needs confirmation.',
      body: 'Outbound messages enter approval and run only after you confirm.',
    ),
    (
      title: 'Unconfigured email shows connection state.',
      body:
          'Configure Email is shown instead of pretending the draft was sent.',
    ),
    (
      title: 'Drafts can be saved without sending.',
      body: 'You can keep editing a draft with no external side effect.',
    ),
    (
      title: 'Contacts and calendar changes enter review.',
      body: 'New or changed external data is reviewed before applying.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_calendar_email_interaction_notes'),
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
