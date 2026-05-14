part of 'agent_home_storyboard.dart';

final class _DesktopCanvas extends StatelessWidget {
  const _DesktopCanvas();

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
                _DesktopWorkspace(),
                SizedBox(width: 56),
                _PhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _InteractionNotesStrip(),
        ],
      ),
    );
  }
}

final class _DesktopWorkspace extends StatelessWidget {
  const _DesktopWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_home_desktop_workspace'),
      width: 1552,
      height: 1115,
      decoration: _box(radius: 16),
      child: const Row(
        children: [
          _Sidebar(),
          _VLine(),
          Expanded(child: _ConversationWorkspace()),
          _VLine(),
          SizedBox(width: 395, child: _ContextRail()),
        ],
      ),
    );
  }
}

final class _Sidebar extends StatelessWidget {
  const _Sidebar();

  static const _items = [
    (label: 'Conversation', glyph: 'C', selected: true, badge: ''),
    (label: 'Memory', glyph: 'M', selected: false, badge: ''),
    (label: 'Review', glyph: 'R', selected: false, badge: '3'),
    (label: 'Settings', glyph: 'S', selected: false, badge: ''),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 30, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const SizedBox(height: 42),
            for (final item in _items) ...[
              _NavItem(
                label: item.label,
                glyph: item.glyph,
                selected: item.selected,
                badge: item.badge,
              ),
              const SizedBox(height: 18),
            ],
            const Spacer(),
            const Divider(color: AgentHomeStoryboard.line),
            const SizedBox(height: 16),
            const _AccountFooter(),
          ],
        ),
      ),
    );
  }
}

final class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _LoopMark(size: 34, color: AgentHomeStoryboard.blue),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'SecondLoop',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

final class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.badge,
  });

  final String label;
  final String glyph;
  final bool selected;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AgentHomeStoryboard.blue : const Color(0xFF25324F);
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF1FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          _Glyph(glyph, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
          if (badge.isNotEmpty) _Badge(badge),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

final class _AccountFooter extends StatelessWidget {
  const _AccountFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: ValueKey('agent_home_account_footer'),
      children: [
        _Avatar(label: 'AL', color: Color(0xFF24386D), size: 40),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ada Lin',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              SizedBox(height: 3),
              Text('Pro Plan',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted, fontSize: 13)),
            ],
          ),
        ),
        Text('v',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 18,
                fontWeight: FontWeight.w900)),
      ],
    );
  }
}

final class _ConversationWorkspace extends StatelessWidget {
  const _ConversationWorkspace();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConversationHeader(),
          SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MorningBriefMessage(),
                  SizedBox(height: 20),
                  _UserMessage(),
                  SizedBox(height: 20),
                  _AssistantPreviewMessage(),
                  SizedBox(height: 20),
                  _AssistantDoneMessage(),
                ],
              ),
            ),
          ),
          SizedBox(height: 14),
          _Composer(fullText: true),
        ],
      ),
    );
  }
}

final class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('Conversation',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        SizedBox(width: 26),
        _PresenceDot(),
        SizedBox(width: 8),
        Text('Ready',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

final class _MorningBriefMessage extends StatelessWidget {
  const _MorningBriefMessage();

  @override
  Widget build(BuildContext context) {
    return const _MessageRow(
      avatar: _LoopAvatar(size: 32),
      author: 'SecondLoop',
      time: '08:00',
      child: _MorningBriefCard(),
    );
  }
}

final class _MorningBriefCard extends StatelessWidget {
  const _MorningBriefCard();

  static const _columns = [
    (
      title: 'Top priorities',
      items: [
        '1   Complete weekly report',
        '2   Prepare Q2 budget report',
        '3   Client demo materials',
      ],
      link: 'See all tasks (6)',
    ),
    (
      title: 'Calendar windows',
      items: [
        '09:00 - 10:00        Free',
        '11:30 - 12:30        Busy',
        '14:00 - 15:00        Focus time',
        '15:30 - 16:30        Free',
      ],
      link: "See today's calendar",
    ),
    (
      title: 'Reminders',
      items: [
        '09:00   Stand-up meeting',
        '17:00   Buy milk',
        'Birthday gift reminder',
      ],
      link: 'See all reminders (3)',
    ),
    (
      title: 'Commitments owed',
      items: ['Follow up with Alex', 'Send expense report'],
      link: 'See all commitments (2)',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  "Good morning! Here's your brief for today.",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              _Chip('Done', tone: _Tone.green),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 180,
            decoration: _box(radius: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _columns.length; i++) ...[
                  Expanded(
                    child: _BriefColumn(
                      title: _columns[i].title,
                      items: _columns[i].items,
                      link: _columns[i].link,
                    ),
                  ),
                  if (i < _columns.length - 1) const _VLine(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _BriefColumn extends StatelessWidget {
  const _BriefColumn({
    required this.title,
    required this.items,
    required this.link,
  });

  final String title;
  final List<String> items;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const Spacer(),
          Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AgentHomeStoryboard.blue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

final class _UserMessage extends StatelessWidget {
  const _UserMessage();

  @override
  Widget build(BuildContext context) {
    return const _MessageRow(
      avatar: _Avatar(label: 'AL', color: AgentHomeStoryboard.blue, size: 34),
      author: 'You',
      time: '09:12',
      child: Align(
        alignment: Alignment.centerLeft,
        child: _Bubble(
          'Move the weekly report to today 20:00, but do not mark it complete.',
        ),
      ),
    );
  }
}

final class _AssistantPreviewMessage extends StatelessWidget {
  const _AssistantPreviewMessage();

  @override
  Widget build(BuildContext context) {
    return const _MessageRow(
      avatar: _LoopAvatar(size: 32),
      author: 'SecondLoop',
      time: '09:12',
      status: 'Thinking...',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'I prepared the due-time change and kept the task unfinished. Review the change below before I update it.',
            style: TextStyle(
                fontSize: 15, height: 1.45, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          _TaskPreview(desktop: true),
        ],
      ),
    );
  }
}

final class _AssistantDoneMessage extends StatelessWidget {
  const _AssistantDoneMessage();

  @override
  Widget build(BuildContext context) {
    return const _MessageRow(
      avatar: _LoopAvatar(size: 32),
      author: 'SecondLoop',
      time: '09:13',
      status: 'Done',
      child: Row(
        children: [
          Expanded(
              child: _Outcome('Reminder updated',
                  'Today 19:30    Reminder: weekly report', 'Scheduled')),
          SizedBox(width: 10),
          Expanded(
              child: _Outcome("Today's focus", '14:00-15:00    Focus time',
                  'Add to calendar')),
        ],
      ),
    );
  }
}

final class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.avatar,
    required this.author,
    required this.time,
    required this.child,
    this.status,
  });

  final Widget avatar;
  final String author;
  final String time;
  final Widget child;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(author,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 14),
                  Text(time,
                      style: const TextStyle(
                          color: AgentHomeStoryboard.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  if (status != null) ...[
                    const SizedBox(width: 10),
                    _Chip(status!, tone: _Tone.green),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

final class _TaskPreview extends StatelessWidget {
  const _TaskPreview({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 10),
      padding: EdgeInsets.all(desktop ? 14 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              _Glyph('T', color: Color(0xFFFF8A00)),
              SizedBox(width: 10),
              Expanded(
                child: Text('Task change preview',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              _Chip('Needs your OK', tone: _Tone.orange),
            ],
          ),
          SizedBox(height: desktop ? 12 : 10),
          if (desktop) const _DesktopDiff() else const _MobileDiff(),
          SizedBox(height: desktop ? 14 : 10),
          const _ActionButton('Review & Approve', primary: true),
          SizedBox(height: desktop ? 8 : 10),
          const Row(
            children: [
              Expanded(child: _ActionButton('Edit')),
              SizedBox(width: 10),
              Expanded(child: _ActionButton('Reject', danger: true)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _DesktopDiff extends StatelessWidget {
  const _DesktopDiff();

  static const _rows = [
    ['Field', 'Before (current)', 'After (proposed)'],
    ['Task', 'Weekly report', 'Weekly report'],
    ['Due time', 'Today 10:00', '->    Today 20:00'],
    ['Status', 'Unfinished', '->    Unfinished'],
    ['Mark as completed', 'No', '->    No'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 6),
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++)
            _DiffRow(cells: _rows[i], header: i == 0, accent: i == 2),
        ],
      ),
    );
  }
}

final class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.cells,
    required this.header,
    required this.accent,
  });

  final List<String> cells;
  final bool header;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: header ? 32 : 34,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            Expanded(
              flex: i == 0 ? 2 : 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  cells[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent && i == 2
                        ? const Color(0xFF08A86B)
                        : AgentHomeStoryboard.ink,
                    fontSize: header ? 12 : 13,
                    fontWeight: header ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (i < cells.length - 1) const _VLine(),
          ],
        ],
      ),
    );
  }
}

final class _MobileDiff extends StatelessWidget {
  const _MobileDiff();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _MobileDiffRow('Due time', 'Today 10:00', 'Today 20:00'),
        SizedBox(height: 12),
        _MobileDiffRow('Status', 'Unfinished', 'Unchanged'),
      ],
    );
  }
}

final class _MobileDiffRow extends StatelessWidget {
  const _MobileDiffRow(this.label, this.before, this.after);

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 82, child: Text(label, style: _mutedBold(13))),
        Expanded(
            child: Text(before,
                style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w700))),
        const Text('->',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 38,
                fontWeight: FontWeight.w900)),
        Expanded(
          child: Text(
            after,
            textAlign: TextAlign.end,
            style: const TextStyle(
                color: Color(0xFF08A86B),
                fontSize: 13,
                fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
