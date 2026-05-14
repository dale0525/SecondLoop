part of 'agent_home_storyboard.dart';

final class AgentReviewStoryboard extends StatelessWidget {
  const AgentReviewStoryboard({super.key});

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
            child: _ReviewCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _ReviewCanvas extends StatelessWidget {
  const _ReviewCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1056,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewWorkspace(),
                SizedBox(width: 36),
                _ReviewPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 42),
          _ReviewNotesStrip(),
        ],
      ),
    );
  }
}

final class _ReviewWorkspace extends StatelessWidget {
  const _ReviewWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_review_desktop_workspace'),
      width: 1560,
      height: 1056,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _ReviewSidebar(),
          _VLine(),
          Expanded(child: _ReviewDesktopBody()),
        ],
      ),
    );
  }
}

final class _ReviewSidebar extends StatelessWidget {
  const _ReviewSidebar();

  static const _items = [
    (label: 'Conversation', glyph: 'C', selected: false, badge: ''),
    (label: 'Memory', glyph: 'M', selected: false, badge: ''),
    (label: 'Review', glyph: 'R', selected: true, badge: '7'),
    (label: 'Settings', glyph: 'S', selected: false, badge: ''),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const SizedBox(height: 58),
            for (final item in _items) ...[
              _ReviewNavItem(
                label: item.label,
                glyph: item.glyph,
                selected: item.selected,
                badge: item.badge,
              ),
              const SizedBox(height: 22),
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

final class _ReviewNavItem extends StatelessWidget {
  const _ReviewNavItem({
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
      height: 70,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF1FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          _Glyph(glyph, color: color),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 17,
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

final class _ReviewDesktopBody extends StatelessWidget {
  const _ReviewDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(40, 36, 32, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewHeader(),
          SizedBox(height: 30),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 442, child: _ReviewQueuePanel()),
                SizedBox(width: 14),
                Expanded(child: _ReviewDetailPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Review',
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                  SizedBox(width: 16),
                  _ReviewCountBadge(),
                ],
              ),
              SizedBox(height: 14),
              Text(
                'Approve only what changes your data or sends something out.',
                style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: _box(radius: 7),
          child: Row(
            children: [
              const _Glyph('F', color: Color(0xFF485777)),
              const SizedBox(width: 10),
              const Text('Filter',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(width: 16),
              Text('v', style: _mutedBold(16)),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ReviewQueuePanel extends StatelessWidget {
  const _ReviewQueuePanel();

  static const _items = [
    (
      title: 'Task change',
      subtitle: 'Move weekly report to today 20:00.',
      chip: 'High',
      tone: _Tone.red,
      glyph: 'T',
      selected: true,
      time: '10:15',
    ),
    (
      title: 'Memory candidate',
      subtitle: 'I do not start meetings before 9.',
      chip: 'Medium',
      tone: _Tone.orange,
      glyph: 'M',
      selected: false,
      time: '10:14',
    ),
    (
      title: 'Recurring reminder',
      subtitle: 'Every Monday 09:00 station reminder',
      chip: 'Low',
      tone: _Tone.green,
      glyph: 'O',
      selected: false,
      time: '10:14',
    ),
    (
      title: 'Email draft',
      subtitle: 'Send to client-a@acme.com',
      chip: 'High',
      tone: _Tone.red,
      glyph: 'E',
      selected: false,
      time: '10:13',
    ),
    (
      title: 'Calendar invite',
      subtitle: 'Create 14:00 review meeting',
      chip: 'Medium',
      tone: _Tone.orange,
      glyph: 'C',
      selected: false,
      time: '10:13',
    ),
    (
      title: 'Research budget',
      subtitle: 'Q2 production tool market research',
      chip: 'High',
      tone: _Tone.red,
      glyph: '!',
      selected: false,
      time: '10:12',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Needs your OK',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          const _SegmentedReviewTabs(),
          const SizedBox(height: 18),
          for (final item in _items)
            _ReviewQueueItem(
              title: item.title,
              subtitle: item.subtitle,
              chip: item.chip,
              tone: item.tone,
              glyph: item.glyph,
              selected: item.selected,
              time: item.time,
            ),
          const Spacer(),
          Text('Showing 1-6 of 7', style: _mutedBold(14)),
        ],
      ),
    );
  }
}

final class _SegmentedReviewTabs extends StatelessWidget {
  const _SegmentedReviewTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: _box(radius: 7),
      child: const Row(
        children: [
          Expanded(child: _Segment('All', selected: true)),
          Expanded(child: _Segment('High risk')),
          Expanded(child: _Segment('Drafts')),
        ],
      ),
    );
  }
}

final class _Segment extends StatelessWidget {
  const _Segment(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF1FF) : Colors.transparent,
        border: selected
            ? const Border(
                bottom: BorderSide(color: AgentHomeStoryboard.blue, width: 2))
            : null,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.muted,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

final class _ReviewQueueItem extends StatelessWidget {
  const _ReviewQueueItem({
    required this.title,
    required this.subtitle,
    required this.chip,
    required this.tone,
    required this.glyph,
    required this.selected,
    required this.time,
  });

  final String title;
  final String subtitle;
  final String chip;
  final _Tone tone;
  final String glyph;
  final bool selected;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: _box(
        radius: 7,
        color: selected ? const Color(0xFFFBFDFF) : AgentHomeStoryboard.panel,
        border: selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
        borderWidth: selected ? 1.5 : 1,
      ),
      child: Row(
        children: [
          _Glyph(glyph,
              color: tone == _Tone.red ? Colors.red : AgentHomeStoryboard.blue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _mutedBold(13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Chip(chip, tone: tone),
              const SizedBox(height: 10),
              Text(time, style: _mutedBold(13)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ReviewDetailPanel extends StatelessWidget {
  const _ReviewDetailPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(24, 42, 24, 50),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewDetailTitle(),
          SizedBox(height: 42),
          _SourceMessageBox(),
          SizedBox(height: 54),
          Text('Change preview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          _ReviewDiffTable(),
          Spacer(),
          Center(
            child: Text(
              'Nothing is applied until you approve.',
              style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 74),
          Row(
            children: [
              Expanded(
                  child: _ReviewDecisionButton('Approve',
                      tone: _DecisionTone.approve)),
              SizedBox(width: 28),
              Expanded(child: _ReviewDecisionButton('Edit')),
              SizedBox(width: 28),
              Expanded(
                  child: _ReviewDecisionButton('Reject',
                      tone: _DecisionTone.reject)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ReviewDetailTitle extends StatelessWidget {
  const _ReviewDetailTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Glyph('T', color: Color(0xFF0B9B63)),
        SizedBox(width: 22),
        Text('Task change',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        SizedBox(width: 22),
        _Chip('High risk', tone: _Tone.red),
        Spacer(),
        _Chip('Pending', tone: _Tone.orange),
      ],
    );
  }
}

final class _SourceMessageBox extends StatelessWidget {
  const _SourceMessageBox();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source message', style: _mutedBold(17)),
        const SizedBox(height: 12),
        Container(
          height: 82,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: _box(radius: 8),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Move weekly report to today 20:00, but do not mark it complete.',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Text('10:15',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ReviewDiffTable extends StatelessWidget {
  const _ReviewDiffTable();

  static const _rows = [
    ['Field', 'Before (current)', 'After (proposed)'],
    ['Due time', 'Today 10:00', '->    Today 20:00'],
    ['Status', 'not completed', '->    not completed (unchanged)'],
    ['Title', 'Weekly report', '->    Weekly report (unchanged)'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 8),
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++)
            _DiffRow(cells: _rows[i], header: i == 0, accent: i == 1),
        ],
      ),
    );
  }
}

enum _DecisionTone { approve, neutral, reject }

final class _ReviewDecisionButton extends StatelessWidget {
  const _ReviewDecisionButton(
    this.label, {
    this.tone = _DecisionTone.neutral,
  });

  final String label;
  final _DecisionTone tone;

  @override
  Widget build(BuildContext context) {
    final isApprove = tone == _DecisionTone.approve;
    final isReject = tone == _DecisionTone.reject;
    return Container(
      height: 64,
      alignment: Alignment.center,
      decoration: _box(
        radius: 7,
        color: isApprove ? const Color(0xFF08945F) : AgentHomeStoryboard.panel,
        border: isReject
            ? const Color(0xFFFF6F6F)
            : isApprove
                ? const Color(0xFF08945F)
                : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isApprove
              ? Colors.white
              : isReject
                  ? Colors.red
                  : AgentHomeStoryboard.ink,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _ReviewPhoneFrame extends StatelessWidget {
  const _ReviewPhoneFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_review_mobile_mock'),
      width: 430,
      height: 1056,
      decoration: _box(
        radius: 54,
        border: const Color(0xFFE2E4E8),
        borderWidth: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: const _ReviewMobileCanvas(),
      ),
    );
  }
}

final class _ReviewMobileCanvas extends StatelessWidget {
  const _ReviewMobileCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AgentHomeStoryboard.panel,
      child: Stack(
        children: [
          Positioned.fill(child: _ReviewMobileBody()),
          Positioned(left: 0, right: 0, bottom: 0, child: _ReviewMobileSheet()),
        ],
      ),
    );
  }
}

final class _ReviewMobileBody extends StatelessWidget {
  const _ReviewMobileBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Column(
        children: [
          _PhoneStatus(),
          SizedBox(height: 22),
          Row(
            children: [
              Text('=',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Review',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      SizedBox(width: 10),
                      _ReviewCountBadge(),
                    ],
                  ),
                ),
              ),
              _Glyph('F', color: Color(0xFF485777)),
            ],
          ),
          SizedBox(height: 22),
          _SegmentedReviewTabs(),
          SizedBox(height: 12),
          Expanded(child: _ReviewMobileQueue()),
        ],
      ),
    );
  }
}

final class _ReviewMobileQueue extends StatelessWidget {
  const _ReviewMobileQueue();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ReviewQueueItem(
          title: 'Task change',
          subtitle: 'Move weekly report to today 20:00.',
          chip: 'High',
          tone: _Tone.red,
          glyph: 'T',
          selected: true,
          time: '10:15',
        ),
        _ReviewQueueItem(
          title: 'Memory candidate',
          subtitle: 'I do not start meetings before 9.',
          chip: 'Medium',
          tone: _Tone.orange,
          glyph: 'M',
          selected: false,
          time: '10:14',
        ),
        _ReviewQueueItem(
          title: 'Recurring reminder',
          subtitle: 'Every Monday 09:00 station reminder',
          chip: 'Low',
          tone: _Tone.green,
          glyph: 'O',
          selected: false,
          time: '10:14',
        ),
      ],
    );
  }
}

final class _ReviewMobileSheet extends StatelessWidget {
  const _ReviewMobileSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
      decoration: const BoxDecoration(
        color: AgentHomeStoryboard.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -8)),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Divider(thickness: 5, color: Color(0xFFB9C1D2)),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Task change',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              _Chip('High risk', tone: _Tone.red),
              SizedBox(width: 16),
              Text('x',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          SizedBox(height: 12),
          Text('Source message', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          _Bubble(
              'Move weekly report to today 20:00, but do not mark it complete.'),
          SizedBox(height: 12),
          _ReviewDiffTable(),
          Spacer(),
          Row(
            children: [
              Expanded(
                  child: _ReviewDecisionButton('Approve',
                      tone: _DecisionTone.approve)),
              SizedBox(width: 10),
              Expanded(child: _ReviewDecisionButton('Edit')),
              SizedBox(width: 10),
              Expanded(
                  child: _ReviewDecisionButton('Reject',
                      tone: _DecisionTone.reject)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ReviewCountBadge extends StatelessWidget {
  const _ReviewCountBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1FF),
        shape: BoxShape.circle,
      ),
      child: const Text(
        '7',
        style: TextStyle(
          color: AgentHomeStoryboard.blue,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _ReviewNotesStrip extends StatelessWidget {
  const _ReviewNotesStrip();

  static const _notes = [
    (
      title: 'Only side effects need approval.',
      body: 'We ask for OK only when data is changed or something is sent.',
    ),
    (
      title: 'Each candidate stands alone.',
      body: 'Review one change at a time for clarity and focus.',
    ),
    (
      title: 'Diffs are plain-language.',
      body: 'See exactly what will change, before and after.',
    ),
    (
      title: 'Reject keeps history.',
      body: 'Nothing is lost; rejected items remain visible in history.',
    ),
    (
      title: 'Audit details stay hidden.',
      body: 'Technical logs and systems are not shown in Review.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_review_interaction_notes'),
      height: 235,
      decoration: _box(radius: 10),
      padding: const EdgeInsets.fromLTRB(48, 36, 48, 30),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _notes.length; i++) ...[
            Expanded(
              child: _ReviewNote(
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

final class _ReviewNote extends StatelessWidget {
  const _ReviewNote({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NumberBubble(number),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, height: 1.25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 28),
              Text(body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, height: 1.45, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
