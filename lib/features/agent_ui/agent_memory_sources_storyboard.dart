part of 'agent_home_storyboard.dart';

final class AgentMemorySourcesStoryboard extends StatelessWidget {
  const AgentMemorySourcesStoryboard({super.key});

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
            child: _MemorySourcesCanvas(),
          ),
        ),
      ),
    );
  }
}

final class _MemorySourcesCanvas extends StatelessWidget {
  const _MemorySourcesCanvas();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Column(
        children: [
          SizedBox(
            height: 1106,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemorySourcesWorkspace(),
                SizedBox(width: 32),
                _MemorySourcesPhoneFrame(),
              ],
            ),
          ),
          SizedBox(height: 20),
          _MemorySourcesNotesStrip(),
        ],
      ),
    );
  }
}

final class _MemorySourcesWorkspace extends StatelessWidget {
  const _MemorySourcesWorkspace();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent_memory_sources_workspace'),
      width: 1534,
      height: 1106,
      decoration: _box(radius: 10),
      child: const Row(
        children: [
          _MemorySidebar(),
          _VLine(),
          Expanded(child: _MemorySourcesDesktopBody()),
        ],
      ),
    );
  }
}

final class _MemorySourcesDesktopBody extends StatelessWidget {
  const _MemorySourcesDesktopBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(30, 30, 30, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(),
          SizedBox(height: 26),
          _MemorySourcesTabs(),
          SizedBox(height: 30),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 460, child: _SourcesListPanel()),
                SizedBox(width: 20),
                Expanded(child: _SourceDetailPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _MemorySourcesTabs extends StatelessWidget {
  const _MemorySourcesTabs();

  static const _tabs = [
    (label: 'Preferences', selected: false),
    (label: 'People', selected: false),
    (label: 'Projects', selected: false),
    (label: 'Sources', selected: true),
    (label: 'Suggestions', selected: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            SizedBox(
              width: 122,
              child: _MemoryTab(label: tab.label, selected: tab.selected),
            ),
        ],
      ),
    );
  }
}

final class _SourcesListPanel extends StatelessWidget {
  const _SourcesListPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(18, 22, 14, 18),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sources',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          SizedBox(height: 26),
          _SourceFilterRow(),
          SizedBox(height: 24),
          _SourceListRow(
            title: 'Conversation - May 20',
            body: 'You and SecondLoop',
            date: 'May 20, 2025',
            count: '5 memories',
            color: AgentHomeStoryboard.blue,
            icon: 'C',
            selected: true,
          ),
          _SourceListRow(
            title: 'Meeting notes - Q2 review',
            body: 'Q2 review sync',
            date: 'May 18, 2025',
            count: '4 memories',
            color: Color(0xFF08945F),
            icon: 'N',
          ),
          _SourceListRow(
            title: 'Client_Requirements.docx',
            body: 'Document',
            date: 'May 16, 2025',
            count: '6 memories',
            color: AgentHomeStoryboard.blue,
            icon: 'W',
          ),
          _SourceListRow(
            title: 'Passport scan',
            body: 'Image',
            date: 'May 12, 2025',
            count: '3 memories',
            color: Color(0xFF08945F),
            icon: 'I',
          ),
          Spacer(),
          Text('4 sources',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

final class _SourceFilterRow extends StatelessWidget {
  const _SourceFilterRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _SourceFilterPill('All sources', selected: true),
        SizedBox(width: 12),
        _SourceFilterPill('Conversations'),
        SizedBox(width: 12),
        _SourceFilterPill('Files'),
        SizedBox(width: 12),
        _SourceFilterPill('Meetings'),
      ],
    );
  }
}

final class _SourceFilterPill extends StatelessWidget {
  const _SourceFilterPill(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: _box(
        radius: 19,
        color: selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.panel,
        border: selected ? AgentHomeStoryboard.blue : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AgentHomeStoryboard.muted,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _SourceListRow extends StatelessWidget {
  const _SourceListRow({
    required this.title,
    required this.body,
    required this.date,
    required this.count,
    required this.color,
    required this.icon,
    this.selected = false,
  });

  final String title;
  final String body;
  final String date;
  final String count;
  final Color color;
  final String icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(
        radius: 7,
        color: selected ? const Color(0xFFFBFDFF) : AgentHomeStoryboard.panel,
        border: selected ? const Color(0xFF7FA9FF) : AgentHomeStoryboard.line,
        borderWidth: selected ? 1.5 : 0,
      ),
      child: Row(
        children: [
          _SourceIcon(icon: icon, color: color),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedBold(13)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(date, style: _mutedBold(13)),
              const SizedBox(height: 8),
              Text(count, style: _mutedBold(13)),
            ],
          ),
          const SizedBox(width: 14),
          const Text('>',
              style: TextStyle(
                  color: AgentHomeStoryboard.muted,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

final class _SourceDetailPanel extends StatelessWidget {
  const _SourceDetailPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SourceDetailHeader(),
          SizedBox(height: 34),
          Text('Extracted memory references',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
            'Snippets show where each memory came from in this conversation.',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 20),
          _SourceReferenceTable(),
          SizedBox(height: 30),
          Text('Source summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          Text(
            'This conversation includes scheduling preferences, communication rules, person preferences, and family facts.',
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w700),
          ),
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(width: 170, child: _SourceActionButton('Open source')),
              SizedBox(width: 22),
              SizedBox(
                width: 190,
                child: _SourceActionButton('Detach memory', danger: true),
              ),
            ],
          ),
          SizedBox(height: 34),
          _SourceNotice(),
        ],
      ),
    );
  }
}

final class _SourceDetailHeader extends StatelessWidget {
  const _SourceDetailHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _SourceIcon(icon: 'C', color: AgentHomeStoryboard.blue, large: true),
        SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conversation - May 20',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('You and SecondLoop',
                  style: TextStyle(
                      color: AgentHomeStoryboard.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Text('May 20, 2025\n5 memories',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: AgentHomeStoryboard.muted,
                fontSize: 15,
                height: 1.55,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

final class _SourceReferenceTable extends StatelessWidget {
  const _SourceReferenceTable();

  static const _rows = [
    (
      title: 'No meetings before 9 AM',
      type: 'Preference',
      snippet: '"I normally do deep work before 9, so avoid meetings then."',
      confidence: 'High',
      linked: 'No meetings before 9 AM',
      icon: 'A',
      color: Color(0xFF08945F),
      medium: false,
    ),
    (
      title: 'Reply to tasks in Chinese',
      type: 'Communication preference',
      snippet: '"Please reply in Chinese for task-related updates."',
      confidence: 'High',
      linked: 'Reply to tasks in Chinese',
      icon: 'Q',
      color: Color(0xFF08945F),
      medium: false,
    ),
    (
      title: 'Alex prefers afternoon meetings',
      type: 'Person',
      snippet: '"Alex said afternoon meetings are more efficient."',
      confidence: 'High',
      linked: 'Alex prefers afternoon meetings',
      icon: 'W',
      color: AgentHomeStoryboard.blue,
      medium: false,
    ),
    (
      title: 'Child birthday is June 20',
      type: 'Family fact',
      snippet: '"My child has a birthday on June 20 every year."',
      confidence: 'High',
      linked: 'Child birthday is June 20',
      icon: 'B',
      color: Color(0xFFFF8A00),
      medium: false,
    ),
    (
      title: 'Buy gift one day before birthday',
      type: 'Recurring reminder',
      snippet: '"Remind me to buy a gift the day before the birthday."',
      confidence: 'Medium',
      linked: 'Birthday gift reminder',
      icon: 'R',
      color: AgentHomeStoryboard.blue,
      medium: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _box(radius: 9),
      child: Column(
        children: [
          const _SourceReferenceHeader(),
          for (final row in _rows)
            _SourceReferenceRow(
              title: row.title,
              type: row.type,
              snippet: row.snippet,
              confidence: row.confidence,
              linked: row.linked,
              icon: row.icon,
              color: row.color,
              medium: row.medium,
            ),
        ],
      ),
    );
  }
}

final class _SourceReferenceHeader extends StatelessWidget {
  const _SourceReferenceHeader();

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Memory content',
      'Snippet (readable)',
      'Confidence',
      'Linked memory',
    ];
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(labels[0], style: _mutedBold(12))),
          Expanded(flex: 4, child: Text(labels[1], style: _mutedBold(12))),
          Expanded(flex: 2, child: Text(labels[2], style: _mutedBold(12))),
          Expanded(flex: 2, child: Text(labels[3], style: _mutedBold(12))),
        ],
      ),
    );
  }
}

final class _SourceReferenceRow extends StatelessWidget {
  const _SourceReferenceRow({
    required this.title,
    required this.type,
    required this.snippet,
    required this.confidence,
    required this.linked,
    required this.icon,
    required this.color,
    required this.medium,
  });

  final String title;
  final String type;
  final String snippet;
  final String confidence;
  final String linked;
  final String icon;
  final Color color;
  final bool medium;

  @override
  Widget build(BuildContext context) {
    final dot = medium ? const Color(0xFFFF8A00) : const Color(0xFF08945F);
    return Container(
      height: 82,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentHomeStoryboard.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _Glyph(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(type, style: _mutedBold(11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _mutedBold(12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(confidence, style: _mutedBold(12)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              linked,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AgentHomeStoryboard.blue,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SourceActionButton extends StatelessWidget {
  const _SourceActionButton(this.label, {this.danger = false});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: _box(
        radius: 7,
        border: danger ? const Color(0xFFFFB5B5) : AgentHomeStoryboard.line,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? const Color(0xFFFF2E2E) : AgentHomeStoryboard.blue,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

final class _SourceNotice extends StatelessWidget {
  const _SourceNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: _box(
        radius: 7,
        color: const Color(0xFFF0FBF7),
        border: const Color(0xFFCFEFE2),
      ),
      child: const Row(
        children: [
          _Glyph('V', color: Color(0xFF08945F)),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'If a source is incorrect or outdated, detach the affected memories.',
              style: TextStyle(
                  color: Color(0xFF1B5C47),
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
