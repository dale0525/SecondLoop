part of 'agent_home_storyboard.dart';

final class _CalendarEmailPhoneFrame extends StatelessWidget {
  const _CalendarEmailPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_calendar_email_mobile_mock'),
      width: 430,
      height: 1115,
      decoration: _box(
        radius: 58,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(52),
        child: const _CalendarEmailMobileCanvas(),
      ),
    );
  }
}

final class _CalendarEmailMobileCanvas extends StatelessWidget {
  const _CalendarEmailMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Stack(
        children: [
          Positioned.fill(child: _CalendarEmailMobileBody()),
          Positioned(
              left: 0, right: 0, bottom: 0, child: _CalendarMobileSheet()),
        ],
      ),
    );
  }
}

final class _CalendarEmailMobileBody extends StatelessWidget {
  const _CalendarEmailMobileBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneStatus(),
          SizedBox(height: 22),
          _MobileHeader(),
          Divider(height: 26, color: AgentHomeStoryboard.line),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  _MobileMessage(
                    author: 'You',
                    time: '09:01',
                    avatar: _Avatar(
                        label: 'AL', color: AgentHomeStoryboard.blue, size: 32),
                    text: 'Find dinner times next week.',
                  ),
                  SizedBox(height: 16),
                  _CalendarMobileInviteReply(),
                  SizedBox(height: 18),
                  _MobileMessage(
                    author: 'You',
                    time: '10:15',
                    avatar: _Avatar(
                        label: 'AL', color: AgentHomeStoryboard.blue, size: 32),
                    text: "Draft a follow-up email from today's meeting.",
                  ),
                  SizedBox(height: 16),
                  _CalendarMobileEmailReply(),
                  SizedBox(height: 320),
                ],
              ),
            ),
          ),
          _Composer(fullText: false),
        ],
      ),
    );
  }
}

final class _CalendarMobileInviteReply extends StatelessWidget {
  const _CalendarMobileInviteReply();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 32),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '09:02'),
              SizedBox(height: 8),
              Text(
                'Here are recommended evening times and a draft invite.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _CalendarMobileInviteCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CalendarMobileInviteCard extends StatelessWidget {
  const _CalendarMobileInviteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recommended evening times',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          _CalendarMobileSlot('Tue 5/20', '19:30 - 21:00'),
          SizedBox(height: 8),
          _CalendarMobileSlot('Thu 5/22', '19:00 - 20:30'),
          SizedBox(height: 12),
          Text('See more available times',
              style: TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _TinyActionButton('Needs your approval to send', primary: true),
        ],
      ),
    );
  }
}

final class _CalendarMobileSlot extends StatelessWidget {
  const _CalendarMobileSlot(this.day, this.time);

  final String day;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _box(radius: 8, color: const Color(0xFFFBFCFE)),
      child: Row(
        children: [
          const _Glyph('C', color: AgentHomeStoryboard.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(day,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          Text(time,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _CalendarMobileEmailReply extends StatelessWidget {
  const _CalendarMobileEmailReply();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LoopAvatar(size: 32),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageMeta(name: 'SecondLoop', time: '10:16'),
              SizedBox(height: 8),
              Text(
                'I drafted the follow-up. Sending needs your approval.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              _CalendarMobileEmailCard(),
            ],
          ),
        ),
      ],
    );
  }
}

final class _CalendarMobileEmailCard extends StatelessWidget {
  const _CalendarMobileEmailCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Follow-up email draft',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                _DraftField('To', 'Team members (8)'),
                _DraftField('Subject', 'Q2 plan follow-up'),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _TinyActionButton('Save draft')),
                    SizedBox(width: 8),
                    Expanded(
                        child:
                            _TinyActionButton('Needs approval', primary: true)),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHomeStoryboard.line),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    _Glyph('E', color: Color(0xFFFF8A00)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Email not connected',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                _TinyActionButton('Configure Email'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _CalendarMobileSheet extends StatelessWidget {
  const _CalendarMobileSheet();

  static const _rows = [
    'Today at a glance',
    'Long-term memory',
    'People',
    'Recent files',
    'Pending review',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        color: AgentHomeStoryboard.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        children: [
          const SizedBox(
            width: 42,
            child: Divider(thickness: 5, color: Color(0xFFB9C1D2)),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(
                child: Text('Your context',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              Text('^',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in _rows) _CalendarSheetRow(row),
        ],
      ),
    );
  }
}

final class _CalendarSheetRow extends StatelessWidget {
  const _CalendarSheetRow(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const Text('>',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
