part of 'agent_home_storyboard.dart';

final class _ContextRail extends StatelessWidget {
  const _ContextRail();

  static const _today = [
    '3 top priorities',
    '2 calendar windows',
    '3 reminders',
    '2 commitments owed',
  ];
  static const _memory = [
    'Prefers Chinese',
    'No meetings before 9 AM',
    'Focus time 14:00-15:00',
    'Important follow-ups',
  ];
  static const _files = [
    'Q2_Budget_Report.pdf',
    'Client_Requirements.docx',
    'Meeting_Notes_2025-05-19.md',
  ];

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 28, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your context',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              _Glyph('S', color: Color(0xFF485777)),
            ],
          ),
          SizedBox(height: 16),
          Divider(color: AgentHomeStoryboard.line),
          SizedBox(height: 12),
          _ContextSection(
              number: '1', title: 'Today at a glance', items: _today),
          _ContextSection(
              number: '2', title: 'Long-term memory', items: _memory),
          _PeopleSection(),
          _ContextSection(number: '4', title: 'Recent files', items: _files),
          _PendingReviews(),
          _PrivacyBox(),
        ],
      ),
    );
  }
}

final class _ContextSection extends StatelessWidget {
  const _ContextSection({
    required this.number,
    required this.title,
    required this.items,
  });

  final String number;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NumberedTitle(number, title),
          const SizedBox(height: 8),
          for (final item in items) _ContextRow(item),
          const Divider(color: AgentHomeStoryboard.line),
        ],
      ),
    );
  }
}

final class _NumberedTitle extends StatelessWidget {
  const _NumberedTitle(this.number, this.title);

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 24, child: Text(number, style: _titleStyle(16))),
        Expanded(child: Text(title, style: _titleStyle(16))),
      ],
    );
  }
}

final class _ContextRow extends StatelessWidget {
  const _ContextRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const _Square(size: 17),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const Text('>',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _PeopleSection extends StatelessWidget {
  const _PeopleSection();

  static const _people = [
    (name: 'Alex - Project', color: Color(0xFFB97948)),
    (name: 'Li Wei - Client', color: Color(0xFF2C4A75)),
    (name: 'Ethan - Finance', color: Color(0xFF9D6A3D)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NumberedTitle('3', 'People'),
          const SizedBox(height: 8),
          for (final person in _people)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _Avatar(label: person.name[0], color: person.color, size: 28),
                  const SizedBox(width: 12),
                  Text(person.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const Divider(color: AgentHomeStoryboard.line),
        ],
      ),
    );
  }
}

final class _PendingReviews extends StatelessWidget {
  const _PendingReviews();

  static const _rows = [
    (title: 'Task change: weekly report', chip: 'High', tone: _Tone.red),
    (title: 'Email draft to client', chip: 'Medium', tone: _Tone.orange),
    (title: 'Recurring reminder rule', chip: 'Low', tone: _Tone.green),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NumberedTitle('5', 'Pending review'),
          const SizedBox(height: 8),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const _Square(size: 17),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  _Chip(row.chip, tone: row.tone),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _PrivacyBox extends StatelessWidget {
  const _PrivacyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(
        radius: 8,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      child: const Row(
        children: [
          _Square(size: 17),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Privacy note\nMemory is private and editable.',
              style: TextStyle(
                  color: Color(0xFF1B5C47),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_home_mobile_mock'),
      width: 430,
      height: 1115,
      decoration: _box(
        radius: 58,
        border: const Color(0xFF111827),
        borderWidth: 5,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(52),
        child: const _MobileConversationCanvas(showSheet: true),
      ),
    );
  }
}

final class _MobileConversationCanvas extends StatelessWidget {
  const _MobileConversationCanvas({this.showSheet = false});

  final bool showSheet;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Stack(
        children: [
          const Positioned.fill(child: _MobileBody()),
          if (showSheet)
            const Positioned(
                left: 0, right: 0, bottom: 0, child: _MobileSheet()),
        ],
      ),
    );
  }
}

final class _MobileBody extends StatelessWidget {
  const _MobileBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 26, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneStatus(),
          SizedBox(height: 20),
          _MobileHeader(),
          Divider(height: 28, color: AgentHomeStoryboard.line),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  _MobileMessage(
                    author: 'You',
                    time: '09:12',
                    avatar: _Avatar(
                        label: 'AL', color: AgentHomeStoryboard.blue, size: 28),
                    text:
                        'Move the weekly report to today 20:00, but do not mark it complete.',
                  ),
                  SizedBox(height: 20),
                  _MobileMessage(
                    author: 'SecondLoop',
                    time: '09:12',
                    status: 'Thinking...',
                    avatar: _LoopAvatar(size: 28),
                    text:
                        'I prepared the change and kept the task unfinished. Review it below before I update it.',
                  ),
                  SizedBox(height: 12),
                  _TaskPreview(desktop: false),
                ],
              ),
            ),
          ),
          SizedBox(height: 8),
          _Composer(fullText: false),
        ],
      ),
    );
  }
}

final class _PhoneStatus extends StatelessWidget {
  const _PhoneStatus();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(width: 30),
        Expanded(
          child: Text('9:41',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ),
        Text('|||',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900)),
      ],
    );
  }
}

final class _MobileHeader extends StatelessWidget {
  const _MobileHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('=', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Expanded(
          child: Column(
            children: [
              Text('Conversation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PresenceDot(),
                  SizedBox(width: 6),
                  Text('Always on',
                      style: TextStyle(
                          color: AgentHomeStoryboard.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        _Glyph('S', color: Color(0xFF485777)),
      ],
    );
  }
}

final class _MobileMessage extends StatelessWidget {
  const _MobileMessage({
    required this.author,
    required this.time,
    required this.avatar,
    required this.text,
    this.status,
  });

  final String author;
  final String time;
  final Widget avatar;
  final String text;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(author,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Text(time, style: _mutedBold(12)),
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    _Chip(status!, tone: _Tone.blue),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(text,
                  style: const TextStyle(
                      fontSize: 13, height: 1.45, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

final class _MobileSheet extends StatelessWidget {
  const _MobileSheet();

  static const _rows = [
    'Today at a glance',
    'Long-term memory',
    'People',
    'Recent files',
    'Pending review',
    'Privacy note',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 430,
      decoration: const BoxDecoration(
        color: AgentHomeStoryboard.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        children: [
          const SizedBox(
            width: 42,
            child: Divider(thickness: 5, color: Color(0xFFB9C1D2)),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: Text('Your context',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              Text('x',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AgentHomeStoryboard.line),
          for (var i = 0; i < _rows.length; i++)
            _SheetRow(number: '${i + 1}', title: _rows[i]),
        ],
      ),
    );
  }
}

final class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(number, style: _titleStyle(15))),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800))),
          const Text('>',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
